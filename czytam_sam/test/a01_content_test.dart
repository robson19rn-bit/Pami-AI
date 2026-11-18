// (01) wszystkie 32 polskie litery, małe/wielkie, diakrytyki; walidacja materiału.
import 'package:czytam_sam/content/models.dart';
import 'package:czytam_sam/content/tokenizer.dart';
import 'package:czytam_sam/content/validator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fixtures.dart';

void main() {
  final c = loadTestContent();

  test('(01) 32 litery polskiego alfabetu w poprawnej kolejności i z poprawnymi parami wielka/mała', () {
    const upper = 'AĄBCĆDEĘFGHIJKLŁMNŃOÓPRSŚTUWYZŹŻ';
    const lower = 'aąbcćdeęfghijklłmnńoóprsśtuwyzźż';
    expect(c.letters.length, 32);
    for (var i = 0; i < 32; i++) {
      final l = c.letter(lower[i]);
      expect(l, isNotNull, reason: 'brak ${lower[i]}');
      expect(l!.upper, upper[i]);
      expect(l.lower, lower[i]);
      expect(l.name, isNotEmpty);
      expect(l.sounds, isNotEmpty);
    }
    // diakrytyki są osobnymi literami, a nie odmianami
    for (final d in ['ą', 'ć', 'ę', 'ł', 'ń', 'ó', 'ś', 'ź', 'ż']) {
      expect(c.letter(d), isNotNull);
      expect(c.letter(d)!.upper.toLowerCase(), d);
    }
    // q, v, x nie należą do polskiego alfabetu
    for (final x in ['q', 'v', 'x']) {
      expect(c.letter(x), isNull);
    }
  });

  test('dwuznaki i zmiękczenia są osobnymi grafemami, nie literami alfabetu', () {
    for (final g in ['ch', 'cz', 'dz', 'dź', 'dż', 'rz', 'sz']) {
      expect(c.grapheme(g), isNotNull);
      expect(c.letter(g), isNull);
    }
    expect(tokenizeGraphemes('szkoła'), ['sz', 'k', 'o', 'ł', 'a']);
    expect(tokenizeGraphemes('dziadek'), ['dzi', 'a', 'd', 'e', 'k']);
    expect(tokenizeGraphemes('dżem'), ['dż', 'e', 'm']);
    expect(tokenizeGraphemes('rzeka'), ['rz', 'e', 'k', 'a']);
  });

  test('brak fałszywej reguły „jedna litera = jeden dźwięk” dla ą, ę, u/ó, rz/ż, ch/h', () {
    expect(c.letter('ą')!.sounds.length, greaterThan(1));
    expect(c.letter('ę')!.sounds.length, greaterThan(1));
    expect(c.letter('ó')!.sounds.single.ipa, c.letter('u')!.sounds.single.ipa);
    expect(c.grapheme('rz')!.sounds.first.ipa, c.letter('ż')!.sounds.first.ipa);
    expect(c.grapheme('ch')!.sounds.single.ipa, c.letter('h')!.sounds.single.ipa);
  });

  test('materiał spełnia minimum ilościowe i przechodzi walidację', () {
    final errors = validateContent(c).where((i) => i.isError).toList();
    expect(errors, isEmpty, reason: errors.join('\n'));
    expect(c.pool(ItemKind.syllable).length, greaterThanOrEqualTo(60));
    expect(c.pool(ItemKind.word).length, greaterThanOrEqualTo(100));
    expect(c.pool(ItemKind.sentence).length, greaterThanOrEqualTo(30));
    expect(c.pool(ItemKind.reading).length, greaterThanOrEqualTo(10));
  });

  test('pozycje oznaczone do weryfikacji są wyłączone z puli', () {
    final flagged = c.words.where((w) => w.needsReview).toList();
    expect(flagged, isNotEmpty);
    for (final f in flagged) {
      expect(c.pool(ItemKind.word).contains(f), isFalse);
    }
  });

  test('walidator wykrywa błędną pozycję', () {
    final bad = ContentBundle(
      letters: c.letters,
      graphemes: c.graphemes,
      syllables: [ReadingUnit(id: 'x', kind: ItemKind.syllable, text: 'ma', graphemes: ['m'], level: 1, goal: 'cel', pronunciation: 'ma')],
      words: const [],
      sentences: const [],
      readings: const [],
    );
    final errs = validateContent(bad).where((i) => i.isError).map((e) => e.toString()).join('\n');
    expect(errs, contains('zadeklarowane grafemy'));
    expect(errs, contains('minimum 100'));
  });
}
