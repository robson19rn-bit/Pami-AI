import 'dart:convert';
import 'dart:io';

import 'package:czytam_sam/content/models.dart';
import 'package:czytam_sam/engine/types.dart';

Map<String, dynamic> _load(String n) => jsonDecode(File('assets/content/$n.json').readAsStringSync()) as Map<String, dynamic>;

ContentBundle loadTestContent() => ContentBundle.fromJsonMaps(
      letters: _load('letters'),
      syllables: _load('syllables'),
      words: _load('words'),
      sentences: _load('sentences'),
      readings: _load('readings'),
    );

int _n = 0;

/// Fabryka prób do testów.
Attempt att(
  String item,
  Skill skill,
  Outcome o, {
  DateTime? at,
  String session = 's1',
  bool hinted = false,
  bool firstTry = true,
  bool assisted = false,
  Evidence? evidence,
  String? chosen,
  ItemKind kind = ItemKind.letter,
  TaskType task = TaskType.t1HearPoint,
}) =>
    Attempt(
      id: 'a${_n++}',
      profileId: 'p',
      sessionId: session,
      at: at ?? DateTime(2026, 1, 1, 10, 0, _n % 60),
      itemId: item,
      kind: kind,
      skill: skill,
      task: task,
      outcome: o,
      evidence: evidence ?? (skill.isSpeech ? Evidence.guardian : Evidence.touch),
      hinted: hinted,
      firstTry: firstTry,
      assisted: assisted,
      chosenId: chosen,
    );

/// [n] poprawnych prób w danej sesji/dniu.
List<Attempt> correctRun(String item, Skill skill, int n, DateTime day, String session, {ItemKind kind = ItemKind.letter}) => [
      for (var i = 0; i < n; i++) att(item, skill, Outcome.correct, at: day.add(Duration(minutes: i)), session: session, kind: kind)
    ];
