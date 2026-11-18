// Uruchom: dart run tool/validate_content.dart
// Sprawdza materiał w assets/content i kończy się kodem 1 przy błędach.
import 'dart:convert';
import 'dart:io';

import 'package:czytam_sam/content/models.dart';
import 'package:czytam_sam/content/validator.dart';

Map<String, dynamic> _load(String name) =>
    jsonDecode(File('assets/content/$name.json').readAsStringSync()) as Map<String, dynamic>;

void main() {
  final c = ContentBundle.fromJsonMaps(
    letters: _load('letters'),
    syllables: _load('syllables'),
    words: _load('words'),
    sentences: _load('sentences'),
    readings: _load('readings'),
  );
  final issues = validateContent(c);
  for (final i in issues) {
    stdout.writeln(i);
  }
  final errors = issues.where((i) => i.isError).length;
  stdout.writeln('Litery: ${c.letters.length}, grafemy: ${c.graphemes.length}, '
      'sylaby: ${c.pool(ItemKind.syllable).length}, wyrazy: ${c.pool(ItemKind.word).length}, '
      'zdania: ${c.pool(ItemKind.sentence).length}, czytanki: ${c.pool(ItemKind.reading).length}. Błędy: $errors');
  exit(errors == 0 ? 0 : 1);
}
