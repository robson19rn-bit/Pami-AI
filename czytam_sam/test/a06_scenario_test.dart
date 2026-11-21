// Pełny scenariusz syntetycznego dziecka (dane demonstracyjne):
// 20 liter częściowo znanych, B/D/P mylone, brak błędnego awansu,
// później opanowanie grupy M/A/L/O i odblokowanie prostych sylab, utrwalanie w kolejnych sesjach.
import 'dart:math';

import 'package:czytam_sam/content/models.dart';
import 'package:czytam_sam/engine/curriculum.dart';
import 'package:czytam_sam/engine/mastery.dart';
import 'package:czytam_sam/engine/report.dart';
import 'package:czytam_sam/engine/scheduler.dart';
import 'package:czytam_sam/engine/session.dart';
import 'package:czytam_sam/engine/types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';

const known20 = ['a', 'm', 'o', 'l', 'e', 't', 'i', 's', 'u', 'p', 'y', 'k', 'r', 'd', 'n', 'w', 'b', 'j', 'z', 'g'];
const malo = {'m', 'a', 'l', 'o'};
const confused = {'b', 'd', 'p'};

/// Model dziecka: prawdopodobieństwo poprawnej odpowiedzi.
double pCorrect(String item, Skill skill, int day) {
  if (confused.contains(item)) return 0.45; // stale myli b/d/p
  if (malo.contains(item)) return day >= 2 ? 0.97 : 0.75; // M/A/L/O utrwalają się od 2. dnia
  if (item.startsWith('syl_') || item.startsWith('w_')) return 0.9;
  if (known20.contains(item)) return skill.isSpeech || skill == Skill.recognizeSound ? 0.6 : 0.8;
  return 0.3;
}

Future<void> playSession(SessionController c, int day, Random r) async {
  while (!c.finished) {
    final t = c.current;
    if (t == null) break;
    if (c.phase == Phase.awaitingPrompt) c.promptDelivered();
    final ok = r.nextDouble() < pCorrect(t.itemId, t.skill, day);
    if (c.phase == Phase.awaitingTouch) {
      if (t.type == TaskType.t5Segment) {
        final order = ok ? t.correctSequence : t.correctSequence.reversed.toList();
        final used = <int>{};
        for (final g in order) {
          final i = List.generate(t.optionIds.length, (i) => i).firstWhere((i) => t.optionIds[i] == g && !used.contains(i));
          used.add(i);
          c.tapTile(i);
        }
        await c.submitTiles();
      } else {
        var wrong = (t.correctIndex + 1) % t.options.length;
        // b/d/p: wybiera literę z tej grupy, jeśli jest na ekranie
        final conf = t.optionIds.indexWhere((x) => confused.contains(x) && x != t.itemId);
        if (confused.contains(t.itemId) && conf >= 0) wrong = conf;
        await c.touch(ok ? t.correctIndex : wrong);
      }
    }
    if (c.phase == Phase.awaitingSpeech) {
      await c.speechFinished(null); // brak modelu ASR – ocenia opiekun
      final ok2 = r.nextDouble() < pCorrect(t.itemId, t.activeSpeechSkill!, day);
      await c.guardianRate(ok2 ? GuardianVerdict.correct : GuardianVerdict.notYet);
    }
    c.next();
  }
}

void main() {
  test('scenariusz: diagnoza → brak błędnego awansu → M/A/L/O → sylaby → utrwalanie', () async {
    var now = DateTime(2026, 9, 1, 16);
    final s = await testState(clock: () => now, tts: FakeTts(), seed: 11);
    await s.setSetting('ttsOk', true);
    await s.setSetting('config', const MasteryConfig(sessionLength: 30, alphabetFirst: false).toJson());

    // Diagnoza: 20 liter – nazwy znane (b/d/p mylone), głoski znane częściowo
    for (final l in known20) {
      if (l == 'b') {
        await s.recordDiagnosis(l, Skill.sayName, Outcome.incorrect, confusedWith: 'd');
      } else if (l == 'd') {
        await s.recordDiagnosis(l, Skill.sayName, Outcome.incorrect, confusedWith: 'b');
      } else if (l == 'p') {
        await s.recordDiagnosis(l, Skill.sayName, Outcome.incorrect, confusedWith: 'b');
      } else {
        await s.recordDiagnosis(l, Skill.sayName, Outcome.correct);
      }
      await s.recordDiagnosis(l, Skill.saySound, known20.indexOf(l) < 12 ? Outcome.correct : Outcome.incorrect);
    }
    expect(s.curriculum.activeLetters().map((l) => l.id).toSet(), containsAll(known20.where((x) => !confused.contains(x))));
    expect(s.curriculum.activeLetters().map((l) => l.id), isNot(contains('ż')), reason: 'nieznane litery nie wchodzą od razu');

    final r = Random(42);
    // Dzień 1 – jedna sesja: nic nie może być „potwierdzone”, b/d/p nieopanowane
    var ctl = await s.startSession(guardianPresent: false, asrReady: false);
    await playSession(ctl, 1, r);
    await s.endSession(ctl.completedTasks);
    expect(s.index.stats.values.where((x) => x.state == MasteryState.potwierdzone), isEmpty);
    for (final x in confused) {
      expect(s.index.mastered(x, Skill.recognizeName), isFalse);
      expect(s.index.mastered(x, Skill.sayName), isFalse);
    }
    expect(s.curriculum.units(ItemKind.syllable), isEmpty, reason: 'po jednej sesji brak sylab');

    // Kolejne dni: 2 sesje dziennie
    var syllablesDay = -1, maloDay = -1, listenDay = -1;
    for (var day = 2; day <= 60 && maloDay < 0; day++) {
      now = DateTime(2026, 9, day, 16);
      // dziecko ćwiczy samo 2 razy (prowadzi lektor), potem krótka ocena wypowiedzi z opiekunem
      for (var k = 0; k < 3; k++) {
        ctl = await s.startSession(guardianPresent: false, asrReady: false, assessment: k == 2);
        await playSession(ctl, day, r);
        now = now.add(const Duration(hours: 2));
        await s.endSession(ctl.completedTasks);
      }
      final avail = s.curriculum.units(ItemKind.syllable).where((u) => u.access == Access.available);
      if (avail.isNotEmpty && syllablesDay < 0) syllablesDay = day;
      if (listenDay < 0 && s.curriculum.units(ItemKind.syllable).isNotEmpty) listenDay = day;
      if (malo.every(s.index.soundReady)) maloDay = day;
    }
    // ignore: avoid_print
    print('Sylaby do słuchania od dnia $listenDay; do czytania na głos od dnia $syllablesDay; cała grupa M/A/L/O w dniu $maloDay; prób: ${s.attempts.length}');
    expect(listenDay, greaterThan(1));
    expect(listenDay, lessThanOrEqualTo(syllablesDay), reason: 'słuchanie sylab wcześniej niż czytanie na głos');
    expect(syllablesDay, greaterThan(1));
    expect(maloDay, greaterThan(0), reason: 'grupa M/A/L/O powinna zostać opanowana');
    expect(s.curriculum.units(ItemKind.syllable).map((u) => u.unit.text), containsAll(['ma', 'la', 'mo', 'lo', 'al', 'ol', 'am', 'om']));
    // Utrwalanie: kolejne 4 dni
    for (var day = maloDay + 1; day <= maloDay + 4; day++) {
      now = DateTime(2026, 9, day, 16);
      for (var k = 0; k < 2; k++) {
        ctl = await s.startSession(guardianPresent: false, asrReady: false, assessment: k == 1);
        await playSession(ctl, day, r);
        await s.endSession(ctl.completedTasks);
      }
    }
    final idx = s.index;
    final cur = s.curriculum;
    final readyLetters = [for (final l in s.content.letters) if (idx.soundReady(l.id)) l.id];
    final open = cur.units(ItemKind.syllable).where((u) => u.access == Access.available).toList();
    expect(open, isNotEmpty);
    for (final u in open) {
      expect(u.unit.graphemes.every(readyLetters.contains), isTrue, reason: '${u.unit.text} wymaga ${u.unit.graphemes}');
    }
    // Po dniach utrwalania każda z M/A/L/O jest gotowa albo – po pomyłce w kolejnym dniu –
    // jawnie wróciła do powtórek (wtedy jej sylaby są czasowo niedostępne).
    for (final x in malo) {
      final review = [Skill.recognizeSound, Skill.saySound].any((sk) => idx.state(x, sk) == MasteryState.doPowtorzenia);
      expect(idx.soundReady(x) || review, isTrue, reason: '$x: ${idx.state(x, Skill.recognizeSound).label} / ${idx.state(x, Skill.saySound).label}');
      if (!idx.soundReady(x)) {
        expect(open.any((u) => u.unit.graphemes.contains(x)), isFalse, reason: 'sylaby z „$x” ukryte na czas powtórki');
      }
    }
    // b/d/p wciąż nieopanowane mimo wielu sesji – brak błędnego awansu
    for (final x in confused) {
      expect(idx.soundReady(x), isFalse, reason: x);
      expect(idx.mastered(x, Skill.recognizeName), isFalse, reason: x);
    }
    // mapa pomyłek pokazuje b/d/p
    final rep = buildReport(s.attempts, s.actions, s.sessions);
    final bdp = rep.confusions.entries.where((e) => confused.contains(e.key.$1) && confused.contains(e.key.$2)).fold(0, (a, e) => a + e.value);
    expect(bdp, greaterThan(5));

    // ignore: avoid_print
    print('Gotowe głoski: $readyLetters; dostępne sylaby: ${open.map((u) => u.unit.text).toList()}; pomyłki b/d/p: $bdp; '
        'potwierdzone umiejętności: ${idx.stats.values.where((x) => x.state == MasteryState.potwierdzone).length}');
    // Utrwalanie: w kolejnych dniach plan zawiera zarówno trudne, jak i opanowane elementy
    now = now.add(const Duration(days: 3));
    final plan = planSession(
      candidates: buildCandidates(s.curriculum, const Capabilities(ttsOk: true)),
      index: s.index,
      now: now,
      n: 20,
      rng: Random(1),
    );
    expect(plan.where((p) => p.bucket == Bucket.due), isNotEmpty);
    expect(plan.where((p) => p.bucket == Bucket.consolidation || (p.bucket == Bucket.due && s.index.state(p.candidate.itemId, p.candidate.skill).isMastered)), isNotEmpty);
    expect(plan.map((p) => p.candidate.itemId).toSet().intersection(confused), isNotEmpty, reason: 'mylone litery wracają do ćwiczeń');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
