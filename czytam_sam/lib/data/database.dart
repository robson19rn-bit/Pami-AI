/// Trwała baza postępów (SQLite przez sqflite). Materiał dydaktyczny jest
/// oddzielnie – w zasobach aplikacji (assets/content), nie w tej bazie.
library;

import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../engine/types.dart';

const currentSchemaVersion = 2;

/// Schemat wersji 1 (pierwsze wydanie) – zachowany do testów migracji.
const schemaV1 = [
  'CREATE TABLE profiles(id TEXT PRIMARY KEY, display_name TEXT, created_at INTEGER NOT NULL)',
  'CREATE TABLE attempts(id TEXT PRIMARY KEY, profile_id TEXT NOT NULL, session_id TEXT NOT NULL, at INTEGER NOT NULL, '
      'item_id TEXT NOT NULL, item_kind TEXT NOT NULL, skill TEXT NOT NULL, task_type TEXT NOT NULL, outcome TEXT NOT NULL, '
      'hinted INTEGER NOT NULL DEFAULT 0, first_try INTEGER NOT NULL DEFAULT 1, chosen_id TEXT, response_ms INTEGER, '
      'asr_text TEXT, asr_conf REAL)',
  'CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
];

/// Migracja 1 → 2: źródło dowodu, materiał z pomocą, działania opiekuna, sesje.
const migrationV1toV2 = [
  "ALTER TABLE attempts ADD COLUMN evidence TEXT NOT NULL DEFAULT 'touch'",
  'ALTER TABLE attempts ADD COLUMN assisted INTEGER NOT NULL DEFAULT 0',
  'CREATE TABLE guardian_actions(id TEXT PRIMARY KEY, profile_id TEXT NOT NULL, at INTEGER NOT NULL, type TEXT NOT NULL, '
      'target_id TEXT, value TEXT)',
  'CREATE TABLE sessions(id TEXT PRIMARY KEY, profile_id TEXT NOT NULL, started_at INTEGER NOT NULL, ended_at INTEGER, '
      'guardian_present INTEGER NOT NULL DEFAULT 0, task_count INTEGER NOT NULL DEFAULT 0)',
  'CREATE INDEX idx_attempts_profile ON attempts(profile_id, item_id, skill)',
];

class ProgressDb {
  ProgressDb._(this.db);
  final Database db;

  static Future<ProgressDb> open(DatabaseFactory factory, String path) async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: currentSchemaVersion,
        onConfigure: (db) async {
          await db.rawQuery('PRAGMA journal_mode=WAL');
        },
        onCreate: (db, version) async {
          final batch = db.batch();
          for (final s in [...schemaV1, ...migrationV1toV2]) {
            batch.execute(s);
          }
          await batch.commit(noResult: true);
        },
        onUpgrade: (db, oldV, newV) async {
          if (oldV < 2) {
            final batch = db.batch();
            for (final s in migrationV1toV2) {
              batch.execute(s);
            }
            await batch.commit(noResult: true);
          }
        },
        onDowngrade: (db, oldV, newV) async {
          // Nigdy nie usuwamy danych przy starszej wersji aplikacji.
          throw StateError('Baza pochodzi z nowszej wersji aplikacji ($oldV). Zaktualizuj aplikację.');
        },
      ),
    );
    return ProgressDb._(db);
  }

  Future<void> close() => db.close();

  // ---------- profile ----------
  Future<List<Map<String, Object?>>> profiles() => db.query('profiles', orderBy: 'created_at');

  Future<void> upsertProfile(String id, String? name, DateTime createdAt) => db.insert(
        'profiles',
        {'id': id, 'display_name': name, 'created_at': createdAt.millisecondsSinceEpoch},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  // ---------- próby (tylko dopisywanie) ----------
  Future<void> addAttempt(Attempt a) =>
      db.insert('attempts', a.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);

  Future<List<Attempt>> attempts(String profileId) async {
    final rows = await db.query('attempts', where: 'profile_id = ?', whereArgs: [profileId], orderBy: 'at, id');
    return rows.map(Attempt.fromMap).toList();
  }

  // ---------- działania opiekuna ----------
  Future<void> addGuardianAction(GuardianAction g) =>
      db.insert('guardian_actions', g.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);

  Future<List<GuardianAction>> guardianActions(String profileId) async {
    final rows = await db.query('guardian_actions', where: 'profile_id = ?', whereArgs: [profileId], orderBy: 'at, id');
    return rows.map(GuardianAction.fromMap).toList();
  }

  // ---------- sesje ----------
  Future<void> upsertSession(SessionRecord s) =>
      db.insert('sessions', s.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<SessionRecord>> sessions(String profileId) async {
    final rows = await db.query('sessions', where: 'profile_id = ?', whereArgs: [profileId], orderBy: 'started_at');
    return rows.map(SessionRecord.fromMap).toList();
  }

  // ---------- ustawienia ----------
  Future<void> setSetting(String key, Object value) =>
      db.insert('settings', {'key': key, 'value': jsonEncode(value)}, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<Map<String, Object?>> settings() async {
    final rows = await db.query('settings');
    return {for (final r in rows) r['key'] as String: jsonDecode(r['value'] as String)};
  }

  /// Reset profilu (wywoływany dopiero po dwuetapowym potwierdzeniu w interfejsie).
  Future<void> resetProfile(String profileId) => db.transaction((txn) async {
        await txn.delete('attempts', where: 'profile_id = ?', whereArgs: [profileId]);
        await txn.delete('guardian_actions', where: 'profile_id = ?', whereArgs: [profileId]);
        await txn.delete('sessions', where: 'profile_id = ?', whereArgs: [profileId]);
        await txn.delete('settings', where: 'key LIKE ?', whereArgs: ['profile.$profileId.%']);
      });
}
