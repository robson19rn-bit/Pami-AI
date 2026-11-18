import 'package:czytam_sam/content/models.dart';
// (02) (03) (07) (08) (09) (13) – niezależne umiejętności i kryteria opanowania.
import 'package:czytam_sam/engine/mastery.dart';
import 'package:czytam_sam/engine/types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fixtures.dart';

const cfg = MasteryConfig();
final d1 = DateTime(2026, 3, 2, 10), d2 = DateTime(2026, 3, 3, 10), d3 = DateTime(2026, 3, 4, 10);

void main() {
  test('(02) rozpoznawanie, nazywanie i głoska mają niezależne stany', () {
    final a = [
      ...correctRun('k', Skill.recognizeName, 10, d1, 's1'),
      att('k', Skill.sayName, Outcome.incorrect, at: d1),
    ];
    final idx = ProgressIndex.build(a, const [], cfg);
    expect(idx.state('k', Skill.recognizeName), MasteryState.opanowaneWarunkowo);
    expect(idx.state('k', Skill.sayName), MasteryState.uczone);
    expect(idx.state('k', Skill.recognizeSound), MasteryState.nowe);
    expect(idx.state('k', Skill.saySound), MasteryState.nowe);
  });

  test('(03) samo wskazanie (bez wypowiedzi) NIE daje pełnej znajomości litery', () {
    final a = [
      ...correctRun('k', Skill.recognizeName, 10, d1, 's1'),
      ...correctRun('k', Skill.recognizeName, 3, d2, 's2'),
      ...correctRun('k', Skill.recognizeSound, 10, d1, 's1'),
      ...correctRun('k', Skill.caseMatch, 10, d1, 's1'),
    ];
    final idx = ProgressIndex.build(a, const [], cfg);
    expect(idx.mastered('k', Skill.recognizeName), isTrue);
    expect(idx.letterFullyMastered('k'), isFalse);
    expect(idx.soundReady('k'), isFalse, reason: 'głoska nie wypowiedziana – nie można łączyć w sylaby');
  });

  test('(07) poprawna odpowiedź po podpowiedzi nie zwiększa liczby samodzielnych', () {
    final a = [
      att('b', Skill.recognizeName, Outcome.correct, at: d1, hinted: true),
      att('b', Skill.recognizeName, Outcome.correct, at: d1, hinted: true),
      att('b', Skill.recognizeName, Outcome.correct, at: d1),
    ];
    final s = ProgressIndex.build(a, const [], cfg).of('b', Skill.recognizeName);
    expect(s.independentCorrect, 1);
    expect(s.hintedCorrect, 2);
    expect(s.validResults.length, 1);
  });

  test('(07b) kolejne kliknięcia w tym samym zadaniu (firstTry=false) nie liczą się', () {
    final a = [for (var i = 0; i < 20; i++) att('b', Skill.recognizeName, Outcome.correct, at: d1, firstTry: false)];
    final s = ProgressIndex.build(a, const [], cfg).of('b', Skill.recognizeName);
    expect(s.independentCorrect, 0);
    expect(s.state, isNot(MasteryState.opanowaneWarunkowo));
  });

  test('(08) przypadkowe trafienia w jednej sesji nie oznaczają opanowania', () {
    final few = [
      att('d', Skill.recognizeName, Outcome.correct, at: d1),
      att('d', Skill.recognizeName, Outcome.correct, at: d1),
      att('d', Skill.recognizeName, Outcome.incorrect, at: d1, chosen: 'b'),
      att('d', Skill.recognizeName, Outcome.correct, at: d1),
    ];
    expect(ProgressIndex.build(few, const [], cfg).state('d', Skill.recognizeName).isMastered, isFalse);
    // nawet 10/10 w jednej sesji = tylko warunkowo, nie potwierdzone
    final oneSession = correctRun('d', Skill.recognizeName, 10, d1, 's1');
    expect(ProgressIndex.build(oneSession, const [], cfg).state('d', Skill.recognizeName), MasteryState.opanowaneWarunkowo);
  });

  test('(09) trwałość sprawdzana w późniejszej sesji: potwierdzenie albo powrót do powtórek', () {
    final base = correctRun('m', Skill.recognizeName, 10, d1, 's1');
    final confirmed = [...base, ...correctRun('m', Skill.recognizeName, 2, d2, 's2')];
    expect(ProgressIndex.build(confirmed, const [], cfg).state('m', Skill.recognizeName), MasteryState.potwierdzone);

    final lapsed = [...confirmed, att('m', Skill.recognizeName, Outcome.incorrect, at: d3, session: 's3', chosen: 'n')];
    final st = ProgressIndex.build(lapsed, const [], cfg).of('m', Skill.recognizeName);
    expect(st.state, MasteryState.doPowtorzenia);
    expect(st.confusions['n'], 1);

    // powrót: kolejne poprawne odpowiedzi przywracają opanowanie
    final recovered = [...lapsed, ...correctRun('m', Skill.recognizeName, 2, d3.add(const Duration(hours: 1)), 's3')];
    expect(ProgressIndex.build(recovered, const [], cfg).state('m', Skill.recognizeName).isMastered, isTrue);
  });

  test('(09b) mowa: min. 5 prób, 4 poprawne, 2 sesje w różnych dniach', () {
    final four = correctRun('a', Skill.sayName, 4, d1, 's1');
    expect(ProgressIndex.build(four, const [], cfg).state('a', Skill.sayName).isMastered, isFalse);
    final five = [...four, att('a', Skill.sayName, Outcome.incorrect, at: d1)];
    expect(ProgressIndex.build(five, const [], cfg).state('a', Skill.sayName), MasteryState.opanowaneWarunkowo);
    final later = [...five, ...correctRun('a', Skill.sayName, 1, d2, 's2')];
    expect(ProgressIndex.build(later, const [], cfg).state('a', Skill.sayName), MasteryState.potwierdzone);
  });

  test('(13) wyniki różnych typów ćwiczeń pozostają odrębne', () {
    final a = [
      ...correctRun('p', Skill.recognizeName, 10, d1, 's1'),
      for (var i = 0; i < 6; i++) att('p', Skill.caseMatch, Outcome.incorrect, at: d1, chosen: 'b', task: TaskType.t4Case),
    ];
    final idx = ProgressIndex.build(a, const [], cfg);
    expect(idx.state('p', Skill.recognizeName), MasteryState.opanowaneWarunkowo);
    expect(idx.state('p', Skill.caseMatch), MasteryState.uczone);
    expect(idx.of('p', Skill.caseMatch).independentErrors, 6);
    expect(idx.of('p', Skill.recognizeName).independentErrors, 0);
  });

  test('wykluczone z licznika: brak dźwięku, niepewne, nieocenione, materiał z pomocą', () {
    final a = [
      att('o', Skill.sayName, Outcome.noSpeech, at: d1),
      att('o', Skill.sayName, Outcome.uncertain, at: d1),
      att('o', Skill.sayName, Outcome.notEvaluated, at: d1),
      att('o', Skill.sayName, Outcome.correct, at: d1, assisted: true),
    ];
    final s = ProgressIndex.build(a, const [], cfg).of('o', Skill.sayName);
    expect(s.validResults, isEmpty);
    expect(s.noSpeech, 1);
    expect(s.uncertain, 1);
    expect(s.notEvaluated, 1);
  });

  test('czas odpowiedzi nie wpływa na ocenę', () {
    final fast = [for (var i = 0; i < 10; i++) Attempt(id: 'f$i', profileId: 'p', sessionId: 's', at: d1.add(Duration(minutes: i)), itemId: 'l', kind: ItemKind.letter, skill: Skill.recognizeName, task: TaskType.t1HearPoint, outcome: Outcome.correct, evidence: Evidence.touch, responseMs: 500)];
    final slow = [for (var i = 0; i < 10; i++) Attempt(id: 's$i', profileId: 'p', sessionId: 's', at: d1.add(Duration(minutes: i)), itemId: 'l', kind: ItemKind.letter, skill: Skill.recognizeName, task: TaskType.t1HearPoint, outcome: Outcome.correct, evidence: Evidence.touch, responseMs: 60000)];
    expect(ProgressIndex.build(fast, const [], cfg).state('l', Skill.recognizeName), ProgressIndex.build(slow, const [], cfg).state('l', Skill.recognizeName));
  });
}
