// (10) (11) (12) (14) (15) – dobór zadań i odblokowywanie etapów.
import 'dart:math';

import 'package:czytam_sam/content/models.dart';
import 'package:czytam_sam/engine/curriculum.dart';
import 'package:czytam_sam/engine/mastery.dart';
import 'package:czytam_sam/engine/scheduler.dart';
import 'package:czytam_sam/engine/session.dart';
import 'package:czytam_sam/engine/types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fixtures.dart';

const cfg = MasteryConfig();
final day1 = DateTime(2026, 4, 1, 9), day2 = DateTime(2026, 4, 2, 9), day5 = DateTime(2026, 4, 5, 9);

/// Opanowanie głoski (rozpoznanie + wypowiedź) w dwóch dniach.
List<Attempt> soundMastered(String id) => [
      ...correctRun(id, Skill.recognizeSound, 10, day1, 's1'),
      ...correctRun(id, Skill.recognizeSound, 1, day2, 's2'),
      ...correctRun(id, Skill.saySound, 5, day1, 's1'),
      ...correctRun(id, Skill.saySound, 1, day2, 's2'),
    ];

void main() {
  final content = loadTestContent();

  test('(10) zaplanowane powtórki trudnych liter mają pierwszeństwo, ale utrwalanie zostaje', () {
    final a = [
      // b – do powtórzenia (opanowane, potem błąd następnego dnia)
      ...correctRun('b', Skill.recognizeName, 10, day1, 's1'),
      att('b', Skill.recognizeName, Outcome.incorrect, at: day2, session: 's2', chosen: 'd'),
      // m, a – potwierdzone, termin powtórki jeszcze nie minął
      for (final x in ['m', 'a', 'o', 'l']) ...[...correctRun(x, Skill.recognizeName, 10, day1, 's1'), ...correctRun(x, Skill.recognizeName, 1, day2, 's2')],
    ];
    final idx = ProgressIndex.build(a, const [], cfg);
    expect(idx.state('b', Skill.recognizeName), MasteryState.doPowtorzenia);
    final cands = [
      for (final x in ['b', 'm', 'a', 'o', 'l', 't', 'e']) Candidate(x, ItemKind.letter, Skill.recognizeName, TaskType.t1HearPoint),
    ];
    final plan = planSession(candidates: cands, index: idx, now: day2.add(const Duration(hours: 1)), n: 10, rng: Random(3));
    final due = plan.where((p) => p.bucket == Bucket.due).toList();
    expect(due.map((p) => p.candidate.itemId).toSet(), {'b'});
    expect(due.length, greaterThanOrEqualTo(plan.where((p) => p.bucket == Bucket.current).length ~/ 2));
    expect(plan.where((p) => p.bucket == Bucket.consolidation), isNotEmpty, reason: 'utrwalanie nie może zniknąć');
  });

  test('(10b) proporcje 60/25/15 przy pełnych koszykach', () {
    final a = <Attempt>[];
    final due = ['b', 'd', 'p', 'n', 'u', 'w'], cons = ['m', 'a', 'o', 'l'], cur = ['t', 'e', 'i', 's', 'k'];
    for (final x in due) {
      a.addAll([...correctRun(x, Skill.recognizeName, 10, day1, 's1'), att(x, Skill.recognizeName, Outcome.incorrect, at: day2, session: 's2')]);
    }
    for (final x in cons) {
      a.addAll([...correctRun(x, Skill.recognizeName, 10, day1, 's1'), ...correctRun(x, Skill.recognizeName, 1, day2, 's2')]);
    }
    final idx = ProgressIndex.build(a, const [], cfg);
    final cands = [for (final x in [...due, ...cons, ...cur]) Candidate(x, ItemKind.letter, Skill.recognizeName, TaskType.t1HearPoint)];
    final plan = planSession(candidates: cands, index: idx, now: day2, n: 20, rng: Random(1));
    int n(Bucket b) => plan.where((p) => p.bucket == b).length;
    expect(n(Bucket.due), 12);
    expect(n(Bucket.current), 5);
    expect(n(Bucket.consolidation), 3);
  });

  test('(11) pozycje poprawnych odpowiedzi są zrównoważone', () {
    final bal = PositionBalancer(Random(5));
    for (final k in [2, 3, 4, 6]) {
      for (var i = 0; i < 600; i++) {
        bal.pick(k);
      }
      final c = bal.counts[k]!;
      expect(c.reduce(max) - c.reduce(min), lessThanOrEqualTo(1), reason: 'opcje: $k, rozkład: $c');
    }
  });

  test('(11b) w zbudowanych zadaniach pozycja poprawnej odpowiedzi jest zrównoważona', () {
    final idx = ProgressIndex.build(const [], const [], cfg);
    final cur = Curriculum(content, idx);
    final b = TaskBuilder(content: content, curriculum: cur, cap: const Capabilities(ttsOk: true), rng: Random(9));
    final counts = <int, int>{};
    for (var i = 0; i < 400; i++) {
      final t = b.build(Planned(Candidate('a', ItemKind.letter, Skill.recognizeName, TaskType.t1HearPoint), Bucket.current));
      expect(t.options.length, 2, reason: 'stan „nowe” → 2 opcje');
      counts[t.correctIndex] = (counts[t.correctIndex] ?? 0) + 1;
    }
    expect((counts[0]! - counts[1]!).abs(), lessThanOrEqualTo(1));
  });

  test('(12) brak bezpośredniego powtórzenia tego samego celu, jeśli są alternatywy', () {
    final idx = ProgressIndex.build(const [], const [], cfg);
    for (var seed = 0; seed < 50; seed++) {
      final cands = [
        for (final x in ['a', 'm', 'o'])
          for (final sk in [Skill.recognizeName, Skill.caseMatch]) Candidate(x, ItemKind.letter, sk, sk == Skill.caseMatch ? TaskType.t4Case : TaskType.t1HearPoint)
      ];
      final plan = planSession(candidates: cands, index: idx, now: day1, n: 12, rng: Random(seed));
      for (var i = 1; i < plan.length; i++) {
        expect(plan[i].candidate.itemId, isNot(plan[i - 1].candidate.itemId), reason: 'seed $seed, pozycja $i');
      }
    }
  });

  test('liczba opcji rośnie ze stanem: 2/3/4/6; w stanie „nowe” bez par mylonych', () {
    expect([for (final s in MasteryState.values) optionCountFor(s)], [2, 3, 4, 6, 6, 4]);
    final st = SkillStats('b', Skill.recognizeName);
    final d = pickDistractors(target: 'b', count: 1, stats: st, staticConfusable: const ['d', 'p'], activePool: const ['a', 'b', 'd', 'p', 'm'], fullPool: content.letters.map((l) => l.id).toList(), rng: Random(1));
    expect(d.single, isNot(anyOf('d', 'p')));
    final st2 = SkillStats('b', Skill.recognizeName)..state = MasteryState.cwiczone..confusions['d'] = 3;
    final d2 = pickDistractors(target: 'b', count: 3, stats: st2, staticConfusable: const ['d', 'p'], activePool: const ['a', 'b', 'm'], fullPool: content.letters.map((l) => l.id).toList(), rng: Random(1));
    expect(d2.first, 'd', reason: 'najczęściej mylona litera jako pierwszy dystraktor');
    expect(d2, contains('p'));
  });

  test('(14) sylaby wymagają konkretnych głosek, ale nie całego alfabetu', () {
    final a = [...soundMastered('m'), ...soundMastered('a')];
    final cur = Curriculum(content, ProgressIndex.build(a, const [], cfg));
    final avail = cur.units(ItemKind.syllable).where((u) => u.access == Access.available).map((u) => u.unit.text).toSet();
    expect(avail, containsAll(['ma', 'am']));
    expect(avail.contains('ta'), isFalse);
    expect(avail.contains('mo'), isFalse);
    expect(avail.length, 2, reason: 'tylko sylaby złożone z opanowanych głosek');
    // bez opanowania głoski (tylko nazwa) – brak sylab
    final onlyNames = [...correctRun('m', Skill.recognizeName, 10, day1, 's1'), ...correctRun('a', Skill.recognizeName, 10, day1, 's1')];
    expect(Curriculum(content, ProgressIndex.build(onlyNames, const [], cfg)).units(ItemKind.syllable), isEmpty);
  });

  test('(15) wyrazy i zdania nie zawierają bez oznaczenia elementów spoza poziomu dziecka', () {
    final letters = ['m', 'a', 'l', 'o', 't', 'k'];
    final a = [for (final x in letters) ...soundMastered(x)];
    // etap wyrazów osiągnięty: 3 sylaby przeczytane samodzielnie
    for (final syl in ['syl_ma', 'syl_la', 'syl_to']) {
      a.addAll([
        ...correctRun(syl, Skill.readAloud, 5, day1, 's1', kind: ItemKind.syllable),
        ...correctRun(syl, Skill.readAloud, 1, day2, 's2', kind: ItemKind.syllable),
      ]);
    }
    final idx = ProgressIndex.build(a, const [], cfg);
    final cur = Curriculum(content, idx);
    final words = cur.units(ItemKind.word);
    expect(words, isNotEmpty);
    for (final w in words) {
      expect(w.access, Access.available);
      expect(w.unit.graphemes.every(letters.contains), isTrue, reason: w.unit.text);
    }
    expect(words.map((w) => w.unit.text), containsAll(['mama', 'tata', 'lato', 'oko', 'kot']));
    expect(cur.units(ItemKind.sentence), isEmpty, reason: 'zdania wymagają opanowanych wyrazów');

    // ręczne odblokowanie: materiał oznaczony jako „z pomocą” z listą brakujących głosek
    final manual = Curriculum(content, idx, manualStages: {ItemKind.sentence});
    final sent = manual.units(ItemKind.sentence);
    expect(sent, isNotEmpty);
    for (final s in sent) {
      expect(s.access, Access.manualAssisted);
    }
    final cands = buildCandidates(manual, const Capabilities(ttsOk: true));
    expect(cands.where((c) => c.kind == ItemKind.sentence).every((c) => c.assisted), isTrue);
  });

  test('aktywne litery: najwyżej 4 nowe naraz; diagnoza wprowadza znane litery od razu', () {
    final idx = ProgressIndex.build(const [], const [], cfg);
    expect(Curriculum(content, idx).activeLetters().map((l) => l.id), ['a', 'm', 'o', 'l']);
    final withDiag = Curriculum(content, idx, knownFromDiagnosis: {'k', 'ż'});
    expect(withDiag.activeLetters().map((l) => l.id), containsAll(['k', 'ż']));
  });
}
