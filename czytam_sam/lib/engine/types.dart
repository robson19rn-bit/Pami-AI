/// Typy podstawowe silnika nauki (czysty Dart).
library;

import 'dart:math';

import '../content/models.dart';

/// Umiejętności – śledzone NIEZALEŻNIE dla każdego elementu.
enum Skill {
  /// Wskazanie litery po usłyszeniu jej NAZWY (T1/T2 – dotyk).
  recognizeName,

  /// Wskazanie litery po usłyszeniu GŁOSKI (T1 – dotyk; polecenie wymawia opiekun).
  recognizeSound,

  /// Samodzielne wypowiedzenie NAZWY litery (T2/T3 – mowa).
  sayName,

  /// Samodzielne wypowiedzenie GŁOSKI (T3 – mowa).
  saySound,

  /// Powiązanie wielkiej i małej litery (T4).
  caseMatch,

  /// Rozpoznanie głosek w usłyszanej sylabie/wyrazie i ułożenie ich (T5).
  segment,

  /// Przeczytanie sylaby/wyrazu na głos (T6 – mowa).
  readAloud,

  /// Czytanie ze zrozumieniem (T7).
  comprehension,

  /// Rozpoznanie całej sylaby/wyrazu ze słuchu – czytanie „całościowe”, bez składania liter (T8).
  recognizeUnit,
}

extension SkillInfo on Skill {
  bool get isSpeech => this == Skill.sayName || this == Skill.saySound || this == Skill.readAloud;
  String get label => switch (this) {
        Skill.recognizeName => 'wskazanie po nazwie',
        Skill.recognizeSound => 'wskazanie po głosce',
        Skill.sayName => 'nazwanie (mowa)',
        Skill.saySound => 'głoska (mowa)',
        Skill.caseMatch => 'wielka–mała',
        Skill.segment => 'głoski w sylabie',
        Skill.readAloud => 'czytanie na głos',
        Skill.comprehension => 'rozumienie',
        Skill.recognizeUnit => 'wskazanie całej sylaby/wyrazu',
      };
}

enum TaskType {
  t1HearPoint('T1 Usłysz i wskaż'),
  t2PointSay('T2 Wskaż i powiedz'),
  t3SeeName('T3 Zobacz i nazwij'),
  t4Case('T4 Wielka–mała'),
  t5Segment('T5 Które głoski słyszysz'),
  t6ReadAloud('T6 Przeczytaj na głos'),
  t7Comprehension('T7 Zrozumienie'),
  t8HearPickUnit('T8 Usłysz i wskaż sylabę/wyraz'),
  diagnosis('Diagnoza');

  const TaskType(this.label);
  final String label;
}

/// Wynik pojedynczej próby.
enum Outcome {
  correct,
  incorrect,

  /// Mikrofon nic nie usłyszał (NIE jest błędem dziecka).
  noSpeech,

  /// Wynik niepewny / problem techniczny / opiekun: „nie można ocenić”.
  uncertain,

  /// Wypowiedź była, ale nikt jej nie ocenił (brak opiekuna i brak wiarygodnego ASR).
  notEvaluated,
}

extension OutcomeLabel on Outcome {
  String get label => switch (this) {
        Outcome.correct => 'poprawnie',
        Outcome.incorrect => 'jeszcze nie',
        Outcome.noSpeech => 'nic nie usłyszano',
        Outcome.uncertain => 'niepewne',
        Outcome.notEvaluated => 'nieocenione',
      };
}

/// Źródło dowodu.
enum Evidence { touch, asr, guardian, none }

enum MasteryState {
  nowe('nowe'),
  uczone('uczone'),
  cwiczone('ćwiczone'),
  opanowaneWarunkowo('opanowane warunkowo'),
  potwierdzone('potwierdzone'),
  doPowtorzenia('do powtórzenia');

  const MasteryState(this.label);
  final String label;
  bool get isMastered => this == opanowaneWarunkowo || this == potwierdzone;
}

DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

/// Pojedyncze zdarzenie próby (dziennik tylko do dopisywania – nigdy nie nadpisywany).
class Attempt {
  Attempt({
    required this.id,
    required this.profileId,
    required this.sessionId,
    required this.at,
    required this.itemId,
    required this.kind,
    required this.skill,
    required this.task,
    required this.outcome,
    required this.evidence,
    this.hinted = false,
    this.firstTry = true,
    this.assisted = false,
    this.chosenId,
    this.responseMs,
    this.asrText,
    this.asrConfidence,
  });

  final String id, profileId, sessionId, itemId;
  final DateTime at;
  final ItemKind kind;
  final Skill skill;
  final TaskType task;
  final Outcome outcome;
  final Evidence evidence;

  /// Odpowiedź po podpowiedzi lub po pokazaniu odpowiedzi – nie jest dowodem samodzielności.
  final bool hinted;

  /// Pierwsza próba w danym zadaniu (kolejne kliknięcia w tym samym zadaniu = false).
  final bool firstTry;

  /// Materiał odblokowany ręcznie / z nieopanowanymi elementami – bez zaliczenia.
  final bool assisted;

  /// Co dziecko wybrało (np. pomylona litera).
  final String? chosenId;

  /// Czas odpowiedzi – tylko do raportu, NIE wpływa na ocenę.
  final int? responseMs;
  final String? asrText;
  final double? asrConfidence;

  Map<String, Object?> toMap() => {
        'id': id,
        'profile_id': profileId,
        'session_id': sessionId,
        'at': at.millisecondsSinceEpoch,
        'item_id': itemId,
        'item_kind': kind.name,
        'skill': skill.name,
        'task_type': task.name,
        'outcome': outcome.name,
        'evidence': evidence.name,
        'hinted': hinted ? 1 : 0,
        'first_try': firstTry ? 1 : 0,
        'assisted': assisted ? 1 : 0,
        'chosen_id': chosenId,
        'response_ms': responseMs,
        'asr_text': asrText,
        'asr_conf': asrConfidence,
      };

  factory Attempt.fromMap(Map<String, Object?> m) => Attempt(
        id: m['id'] as String,
        profileId: m['profile_id'] as String,
        sessionId: m['session_id'] as String,
        at: DateTime.fromMillisecondsSinceEpoch(m['at'] as int),
        itemId: m['item_id'] as String,
        kind: ItemKind.values.byName(m['item_kind'] as String),
        skill: Skill.values.byName(m['skill'] as String),
        task: TaskType.values.byName(m['task_type'] as String),
        outcome: Outcome.values.byName(m['outcome'] as String),
        evidence: Evidence.values.byName((m['evidence'] as String?) ?? 'touch'),
        hinted: (m['hinted'] as int? ?? 0) == 1,
        firstTry: (m['first_try'] as int? ?? 1) == 1,
        assisted: (m['assisted'] as int? ?? 0) == 1,
        chosenId: m['chosen_id'] as String?,
        responseMs: m['response_ms'] as int?,
        asrText: m['asr_text'] as String?,
        asrConfidence: (m['asr_conf'] as num?)?.toDouble(),
      );
}

enum GuardianActionType {
  /// Korekta oceny wypowiedzi (nie zmienia zapisu próby – dodaje ocenę opiekuna).
  rateSpeech,

  /// Ręczne odblokowanie etapu („ręczne, bez zaliczenia”).
  manualUnlock,

  /// Cofnięcie ręcznego odblokowania.
  revokeUnlock,
}

class GuardianAction {
  GuardianAction({
    required this.id,
    required this.profileId,
    required this.at,
    required this.type,
    this.targetId,
    this.value,
  });
  final String id, profileId;
  final DateTime at;
  final GuardianActionType type;

  /// rateSpeech: id próby; manualUnlock: nazwa etapu (syllable/word/sentence/reading).
  final String? targetId;

  /// rateSpeech: nazwa [Outcome].
  final String? value;

  Map<String, Object?> toMap() => {
        'id': id,
        'profile_id': profileId,
        'at': at.millisecondsSinceEpoch,
        'type': type.name,
        'target_id': targetId,
        'value': value,
      };
  factory GuardianAction.fromMap(Map<String, Object?> m) => GuardianAction(
        id: m['id'] as String,
        profileId: m['profile_id'] as String,
        at: DateTime.fromMillisecondsSinceEpoch(m['at'] as int),
        type: GuardianActionType.values.byName(m['type'] as String),
        targetId: m['target_id'] as String?,
        value: m['value'] as String?,
      );
}

class SessionRecord {
  SessionRecord({
    required this.id,
    required this.profileId,
    required this.startedAt,
    this.endedAt,
    this.guardianPresent = false,
    this.taskCount = 0,
  });
  final String id, profileId;
  final DateTime startedAt;
  DateTime? endedAt;
  final bool guardianPresent;
  int taskCount;

  Map<String, Object?> toMap() => {
        'id': id,
        'profile_id': profileId,
        'started_at': startedAt.millisecondsSinceEpoch,
        'ended_at': endedAt?.millisecondsSinceEpoch,
        'guardian_present': guardianPresent ? 1 : 0,
        'task_count': taskCount,
      };
  factory SessionRecord.fromMap(Map<String, Object?> m) => SessionRecord(
        id: m['id'] as String,
        profileId: m['profile_id'] as String,
        startedAt: DateTime.fromMillisecondsSinceEpoch(m['started_at'] as int),
        endedAt: m['ended_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch(m['ended_at'] as int),
        guardianPresent: (m['guardian_present'] as int? ?? 0) == 1,
        taskCount: m['task_count'] as int? ?? 0,
      );
}

/// Generator unikalnych identyfikatorów zdarzeń (unikalnych także między urządzeniami).
class IdGen {
  IdGen([Random? random]) : _r = random ?? Random.secure();
  final Random _r;
  String next(String prefix) => '$prefix-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
      '${_r.nextInt(1 << 32).toRadixString(36)}${_r.nextInt(1 << 32).toRadixString(36)}';
}
