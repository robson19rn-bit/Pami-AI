/// Dostępność materiału: które litery są w nauce, które sylaby/wyrazy/zdania
/// można podać dziecku. Zasada: nie wymagamy całego alfabetu przed sylabami,
/// ale każda jednostka wymaga opanowania KONKRETNYCH głosek, które ją tworzą.
library;

import '../content/models.dart';
import 'mastery.dart';
import 'types.dart';

enum Access {
  locked,

  /// Wszystkie wymagane głoski opanowane (rozpoznanie + potwierdzona wymowa) – także czytanie na głos.
  available,

  /// Głoski rozpoznawane ze słuchu, wymowa jeszcze niepotwierdzona: tylko zadania „słuchaj i wskaż”
  /// oraz układanie (bez czytania na głos). Wynik liczy się do postępów.
  receptive,

  /// Etap odblokowany ręcznie przez opiekuna, jednostka zawiera nieopanowane
  /// elementy: „materiał z pomocą – ręczne, bez zaliczenia”.
  manualAssisted,
}

class UnitAccess {
  UnitAccess(this.unit, this.access, this.missing);
  final ReadingUnit unit;
  final Access access;

  /// Grafemy jeszcze nieopanowane (do wyjaśnienia / oznaczenia).
  final List<String> missing;
}

class Curriculum {
  Curriculum(this.content, this.index, {this.knownFromDiagnosis = const {}, this.manualStages = const {}});

  final ContentBundle content;
  final ProgressIndex index;

  /// Litery wskazane w diagnozie jako znane (wprowadzane od razu).
  final Set<String> knownFromDiagnosis;

  /// Etapy odblokowane ręcznie (ItemKind.syllable / word / sentence / reading).
  final Set<ItemKind> manualStages;

  MasteryConfig get config => index.config;

  bool _letterStarted(String id) =>
      knownFromDiagnosis.contains(id) ||
      index.stats.values.any((s) => s.itemId == id && s.practiceAttempts > 0);

  /// Litera „oswojona”: dziecko pewnie ją rozpoznaje (≥3 samodzielne próby, ≥80% z ostatnich 5 poprawnych)
  /// albo już ją opanowało. Wystarcza to do wprowadzenia kolejnej litery – pełne opanowanie
  /// i potwierdzenie w kolejnych dniach odbywają się równolegle, w powtórkach.
  bool letterFamiliar(String id) {
    final skills = [Skill.recognizeName, Skill.recognizeSound, Skill.caseMatch];
    if (skills.any((sk) => index.of(id, sk).state.isMastered)) return true;
    // Łącznie ze wszystkich zadań rozpoznawania (kolejność chronologiczna nie jest tu istotna).
    final all = [for (final sk in skills) ...index.of(id, sk).validResults];
    if (all.length < 3) return false;
    final w = all.length > 6 ? all.sublist(all.length - 6) : all;
    return w.where((x) => x).length / w.length >= 0.8;
  }

  /// Litery w nauce: rozpoczęte (lub znane z diagnozy) + kolejne nowe, tak by naraz było najwyżej
  /// [MasteryConfig.maxActiveNewLetters] liter, których dziecko jeszcze pewnie nie rozpoznaje.
  /// Dziecko, które zna litery, przechodzi więc szybko przez cały alfabet.
  List<Letter> activeLetters() {
    final ordered = content.lettersInOrder;
    final active = <Letter>[];
    var unfamiliar = 0;
    for (final l in ordered) {
      if (_letterStarted(l.id)) {
        active.add(l);
        if (!letterFamiliar(l.id)) unfamiliar++;
      }
    }
    for (final l in ordered) {
      if (unfamiliar >= config.maxActiveNewLetters) break;
      if (active.contains(l)) continue;
      active.add(l);
      unfamiliar++;
    }
    return active;
  }

  /// Litera „poznana”: pewnie rozpoznawana ORAZ jej głoska pewnie rozpoznawana ze słuchu
  /// (głoski są potrzebne od pierwszej sylaby).
  bool letterKnown(String id) => letterFamiliar(id) && graphemeHeard(id);

  /// Cały alfabet poznany: wszystkie 32 litery (nazwa/kształt i głoska) pewnie rozpoznawane.
  bool get alphabetComplete => content.letters.every((l) => letterKnown(l.id));

  /// Czego brakuje do poznania litery – do priorytetu w lekcji.
  Map<String, Set<Skill>> lettersFocus() => {
        for (final l in activeLetters())
          if (!letterKnown(l.id))
            l.id: letterFamiliar(l.id) ? {Skill.recognizeSound} : {Skill.recognizeName, Skill.recognizeSound, Skill.caseMatch}
      };

  /// Litery jeszcze niepoznane (do panelu opiekuna i do priorytetu w lekcji).
  List<Letter> lettersNotYetFamiliar() => [for (final l in content.lettersInOrder) if (!letterKnown(l.id)) l];

  /// Czy etap liter blokuje dalszą część (ustawienie „najpierw cały alfabet”).
  bool get lettersStageOnly => config.alphabetFirst && !alphabetComplete;

  /// Dwuznaki i zmiękczenia: dostępne, gdy litery składowe mają gotowe głoski (i – przy ustawieniu
  /// „najpierw cały alfabet” – po poznaniu całego alfabetu).
  List<Grapheme> activeGraphemes() => lettersStageOnly ? const [] : [
        for (final g in content.graphemes)
          if (g.letters.every(index.soundReady)) g
      ];

  bool graphemeReady(String g) => index.soundReady(g);

  /// Głoska pewnie rozpoznawana ze słuchu (≥3 samodzielne próby, ≥80% z ostatnich 5, albo opanowana) –
  /// wystarcza do zadań „słuchaj i wskaż sylabę”, które same są ćwiczeniem o niskim ryzyku.
  bool graphemeHeard(String g) {
    final st = index.of(g, Skill.recognizeSound);
    if (st.state.isMastered) return true;
    final v = st.validResults;
    if (v.length < 3) return false;
    final w = v.length > 5 ? v.sublist(v.length - 5) : v;
    return w.where((x) => x).length / w.length >= 0.8;
  }

  int _countMastered(Iterable<ReadingUnit> units, List<Skill> skills) =>
      units.where((u) => skills.any((s) => index.mastered(u.id, s))).length;

  static const _receptiveSkills = [Skill.segment, Skill.recognizeUnit, Skill.readAloud];

  /// Czy etap osiągnięty z wyników dziecka. [spoken] – wersja z czytaniem na głos.
  bool stageReached(ItemKind kind, {bool spoken = true}) => switch (kind) {
        ItemKind.syllable => true, // każda sylaba ma własne wymagania głoskowe
        ItemKind.word => _countMastered(content.pool(ItemKind.syllable), spoken ? [Skill.readAloud, Skill.segment] : _receptiveSkills) >=
            config.syllablesBeforeWords,
        ItemKind.sentence =>
          _countMastered(content.pool(ItemKind.word), spoken ? [Skill.readAloud] : [Skill.readAloud, Skill.recognizeUnit]) >= config.wordsBeforeSentences,
        ItemKind.reading => _countMastered(content.pool(ItemKind.sentence), [Skill.comprehension]) >= config.sentencesBeforeReadings,
        _ => true,
      };

  UnitAccess accessOf(ReadingUnit u) {
    final missing = [for (final g in u.graphemes) if (!graphemeReady(g)) g];
    if (u.needsReview) return UnitAccess(u, Access.locked, missing);
    if (lettersStageOnly && !manualStages.contains(u.kind)) return UnitAccess(u, Access.locked, missing);
    if (missing.isEmpty && stageReached(u.kind)) return UnitAccess(u, Access.available, missing);
    final unheard = [for (final g in u.graphemes) if (!graphemeHeard(g)) g];
    if (unheard.isEmpty && stageReached(u.kind, spoken: false)) return UnitAccess(u, Access.receptive, missing);
    if (manualStages.contains(u.kind)) return UnitAccess(u, Access.manualAssisted, missing);
    return UnitAccess(u, Access.locked, missing);
  }

  List<UnitAccess> units(ItemKind kind, {bool includeLocked = false}) => [
        for (final u in content.pool(kind))
          if (includeLocked || accessOf(u).access != Access.locked) accessOf(u)
      ];

  /// Postęp do kolejnego etapu – dla panelu opiekuna.
  Map<String, String> stageProgress() {
    final syl = units(ItemKind.syllable);
    final c = config;
    final notYet = lettersNotYetFamiliar();
    return {
      'Alfabet (pewnie rozpoznawane litery)': '${32 - notYet.length} z 32'
          '${notYet.isEmpty ? ' – cały alfabet poznany' : '; jeszcze: ${notYet.map((l) => l.lower).join(' ')}'}'
          '${c.alphabetFirst && notYet.isNotEmpty ? ' (sylaby po poznaniu całego alfabetu)' : ''}',
      'Litery w nauce': activeLetters().map((l) => l.upper).join(' '),
      'Głoski gotowe do łączenia': [for (final l in content.lettersInOrder) if (index.soundReady(l.id)) l.lower].join(' '),
      'Sylaby do słuchania i wskazywania': '${syl.where((u) => u.access != Access.locked).length} z ${content.pool(ItemKind.syllable).length}',
      'Sylaby do czytania na głos (wymowa potwierdzona)': '${syl.where((u) => u.access == Access.available).length}',
      'Czeka na ocenę wypowiedzi z opiekunem': () {
        final w = [
          for (final l in content.lettersInOrder)
            if (index.mastered(l.id, Skill.recognizeSound) && !index.mastered(l.id, Skill.saySound)) l.lower
        ];
        return w.isEmpty ? 'nic – można ćwiczyć dalej samodzielnie' : 'głoski: ${w.join(' ')} (rozpoznawane ze słuchu, trzeba potwierdzić wymowę)';
      }(),
      'Do wyrazów': '${_countMastered(content.pool(ItemKind.syllable), _receptiveSkills)}/${c.syllablesBeforeWords} sylab opanowanych',
      'Do zdań': '${_countMastered(content.pool(ItemKind.word), [Skill.readAloud, Skill.recognizeUnit])}/${c.wordsBeforeSentences} wyrazów opanowanych',
      'Do czytanek': '${_countMastered(content.pool(ItemKind.sentence), [Skill.comprehension])}/${c.sentencesBeforeReadings} zdań zrozumianych',
    };
  }
}
