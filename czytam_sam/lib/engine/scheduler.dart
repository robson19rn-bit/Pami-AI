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
  });

  /// Opiekun jest obok (może wymówić głoskę i ocenić wypowiedź).
  final bool guardianPresent;

  /// Polski lektor działa (sprawdzone przy konfiguracji).
  final bool ttsOk;

  /// Lokalny model rozpoznawania mowy zainstalowany i jest uprawnienie mikrofonu.
  final bool asrReady;

  /// Jednostki, które lektor czyta błędnie (oznaczone przez opiekuna).
  final Set<String> ttsBadUnits;

  bool canSpeak(String unitId) => ttsOk && !ttsBadUnits.contains(unitId);
}

class Candidate {
  Candidate(this.itemId, this.kind, this.skill, this.task, {this.assisted = false});
  final String itemId;
  final ItemKind kind;
  final Skill skill;
  final TaskType task;
  final bool assisted;
  @override
  String toString() => '$itemId/${skill.name}/${task.name}';
}

class Planned {
  Planned(this.candidate, this.bucket);
  final Candidate candidate;
  final Bucket bucket;
}

/// Generuje kandydatów zgodnie z etapem i możliwościami.
List<Candidate> buildCandidates(Curriculum cur, Capabilities cap) {
  final out = <Candidate>[];
  final g = cap.guardianPresent;
  for (final l in cur.activeLetters()) {
    final canPromptName = cap.canSpeak(l.id) || g;
    if (canPromptName) {
      out.add(Candidate(l.id, ItemKind.letter, Skill.recognizeName, TaskType.t1HearPoint));
      // T2: dotyk liczony zawsze; wypowiedź oceniana tylko przez opiekuna.
      out.add(Candidate(l.id, ItemKind.letter, Skill.recognizeName, TaskType.t2PointSay));
    }
    out.add(Candidate(l.id, ItemKind.letter, Skill.caseMatch, TaskType.t4Case));
    if (g) {
      // Pojedyncze głoski: tylko opiekun (brak zweryfikowanych nagrań).
      out.add(Candidate(l.id, ItemKind.letter, Skill.recognizeSound, TaskType.t1HearPoint));
      out.add(Candidate(l.id, ItemKind.letter, Skill.sayName, TaskType.t3SeeName));
      out.add(Candidate(l.id, ItemKind.letter, Skill.saySound, TaskType.t3SeeName));
    }
  }
  if (g) {
    for (final gr in cur.activeGraphemes()) {
      out.add(Candidate(gr.id, ItemKind.grapheme, Skill.recognizeSound, TaskType.t1HearPoint));
      out.add(Candidate(gr.id, ItemKind.grapheme, Skill.saySound, TaskType.t3SeeName));
    }
  }
  final canJudgeReading = g || cap.asrReady;
  for (final ua in cur.units(ItemKind.syllable)) {
    final a = ua.access == Access.manualAssisted;
    if (cap.canSpeak(ua.unit.id) || g) out.add(Candidate(ua.unit.id, ItemKind.syllable, Skill.segment, TaskType.t5Segment, assisted: a));
    if (canJudgeReading) out.add(Candidate(ua.unit.id, ItemKind.syllable, Skill.readAloud, TaskType.t6ReadAloud, assisted: a));
  }
  for (final ua in cur.units(ItemKind.word)) {
    final a = ua.access == Access.manualAssisted;
    if (canJudgeReading) out.add(Candidate(ua.unit.id, ItemKind.word, Skill.readAloud, TaskType.t6ReadAloud, assisted: a));
    if (ua.unit.graphemes.length <= 4 && tokenCount(ua.unit) <= 5 && (cap.canSpeak(ua.unit.id) || g)) {
      out.add(Candidate(ua.unit.id, ItemKind.word, Skill.segment, TaskType.t5Segment, assisted: a));
    }
  }
  for (final k in [ItemKind.sentence, ItemKind.reading]) {
    for (final ua in cur.units(k)) {
      out.add(Candidate(ua.unit.id, k, Skill.comprehension, TaskType.t7Comprehension, assisted: ua.access == Access.manualAssisted));
    }
  }
  return out;
}

int tokenCount(ReadingUnit u) => u.text.replaceAll(RegExp(r'[^a-ząćęłńóśźż]', caseSensitive: false), '').length;

Bucket bucketOf(SkillStats s, DateTime now) {
  final st = s.state;
  if (st == MasteryState.doPowtorzenia) return Bucket.due;
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
}) {
  if (candidates.isEmpty || n <= 0) return [];
  final c = index.config;
  final buckets = {for (final b in Bucket.values) b: <Candidate>[]};
  for (final cand in candidates) {
    buckets[bucketOf(index.of(cand.itemId, cand.skill), now)]!.add(cand);
  }
  // Priorytety w koszykach (stabilne sortowanie po kluczu + losowy remis).
  final tiebreak = {for (final cand in candidates) cand.toString(): rng.nextDouble()};
  int byTie(Candidate a, Candidate b) => tiebreak[a.toString()]!.compareTo(tiebreak[b.toString()]!);
  buckets[Bucket.due]!.sort((a, b) {
    final sa = index.of(a.itemId, a.skill), sb = index.of(b.itemId, b.skill);
    final ra = sa.state == MasteryState.doPowtorzenia ? 0 : 1, rb = sb.state == MasteryState.doPowtorzenia ? 0 : 1;
    if (ra != rb) return ra - rb;
    final aa = sa.recentAccuracy ?? 1, ab = sb.recentAccuracy ?? 1;
    if (aa != ab) return aa.compareTo(ab);
    return byTie(a, b);
  });
  buckets[Bucket.current]!.sort((a, b) {
    final sa = index.of(a.itemId, a.skill), sb = index.of(b.itemId, b.skill);
    if (sa.state.index != sb.state.index) return sb.state.index - sa.state.index; // najpierw rozpoczęte
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
  Candidate? take(Bucket b) {
    final list = buckets[b]!;
    if (list.isEmpty) return null;
    final cand = list[cursor[b]! % list.length];
    cursor[b] = cursor[b]! + 1;
    return cand;
  }

  // Najpierw kwoty, potem dopełnienie z koszyków niepustych.
  for (final b in Bucket.values) {
    for (var i = 0; i < quota[b]! && buckets[b]!.isNotEmpty; i++) {
      // nie powielaj w kwocie, jeśli koszyk krótszy niż kwota – oddaj resztę innym
      if (cursor[b]! >= buckets[b]!.length) break;
      picked.add(Planned(take(b)!, b));
    }
  }
  final order = [Bucket.due, Bucket.current, Bucket.consolidation];
  var guard = 0;
  while (picked.length < n && guard++ < n * 10) {
    for (final b in order) {
      if (picked.length >= n) break;
      final cand = take(b);
      if (cand != null) picked.add(Planned(cand, b));
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
    var idx = pool.indexWhere((p) => p.candidate.itemId != prev);
    if (idx < 0) idx = 0;
    final p = pool.removeAt(idx);
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
