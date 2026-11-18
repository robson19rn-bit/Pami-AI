/// Lektor (systemowy TTS Androida). Aplikacja NIE zakłada, że silnik działa:
/// każde odtworzenie musi potwierdzić start, inaczej zadanie „ze słuchu” jest wstrzymywane.
library;

import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

enum PlaybackResult {
  /// Silnik potwierdził rozpoczęcie mowy.
  played,

  /// Silnik nie rozpoczął mowy w wyznaczonym czasie (cisza).
  notStarted,

  /// Brak polskiego głosu / silnika.
  unavailable,
}

class VoiceCheck {
  VoiceCheck({required this.engineAvailable, required this.polishAvailable, required this.polishInstalledOffline, required this.voices, required this.message});
  final bool engineAvailable, polishAvailable;

  /// null = nie da się sprawdzić na tym urządzeniu.
  final bool? polishInstalledOffline;
  final List<String> voices;
  final String message;
}

abstract class SpeechOutput {
  Future<VoiceCheck> check();
  Future<PlaybackResult> speak(String text);
  Future<void> stop();
  Future<void> setRate(double rate);
}

class FlutterTtsOutput implements SpeechOutput {
  FlutterTtsOutput({this.startTimeout = const Duration(milliseconds: 2500)});
  final Duration startTimeout;
  final FlutterTts _tts = FlutterTts();
  bool _configured = false;
  bool _polishOk = false;
  double _rate = 0.42;

  Future<void> _configure() async {
    if (_configured) return;
    _configured = true;
    try {
      await _tts.awaitSpeakCompletion(true);
      final avail = await _tts.isLanguageAvailable('pl-PL');
      _polishOk = avail == true || avail == 1;
      if (_polishOk) {
        await _tts.setLanguage('pl-PL');
        await _tts.setSpeechRate(_rate);
        await _tts.setPitch(1.0);
        await _tts.setVolume(1.0);
      }
    } catch (_) {
      _polishOk = false;
    }
  }

  @override
  Future<VoiceCheck> check() async {
    _configured = false;
    await _configure();
    final voices = <String>[];
    bool? installed;
    var engine = true;
    try {
      final v = await _tts.getVoices;
      if (v is List) {
        for (final x in v) {
          if (x is Map && (x['locale']?.toString().toLowerCase().startsWith('pl') ?? false)) {
            voices.add('${x['name']} (${x['locale']})');
          }
        }
      }
      final inst = await _tts.isLanguageInstalled('pl-PL');
      installed = inst == true;
    } catch (_) {
      engine = voices.isNotEmpty;
    }
    final msg = !_polishOk
        ? 'Brak polskiego głosu lektora. Zainstaluj polski głos w ustawieniach Androida (Ustawienia → Zamiana tekstu na mowę) albo korzystaj z trybu, w którym polecenia czyta opiekun.'
        : installed == false
            ? 'Polski głos jest dostępny, ale może wymagać internetu. Pobierz polski pakiet głosu w ustawieniach Androida, aby działał offline.'
            : 'Polski lektor jest dostępny.';
    return VoiceCheck(engineAvailable: engine, polishAvailable: _polishOk, polishInstalledOffline: installed, voices: voices, message: msg);
  }

  @override
  Future<PlaybackResult> speak(String text) async {
    await _configure();
    if (!_polishOk) return PlaybackResult.unavailable;
    final started = Completer<bool>();
    _tts.setStartHandler(() {
      if (!started.isCompleted) started.complete(true);
    });
    _tts.setErrorHandler((_) {
      if (!started.isCompleted) started.complete(false);
    });
    final Future<dynamic> done;
    try {
      done = _tts.speak(text);
    } catch (_) {
      return PlaybackResult.notStarted;
    }
    final ok = await started.future.timeout(startTimeout, onTimeout: () => false);
    if (!ok) {
      await stop();
      return PlaybackResult.notStarted;
    }
    try {
      await done.timeout(const Duration(seconds: 20));
    } catch (_) {}
    return PlaybackResult.played;
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  @override
  Future<void> setRate(double rate) async {
    _rate = rate;
    if (_polishOk) await _tts.setSpeechRate(rate);
  }
}
