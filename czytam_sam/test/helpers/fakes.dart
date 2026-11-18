import 'dart:io';
import 'dart:math';

import 'package:czytam_sam/app_state.dart';
import 'package:czytam_sam/data/database.dart';
import 'package:czytam_sam/engine/speech_policy.dart';
import 'package:czytam_sam/services/speech_input.dart';
import 'package:czytam_sam/services/speech_output.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fixtures.dart';

class FakeTts implements SpeechOutput {
  FakeTts({this.result = PlaybackResult.played});
  PlaybackResult result;
  final List<String> spoken = [];
  @override
  Future<VoiceCheck> check() async => VoiceCheck(
      engineAvailable: true,
      polishAvailable: result != PlaybackResult.unavailable,
      polishInstalledOffline: true,
      voices: const ['test (pl-PL)'],
      message: 'test');
  @override
  Future<PlaybackResult> speak(String text) async {
    if (result == PlaybackResult.played) spoken.add(text);
    return result;
  }

  @override
  Future<void> setRate(double rate) async {}
  @override
  Future<void> stop() async {}
}

class FakeAsr implements SpeechInput {
  FakeAsr({this.installed = false, this.permission = MicPermission.granted, this.next});
  bool installed;
  MicPermission permission;
  AsrResult? next;
  @override
  Future<void> cancel() async {}
  @override
  Future<MicPermission> ensurePermission() async => permission;
  @override
  Future<String?> installModel(String zipPath) async => null;
  @override
  Future<AsrResult> listen(List<String> grammar, {int maxMs = 6000}) async =>
      next ?? const AsrResult(AsrStatus.noSpeech);
  @override
  Future<bool> modelInstalled() async => installed;
  @override
  Future<MicPermission> permissionStatus() async => permission;
  @override
  Future<void> removeModel() async {}
}

/// Osobna, świeża baza dla każdego wywołania (plik tymczasowy).
Future<ProgressDb> memoryDb() async {
  sqfliteFfiInit();
  final dir = Directory.systemTemp.createTempSync('czytam_test');
  return ProgressDb.open(databaseFactoryFfi, p.join(dir.path, 'test.db'));
}

Future<AppState> testState({FakeTts? tts, FakeAsr? asr, ProgressDb? db, DateTime Function()? clock, int seed = 7}) async {
  final s = AppState(
    content: loadTestContent(),
    db: db ?? await memoryDb(),
    tts: tts ?? FakeTts(),
    asr: asr ?? FakeAsr(),
    clock: clock,
    rng: Random(seed),
  );
  await s.load();
  return s;
}
