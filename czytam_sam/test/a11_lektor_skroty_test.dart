// Lektor Androida rozwija polskie skróty: „em.” → „emerytowany”, „ul.” → „ulica”, „ok.” → „około”.
// Żadne zdanie lektora nie może więc mieć nazwy litery, sylaby ani krótkiego wyrazu tuż przed kropką.
import 'dart:math';

import 'package:czytam_sam/content/models.dart';
import 'package:czytam_sam/engine/curriculum.dart';
import 'package:czytam_sam/engine/mastery.dart';
import 'package:czytam_sam/engine/scheduler.dart';
import 'package:czytam_sam/engine/session.dart';
import 'package:czytam_sam/engine/speech_policy.dart';
import 'package:czytam_sam/engine/types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fixtures.dart';

void main() {
  final content = loadTestContent();

  test('żadne zdanie lektora nie kończy się nazwą litery, sylabą ani krótkim wyrazem z kropką', () async {
    final risky = <String>{
      for (final l in content.letters) ...[l.name, l.nameTts],
      for (final u in [...content.syllables, ...content.words]) if (u.text.length <= 5) u.text,
      for (final l in content.letters) ...l.examples,
      for (final g in content.graphemes) ...[g.text, ...g.examples],
    };
    // Wszystko odblokowane, by zbudować każdy typ zadania.
    final atts = <Attempt>[
      for (final l in [...content.letters.map((l) => l.id), ...content.graphemes.map((g) => g.id)])
        for (final sk in [Skill.recognizeSound, Skill.saySound]) ...correctRun(l, sk, 10, DateTime(2026, 1, 1), 's1'),
    ];
    final idx = ProgressIndex.build(atts, const [], const MasteryConfig(alphabetFirst: false));
    final cur = Curriculum(content, idx, knownFromDiagnosis: content.letters.map((l) => l.id).toSet(),
        manualStages: {ItemKind.word, ItemKind.sentence, ItemKind.reading});
    const cap = Capabilities(ttsOk: true);
    final b = TaskBuilder(content: content, curriculum: cur, cap: cap, rng: Random(5));
    final tasks = <TaskSpec>[];
    Planned p(String id, ItemKind k, Skill s, TaskType t) => Planned(Candidate(id, k, s, t), Bucket.current);
    for (final l in content.letters) {
      tasks
        ..add(b.build(p(l.id, ItemKind.letter, Skill.recognizeName, TaskType.t1HearPoint)))
        ..add(b.build(p(l.id, ItemKind.letter, Skill.recognizeSound, TaskType.t1HearPoint)))
        ..add(b.build(p(l.id, ItemKind.letter, Skill.recognizeName, TaskType.t2PointSay)))
        ..add(b.build(p(l.id, ItemKind.letter, Skill.sayName, TaskType.t3SeeName)))
        ..add(b.build(p(l.id, ItemKind.letter, Skill.caseMatch, TaskType.t4Case)));
    }
    for (final g in content.graphemes) {
      tasks.add(b.build(p(g.id, ItemKind.grapheme, Skill.recognizeSound, TaskType.t1HearPoint)));
    }
    for (final u in [...content.pool(ItemKind.syllable), ...content.pool(ItemKind.word)]) {
      tasks
        ..add(b.build(p(u.id, u.kind, Skill.recognizeUnit, TaskType.t8HearPickUnit)))
        ..add(b.build(p(u.id, u.kind, Skill.segment, TaskType.t5Segment)))
        ..add(b.build(p(u.id, u.kind, Skill.readAloud, TaskType.t6ReadAloud)));
    }
    for (final u in [...content.pool(ItemKind.sentence), ...content.pool(ItemKind.reading)]) {
      tasks.add(b.build(p(u.id, u.kind, Skill.comprehension, TaskType.t7Comprehension)));
    }

    final spoken = <String>[];
    for (final t in tasks) {
      if (t.promptMode == PromptMode.tts) spoken.add(t.promptSpeech);
      for (final variant in [0, 1]) {
        final c = SessionController(profileId: 'p', sessionId: 's', tasks: [t], sink: (a) async {}, guardianPresent: variant == 1, mode: EvaluationMode.guardian);
        c.promptDelivered();
        if (t.type == TaskType.t5Segment) {
          final seq = variant == 0 ? t.correctSequence : t.correctSequence.reversed.toList();
          final used = <int>{};
          for (final g in seq) {
            final i = List.generate(t.optionIds.length, (i) => i).firstWhere((i) => t.optionIds[i] == g && !used.contains(i));
            used.add(i);
            c.tapTile(i);
          }
          await c.submitTiles();
        } else if (t.hasTouch) {
          await c.touch(variant == 0 ? t.correctIndex : (t.correctIndex + 1) % t.options.length);
        }
        if (c.phase == Phase.awaitingSpeech) await c.speechFinished(null);
        if (c.phase == Phase.awaitingGuardian) await c.guardianRate(variant == 0 ? GuardianVerdict.correct : GuardianVerdict.notYet);
        if (c.feedback?.spoken != null) spoken.add(c.feedback!.spoken!);
      }
    }
    expect(spoken.length, greaterThan(500));
    final bad = <String>[];
    for (final text in spoken) {
      for (final r in risky) {
        if (RegExp('(^|[\\s:,„(])${RegExp.escape(r)}\\.', caseSensitive: false).hasMatch(text)) bad.add('„$r.” w: $text');
      }
    }
    expect(bad.toSet().toList(), isEmpty);
  });

  test('„ok” nie jest podawane lektorem (czytane jako „okej”)', () {
    const cap = Capabilities(ttsOk: true);
    expect(cap.canSpeak('syl_ok'), isFalse);
    expect(cap.canSpeak('syl_ma'), isTrue);
  });
}
