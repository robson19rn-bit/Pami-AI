/// Mikrofon i lokalne rozpoznawanie mowy (Vosk, Apache-2.0) – przetwarzanie
/// wyłącznie na urządzeniu. Nagrania nie są zapisywane: dźwięk trafia z mikrofonu
/// prosto do rozpoznawania w pamięci i jest odrzucany.
library;

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../engine/speech_policy.dart';

enum MicPermission { granted, denied, permanentlyDenied }

abstract class SpeechInput {
  Future<bool> modelInstalled();
  Future<String?> installModel(String zipPath);
  Future<void> removeModel();
  Future<MicPermission> ensurePermission();
  Future<MicPermission> permissionStatus();
  Future<AsrResult> listen(List<String> grammar, {int maxMs = 6000});
  Future<void> cancel();
}

class VoskSpeechInput implements SpeechInput {
  static const _ch = MethodChannel('czytamsam/asr');

  @override
  Future<bool> modelInstalled() async {
    try {
      return await _ch.invokeMethod<bool>('modelInstalled') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Zwraca null przy sukcesie lub komunikat błędu.
  @override
  Future<String?> installModel(String zipPath) async {
    try {
      final r = await _ch.invokeMapMethod<String, dynamic>('installModel', {'zipPath': zipPath});
      return r?['ok'] == true ? null : (r?['message'] as String? ?? 'Nieznany błąd instalacji modelu.');
    } on PlatformException catch (e) {
      return e.message ?? 'Błąd instalacji modelu.';
    }
  }

  @override
  Future<void> removeModel() async {
    try {
      await _ch.invokeMethod('removeModel');
    } catch (_) {}
  }

  @override
  Future<MicPermission> permissionStatus() async {
    final s = await Permission.microphone.status;
    if (s.isGranted) return MicPermission.granted;
    if (s.isPermanentlyDenied) return MicPermission.permanentlyDenied;
    return MicPermission.denied;
  }

  /// Prośba o uprawnienie – wywoływana dopiero przy ćwiczeniu głosowym.
  @override
  Future<MicPermission> ensurePermission() async {
    final s = await Permission.microphone.request();
    if (s.isGranted) return MicPermission.granted;
    if (s.isPermanentlyDenied) return MicPermission.permanentlyDenied;
    return MicPermission.denied;
  }

  @override
  Future<AsrResult> listen(List<String> grammar, {int maxMs = 6000}) async {
    if (await permissionStatus() != MicPermission.granted) {
      return const AsrResult(AsrStatus.noPermission, message: 'Brak uprawnienia do mikrofonu.');
    }
    if (!await modelInstalled()) {
      return const AsrResult(AsrStatus.noModel, message: 'Brak lokalnego modelu rozpoznawania mowy.');
    }
    try {
      final r = await _ch.invokeMapMethod<String, dynamic>('listen', {'grammar': grammar, 'maxMs': maxMs});
      return AsrResult.fromMap(r ?? const {'status': 'error'});
    } on PlatformException catch (e) {
      return AsrResult(AsrStatus.error, message: e.message);
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _ch.invokeMethod('cancel');
    } catch (_) {}
  }
}
