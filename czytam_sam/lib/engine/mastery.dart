/// Ocena opanowania – jawny, deterministyczny algorytm.
///
/// Parametry są KONFIGUROWALNE i nie stanowią uniwersalnej normy naukowej.
library;

import 'types.dart';

class MasteryConfig {
  const MasteryConfig({
    this.recognitionMinAttempts = 10,
    this.recognitionWindow = 10,
    this.recognitionMinAccuracy = 0.8,
    this.speechMinAttempts = 5,
    this.speechWindow = 5,
    this.speechMinCorrect = 4,
    this.minSessions = 2,
    this.minDays = 2,
    this.recoverStreak = 2,
    this.shareDue = 0.60,
    this.shareCurrent = 0.25,
    this.shareConsolidation = 0.15,
    this.maxActiveNewLetters = 4,
    this.syllablesBeforeWords = 3,
    this.wordsBeforeSentences = 5,
    this.sentencesBeforeReadings = 3,
    this.sessionLength = 12,
  });

  final int recognitionMinAttempts, recognitionWindow;
  final double recognitionMinAccuracy;
  final int speechMinAttempts, speechWindow, speechMinCorrect;
  final int minSessions, minDays, recoverStreak;
  final double shareDue, shareCurrent, shareConsolidation;
  final int maxActiveNewLetters, syllablesBeforeWords, wordsBeforeSentences, sentencesBeforeReadings;
  final int sessionLength;

  Map<String, Object> toJson() => {
        'recognitionMinAttempts': recognitionMinAttempts,
        'recognitionWindow': recognitionWindow,
        'recognitionMinAccuracy': recognitionMinAccuracy,
        'speechMinAttempts': speechMinAttempts,
        'speechWindow': speechWindow,
        'speechMinCorrect': speechMinCorrect,
        'minSessions': minSessions,
        'minDays': minDays,
        'recoverStreak': recoverStreak,
        'shareDue': shareDue,
        'shareCurrent': shareCurrent,
        'shareConsolidation': shareConsolidation,
        'maxActiveNewLetters': maxActiveNewLetters,
        'syllablesBeforeWords': syllablesBeforeWords,
        'wordsBeforeSentences': wordsBeforeSentences,
        'sentencesBeforeReadings': sentencesBeforeReadings,
        'sessionLength': sessionLength,
      };

  factory MasteryConfig.fromJson(Map<String, dynamic> j) {
    const d = MasteryConfig();
    int i(String k, int def) => (j[k] as num?)?.toInt() ?? def;
    double f(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    return MasteryConfig(
      recognitionMinAttempts: i('recognitionMinAttempts', d.recognitionMinAttempts),
      recognitionWindow: i('recognitionWindow', d.recognitionWindow),
      recognitionMinAccuracy: f('recognitionMinAccuracy', d.recognitionMinAccuracy),
      speechMinAttempts: i('speechMinAttempts', d.speechMinAttempts),
      speechWindow: i('speechWindow', d.speechWindow),
      speechMinCorrect: i('speechMinCorrect', d.speechMinCorrect),
      minSessions: i('minSessions', d.minSessions),
      minDays: i('minDays', d.minDays),
      recoverStreak: i('recoverStreak', d.recoverStreak),
      shareDue: f('shareDue', d.shareDue),
      shareCurrent: f('shareCurrent', d.shareCurrent),
      shareConsolidation: f('shareConsolidation', d.shareConsolidation),
      maxActiveNewLetters: i('maxActiveNewLetters', d.maxActiveNewLetters),
      syllablesBeforeWords: i('syllablesBeforeWords', d.syllablesBeforeWords),
      wordsBeforeSentences: i('wordsBeforeSentences', d.wordsBeforeSentences),
      sentencesBeforeReadings: i('sentencesBeforeReadings', d.sentencesBeforeReadings),
      sessionLength: i('sessionLength', d.sessionLength),
    );
  }
}

/// Skuteczny wynik próby: ocena opiekuna (dodana później) ma pierwszeństwo,
/// ale oryginalna próba pozostaje bez zmian.
Outcome effectiveOutcome(Attempt a, Map<String, Outcome> overrides) => overrides[a.id] ?? a.outcome;

/// Czy próba liczy się do statystyki samodzielnej poprawności.
/// Wykluczone: próby po podpowiedzi, nie-pierwsze kliknięcia, materiał z pomocą,
/// brak wykrycia mowy, wyniki niepewne i nieocenione.
bool isValidEvidence(Attempt a, Outcome eff) =>
    a.firstTry && !a.hinted && !a.assisted && (eff == Outcome.correct || eff == Outcome.incorrect);

class SkillStats {
  SkillStats(this.itemId, this.skill);
  final String itemId;
  final Skill skill;

  int totalAttempts = 0;
  int firstAttempts = 0;
  int independentCorrect = 0;
  int independentErrors = 0;
  int hintedCorrect = 0;
  int hintedOrAssisted = 0;
  int noSpeech = 0;
  int uncertain = 0;
  int notEvaluated = 0;
  int guardianRated = 0;
  int asrRated = 0;
  final Map<String, int> confusions = {};
  final Set<String> sessionsWithCorrect = {};
  final Set<DateTime> daysWithCorrect = {};
  final List<DateTime> history = [];
  final List<bool> validResults = [];
  int responseMsSum = 0, responseMsCount = 0;
  DateTime? lastAttemptAt;
  DateTime? masteredDay;
  MasteryState state = MasteryState.nowe;
  DateTime? dueAt;

  double? get recentAccuracy {
    if (validResults.isEmpty) return null;
    final w = validResults.length > 10 ? validResults.sublist(validResults.length - 10) : validResults;
    return w.where((x) => x).length / w.length;
  }

  int? get avgResponseMs => responseMsCount == 0 ? null : responseMsSum ~/ responseMsCount;
}

bool _thresholdMet(Skill skill, List<bool> valid, MasteryConfig c) {
  if (skill.isSpeech) {
    if (valid.length < c.speechMinAttempts) return false;
    final w = valid.sublist(valid.length - c.speechWindow.clamp(1, valid.length));
    return w.where((x) => x).length >= c.speechMinCorrect;
  }
  if (valid.length < c.recognitionMinAttempts) return false;
  final w = valid.sublist(valid.length - c.recognitionWindow.clamp(1, valid.length));
  return w.where((x) => x).length / w.length >= c.recognitionMinAccuracy;
}

/// Liczy statystyki i stan dla jednej pary (element, umiejętność).
/// [attempts] – wszystkie próby tej pary (dowolna kolejność).
SkillStats computeSkillStats(
  String itemId,
  Skill skill,
  Iterable<Attempt> attempts,
  Map<String, Outcome> overrides,
  MasteryConfig c,
) {
  final s = SkillStats(itemId, skill);
  final list = attempts.toList()..sort((a, b) => a.at.compareTo(b.at));
  final valid = <bool>[];
  var lapse = false;
  var streak = 0;
  for (final a in list) {
    final eff = effectiveOutcome(a, overrides);
    s.totalAttempts++;
    s.history.add(a.at);
    s.lastAttemptAt = a.at;
    if (a.firstTry) s.firstAttempts++;
    if (a.responseMs != null) {
      s.responseMsSum += a.responseMs!;
      s.responseMsCount++;
    }
    if (overrides.containsKey(a.id) || a.evidence == Evidence.guardian) {
      s.guardianRated++;
    } else if (a.evidence == Evidence.asr) {
      s.asrRated++;
    }
    switch (eff) {
      case Outcome.noSpeech:
        s.noSpeech++;
      case Outcome.uncertain:
        s.uncertain++;
      case Outcome.notEvaluated:
        s.notEvaluated++;
      case Outcome.incorrect:
        if (a.chosenId != null && a.chosenId != itemId) {
          s.confusions[a.chosenId!] = (s.confusions[a.chosenId!] ?? 0) + 1;
        }
      case Outcome.correct:
        break;
    }
    if (a.hinted || a.assisted || !a.firstTry) {
      s.hintedOrAssisted++;
      if (eff == Outcome.correct) s.hintedCorrect++;
    }
    if (!isValidEvidence(a, eff)) continue;

    final ok = eff == Outcome.correct;
    valid.add(ok);
    if (ok) {
      s.independentCorrect++;
      s.sessionsWithCorrect.add(a.sessionId);
      s.daysWithCorrect.add(dayOf(a.at));
    } else {
      s.independentErrors++;
    }
    final day = dayOf(a.at);
    final met = _thresholdMet(skill, valid, c);
    if (lapse) {
      streak = ok ? streak + 1 : 0;
      if (streak >= c.recoverStreak && met) {
        lapse = false;
        s.masteredDay = day;
      }
    } else if (s.masteredDay != null && !ok && day.isAfter(s.masteredDay!)) {
      // Pomyłka w kolejnym dniu po opanowaniu → do powtórek.
      lapse = true;
      streak = 0;
    } else if (met && s.masteredDay == null) {
      s.masteredDay = day;
    }
  }
  s.validResults.addAll(valid);

  final met = _thresholdMet(skill, valid, c);
  if (list.isEmpty) {
    s.state = MasteryState.nowe;
  } else if (lapse) {
    s.state = MasteryState.doPowtorzenia;
  } else if (met && s.masteredDay != null) {
    final laterCorrect = s.daysWithCorrect.any((d) => d.isAfter(s.masteredDay!));
    final confirmed = s.sessionsWithCorrect.length >= c.minSessions && s.daysWithCorrect.length >= c.minDays && laterCorrect;
    s.state = confirmed ? MasteryState.potwierdzone : MasteryState.opanowaneWarunkowo;
  } else {
    final acc = s.recentAccuracy ?? 0;
    s.state = (valid.length < 3 || acc < 0.5) ? MasteryState.uczone : MasteryState.cwiczone;
  }

  // Plan powtórek.
  final last = s.lastAttemptAt;
  if (last == null) {
    s.dueAt = null;
  } else {
    final base = dayOf(last);
    s.dueAt = switch (s.state) {
      MasteryState.nowe || MasteryState.uczone || MasteryState.doPowtorzenia => last,
      MasteryState.cwiczone => base.add(const Duration(days: 1)),
      MasteryState.opanowaneWarunkowo => base.add(const Duration(days: 1)),
      MasteryState.potwierdzone => base.add(const Duration(days: 4)),
    };
  }
  return s;
}

/// Indeks wszystkich statystyk profilu.
class ProgressIndex {
  ProgressIndex(this.stats, this.config);
  final Map<String, SkillStats> stats;
  final MasteryConfig config;

  static String key(String itemId, Skill skill) => '$itemId|${skill.name}';

  SkillStats of(String itemId, Skill skill) => stats[key(itemId, skill)] ?? SkillStats(itemId, skill);
  MasteryState state(String itemId, Skill skill) => of(itemId, skill).state;
  bool mastered(String itemId, Skill skill) => state(itemId, skill).isMastered;

  /// Gotowość głoski do łączenia: rozpoznanie głoski ze słuchu ORAZ jej samodzielne wypowiedzenie.
  bool soundReady(String graphemeId) =>
      mastered(graphemeId, Skill.recognizeSound) && mastered(graphemeId, Skill.saySound);

  /// Pełna znajomość litery: wszystkie podumiejętności, w tym mowa.
  bool letterFullyMastered(String id) =>
      mastered(id, Skill.recognizeName) &&
      mastered(id, Skill.sayName) &&
      mastered(id, Skill.recognizeSound) &&
      mastered(id, Skill.saySound) &&
      mastered(id, Skill.caseMatch);

  static ProgressIndex build(List<Attempt> attempts, List<GuardianAction> actions, MasteryConfig c) {
    final overrides = speechOverrides(actions);
    final groups = <String, List<Attempt>>{};
    for (final a in attempts) {
      (groups[key(a.itemId, a.skill)] ??= []).add(a);
    }
    final stats = <String, SkillStats>{};
    groups.forEach((k, list) {
      stats[k] = computeSkillStats(list.first.itemId, list.first.skill, list, overrides, c);
    });
    return ProgressIndex(stats, c);
  }
}

/// Oceny opiekuna dodane później (ostatnia ocena danej próby wygrywa).
Map<String, Outcome> speechOverrides(List<GuardianAction> actions) {
  final sorted = [...actions]..sort((a, b) => a.at.compareTo(b.at));
  final m = <String, Outcome>{};
  for (final a in sorted) {
    if (a.type == GuardianActionType.rateSpeech && a.targetId != null && a.value != null) {
      m[a.targetId!] = Outcome.values.byName(a.value!);
    }
  }
  return m;
}
