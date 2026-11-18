// (03) (04) (05) (06) (07) (19) – sesja, mowa i polecenia głosowe.
import 'package:czytam_sam/content/models.dart';
import 'package:czytam_sam/engine/scheduler.dart';
import 'package:czytam_sam/engine/session.dart';
import 'package:czytam_sam/engine/speech_policy.dart';
import 'package:czytam_sam/engine/types.dart';
import 'package:flutter_test/flutter_test.dart';

TaskSpec t2() => TaskSpec(
      id: 't', type: TaskType.t2PointSay, kind: ItemKind.letter, itemId: 'k', skill: Skill.recognizeName, speechSkill: Skill.sayName,
      instruction: '', promptSpeech: 'Wskaż literę ka', promptMode: PromptMode.tts, requiresHeardPrompt: true,
      options: ['k', 'h', 'm'], optionIds: ['k', 'h', 'm'], correctIndex: 0, expectedSpeech: 'ka', hintText: 'kot');

TaskSpec t6() => TaskSpec(
      id: 'w', type: TaskType.t6ReadAloud, kind: ItemKind.word, itemId: 'w_mama', skill: Skill.readAloud,
      instruction: '', promptSpeech: 'Przeczytaj', promptMode: PromptMode.tts, requiresHeardPrompt: false, display: 'mama', expectedSpeech: 'mama');

TaskSpec t1() => TaskSpec(
      id: 'x', type: TaskType.t1HearPoint, kind: ItemKind.letter, itemId: 'd', skill: Skill.recognizeName,
      instruction: '', promptSpeech: 'Wskaż literę de', promptMode: PromptMode.tts, requiresHeardPrompt: true,
      options: ['b', 'd', 'p', 'm'], optionIds: ['b', 'd', 'p', 'm'], correctIndex: 1, hintText: 'dom');

(SessionController, List<Attempt>) ctl(List<TaskSpec> tasks, {bool guardian = false, EvaluationMode mode = EvaluationMode.guardian}) {
  final log = <Attempt>[];
  final c = SessionController(profileId: 'p', sessionId: 's', tasks: tasks, sink: (a) async => log.add(a), guardianPresent: guardian, mode: mode);
  return (c, log);
}

const noise = AsrResult(AsrStatus.ok, text: '[unk]', words: [AsrWord('[unk]', 0.9)]);
const weak = AsrResult(AsrStatus.ok, text: 'mama', words: [AsrWord('mama', 0.41)]);
const strong = AsrResult(AsrStatus.ok, text: 'mama', words: [AsrWord('mama', 0.97)]);
const strongWrong = AsrResult(AsrStatus.ok, text: 'tata', words: [AsrWord('tata', 0.97)]);

void main() {
  test('(03) T2: dotyk i mowa to dwa niezależne wyniki; pominięcie mowy zalicza tylko wskazanie', () async {
    final (c, log) = ctl([t2()]);
    c.promptDelivered();
    await c.touch(0);
    expect(c.phase, Phase.awaitingSpeech);
    await c.skipSpeech();
    expect(log.length, 1);
    expect(log.single.skill, Skill.recognizeName);
    expect(log.single.outcome, Outcome.correct);
    expect(log.where((a) => a.skill == Skill.sayName), isEmpty);
  });

  test('(03b) T2 z opiekunem: zapisane dwie oddzielne próby (dotyk + mowa)', () async {
    final (c, log) = ctl([t2()], guardian: true);
    c.promptDelivered();
    await c.touch(0);
    await c.speechFinished(null);
    expect(c.phase, Phase.awaitingGuardian);
    await c.guardianRate(GuardianVerdict.correct);
    expect(log.map((a) => a.skill), [Skill.recognizeName, Skill.sayName]);
    expect(log.last.evidence, Evidence.guardian);
  });

  test('(04) samo wykrycie hałasu NIE zalicza wypowiedzi', () async {
    expect(classifyAsr(noise, 'mama'), AsrVerdict.uncertain);
    final (c, log) = ctl([t6()], mode: EvaluationMode.autoWhereReliable);
    await c.speechFinished(noise);
    await c.speechFinished(noise);
    expect(log.where((a) => a.outcome == Outcome.correct), isEmpty);
    expect(log.single.outcome, Outcome.uncertain);
  });

  test('(05) brak mikrofonu / odmowa uprawnienia nie produkuje fikcyjnych ocen', () async {
    expect(classifyAsr(const AsrResult(AsrStatus.noPermission), 'mama'), AsrVerdict.uncertain);
    expect(classifyAsr(const AsrResult(AsrStatus.noModel), 'mama'), AsrVerdict.uncertain);
    final (c, log) = ctl([t6()], mode: EvaluationMode.autoWhereReliable);
    await c.speechFinished(const AsrResult(AsrStatus.noPermission));
    await c.speechFinished(const AsrResult(AsrStatus.noPermission));
    expect(log.every((a) => a.outcome != Outcome.correct && a.outcome != Outcome.incorrect), isTrue);
    // bez ASR i bez opiekuna: wypowiedź „nieoceniona”
    final (c2, log2) = ctl([t6()]);
    await c2.speechFinished(null);
    expect(log2.single.outcome, Outcome.notEvaluated);
    expect(log2.single.evidence, Evidence.none);
  });

  test('(06) niepewny ASR → powtórzenie, potem opiekun lub „niepewne”, nigdy automatyczne „błędnie”', () async {
    expect(classifyAsr(weak, 'mama'), AsrVerdict.uncertain);
    final (c, log) = ctl([t6()], mode: EvaluationMode.autoWhereReliable);
    final d1 = await c.speechFinished(weak);
    expect(d1!.kind, SpeechDecisionKind.retry);
    expect(log, isEmpty);
    await c.speechFinished(strongWrong);
    expect(log.single.outcome, Outcome.uncertain, reason: 'nawet pewne „inne słowo” nie jest automatycznie błędem');
    // z opiekunem – decyzja należy do opiekuna
    final (g, glog) = ctl([t6()], guardian: true, mode: EvaluationMode.autoWhereReliable);
    final d = await g.speechFinished(weak);
    expect(d!.kind, SpeechDecisionKind.askGuardian);
    expect(glog, isEmpty);
  });

  test('pewne rozpoznanie wyrazu w trybie automatycznym zalicza; litery zawsze ocenia opiekun', () async {
    final (c, log) = ctl([t6()], mode: EvaluationMode.autoWhereReliable);
    await c.speechFinished(strong);
    expect(log.single.outcome, Outcome.correct);
    expect(log.single.evidence, Evidence.asr);
    final letter = decideSpeech(verdict: AsrVerdict.correct, kind: ItemKind.letter, skill: Skill.sayName, mode: EvaluationMode.autoWhereReliable, guardianPresent: false, retriesSoFar: 0);
    expect(letter.kind, isNot(SpeechDecisionKind.recordCorrect));
  });

  test('nic nie usłyszano → zapis „brak dźwięku” i możliwość ponowienia (nie jest błędem)', () async {
    final (c, log) = ctl([t6()]);
    final d = await c.speechFinished(const AsrResult(AsrStatus.noSpeech));
    expect(d!.kind, SpeechDecisionKind.retry);
    expect(log.single.outcome, Outcome.noSpeech);
    expect(c.phase, Phase.awaitingSpeech);
  });

  test('(07) podpowiedź → odpowiedź oznaczona jako po podpowiedzi; podpowiedź dostępna tylko na życzenie', () async {
    final (c, log) = ctl([t1()]);
    expect(c.canRequestHint, isFalse, reason: 'przed usłyszeniem polecenia');
    c.promptDelivered();
    expect(c.hintUsed, isFalse);
    c.requestHint();
    expect(c.visibleOptionIndexes().length, 2);
    await c.touch(1);
    expect(log.single.hinted, isTrue);
    expect(c.independentCorrect, 0);
  });

  test('wielokrotne klikanie nie podbija statystyki; po błędzie ponowne sprawdzenie odłożone na później', () async {
    final filler = [for (var i = 0; i < 5; i++) t6()];
    final (c, log) = ctl([t1(), ...filler]);
    c.promptDelivered();
    await c.touch(0); // błąd: b zamiast d
    await c.touch(1);
    await c.touch(1);
    expect(log.length, 1);
    expect(log.single.outcome, Outcome.incorrect);
    expect(log.single.chosenId, 'b');
    expect(c.total, 7);
    final recheckPos = c.queue.indexWhere((t) => t.recheck);
    expect(recheckPos, 4, reason: 'ponowne sprawdzenie kilka zadań później, nie od razu');
    expect(c.queue[recheckPos].itemId, 'd');
  });

  test('(19) bez odtworzonego polecenia zadanie „ze słuchu” jest wstrzymane', () async {
    final (c, log) = ctl([t1()]);
    c.promptNotDelivered();
    expect(c.phase, Phase.awaitingPrompt);
    expect(c.promptFailed, isTrue);
    expect(await c.touch(1), isNull);
    expect(log, isEmpty);
    c.promptDelivered(); // np. opiekun przeczytał polecenie
    expect(c.phase, Phase.awaitingTouch);
  });

  test('„Wróć później” przenosi zadanie na koniec bez zapisu', () async {
    final (c, log) = ctl([t1(), t6()]);
    c.postpone();
    expect(c.current!.type, TaskType.t6ReadAloud);
    expect(log, isEmpty);
  });

  test('Capabilities: bez lektora i bez opiekuna nie ma zadań „ze słuchu”', () {
    const cap = Capabilities(ttsOk: false, guardianPresent: false);
    expect(cap.canSpeak('k'), isFalse);
  });
}
