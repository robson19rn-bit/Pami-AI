// Regresja: aplikacja nie może utknąć na kilku literach (zgłoszenie z używania: 8 lekcji, ciągle ~6 liter).
import 'dart:math';

import 'package:czytam_sam/content/models.dart';
import 'package:czytam_sam/engine/session.dart';
import 'package:czytam_sam/engine/types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';

void main() {
  test('8 lekcji bez diagnozy: kolejne litery wchodzą, a lekcje obejmują wiele różnych liter', () async {
    var now = DateTime(2026, 11, 10, 16);
    final s = await testState(clock: () => now, tts: FakeTts(), seed: 3);
    await s.setSetting('ttsOk', true);
    final r = Random(1);
    final perLesson = <int>[];
    final everSeen = <String>{};
    for (var lesson = 1; lesson <= 8; lesson++) {
      final c = await s.startSession(guardianPresent: false, asrReady: false);
      final letters = <String>{};
      while (!c.finished) {
        final t = c.current!;
        if (t.kind == ItemKind.letter) letters.add(t.itemId);
        if (c.phase == Phase.awaitingPrompt) c.promptDelivered();
        if (c.phase == Phase.awaitingTouch) {
          if (t.type == TaskType.t5Segment) {
            final used = <int>{};
            for (final g in t.correctSequence) {
              final i = List.generate(t.optionIds.length, (i) => i).firstWhere((i) => t.optionIds[i] == g && !used.contains(i));
              used.add(i);
              c.tapTile(i);
            }
            await c.submitTiles();
          } else {
            await c.touch(r.nextDouble() < 0.9 ? t.correctIndex : (t.correctIndex + 1) % t.options.length);
          }
        }
        if (c.phase == Phase.awaitingSpeech) await c.speechFinished(null);
        c.next();
      }
      await s.endSession(c.completedTasks);
      perLesson.add(letters.length);
      everSeen.addAll(letters);
      now = now.add(const Duration(hours: 12));
    }
    // ignore: avoid_print
    print('różne litery w lekcjach: $perLesson; łącznie ćwiczone: ${everSeen.length}; aktywne: ${s.curriculum.activeLetters().length}');
    expect(s.curriculum.activeLetters().length, greaterThanOrEqualTo(12));
    expect(everSeen.length, greaterThanOrEqualTo(12));
    expect(perLesson.skip(1).every((n) => n >= 4), isTrue, reason: '$perLesson');
  });

  test('najpierw cały alfabet: żadnych sylab, dopóki wszystkie 32 litery nie są pewnie rozpoznawane; potem sylaby', () async {
    var now = DateTime(2026, 11, 10, 16);
    final s = await testState(clock: () => now, tts: FakeTts(), seed: 5);
    await s.setSetting('ttsOk', true);
    expect(s.config.alphabetFirst, isTrue, reason: 'domyślnie najpierw cały alfabet');
    final r = Random(2);
    int? allFamiliar, firstSyllable;
    for (var lesson = 1; lesson <= 60; lesson++) {
      final c = await s.startSession(guardianPresent: false, asrReady: false);
      while (!c.finished) {
        final t = c.current!;
        if (t.kind != ItemKind.letter) {
          firstSyllable ??= lesson;
          expect(allFamiliar, isNotNull, reason: 'lekcja $lesson: ${t.itemId} przed poznaniem całego alfabetu');
        }
        if (c.phase == Phase.awaitingPrompt) c.promptDelivered();
        if (c.phase == Phase.awaitingTouch) {
          if (t.type == TaskType.t5Segment) {
            final used = <int>{};
            for (final g in t.correctSequence) {
              final i = List.generate(t.optionIds.length, (i) => i).firstWhere((i) => t.optionIds[i] == g && !used.contains(i));
              used.add(i);
              c.tapTile(i);
            }
            await c.submitTiles();
          } else {
            await c.touch(r.nextDouble() < 0.9 ? t.correctIndex : (t.correctIndex + 1) % t.options.length);
          }
        }
        if (c.phase == Phase.awaitingSpeech) await c.speechFinished(null);
        c.next();
      }
      await s.endSession(c.completedTasks);
      now = now.add(const Duration(hours: 12));
      if (allFamiliar == null && s.curriculum.alphabetComplete) allFamiliar = lesson;
      if (firstSyllable != null) break;
    }
    // ignore: avoid_print
    print('cały alfabet po lekcji $allFamiliar; pierwsza sylaba w lekcji $firstSyllable');
    expect(allFamiliar, isNotNull);
    expect(allFamiliar, lessThanOrEqualTo(30), reason: 'dziecko odpowiadające dobrze nie może czekać w nieskończoność');
    expect(firstSyllable, allFamiliar! + 1, reason: 'sylaby od razu w następnej lekcji');
  });

  test('dziecko jak wnuk: zna większość liter, myli b/p/d, trudne j g f h i litery ze znakami (zaznaczone przez opiekuna)', () async {
    var now = DateTime(2026, 11, 10, 16);
    final s = await testState(clock: () => now, tts: FakeTts(), seed: 9);
    await s.setSetting('ttsOk', true);
    const hard = ['b', 'p', 'd', 'j', 'g', 'f', 'h', 'ą', 'ę', 'ć', 'ś', 'ź', 'ż', 'ń', 'ó'];
    await s.setSetting('profile.${s.profileId}.hardLetters', hard);
    final r = Random(4);
    final seenInLessons = <int, Set<String>>{};
    double p(String target, int lesson) => hard.contains(target) ? min(0.95, 0.5 + lesson * 0.03) : 0.95;
    int? done;
    for (var lesson = 1; lesson <= 60 && done == null; lesson++) {
      final c = await s.startSession(guardianPresent: false, asrReady: false);
      final seen = seenInLessons[lesson] = <String>{};
      while (!c.finished) {
        final t = c.current!;
        expect(t.kind, ItemKind.letter, reason: 'pierwsza część: tylko zadania z literami');
        expect(t.type == TaskType.t1HearPoint && t.skill == Skill.recognizeSound, isFalse, reason: 'bez zadań ze słowami-nośnikami');
        seen.add(t.itemId);
        if (c.phase == Phase.awaitingPrompt) c.promptDelivered();
        if (c.phase == Phase.awaitingTouch) {
          var wrong = (t.correctIndex + 1) % t.options.length;
          final conf = t.optionIds.indexWhere((x) => ['b', 'p', 'd'].contains(x) && x != t.itemId);
          if (['b', 'p', 'd'].contains(t.itemId) && conf >= 0) wrong = conf;
          await c.touch(r.nextDouble() < p(t.itemId, lesson) ? t.correctIndex : wrong);
        }
        if (c.phase == Phase.awaitingSpeech) await c.speechFinished(null);
        c.next();
      }
      await s.endSession(c.completedTasks);
      now = now.add(const Duration(hours: 12));
      if (s.curriculum.alphabetComplete) done = lesson;
    }
    final hardInFirst3 = {for (var l = 1; l <= 3; l++) ...seenInLessons[l]!}.intersection(hard.toSet());
    // ignore: avoid_print
    print('wnuk: cały alfabet po lekcji $done; trudne litery w pierwszych 3 lekcjach: ${hardInFirst3.length} z ${hard.length}');
    expect(done, isNotNull);
    expect(hardInFirst3.length, greaterThanOrEqualTo(8), reason: 'trudne litery od razu w lekcjach');
  });
}
