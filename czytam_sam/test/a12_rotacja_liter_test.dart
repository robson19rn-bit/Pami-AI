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
}
