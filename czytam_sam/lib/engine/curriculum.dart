/// Dostępność materiału: które litery są w nauce, które sylaby/wyrazy/zdania
/// można podać dziecku. Zasada: nie wymagamy całego alfabetu przed sylabami,
/// ale każda jednostka wymaga opanowania KONKRETNYCH głosek, które ją tworzą.
library;

import '../content/models.dart';
import 'mastery.dart';
import 'types.dart';

enum Access {
  locked,

  /// Wszystkie wymagane głoski opanowane – wynik liczy się do postępów.
  available,

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

  bool _letterSettled(String id) =>
      index.mastered(id, Skill.recognizeName) && index.mastered(id, Skill.recognizeSound);

  /// Litery aktualnie w nauce: rozpoczęte + kolejne nowe, tak by naraz uczyć
  /// najwyżej [MasteryConfig.maxActiveNewLetters] nieutrwalonych liter.
  List<Letter> activeLetters() {
    final ordered = content.lettersInOrder;
    final active = <Letter>[];
    var unsettled = 0;
    for (final l in ordered) {
      if (_letterStarted(l.id)) {
        active.add(l);
        if (!_letterSettled(l.id)) unsettled++;
      }
    }
    for (final l in ordered) {
      if (unsettled >= config.maxActiveNewLetters) break;
      if (active.contains(l)) continue;
      active.add(l);
      unsettled++;
    }
    return active;
  }

  /// Dwuznaki i zmiękczenia: dostępne, gdy litery składowe mają gotowe głoski.
  List<Grapheme> activeGraphemes() => [
        for (final g in content.graphemes)
          if (g.letters.every(index.soundReady)) g
      ];

  bool graphemeReady(String g) => index.soundReady(g);

  int _countMastered(Iterable<ReadingUnit> units, List<Skill> skills) =>
      units.where((u) => skills.any((s) => index.mastered(u.id, s))).length;

  /// Czy etap (jako całość) jest osiągnięty z wyników dziecka.
  bool stageReached(ItemKind kind) => switch (kind) {
        ItemKind.syllable => true, // każda sylaba ma własne wymagania głoskowe
        ItemKind.word => _countMastered(content.pool(ItemKind.syllable), [Skill.readAloud, Skill.segment]) >= config.syllablesBeforeWords,
        ItemKind.sentence => _countMastered(content.pool(ItemKind.word), [Skill.readAloud]) >= config.wordsBeforeSentences,
        ItemKind.reading => _countMastered(content.pool(ItemKind.sentence), [Skill.comprehension]) >= config.sentencesBeforeReadings,
        _ => true,
      };

  UnitAccess accessOf(ReadingUnit u) {
    final missing = [for (final g in u.graphemes) if (!graphemeReady(g)) g];
    if (u.needsReview) return UnitAccess(u, Access.locked, missing);
    final reached = stageReached(u.kind);
    if (missing.isEmpty && reached) return UnitAccess(u, Access.available, missing);
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
    return {
      'Litery w nauce': activeLetters().map((l) => l.upper).join(' '),
      'Głoski gotowe do łączenia': [for (final l in content.lettersInOrder) if (index.soundReady(l.id)) l.lower].join(' '),
      'Dostępne sylaby': '${syl.where((u) => u.access == Access.available).length} z ${content.pool(ItemKind.syllable).length}',
      'Do wyrazów': '${_countMastered(content.pool(ItemKind.syllable), [Skill.readAloud, Skill.segment])}/${c.syllablesBeforeWords} sylab opanowanych',
      'Do zdań': '${_countMastered(content.pool(ItemKind.word), [Skill.readAloud])}/${c.wordsBeforeSentences} wyrazów przeczytanych samodzielnie',
      'Do czytanek': '${_countMastered(content.pool(ItemKind.sentence), [Skill.comprehension])}/${c.sentencesBeforeReadings} zdań zrozumianych',
    };
  }
}
