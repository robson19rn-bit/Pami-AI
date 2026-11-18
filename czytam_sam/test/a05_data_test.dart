// (16) (17) (18) (21) (22) – raport, trwałość, kopia, działania opiekuna, migracje.
import 'dart:convert';
import 'dart:io';

import 'package:czytam_sam/content/models.dart';
import 'package:czytam_sam/data/backup.dart';
import 'package:czytam_sam/data/database.dart';
import 'package:czytam_sam/engine/report.dart';
import 'package:czytam_sam/engine/types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/fakes.dart';
import 'helpers/fixtures.dart';

final day = DateTime(2026, 5, 4, 17);

List<Attempt> mixed() => [
      att('k', Skill.recognizeName, Outcome.correct, at: day),
      att('k', Skill.recognizeName, Outcome.correct, at: day, hinted: true),
      att('k', Skill.recognizeName, Outcome.incorrect, at: day, chosen: 'h'),
      att('k', Skill.sayName, Outcome.noSpeech, at: day, evidence: Evidence.asr),
      att('k', Skill.sayName, Outcome.uncertain, at: day, evidence: Evidence.asr),
      att('k', Skill.sayName, Outcome.notEvaluated, at: day, evidence: Evidence.none),
      att('k', Skill.sayName, Outcome.correct, at: day, evidence: Evidence.guardian),
      att('w_mama', Skill.readAloud, Outcome.correct, at: day, evidence: Evidence.asr, kind: ItemKind.word),
    ];

void main() {
  sqfliteFfiInit();

  test('(16) raport przelicza kategorie bez zacierania różnic', () {
    final r = buildReport(mixed(), const [], const []);
    expect(r.total.total, 8);
    expect(r.total[ReportCategory.independentCorrect], 3);
    expect(r.total[ReportCategory.hintedCorrect], 1);
    expect(r.total[ReportCategory.incorrect], 1);
    expect(r.total[ReportCategory.noSpeech], 1);
    expect(r.total[ReportCategory.uncertain], 1);
    expect(r.total[ReportCategory.notEvaluated], 1);
    expect(r.speech.confirmedByGuardian, 1);
    expect(r.speech.confirmedByAsr, 1);
    expect(r.speech.unconfirmed, 3);
    expect(r.confusions[('k', 'h')], 1);
    expect(r.accuracyAfterHint, 1.0);
    expect(r.independentAttempts, 4);
  });

  test('(17) po zamknięciu i ponownym otwarciu bazy postęp pozostaje', () async {
    final dir = await Directory.systemTemp.createTemp('czytam');
    final path = p.join(dir.path, 'test.db');
    var db = await ProgressDb.open(databaseFactoryFfi, path);
    final s1 = await testState(db: db);
    for (final a in correctRun('m', Skill.recognizeName, 10, day, 's1')) {
      await s1.record(a);
    }
    final before = s1.index.state('m', Skill.recognizeName);
    await db.close();

    db = await ProgressDb.open(databaseFactoryFfi, path); // „restart aplikacji”
    final s2 = await testState(db: db);
    expect(s2.attempts.length, 10);
    expect(s2.index.state('m', Skill.recognizeName), before);
    expect(before, MasteryState.opanowaneWarunkowo);
    await db.close();
    await dir.delete(recursive: true);
  });

  test('(18) eksport/import zachowuje historię i nie duplikuje zdarzeń', () async {
    final src = await testState();
    for (final a in mixed()) {
      await src.record(a);
    }
    await src.addAction(GuardianActionType.rateSpeech, target: src.attempts[4].id, value: 'correct');
    await src.setSetting('ttsOk', true);
    final json = await src.exportJson();
    final doc = jsonDecode(json) as Map<String, dynamic>;
    expect(doc['containsVoiceRecordings'], isFalse);
    expect(verifyBackup(json).ok, isTrue);

    final dst = await testState(); // „inny telefon”
    final r1 = await dst.importJson(json);
    expect(r1.added['attempts'], 8);
    expect(dst.attempts.length, 8);
    expect(dst.actions.length, 1);
    expect(dst.ttsOk, isTrue);
    final r2 = await dst.importJson(json); // ponowny import
    expect(r2.added['attempts'], 0);
    expect(r2.skipped['attempts'], 8);
    expect(dst.attempts.length, 8);
    expect(buildReport(dst.attempts, dst.actions, dst.sessions).total.total, buildReport(src.attempts, src.actions, src.sessions).total.total);

    // uszkodzony plik jest odrzucany i nic nie zapisuje
    final tampered = json.replaceFirst('"incorrect"', '"correct"');
    expect(verifyBackup(tampered).ok, isFalse);
    expect(() => importBackup(dst.db, tampered), throwsFormatException);
    expect(verifyBackup('nie json').ok, isFalse);
  });

  test('(21) działania opiekuna nie nadpisują oryginalnych prób dziecka', () async {
    final s = await testState();
    final orig = att('a', Skill.sayName, Outcome.uncertain, at: day, evidence: Evidence.asr);
    await s.record(orig);
    await s.addAction(GuardianActionType.rateSpeech, target: orig.id, value: Outcome.correct.name);
    await s.addAction(GuardianActionType.manualUnlock, target: ItemKind.word.name);
    final stored = (await s.db.attempts(s.profileId)).single;
    expect(stored.outcome, Outcome.uncertain, reason: 'oryginalna próba bez zmian');
    expect(stored.toMap(), orig.toMap());
    expect(s.index.of('a', Skill.sayName).independentCorrect, 1, reason: 'ocena opiekuna liczy się jako osobny wpis');
    expect(s.manualStages, {ItemKind.word});
    // ręczne odblokowanie nie zmienia wyników diagnozy
    await s.recordDiagnosis('b', Skill.sayName, Outcome.incorrect, confusedWith: 'd');
    await s.addAction(GuardianActionType.manualUnlock, target: ItemKind.sentence.name);
    expect(s.attempts.where((a) => a.task == TaskType.diagnosis).single.outcome, Outcome.incorrect);
  });

  test('(22) migracja v1 → v2 nie usuwa wyników', () async {
    final dir = await Directory.systemTemp.createTemp('czytam');
    final path = p.join(dir.path, 'v1.db');
    final old = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(version: 1, onCreate: (db, v) async {
      for (final s in schemaV1) {
        await db.execute(s);
      }
    }));
    await old.insert('profiles', {'id': 'profil-1', 'display_name': null, 'created_at': 1});
    await old.insert('attempts', {
      'id': 'stara-1', 'profile_id': 'profil-1', 'session_id': 's', 'at': day.millisecondsSinceEpoch, 'item_id': 'm',
      'item_kind': 'letter', 'skill': 'recognizeName', 'task_type': 't1HearPoint', 'outcome': 'correct', 'hinted': 0, 'first_try': 1,
    });
    await old.insert('settings', {'key': 'setupDone', 'value': 'true'});
    await old.close();

    final db = await ProgressDb.open(databaseFactoryFfi, path);
    expect(await db.db.getVersion(), currentSchemaVersion);
    final a = (await db.attempts('profil-1')).single;
    expect(a.id, 'stara-1');
    expect(a.evidence, Evidence.touch);
    expect(a.assisted, isFalse);
    expect((await db.settings())['setupDone'], true);
    await db.addGuardianAction(GuardianAction(id: 'g', profileId: 'profil-1', at: day, type: GuardianActionType.manualUnlock, targetId: 'word'));
    expect((await db.guardianActions('profil-1')).length, 1);
    await db.close();
    await dir.delete(recursive: true);
  });

  test('reset profilu usuwa tylko postępy tego profilu', () async {
    final s = await testState();
    await s.record(att('a', Skill.recognizeName, Outcome.correct, at: day));
    await s.setSetting('ttsOk', true);
    await s.resetProfile();
    expect(s.attempts, isEmpty);
    expect(s.ttsOk, isTrue);
  });
}
