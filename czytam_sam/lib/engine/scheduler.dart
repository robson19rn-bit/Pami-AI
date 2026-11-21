/// Dobór zadań – jawny, deterministyczny (dla danego ziarna losowania) i testowalny.
///
/// 1. Kandydaci = (element, umiejętność, typ zadania) dostępni na obecnym etapie
///    i możliwi do przeprowadzenia przy obecnych warunkach (lektor, opiekun, mikrofon).
/// 2. Podział na koszyki: ZALEGŁE/TRUDNE, BIEŻĄCE, UTRWALANIE.
/// 3. Proporcje domyślne 60/25/15 (edytowalne); brakujące miejsca przechodzą do innych koszyków.
/// 4. Kolejność: brak tego samego celu w dwóch kolejnych zadaniach (jeśli pula pozwala).
/// 5. Opcje odpowiedzi: 2/3/4/6 zależnie od stanu, pary mylone kontrolowane,
///    pozycja poprawnej odpowiedzi równoważona.
library;

import 'dart:math';

import '../content/models.dart';
import 'curriculum.dart';
import 'mastery.dart';
import 'types.dart';

enum Bucket { due, current, consolidation }

class Capabilities {
  const Capabilities({
    this.guardianPresent = false,
    this.ttsOk = false,
    this.asrReady = false,
    this.ttsBadUnits = const {},
    this.assessmentOnly = false,
  });

  /// Sesja „Ocena wypowiedzi z opiekunem”: tylko zadania mówione, ocenia opiekun.
  final bool assessmentOnly;

  /// Opiekun jest obok (może wymówić głoskę i ocenić wypowiedź).
  final bool guardianPresent;

  /// Polski lektor działa (sprawdzone przy konfiguracji).
  final bool ttsOk;

  /// Lokalny model rozpoznawania mowy zainstalowany i jest uprawnienie mikrofonu.
  final bool asrReady;

  /// Jednostki, które lektor czyta błędnie (oznaczone przez opiekuna).
  final Set<String> ttsBadUnits;

  bool canSpeak(String unitId) => ttsOk && !ttsBadUnits.contains(unitId) && !ttsKnownBad.contains(unitId);
}

/// Jednostki, które syntezatory czytają jako skrót lub obce słowo („ok” → „okej”) –
/// nie podajemy ich lektorem (tylko opiekun lub czytanie przez dziecko).
const ttsKnownBad = {'syl_ok'};

class Candidate {
  Candidate(this.itemId, this.kind, this.skill, this.task, {this.assisted = false, this.rank = 0});
  final String itemId;
  final ItemKind kind;
  final Skill skill;
  final TaskType task;
  final bool assisted;

  /// Kolejność dydaktyczna (mniej = wcześniej): litery wg kolejności nauki, potem jednostki wg poziomu.
  final int rank;
  @override
  String toString() => '$itemId/${skill.name}/${task.name}';
}

class Planned {
  Planned(this.candidate, this.bucket);
  final Candidate candidate;
  final Bucket bucket;
}

/// Generuje kandydatów zgodnie z etapem i możliwościami.
///
/// Tryb domyślny (dziecko ćwiczy samo): wszystkie polecenia czyta lektor, także
/// głoski – podawane w słowie („na początku słowa mama”), bo syntezatory źle
/// wymawiają głoski w izolacji. Zadania mówione bez oceniającego są ćwiczeniem
/// (zapis „nieocenione”) – nie liczą się do opanowania.
/// Tryb oceny ([Capabilities.assessmentOnly]): tylko wypowiedzi, ocenia opiekun.
List<Candidate> buildCandidates(Curriculum cur, Capabilities cap) {
  final out = <Candidate>[];
  final g = cap.guardianPresent || cap.assessmentOnly;
  final speechJudged = g; // litery i głoski ocenia wyłącznie człowiek
  final readingJudged = g || cap.asrReady;
  final assess = cap.assessmentOnly;
  for (final l in cur.activeLetters()) {
    final canPrompt = cap.canSpeak(l.id) || g;
    if (!assess) {
      if (canPrompt) {
        out.add(Candidate(l.id, ItemKind.letter, Skill.recognizeName, TaskType.t1HearPoint, rank: l.order));
        // T2: dotyk liczony zawsze; wypowiedź oceniana tylko, gdy jest oceniający.
        out.add(Candidate(l.id, ItemKind.letter, Skill.recognizeName, TaskType.t2PointSay, rank: l.order));
        out.add(Candidate(l.id, ItemKind.letter, Skill.recognizeSound, TaskType.t1HearPoint, rank: l.order));
      }
      out.add(Candidate(l.id, ItemKind.letter, Skill.caseMatch, TaskType.t4Case, rank: l.order));
    }
    if (speechJudged) {
      out.add(Candidate(l.id, ItemKind.letter, Skill.sayName, TaskType.t3SeeName, rank: l.order));
      out.add(Candidate(l.id, ItemKind.letter, Skill.saySound, TaskType.t3SeeName, rank: l.order));
    }
  }
  for (final gr in cur.activeGraphemes()) {
    if (!assess && (cap.canSpeak(gr.id) || g)) {
      out.add(Candidate(gr.id, ItemKind.grapheme, Skill.recognizeSound, TaskType.t1HearPoint, rank: 40));
    }
    if (speechJudged) out.add(Candidate(gr.id, ItemKind.grapheme, Skill.saySound, TaskType.t3SeeName, rank: 40));
  }
  for (final k in [ItemKind.syllable, ItemKind.word]) {
    final base = k == ItemKind.syllable ? 50 : 60;
    for (final ua in cur.units(k)) {
      final a = ua.access == Access.manualAssisted;
      final rank = base + ua.unit.level;
      final canPrompt = cap.canSpeak(ua.unit.id) || g;
      if (!assess && canPrompt) {
        // T8: lektor mówi całą sylabę/wyraz, dziecko wskazuje ją wśród podobnych – czytanie całościowe.
        out.add(Candidate(ua.unit.id, k, Skill.recognizeUnit, TaskType.t8HearPickUnit, assisted: a, rank: rank));
        if (k == ItemKind.syllable || (ua.unit.graphemes.length <= 4 && tokenCount(ua.unit) <= 5)) {
          out.add(Candidate(ua.unit.id, k, Skill.segment, TaskType.t5Segment, assisted: a, rank: rank));
        }
      }
      // Czytanie na głos: tylko przy potwierdzonej wymowie głosek (lub materiale „z pomocą”) i gdy ktoś oceni.
      if (readingJudged && ua.access != Access.receptive) {
        out.add(Candidate(ua.unit.id, k, Skill.readAloud, TaskType.t6ReadAloud, assisted: a, rank: rank));
      }
    }
  }
  if (!assess) {
    for (final k in [ItemKind.sentence, ItemKind.reading]) {
      for (final ua in cur.units(k)) {
        out.add(Candidate(ua.unit.id, k, Skill.comprehension, TaskType.t7Comprehension,
            assisted: ua.access == Access.manualAssisted, rank: 70 + ua.unit.level));
      }
    }
  }
  return out;
}

int tokenCount(ReadingUnit u) => u.text.replaceAll(RegExp(r'[^a-ząćęłńóśźż]', caseSensitive: false), '').length;

Bucket bucketOf(SkillStats s, DateTime now, {bool confusedItem = false}) {
  final st = s.state;
  if (st == MasteryState.doPowtorzenia) return Bucket.due;
  // Element mylony z innym (w dowolnej umiejętności, także w diagnozie) i jeszcze nieopanowany → trudny.
  if (confusedItem && !st.isMastered) return Bucket.due;
  final acc = s.recentAccuracy;
  if ((st == MasteryState.uczone || st == MasteryState.cwiczone) && acc != null && s.validResults.length >= 3 && acc < 0.7) {
    return Bucket.due;
  }
  if (st.isMastered) {
    final due = s.dueAt;
    return (due != null && !now.isBefore(due)) ? Bucket.due : Bucket.consolidation;
  }
  return Bucket.current;
}

/// Planuje [n] zadań. Deterministyczne dla danego [rng].
List<Planned> planSession({
  required List<Candidate> candidates,
  required ProgressIndex index,
  required DateTime now,
  required int n,
  required Random rng,
  String? previousTarget,

  /// Elementy blokujące postęp (np. litery jeszcze niepoznane) – pierwszeństwo w koszyku bieżących;
  /// wartość = umiejętności, których brakuje (te idą najpierw).
  Map<String, Set<Skill>> focus = const {},
}) {
  if (candidates.isEmpty || n <= 0) return [];
  final c = index.config;
  final buckets = {for (final b in Bucket.values) b: <Candidate>[]};
  final confusedItems = <String>{
    for (final st in index.stats.values)
      // mylony wielokrotnie (≥2 pomyłki) i wciąż niepewny – pojedyncza pomyłka nie blokuje nowych liter
      if (st.confusions.values.fold(0, (x, y) => x + y) >= 2 && (st.recentAccuracy ?? 0) < 0.8) st.itemId
  };
  for (final cand in candidates) {
    buckets[bucketOf(index.of(cand.itemId, cand.skill), now, confusedItem: confusedItems.contains(cand.itemId))]!.add(cand);
  }
  // Priorytety w koszykach (stabilne sortowanie po kluczu + losowy remis).
  final tiebreak = {for (final cand in candidates) cand.toString(): rng.nextDouble()};
  int byTie(Candidate a, Candidate b) => tiebreak[a.toString()]!.compareTo(tiebreak[b.toString()]!);
  buckets[Bucket.due]!.sort((a, b) {
    final sa = index.of(a.itemId, a.skill), sb = index.of(b.itemId, b.skill);
    final ra = sa.state == MasteryState.doPowtorzenia ? 0 : 1, rb = sb.state == MasteryState.doPowtorzenia ? 0 : 1;
    if (ra != rb) return ra - rb;
    // Priorytet = trudność + czas od ostatniego ćwiczenia: stale mylone elementy wracają
    // częściej, a łatwiejsze z koszyka i tak doczekają się kolejki (brak „zagłodzenia”).
    double score(SkillStats st) {
      final days = st.lastAttemptAt == null ? 30.0 : now.difference(st.lastAttemptAt!).inMinutes / 1440.0;
      return days + 3 * (1 - (st.recentAccuracy ?? 0.5));
    }

    final da = score(sa), db = score(sb);
    if (da != db) return db.compareTo(da);
    return byTie(a, b);
  });
  buckets[Bucket.current]!.sort((a, b) {
    final sa = index.of(a.itemId, a.skill), sb = index.of(b.itemId, b.skill);
    // 1) nigdy nie ćwiczone umiejętności, 2) najdawniej ćwiczona DANA umiejętność (rotacja po całym
    // alfabecie bez zaniedbywania np. wymowy liter często ćwiczonych dotykiem), 3) kolejność nauki.
    final ta = sa.totalAttempts == 0 ? 0 : 1, tb = sb.totalAttempts == 0 ? 0 : 1;
    if (ta != tb) return ta - tb;
    int f(Candidate c) => focus[c.itemId] == null ? 2 : (focus[c.itemId]!.contains(c.skill) ? 0 : 1);
    final fa = f(a), fb = f(b);
    if (fa != fb) return fa - fb;
    final la = sa.lastAttemptAt, lb = sb.lastAttemptAt;
    if (la != null && lb != null && la != lb) return la.compareTo(lb);
    if (a.rank != b.rank) return a.rank - b.rank;
    return byTie(a, b);
  });
  buckets[Bucket.consolidation]!.sort((a, b) {
    final la = index.of(a.itemId, a.skill).lastAttemptAt, lb = index.of(b.itemId, b.skill).lastAttemptAt;
    if (la != null && lb != null && la != lb) return la.compareTo(lb); // najdawniej ćwiczone najpierw
    return byTie(a, b);
  });

  final quota = {
    Bucket.due: (n * c.shareDue).round(),
    Bucket.current: (n * c.shareCurrent).round(),
  };
  quota[Bucket.consolidation] = max(0, n - quota[Bucket.due]! - quota[Bucket.current]!);
  // Utrwalanie nie znika: jeśli są opanowane elementy, co najmniej 1 zadanie.
  if (quota[Bucket.consolidation] == 0 && buckets[Bucket.consolidation]!.isNotEmpty && n >= 3) {
    quota[Bucket.consolidation] = 1;
    quota[Bucket.due] = quota[Bucket.due]! - 1;
  }

  final picked = <Planned>[];
  final cursor = {for (final b in Bucket.values) b: 0};
  // Różnorodność: w jednej lekcji najwyżej 2 zadania z tym samym elementem; limit łamiemy dopiero,
  // gdy w żadnym koszyku nie ma już innych elementów (bardzo mała pula).
  final perItem = <String, int>{};
  Candidate? take(Bucket b, {bool strict = true}) {
    final list = buckets[b]!;
    if (list.isEmpty) return null;
    for (var k = 0; k < list.length; k++) {
      final cand = list[(cursor[b]! + k) % list.length];
      if (!strict || (perItem[cand.itemId] ?? 0) < 2) {
        cursor[b] = cursor[b]! + k + 1;
        perItem[cand.itemId] = (perItem[cand.itemId] ?? 0) + 1;
        return cand;
      }
    }
    return null;
  }

  // Najpierw kwoty koszyków, potem dopełnienie z dowolnego koszyka (nadal z limitem), na końcu bez limitu.
  for (final b in Bucket.values) {
    for (var i = 0; i < quota[b]!; i++) {
      final cand = take(b);
      if (cand == null) break;
      picked.add(Planned(cand, b));
    }
  }
  final order = [Bucket.due, Bucket.current, Bucket.consolidation];
  for (final strict in [true, false]) {
    var progress = true;
    while (picked.length < n && progress) {
      progress = false;
      for (final b in order) {
        if (picked.length >= n) break;
        final cand = take(b, strict: strict);
        if (cand != null) {
          picked.add(Planned(cand, b));
          progress = true;
        }
      }
    }
  }

  return _spread(picked, rng, previousTarget);
}

/// Ustawia kolejność tak, by ten sam cel nie wystąpił dwa razy z rzędu (jeśli to możliwe),
/// a zadania z koszyka ZALEGŁE były rozłożone w całej sesji.
List<Planned> _spread(List<Planned> items, Random rng, String? previousTarget) {
  final pool = [...items]..shuffle(rng);
  final out = <Planned>[];
  var prev = previousTarget;
  while (pool.isNotEmpty) {
    // Ile zostało zadań dla każdego celu – najpierw cel z największą liczbą
    // (klasyczne przestawianie bez sąsiadów: gwarantuje brak powtórzeń, jeśli to możliwe).
    final remaining = <String, int>{};
    for (final p in pool) {
      remaining[p.candidate.itemId] = (remaining[p.candidate.itemId] ?? 0) + 1;
    }
    var best = -1;
    for (var i = 0; i < pool.length; i++) {
      final id = pool[i].candidate.itemId;
      if (id == prev) continue;
      if (best < 0 || remaining[id]! > remaining[pool[best].candidate.itemId]!) best = i;
    }
    if (best < 0) best = 0;
    final p = pool.removeAt(best);
    out.add(p);
    prev = p.candidate.itemId;
  }
  return out;
}

/// Równoważenie pozycji poprawnej odpowiedzi.
class PositionBalancer {
  PositionBalancer(this.rng);
  final Random rng;
  final Map<int, List<int>> counts = {};

  int pick(int optionCount) {
    final c = counts.putIfAbsent(optionCount, () => List.filled(optionCount, 0));
    final minV = c.reduce(min);
    final cands = [for (var i = 0; i < optionCount; i++) if (c[i] == minV) i];
    final pos = cands[rng.nextInt(cands.length)];
    c[pos]++;
    return pos;
  }
}

int optionCountFor(MasteryState s) => switch (s) {
      MasteryState.nowe => 2,
      MasteryState.uczone => 3,
      MasteryState.cwiczone || MasteryState.doPowtorzenia => 4,
      MasteryState.opanowaneWarunkowo || MasteryState.potwierdzone => 6,
    };

/// Dobiera dystraktory dla litery/grafemu.
/// Stan „nowe”: bez par mylonych (łatwiejszy start). Później: najpierw pary
/// faktycznie mylone przez dziecko, potem typowo mylone, potem inne aktywne litery.
List<String> pickDistractors({
  required String target,
  required int count,
  required SkillStats stats,
  required List<String> staticConfusable,
  required List<String> activePool,
  required List<String> fullPool,
  required Random rng,
}) {
  final out = <String>[];
  void addFrom(Iterable<String> src) {
    for (final x in src) {
      if (out.length >= count) return;
      if (x != target && !out.contains(x)) out.add(x);
    }
  }

  final avoidConfusable = stats.state == MasteryState.nowe;
  if (!avoidConfusable) {
    final conf = stats.confusions.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    addFrom(conf.map((e) => e.key).where(fullPool.contains));
    addFrom(staticConfusable.where(fullPool.contains));
  }
  final rest = [...activePool]..shuffle(rng);
  addFrom(avoidConfusable ? rest.where((x) => !staticConfusable.contains(x)) : rest);
  final all = [...fullPool]..shuffle(rng);
  addFrom(avoidConfusable ? all.where((x) => !staticConfusable.contains(x)) : all);
  addFrom(all);
  return out;
}
