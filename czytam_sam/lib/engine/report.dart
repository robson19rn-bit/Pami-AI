/// Raport opiekuna – liczy dokładnie z dziennika prób, bez zacierania różnic
/// między odpowiedziami samodzielnymi, po podpowiedzi, błędnymi i niepewnymi.
library;

import 'mastery.dart';
import 'types.dart';

enum ReportCategory {
  independentCorrect('poprawne samodzielnie'),
  hintedCorrect('poprawne po podpowiedzi / z pomocą'),
  incorrect('błędne'),
  noSpeech('nic nie usłyszano'),
  uncertain('niepewne / nie można ocenić'),
  notEvaluated('wypowiedź nieoceniona');

  const ReportCategory(this.label);
  final String label;
}

ReportCategory categorize(Attempt a, Outcome eff) {
  switch (eff) {
    case Outcome.correct:
      return isValidEvidence(a, eff) ? ReportCategory.independentCorrect : ReportCategory.hintedCorrect;
    case Outcome.incorrect:
      return ReportCategory.incorrect;
    case Outcome.noSpeech:
      return ReportCategory.noSpeech;
    case Outcome.uncertain:
      return ReportCategory.uncertain;
    case Outcome.notEvaluated:
      return ReportCategory.notEvaluated;
  }
}

class Tally {
  final Map<ReportCategory, int> counts = {for (final c in ReportCategory.values) c: 0};
  int get total => counts.values.fold(0, (a, b) => a + b);
  void add(ReportCategory c) => counts[c] = counts[c]! + 1;
  int operator [](ReportCategory c) => counts[c]!;
}

class SpeechTally {
  int confirmedByGuardian = 0, confirmedByAsr = 0, judgedIncorrect = 0, unconfirmed = 0;
}

class GuardianReport {
  final Tally total = Tally();
  final Map<DateTime, Tally> byDay = {};
  final Map<DateTime, Duration> sessionTimeByDay = {};
  final Map<DateTime, int> sessionsByDay = {};
  final SpeechTally speech = SpeechTally();

  /// (cel, wybrane) → liczba pomyłek
  final Map<(String, String), int> confusions = {};
  int hintedAttempts = 0, hintedCorrect = 0, independentAttempts = 0, independentCorrect = 0;

  double? get accuracyAfterHint => hintedAttempts == 0 ? null : hintedCorrect / hintedAttempts;
  double? get accuracyIndependent => independentAttempts == 0 ? null : independentCorrect / independentAttempts;
}

GuardianReport buildReport(List<Attempt> attempts, List<GuardianAction> actions, List<SessionRecord> sessions) {
  final r = GuardianReport();
  final ov = speechOverrides(actions);
  for (final a in attempts) {
    final eff = effectiveOutcome(a, ov);
    final cat = categorize(a, eff);
    r.total.add(cat);
    (r.byDay[dayOf(a.at)] ??= Tally()).add(cat);
    if (eff == Outcome.incorrect && a.chosenId != null && a.chosenId != a.itemId && !a.chosenId!.contains('+')) {
      final k = (a.itemId, a.chosenId!);
      r.confusions[k] = (r.confusions[k] ?? 0) + 1;
    }
    if (eff == Outcome.correct || eff == Outcome.incorrect) {
      if (a.hinted || a.assisted || !a.firstTry) {
        r.hintedAttempts++;
        if (eff == Outcome.correct) r.hintedCorrect++;
      } else {
        r.independentAttempts++;
        if (eff == Outcome.correct) r.independentCorrect++;
      }
    }
    if (a.skill.isSpeech) {
      final byGuardian = ov.containsKey(a.id) || a.evidence == Evidence.guardian;
      if (eff == Outcome.correct) {
        byGuardian ? r.speech.confirmedByGuardian++ : r.speech.confirmedByAsr++;
      } else if (eff == Outcome.incorrect) {
        r.speech.judgedIncorrect++;
      } else {
        r.speech.unconfirmed++;
      }
    }
  }
  for (final s in sessions) {
    final d = dayOf(s.startedAt);
    r.sessionsByDay[d] = (r.sessionsByDay[d] ?? 0) + 1;
    if (s.endedAt != null) {
      r.sessionTimeByDay[d] = (r.sessionTimeByDay[d] ?? Duration.zero) + s.endedAt!.difference(s.startedAt);
    }
  }
  return r;
}
