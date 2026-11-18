/// Przebieg sesji (czysty Dart, testowalny bez interfejsu).
library;

import 'dart:math';

import '../content/models.dart';
import '../content/tokenizer.dart';
import 'curriculum.dart';
import 'mastery.dart';
import 'scheduler.dart';
import 'speech_policy.dart';
import 'types.dart';

enum PromptMode {
  /// Polecenie czyta lektor (TTS).
  tts,

  /// Polecenie czyta opiekun (głoski, brak lektora, jednostka oznaczona jako źle czytana).
  guardian,
}

class TaskSpec {
  TaskSpec({
    required this.id,
    required this.type,
    required this.kind,
    required this.itemId,
    required this.skill,
    required this.instruction,
    required this.promptSpeech,
    required this.promptMode,
    required this.requiresHeardPrompt,
    this.speechSkill,
    this.display,
    this.options = const [],
    this.optionIds = const [],
    this.correctIndex = -1,
    this.correctSequence = const [],
    this.question,
    this.expectedSpeech,
    this.guardianExpected,
    this.hintText,
    this.assisted = false,
    this.recheck = false,
    this.bucket,
  });

  final String id;
  final TaskType type;
  final ItemKind kind;
  final String itemId;

  /// Umiejętność oceniana dotykiem (lub mową dla T3/T6).
  final Skill skill;

  /// Druga, niezależna umiejętność mowy (T2).
  final Skill? speechSkill;

  /// Polecenie wyświetlane.
  final String instruction;

  /// Co ma zostać wypowiedziane jako polecenie (lektor lub opiekun).
  final String promptSpeech;
  final PromptMode promptMode;

  /// Zadanie „ze słuchu” – nie wolno odpowiadać, dopóki polecenie nie zostało usłyszane.
  final bool requiresHeardPrompt;

  /// Duży znak/tekst pokazany dziecku (T3, T4, T6, T7).
  final String? display;

  /// Teksty przycisków odpowiedzi i ich identyfikatory.
  final List<String> options;
  final List<String> optionIds;
  final int correctIndex;

  /// T5: poprawna kolejność kafelków (identyfikatory grafemów).
  final List<String> correctSequence;
  final String? question;

  /// Oczekiwana wypowiedź (dla ASR) i jej opis dla opiekuna.
  final String? expectedSpeech;
  final String? guardianExpected;
  final String? hintText;
  final bool assisted;
  final bool recheck;
  final Bucket? bucket;

  bool get isSpeechOnly => type == TaskType.t3SeeName || type == TaskType.t6ReadAloud;
  bool get hasTouch => !isSpeechOnly;
  Skill? get activeSpeechSkill => isSpeechOnly ? skill : speechSkill;

  TaskSpec copyAsRecheck(String newId) => TaskSpec(
        id: newId,
        type: type,
        kind: kind,
        itemId: itemId,
        skill: skill,
        speechSkill: speechSkill,
        instruction: instruction,
        promptSpeech: promptSpeech,
        promptMode: promptMode,
        requiresHeardPrompt: requiresHeardPrompt,
        display: display,
        options: options,
        optionIds: optionIds,
        correctIndex: correctIndex,
        correctSequence: correctSequence,
        question: question,
        expectedSpeech: expectedSpeech,
        guardianExpected: guardianExpected,
        hintText: hintText,
        assisted: assisted,
        recheck: true,
        bucket: bucket,
      );
}

/// Buduje zadania z planu.
class TaskBuilder {
  TaskBuilder({required this.content, required this.curriculum, required this.cap, required this.rng})
      : balancer = PositionBalancer(rng);

  final ContentBundle content;
  final Curriculum curriculum;
  final Capabilities cap;
  final Random rng;
  final PositionBalancer balancer;
  int _n = 0;

  ProgressIndex get index => curriculum.index;

  List<String> _activeIds(ItemKind kind) => kind == ItemKind.grapheme
      ? curriculum.activeGraphemes().map((g) => g.id).toList()
      : curriculum.activeLetters().map((l) => l.id).toList();

  List<String> _fullIds(ItemKind kind) =>
      kind == ItemKind.grapheme ? content.graphemes.map((g) => g.id).toList() : content.letters.map((l) => l.id).toList();

  List<String> _confusable(String id) => content.letter(id)?.confusable ?? content.grapheme(id)?.confusable ?? const [];

  /// Zwraca (opcje, identyfikatory, indeks poprawnej).
  (List<String>, List<String>, int) _graphemeOptions(String target, ItemKind kind, Skill skill, {bool? upper}) {
    final stats = index.of(target, skill);
    final n = optionCountFor(stats.state);
    final distractors = pickDistractors(
      target: target,
      count: n - 1,
      stats: stats,
      staticConfusable: _confusable(target),
      activePool: _activeIds(kind),
      fullPool: _fullIds(kind),
      rng: rng,
    );
    final count = distractors.length + 1;
    final pos = balancer.pick(count);
    final ids = [...distractors];
    ids.insert(pos, target);
    final useUpper = upper ?? false;
    return ([for (final id in ids) content.displayOf(id, upper: useUpper)], ids, pos);
  }

  String _sayable(String id) => content.letter(id)?.nameTts ?? content.grapheme(id)?.text ?? id;
  String _name(String id) => content.letter(id)?.name ?? content.grapheme(id)?.text ?? id;
  String _soundPrompt(String id) => content.letter(id)?.soundPrompt ?? content.grapheme(id)?.soundPrompt ?? id;

  TaskSpec build(Planned p) {
    final c = p.candidate;
    final id = 'task-${_n++}';
    switch (c.task) {
      case TaskType.t1HearPoint:
        final (opts, ids, pos) = _graphemeOptions(c.itemId, c.kind, c.skill);
        if (c.skill == Skill.recognizeSound) {
          return TaskSpec(
            id: id, type: c.task, kind: c.kind, itemId: c.itemId, skill: c.skill, bucket: p.bucket,
            instruction: 'Posłuchaj głoski i wskaż literę, która ją oznacza.',
            promptSpeech: _soundPrompt(c.itemId),
            promptMode: PromptMode.guardian,
            requiresHeardPrompt: true,
            options: opts, optionIds: ids, correctIndex: pos,
            hintText: 'Ta głoska jest na początku słowa „${_example(c.itemId)}”.',
          );
        }
        final tts = cap.canSpeak(c.itemId);
        return TaskSpec(
          id: id, type: c.task, kind: c.kind, itemId: c.itemId, skill: c.skill, bucket: p.bucket,
          instruction: 'Wskaż literę, którą usłyszysz.',
          promptSpeech: tts ? 'Wskaż literę ${_sayable(c.itemId)}.' : 'Wskaż literę ${_name(c.itemId)}.',
          promptMode: tts ? PromptMode.tts : PromptMode.guardian,
          requiresHeardPrompt: true,
          options: opts, optionIds: ids, correctIndex: pos,
          hintText: 'Szukamy litery z początku słowa „${_example(c.itemId)}”.',
        );
      case TaskType.t2PointSay:
        final (opts, ids, pos) = _graphemeOptions(c.itemId, c.kind, c.skill);
        final tts = cap.canSpeak(c.itemId);
        final nameText = tts ? _sayable(c.itemId) : _name(c.itemId);
        return TaskSpec(
          id: id, type: c.task, kind: c.kind, itemId: c.itemId, skill: Skill.recognizeName, speechSkill: Skill.sayName,
          bucket: p.bucket,
          instruction: 'Wskaż literę, a potem powiedz jej nazwę.',
          promptSpeech: 'Wskaż literę $nameText, a potem powiedz jej nazwę.',
          promptMode: tts ? PromptMode.tts : PromptMode.guardian,
          requiresHeardPrompt: true,
          options: opts, optionIds: ids, correctIndex: pos,
          expectedSpeech: _name(c.itemId),
          guardianExpected: 'nazwa litery: „${_name(c.itemId)}”',
          hintText: 'Szukamy litery z początku słowa „${_example(c.itemId)}”.',
        );
      case TaskType.t3SeeName:
        final sound = c.skill == Skill.saySound;
        final upper = c.kind == ItemKind.letter && rng.nextBool();
        return TaskSpec(
          id: id, type: c.task, kind: c.kind, itemId: c.itemId, skill: c.skill, bucket: p.bucket,
          instruction: sound ? 'Jaką głoskę tu widzisz? Powiedz ją.' : 'Jaka to litera? Powiedz jej nazwę.',
          promptSpeech: sound ? 'Jaką głoskę tu widzisz?' : 'Jaka to litera?',
          promptMode: cap.ttsOk ? PromptMode.tts : PromptMode.guardian,
          requiresHeardPrompt: false,
          display: content.displayOf(c.itemId, upper: upper),
          expectedSpeech: sound ? null : _name(c.itemId),
          guardianExpected: sound ? 'głoska: ${_soundPrompt(c.itemId)}' : 'nazwa litery: „${_name(c.itemId)}”',
          hintText: 'Ta litera jest na początku słowa „${_example(c.itemId)}”.',
        );
      case TaskType.t4Case:
        final showUpper = rng.nextBool();
        final (opts, ids, pos) = _graphemeOptions(c.itemId, c.kind, c.skill, upper: !showUpper);
        return TaskSpec(
          id: id, type: c.task, kind: c.kind, itemId: c.itemId, skill: c.skill, bucket: p.bucket,
          instruction: showUpper ? 'Znajdź małą literę do tej wielkiej.' : 'Znajdź wielką literę do tej małej.',
          promptSpeech: showUpper ? 'Znajdź małą literę do tej wielkiej.' : 'Znajdź wielką literę do tej małej.',
          promptMode: cap.ttsOk ? PromptMode.tts : PromptMode.guardian,
          requiresHeardPrompt: false,
          display: content.displayOf(c.itemId, upper: showUpper),
          options: opts, optionIds: ids, correctIndex: pos,
          hintText: 'Wielka i mała litera mają tę samą nazwę.',
        );
      case TaskType.t5Segment:
        final u = content.unit(c.itemId)!;
        final seq = tokenizeGraphemes(u.text);
        final tiles = <String>[...seq];
        for (final g in seq) {
          for (final x in _confusable(g)) {
            if (tiles.length >= seq.length + 2) break;
            if (!tiles.contains(x) && content.isGraphemeId(x)) tiles.add(x);
          }
        }
        tiles.shuffle(rng);
        final tts = cap.canSpeak(u.id);
        return TaskSpec(
          id: id, type: c.task, kind: c.kind, itemId: c.itemId, skill: c.skill, bucket: p.bucket, assisted: c.assisted,
          instruction: 'Posłuchaj i ułóż z kafelków to, co słyszysz.',
          promptSpeech: u.text,
          promptMode: tts ? PromptMode.tts : PromptMode.guardian,
          requiresHeardPrompt: true,
          options: [for (final t in tiles) content.displayOf(t)],
          optionIds: tiles,
          correctSequence: seq,
          hintText: 'Pierwsza głoska to „${content.displayOf(seq.first)}”.',
        );
      case TaskType.t6ReadAloud:
        final u = content.unit(c.itemId)!;
        return TaskSpec(
          id: id, type: c.task, kind: c.kind, itemId: c.itemId, skill: c.skill, bucket: p.bucket, assisted: c.assisted,
          instruction: 'Przeczytaj na głos.',
          promptSpeech: 'Przeczytaj na głos.',
          promptMode: cap.ttsOk ? PromptMode.tts : PromptMode.guardian,
          requiresHeardPrompt: false,
          display: u.text,
          expectedSpeech: u.text,
          guardianExpected: 'poprawne odczytanie: „${u.text}”${u.pronunciation != null && u.pronunciation != u.text ? ' (wymowa: ${u.pronunciation})' : ''}',
          hintText: tokenizeGraphemes(u.text).map(content.displayOf).join(' · '),
        );
      case TaskType.t7Comprehension:
        final u = content.unit(c.itemId)!;
        final q = u.questions[index.of(c.itemId, c.skill).totalAttempts % u.questions.length];
        final others = q.options.where((o) => o != q.answer).toList()..shuffle(rng);
        final pos = balancer.pick(others.length + 1);
        final opts = [...others]..insert(pos, q.answer);
        return TaskSpec(
          id: id, type: c.task, kind: c.kind, itemId: c.itemId, skill: c.skill, bucket: p.bucket, assisted: c.assisted,
          instruction: 'Przeczytaj i odpowiedz na pytanie.',
          promptSpeech: q.question,
          promptMode: cap.ttsOk ? PromptMode.tts : PromptMode.guardian,
          requiresHeardPrompt: false,
          display: u.text,
          question: q.question,
          options: opts, optionIds: opts, correctIndex: pos,
          hintText: 'Przeczytaj jeszcze raz powoli, słowo po słowie.',
        );
      case TaskType.diagnosis:
        throw ArgumentError('Diagnoza ma osobny przebieg');
    }
  }

  String _example(String id) {
    final ex = content.letter(id)?.examples ?? content.grapheme(id)?.examples ?? const [''];
    return ex.first;
  }
}

enum Phase { awaitingPrompt, awaitingTouch, awaitingSpeech, awaitingGuardian, feedback, finished }

enum GuardianVerdict { correct, notYet, repeat, cannotAssess }

class Feedback {
  Feedback(this.correct, this.message, {this.correctAnswer});
  final bool? correct;
  final String message;
  final String? correctAnswer;
}

typedef AttemptSink = Future<void> Function(Attempt a);

/// Stan i reguły jednej sesji.
class SessionController {
  SessionController({
    required this.profileId,
    required this.sessionId,
    required List<TaskSpec> tasks,
    required this.sink,
    required this.guardianPresent,
    required this.mode,
    IdGen? ids,
    DateTime Function()? clock,
  })  : _queue = [...tasks],
        _ids = ids ?? IdGen(),
        _clock = clock ?? DateTime.now {
    _start();
  }

  final String profileId, sessionId;
  final AttemptSink sink;
  final bool guardianPresent;
  final EvaluationMode mode;
  final List<TaskSpec> _queue;
  final IdGen _ids;
  final DateTime Function() _clock;

  int position = 0;
  Phase phase = Phase.awaitingPrompt;
  bool hintUsed = false;
  bool promptFailed = false;
  bool touchCorrect = false;
  int speechRetries = 0;
  AsrResult? lastAsr;
  AsrVerdict? lastVerdict;
  Feedback? feedback;
  final List<int> selectedTiles = [];
  late DateTime _taskShownAt;
  int completedTasks = 0, independentCorrect = 0;
  final Set<String> _rechecked = {};

  TaskSpec? get current => position < _queue.length ? _queue[position] : null;
  int get total => _queue.length;
  bool get finished => phase == Phase.finished;

  void _start() {
    if (current == null) {
      phase = Phase.finished;
      return;
    }
    hintUsed = false;
    promptFailed = false;
    touchCorrect = false;
    speechRetries = 0;
    lastAsr = null;
    lastVerdict = null;
    feedback = null;
    selectedTiles.clear();
    _taskShownAt = _clock();
    final t = current!;
    phase = t.requiresHeardPrompt ? Phase.awaitingPrompt : (t.hasTouch ? Phase.awaitingTouch : Phase.awaitingSpeech);
  }

  /// Lektor potwierdził rozpoczęcie odtwarzania albo opiekun potwierdził, że przeczytał polecenie.
  void promptDelivered() {
    promptFailed = false;
    if (phase == Phase.awaitingPrompt) {
      phase = current!.hasTouch ? Phase.awaitingTouch : Phase.awaitingSpeech;
      _taskShownAt = _clock();
    }
  }

  /// Lektor NIE odtworzył polecenia – nie wolno kontynuować zadania „ze słuchu”.
  void promptNotDelivered() {
    promptFailed = true;
  }

  bool get canRequestHint => phase == Phase.awaitingTouch || phase == Phase.awaitingSpeech;

  /// Podpowiedź tylko na życzenie (lub po błędzie – wtedy zadanie i tak jest „po podpowiedzi”).
  String? requestHint() {
    if (!canRequestHint) return null;
    hintUsed = true;
    return current!.hintText;
  }

  /// Przy podpowiedzi w zadaniu z wyborem zostają 2 opcje.
  List<int> visibleOptionIndexes() {
    final t = current!;
    final all = List<int>.generate(t.options.length, (i) => i);
    if (!hintUsed || t.type == TaskType.t5Segment || t.correctIndex < 0 || t.options.length <= 2) return all;
    final other = all.firstWhere((i) => i != t.correctIndex);
    return all.where((i) => i == t.correctIndex || i == other).toList();
  }

  Attempt _attempt(Skill skill, Outcome o, Evidence e, {String? chosen, bool? hinted, String? asrText, double? asrConf}) {
    final t = current!;
    return Attempt(
      id: _ids.next('a'),
      profileId: profileId,
      sessionId: sessionId,
      at: _clock(),
      itemId: t.itemId,
      kind: t.kind,
      skill: skill,
      task: t.type,
      outcome: o,
      evidence: e,
      hinted: hinted ?? (hintUsed || t.recheck),
      firstTry: true,
      assisted: t.assisted,
      chosenId: chosen,
      responseMs: _clock().difference(_taskShownAt).inMilliseconds,
      asrText: asrText,
      asrConfidence: asrConf,
    );
  }

  /// Wybór odpowiedzi (T1, T2, T4, T7). Liczy się tylko pierwszy wybór w zadaniu.
  Future<Feedback?> touch(int optionIndex) async {
    final t = current;
    if (t == null || phase != Phase.awaitingTouch || t.type == TaskType.t5Segment) return null;
    final ok = optionIndex == t.correctIndex;
    final chosen = t.optionIds[optionIndex];
    await sink(_attempt(t.skill, ok ? Outcome.correct : Outcome.incorrect, Evidence.touch, chosen: chosen));
    touchCorrect = ok;
    final answer = t.options[t.correctIndex];
    if (ok) {
      if (!hintUsed && !t.recheck && !t.assisted) independentCorrect++;
      feedback = Feedback(true, t.speechSkill != null ? 'Dobrze. Teraz powiedz nazwę tej litery.' : 'Dobrze.');
    } else {
      feedback = Feedback(false, 'To jest „${t.options[optionIndex]}”. Szukaliśmy „$answer”. Wrócimy do tego za chwilę.',
          correctAnswer: answer);
      _scheduleRecheck();
      hintUsed = true; // dalsza część zadania jest już po pokazaniu odpowiedzi
    }
    phase = t.speechSkill != null ? Phase.awaitingSpeech : Phase.feedback;
    if (phase == Phase.feedback) completedTasks++;
    return feedback;
  }

  /// T5: dziecko wybiera kafelki po kolei.
  void tapTile(int i) {
    if (phase != Phase.awaitingTouch || current?.type != TaskType.t5Segment) return;
    if (selectedTiles.length < current!.correctSequence.length) selectedTiles.add(i);
  }

  void undoTile() {
    if (phase == Phase.awaitingTouch && selectedTiles.isNotEmpty) selectedTiles.removeLast();
  }

  Future<Feedback?> submitTiles() async {
    final t = current;
    if (t == null || t.type != TaskType.t5Segment || phase != Phase.awaitingTouch) return null;
    final seq = [for (final i in selectedTiles) t.optionIds[i]];
    final ok = seq.length == t.correctSequence.length && List.generate(seq.length, (i) => seq[i] == t.correctSequence[i]).every((x) => x);
    await sink(_attempt(t.skill, ok ? Outcome.correct : Outcome.incorrect, Evidence.touch, chosen: seq.join('+')));
    final answer = t.correctSequence.join(' · ');
    if (ok) {
      if (!hintUsed && !t.recheck && !t.assisted) independentCorrect++;
      feedback = Feedback(true, 'Dobrze.');
    } else {
      feedback = Feedback(false, 'Prawidłowo: $answer. Wrócimy do tego za chwilę.', correctAnswer: answer);
      _scheduleRecheck();
    }
    phase = Phase.feedback;
    completedTasks++;
    return feedback;
  }

  /// Wynik z lokalnego rozpoznawania mowy (null = brak ASR, dziecko powiedziało, kliknięto „Powiedziałem”).
  Future<SpeechDecision?> speechFinished(AsrResult? asr) async {
    final t = current;
    if (t == null || phase != Phase.awaitingSpeech) return null;
    final skill = t.activeSpeechSkill!;
    lastAsr = asr;
    lastVerdict = asr == null || t.expectedSpeech == null ? (asr?.status == AsrStatus.noSpeech ? AsrVerdict.nothingHeard : null) : classifyAsr(asr, t.expectedSpeech!);
    if (asr != null && asr.status == AsrStatus.noSpeech) lastVerdict = AsrVerdict.nothingHeard;
    final d = decideSpeech(
      verdict: lastVerdict,
      kind: t.kind,
      skill: skill,
      mode: mode,
      guardianPresent: guardianPresent,
      retriesSoFar: speechRetries,
    );
    switch (d.kind) {
      case SpeechDecisionKind.retry:
        if (lastVerdict == AsrVerdict.nothingHeard) {
          await sink(_attempt(skill, Outcome.noSpeech, Evidence.asr, asrText: asr?.text));
        }
        speechRetries++;
        feedback = Feedback(null, d.message);
      case SpeechDecisionKind.askGuardian:
        phase = Phase.awaitingGuardian;
        feedback = Feedback(null, d.message);
      case SpeechDecisionKind.recordCorrect:
        await sink(_attempt(skill, Outcome.correct, Evidence.asr, asrText: asr?.text, asrConf: asr?.confidence));
        if (!hintUsed && !t.recheck && !t.assisted) independentCorrect++;
        _finishSpeech(Feedback(true, d.message));
      case SpeechDecisionKind.recordNoSpeech:
        await sink(_attempt(skill, Outcome.noSpeech, Evidence.asr, asrText: asr?.text));
        _finishSpeech(Feedback(null, d.message));
      case SpeechDecisionKind.recordUncertain:
        await sink(_attempt(skill, Outcome.uncertain, Evidence.asr, asrText: asr?.text, asrConf: asr?.confidence));
        _finishSpeech(Feedback(null, d.message));
      case SpeechDecisionKind.recordNotEvaluated:
        await sink(_attempt(skill, Outcome.notEvaluated, Evidence.none, asrText: asr?.text, asrConf: asr?.confidence));
        _finishSpeech(Feedback(null, d.message));
    }
    return d;
  }

  /// Dziecko pomija wypowiedź – zaliczony może być tylko dotyk (już zapisany).
  Future<void> skipSpeech() async {
    final t = current;
    if (t == null || (phase != Phase.awaitingSpeech && phase != Phase.awaitingGuardian)) return;
    _finishSpeech(Feedback(null, 'Dobrze, spróbujemy powiedzieć to następnym razem.'));
  }

  /// Ocena opiekuna (panel dostępny po przytrzymaniu przycisku).
  Future<void> guardianRate(GuardianVerdict v) async {
    final t = current;
    if (t == null || (phase != Phase.awaitingGuardian && phase != Phase.awaitingSpeech)) return;
    final skill = t.activeSpeechSkill!;
    switch (v) {
      case GuardianVerdict.repeat:
        phase = Phase.awaitingSpeech;
        feedback = Feedback(null, 'Powiedz jeszcze raz.');
        return;
      case GuardianVerdict.correct:
        await sink(_attempt(skill, Outcome.correct, Evidence.guardian, asrText: lastAsr?.text, asrConf: lastAsr?.confidence));
        if (!hintUsed && !t.recheck && !t.assisted) independentCorrect++;
        _finishSpeech(Feedback(true, 'Dobrze.'));
      case GuardianVerdict.notYet:
        await sink(_attempt(skill, Outcome.incorrect, Evidence.guardian, asrText: lastAsr?.text, asrConf: lastAsr?.confidence));
        _scheduleRecheck();
        _finishSpeech(Feedback(false, 'Jeszcze nie. Prawidłowo: ${t.guardianExpected ?? t.expectedSpeech ?? ''}. Wrócimy do tego.',
            correctAnswer: t.expectedSpeech));
      case GuardianVerdict.cannotAssess:
        await sink(_attempt(skill, Outcome.uncertain, Evidence.guardian, asrText: lastAsr?.text, asrConf: lastAsr?.confidence));
        _finishSpeech(Feedback(null, 'W porządku, wrócimy do tego później.'));
    }
  }

  void _finishSpeech(Feedback f) {
    feedback = f;
    phase = Phase.feedback;
    completedTasks++;
  }

  /// „Wróć później” – zadanie przechodzi na koniec kolejki, nic nie jest zapisywane.
  void postpone() {
    final t = current;
    if (t == null || phase == Phase.feedback || phase == Phase.finished) return;
    _queue.removeAt(position);
    _queue.add(t);
    _start();
  }

  void next() {
    if (phase == Phase.finished) return;
    position++;
    _start();
  }

  void abort() {
    phase = Phase.finished;
  }

  /// Po błędzie: ponowne sprawdzenie 3 zadania później (oznaczone jako „po pokazaniu odpowiedzi”).
  void _scheduleRecheck() {
    final t = current!;
    if (t.recheck || _rechecked.contains(t.id)) return;
    _rechecked.add(t.id);
    final at = min(position + 4, _queue.length);
    _queue.insert(at, t.copyAsRecheck('${t.id}-r'));
  }
}
