/// Kopia zapasowa: historia + ustawienia, BEZ nagrań głosu (aplikacja ich nie przechowuje).
/// Format JSON z sumą kontrolną SHA-256. Import nie duplikuje zdarzeń (unikalne id).
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'database.dart';

const backupFormat = 'czytam-sam-kopia';
const backupFormatVersion = 1;

String _canonical(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => k.toString()).toList()..sort();
    return '{${keys.map((k) => '${jsonEncode(k)}:${_canonical(v[k])}').join(',')}}';
  }
  if (v is List) return '[${v.map(_canonical).join(',')}]';
  return jsonEncode(v);
}

String checksumOf(Map<String, Object?> data) => sha256.convert(utf8.encode(_canonical(data))).toString();

Future<String> exportBackup(ProgressDb pdb, {required String appVersion, DateTime? now}) async {
  final db = pdb.db;
  final data = <String, Object?>{
    'profiles': await db.query('profiles', orderBy: 'id'),
    'attempts': await db.query('attempts', orderBy: 'id'),
    'guardian_actions': await db.query('guardian_actions', orderBy: 'id'),
    'sessions': await db.query('sessions', orderBy: 'id'),
    'settings': await db.query('settings', orderBy: 'key'),
  };
  final doc = {
    'format': backupFormat,
    'formatVersion': backupFormatVersion,
    'schemaVersion': currentSchemaVersion,
    'appVersion': appVersion,
    'exportedAt': (now ?? DateTime.now()).toIso8601String(),
    'containsVoiceRecordings': false,
    'checksum': checksumOf(data),
    'data': data,
  };
  return const JsonEncoder.withIndent(' ').convert(doc);
}

class BackupCheck {
  BackupCheck(this.ok, this.problems, {this.counts = const {}});
  final bool ok;
  final List<String> problems;
  final Map<String, int> counts;
}

const _required = {
  'profiles': ['id', 'created_at'],
  'attempts': ['id', 'profile_id', 'session_id', 'at', 'item_id', 'item_kind', 'skill', 'task_type', 'outcome'],
  'guardian_actions': ['id', 'profile_id', 'at', 'type'],
  'sessions': ['id', 'profile_id', 'started_at'],
  'settings': ['key', 'value'],
};

BackupCheck verifyBackup(String json) {
  final problems = <String>[];
  Map<String, dynamic> doc;
  try {
    doc = jsonDecode(json) as Map<String, dynamic>;
  } catch (_) {
    return BackupCheck(false, ['Plik nie jest poprawnym plikiem JSON.']);
  }
  if (doc['format'] != backupFormat) problems.add('To nie jest kopia aplikacji Czytam Sam.');
  if ((doc['formatVersion'] as num? ?? 999) > backupFormatVersion) problems.add('Kopia z nowszej wersji aplikacji – zaktualizuj aplikację.');
  final data = doc['data'];
  if (data is! Map<String, dynamic>) {
    problems.add('Brak danych w kopii.');
    return BackupCheck(false, problems);
  }
  if (doc['checksum'] != checksumOf(data)) problems.add('Suma kontrolna się nie zgadza – plik jest uszkodzony lub zmieniony.');
  final counts = <String, int>{};
  _required.forEach((table, cols) {
    final rows = data[table];
    if (rows is! List) {
      problems.add('Brak tabeli „$table”.');
      return;
    }
    counts[table] = rows.length;
    for (final r in rows) {
      if (r is! Map || cols.any((c) => r[c] == null)) {
        problems.add('Niekompletny wpis w „$table”.');
        break;
      }
    }
  });
  return BackupCheck(problems.isEmpty, problems, counts: counts);
}

class ImportReport {
  final Map<String, int> added = {}, skipped = {};
  @override
  String toString() => 'dodano: $added, pominięto (już były): $skipped';
}

/// Import atomowy: albo wszystko, albo nic. Istniejące zdarzenia (to samo id) są pomijane.
Future<ImportReport> importBackup(ProgressDb pdb, String json) async {
  final check = verifyBackup(json);
  if (!check.ok) throw FormatException(check.problems.join(' '));
  final data = (jsonDecode(json) as Map<String, dynamic>)['data'] as Map<String, dynamic>;
  final report = ImportReport();
  await pdb.db.transaction((txn) async {
    for (final table in ['profiles', 'attempts', 'guardian_actions', 'sessions', 'settings']) {
      var added = 0, skipped = 0;
      for (final r in data[table] as List) {
        final row = Map<String, Object?>.from(r as Map);
        final pk = table == 'settings' ? 'key' : 'id';
        final exists = await txn.query(table, columns: [pk], where: '$pk = ?', whereArgs: [row[pk]], limit: 1);
        if (exists.isEmpty) {
          await txn.insert(table, row);
          added++;
        } else {
          skipped++;
        }
      }
      report.added[table] = added;
      report.skipped[table] = skipped;
    }
  });
  return report;
}
