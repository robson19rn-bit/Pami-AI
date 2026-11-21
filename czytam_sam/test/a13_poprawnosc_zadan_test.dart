// Każde zadanie z literą: lektor prosi o literę X → poprawna (podświetlona) odpowiedź to dokładnie X.
import 'dart:math';

import 'package:czytam_sam/content/models.dart';
import 'package:czytam_sam/engine/curriculum.dart';
import 'package:czytam_sam/engine/mastery.dart';
import 'package:czytam_sam/engine/scheduler.dart';
import 'package:czytam_sam/engine/session.dart';
import 'package:czytam_sam/engine/types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fixtures.dart';

void main() {
  final content = loadTestContent();

  test('nazwy liter wymawiane przez lektora są różne (ą/ę/ó opisowo)', () {
    final names = content.letters.map((l) => l.nameTts).toList();
    expect(names.toSet().length, 32);
    expect(content.letter('ą')!.nameTts, 'a z ogonkiem');
    expect(content.letter('ę')!.nameTts, 'e z ogonkiem');
  });

  test('w każdym zadaniu z literą poprawna odpowiedź = litera z polecenia; opcje bez powtórzeń', () {
    for (final mastered in [false, true]) {
      final atts = mastered
          ? [for (final l in content.letters) for (final sk in [Skill.recognizeName, Skill.caseMatch]) ...correctRun(l.id, sk, 10, DateTime(2026, 1, 1), 's1')]
          : <Attempt>[];
      final idx = ProgressIndex.build(atts, const [], const MasteryConfig());
      final cur = Curriculum(content, idx, knownFromDiagnosis: content.letters.map((l) => l.id).toSet());
      final b = TaskBuilder(content: content, curriculum: cur, cap: const Capabilities(ttsOk: true), rng: Random(11));
      for (var round = 0; round < 6; round++) {
        for (final l in content.letters) {
          for (final (sk, type) in [(Skill.recognizeName, TaskType.t1HearPoint), (Skill.recognizeName, TaskType.t2PointSay), (Skill.caseMatch, TaskType.t4Case)]) {
            final t = b.build(Planned(Candidate(l.id, ItemKind.letter, sk, type), Bucket.current));
            expect(t.optionIds[t.correctIndex], l.id, reason: '${l.id} ${type.name}');
            expect(t.optionIds.toSet().length, t.optionIds.length);
            expect(t.options.toSet().length, t.options.length, reason: 'dwie identycznie wyglądające opcje');
            final shown = t.options[t.correctIndex];
            expect(shown == l.lower || shown == l.upper, isTrue);
            if (type != TaskType.t4Case) {
              expect(t.promptSpeech, startsWith('Wskaż literę ${l.nameTts} na ekranie'));
              // żadna inna opcja nie ma tej samej nazwy
              for (final o in t.optionIds.where((x) => x != l.id)) {
                expect(content.letter(o)!.nameTts, isNot(l.nameTts));
              }
            } else {
              // wielka–mała: pokazana litera i poprawna odpowiedź to ta sama litera w drugiej wielkości
              expect(t.display == l.lower || t.display == l.upper, isTrue);
              expect(shown, isNot(t.display));
            }
          }
        }
      }
    }
  });
}
