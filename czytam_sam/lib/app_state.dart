/// Stan aplikacji: łączy materiał, bazę postępów, silnik i usługi audio.
library;

import 'dart:math';

import 'package:flutter/foundation.dart';

import 'content/models.dart';
import 'data/backup.dart';
import 'data/database.dart';
import 'engine/curriculum.dart';
import 'engine/mastery.dart';
import 'engine/report.dart';
import 'engine/scheduler.dart';
import 'engine/session.dart';
import 'engine/speech_policy.dart';
import 'engine/types.dart';
import 'services/speech_input.dart';
import 'services/sound.dart';
import 'services/speech_output.dart';

const appVersion = '1.0.0';

class AppState extends ChangeNotifier {
  AppState({
    required this.content,
    required this.db,
    required this.tts,
    required this.asr,
    SoundService? sound,
    DateTime Function()? clock,
    Random? rng,
  })  : sound = sound ?? const SilentSound(),
        clock = clock ?? DateTime.now,
        rng = rng ?? Random();

  final ContentBundle content;
  final ProgressDb db;
  final SpeechOutput tts;
  final SpeechInput asr;
  final SoundService sound;
  final DateTime Function() clock;
  final Random rng;
  final IdGen ids = IdGen();

  String profileId = 'profil-1';
  String? childName;
  List<Attempt> attempts = [];
  List<GuardianAction> actions = [];
  List<SessionRecord> sessions = [];
  Map<String, Object?> settings = {};
  ProgressIndex? _index;

  // ---------- ustawienia ----------
  bool get setupDone => settings['setupDone'] == true;
  bool get ttsOk => settings['ttsOk'] == true;
  bool get musicOn => settings['musicOn'] != false; // domyślnie włączona, cicho
  bool get sfxOn => settings['sfxOn'] != false;
  double get ttsRate => (settings['ttsRate'] as num?)?.toDouble() ?? 0.42;
  EvaluationMode get evaluationMode =>
      EvaluationMode.values.asNameMap()[settings['evaluationMode'] as String? ?? 'guardian'] ?? EvaluationMode.guardian;
  Set<String> get ttsBadUnits => Set<String>.from((settings['ttsBadUnits'] as List?) ?? const []);
  MasteryConfig get config =>
      settings['config'] is Map ? MasteryConfig.fromJson(Map<String, dynamic>.from(settings['config'] as Map)) : const MasteryConfig();
  Set<String> get diagnosisDone => Set<String>.from((settings['profile.$profileId.diagDone'] as List?) ?? const []);

  Future<void> setSetting(String key, Object value) async {
    await db.setSetting(key, value);
    settings[key] = value;
    _index = null;
    notifyListeners();
  }

  Future<void> load() async {
    settings = await db.settings();
    final profiles = await db.profiles();
    if (profiles.isEmpty) {
      await db.upsertProfile(profileId, null, clock());
    } else {
      profileId = profiles.first['id'] as String;
      childName = profiles.first['display_name'] as String?;
    }
    await reload();
  }

  Future<void> reload() async {
    attempts = await db.attempts(profileId);
    actions = await db.guardianActions(profileId);
    sessions = await db.sessions(profileId);
    _index = null;
    notifyListeners();
  }

  Future<void> setChildName(String? name) async {
    childName = (name == null || name.trim().isEmpty) ? null : name.trim();
    await db.upsertProfile(profileId, childName, clock());
    notifyListeners();
  }

  // ---------- postęp ----------
  ProgressIndex get index => _index ??= ProgressIndex.build(attempts, actions, config);

  Set<ItemKind> get manualStages {
    final s = <ItemKind>{};
    final sorted = [...actions]..sort((a, b) => a.at.compareTo(b.at));
    for (final a in sorted) {
      if (a.targetId == null) continue;
      final k = ItemKind.values.asNameMap()[a.targetId!];
      if (k == null) continue;
      if (a.type == GuardianActionType.manualUnlock) s.add(k);
      if (a.type == GuardianActionType.revokeUnlock) s.remove(k);
    }
    return s;
  }

  /// Litery, które diagnoza wprowadza od razu do ćwiczeń: znane (nazwa lub głoska
  /// poprawna) oraz MYLONE z inną literą (wymagają ćwiczenia od początku).
  Set<String> get knownFromDiagnosis => {
        for (final a in attempts)
          if (a.task == TaskType.diagnosis && (a.outcome == Outcome.correct || (a.outcome == Outcome.incorrect && a.chosenId != null))) a.itemId
      };

  Curriculum get curriculum =>
      Curriculum(content, index, knownFromDiagnosis: knownFromDiagnosis, manualStages: manualStages);

  GuardianReport get report => buildReport(attempts, actions, sessions);

  Future<void> record(Attempt a) async {
    await db.addAttempt(a); // zapis natychmiastowy (atomowy wiersz)
    attempts.add(a);
    _index = null;
    notifyListeners();
  }

  Future<void> addAction(GuardianActionType type, {String? target, String? value}) async {
    final g = GuardianAction(id: ids.next('g'), profileId: profileId, at: clock(), type: type, targetId: target, value: value);
    await db.addGuardianAction(g);
    actions.add(g);
    _index = null;
    notifyListeners();
  }

  // ---------- sesja ----------
  SessionRecord? activeSession;

  Future<SessionController> startSession({required bool guardianPresent, required bool asrReady, bool assessment = false}) async {
    if (assessment) guardianPresent = true;
    final s = SessionRecord(id: ids.next('s'), profileId: profileId, startedAt: clock(), guardianPresent: guardianPresent);
    activeSession = s;
    await db.upsertSession(s);
    final cap = Capabilities(guardianPresent: guardianPresent, ttsOk: ttsOk, asrReady: asrReady, ttsBadUnits: ttsBadUnits, assessmentOnly: assessment);
    final cur = curriculum;
    final plan = planSession(
      candidates: buildCandidates(cur, cap),
      index: index,
      now: clock(),
      n: config.sessionLength,
      rng: rng,
      focus: cur.lettersFocus(),
    );
    final builder = TaskBuilder(content: content, curriculum: cur, cap: cap, rng: rng);
    final tasks = plan.map(builder.build).toList();
    return SessionController(
      profileId: profileId,
      sessionId: s.id,
      tasks: tasks,
      sink: record,
      guardianPresent: guardianPresent,
      mode: evaluationMode,
      ids: ids,
      clock: clock,
    );
  }

  Future<void> endSession(int taskCount) async {
    final s = activeSession;
    if (s == null) return;
    s.endedAt = clock();
    s.taskCount = taskCount;
    await db.upsertSession(s);
    activeSession = null;
    sessions = await db.sessions(profileId);
    notifyListeners();
  }

  // ---------- diagnoza ----------
  Future<void> recordDiagnosis(String letterId, Skill skill, Outcome outcome, {String? confusedWith}) async {
    await record(Attempt(
      id: ids.next('d'),
      profileId: profileId,
      sessionId: 'diagnoza',
      at: clock(),
      itemId: letterId,
      kind: ItemKind.letter,
      skill: skill,
      task: TaskType.diagnosis,
      outcome: outcome,
      evidence: Evidence.guardian,
      chosenId: confusedWith,
    ));
  }

  Future<void> markDiagnosed(String letterId) async {
    final done = diagnosisDone..add(letterId);
    await setSetting('profile.$profileId.diagDone', done.toList());
  }

  // ---------- kopia ----------
  Future<String> exportJson() => exportBackup(db, appVersion: appVersion, now: clock());

  Future<ImportReport> importJson(String json) async {
    final r = await importBackup(db, json);
    settings = await db.settings();
    await load();
    return r;
  }

  Future<void> resetProfile() async {
    await db.resetProfile(profileId);
    await reload();
  }
}
