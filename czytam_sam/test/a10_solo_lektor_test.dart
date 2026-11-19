// Dziecko ćwiczy samo – lektor prowadzi cały proces; opiekun tylko ocenia wypowiedzi.
import 'dart:math';

import 'package:czytam_sam/content/models.dart';
import 'package:czytam_sam/content/tokenizer.dart';
import 'package:czytam_sam/engine/curriculum.dart';
import 'package:czytam_sam/engine/mastery.dart';
import 'package:czytam_sam/engine/scheduler.dart';
import 'package:czytam_sam/engine/session.dart';
import 'package:czytam_sam/engine/types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fixtures.dart';

void main() {
  final content = loadTestContent();

  test('głoska podawana przez lektora w słowie: jednoznaczne zadanie dla każdej litery i grafemu', () {
    final ids = [...content.letters.map((l) => l.id), ...content.graphemes.map((g) => g.id)];
    final lines = <String>[];
    for (final id in ids) {
      final c = carrierFor(content, id);
      final t = tokenizeGraphemes(c.word);
      expect(t, contains(id), reason: '$id: słowo ${c.word}');
      if (c.where == 'na początku') expect(t.first, id);
      if (c.where == 'na końcu') expect(t.last, id);
      lines.add('$id → ${c.where} słowa „${c.word}”');
    }
    // ignore: avoid_print
    print(lines.join('\n'));
  });

  test('zadanie z głoską: lektor (nie opiekun), bez liter ze słowa i bez liter brzmiących tak samo', () {
    // Wszystkie umiejętności „opanowane”, by wymusić 6 opcji (najtrudniejszy przypadek).
    final atts = <Attempt>[];
    for (final l in content.letters) {
      atts.addAll(correctRun(l.id, Skill.recognizeSound, 10, DateTime(2026, 1, 1), 's1'));
    }
    for (final g in content.graphemes) {
      atts.addAll(correctRun(g.id, Skill.recognizeSound, 10, DateTime(2026, 1, 1), 's1', kind: ItemKind.grapheme));
    }
    final idx = ProgressIndex.build(atts, const [], const MasteryConfig());
    final cur = Curriculum(content, idx, knownFromDiagnosis: content.letters.map((l) => l.id).toSet());
    final b = TaskBuilder(content: content, curriculum: cur, cap: const Capabilities(ttsOk: true), rng: Random(4));
    for (final l in [...content.letters.map((l) => (l.id, ItemKind.letter)), ...content.graphemes.map((g) => (g.id, ItemKind.grapheme))]) {
      for (var k = 0; k < 5; k++) {
        final t = b.build(Planned(Candidate(l.$1, l.$2, Skill.recognizeSound, TaskType.t1HearPoint), Bucket.current));
        expect(t.promptMode, PromptMode.tts, reason: l.$1);
        expect(t.promptSpeech, contains('słowa'));
        final carrier = carrierFor(content, l.$1);
        expect(t.optionIds.where((x) => x == l.$1).length, 1);
        for (final x in t.optionIds.where((x) => x != l.$1)) {
          expect(carrier.tokens.contains(x), isFalse, reason: '${l.$1}: „$x” jest w słowie ${carrier.word}');
          expect(homophones(l.$1).contains(x), isFalse, reason: '${l.$1}: „$x” brzmi tak samo');
        }
        expect(t.options.length, greaterThanOrEqualTo(2));
      }
    }
  });

  test('dziecko samo: brak zadań wymagających opiekuna; głoski i sylaby prowadzi lektor', () {
    final idx = ProgressIndex.build(const [], const [], const MasteryConfig());
    final cands = buildCandidates(Curriculum(content, idx), const Capabilities(ttsOk: true));
    expect(cands.where((c) => c.task == TaskType.t3SeeName), isEmpty, reason: 'nikt nie oceni samej wypowiedzi');
    expect(cands.where((c) => c.skill == Skill.recognizeSound), isNotEmpty, reason: 'głoski podaje lektor');
    expect(cands.where((c) => c.task == TaskType.t2PointSay), isNotEmpty, reason: 'dziecko nadal próbuje mówić');
  });

  test('ocena z opiekunem: wyłącznie zadania mówione', () {
    final atts = [
      for (final l in ['m', 'a']) ...[
        ...correctRun(l, Skill.recognizeSound, 10, DateTime(2026, 1, 1), 's1'),
        ...correctRun(l, Skill.saySound, 5, DateTime(2026, 1, 1), 's1'),
      ]
    ];
    final idx = ProgressIndex.build(atts, const [], const MasteryConfig());
    final cands = buildCandidates(Curriculum(content, idx), const Capabilities(ttsOk: true, assessmentOnly: true));
    expect(cands, isNotEmpty);
    expect(cands.every((c) => c.skill.isSpeech), isTrue);
    expect(cands.where((c) => c.kind == ItemKind.syllable && c.skill == Skill.readAloud), isNotEmpty);
  });
}
