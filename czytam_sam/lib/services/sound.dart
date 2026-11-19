/// Dźwięki odpowiedzi i spokojna muzyczka w tle (własne pliki w assets/audio, offline).
/// Muzyka jest wyciszana na czas mówienia lektora i nasłuchu mikrofonu.
library;

import 'package:just_audio/just_audio.dart';

enum Sfx { correct, tryAgain, newStage }

abstract class SoundService {
  Future<void> play(Sfx s);
  Future<void> startMusic();
  Future<void> pauseMusic();
  Future<void> resumeMusic();
  Future<void> stopMusic();
}

/// Brak dźwięków (testy lub wyłączone w ustawieniach).
class SilentSound implements SoundService {
  const SilentSound();
  @override
  Future<void> play(Sfx s) async {}
  @override
  Future<void> startMusic() async {}
  @override
  Future<void> pauseMusic() async {}
  @override
  Future<void> resumeMusic() async {}
  @override
  Future<void> stopMusic() async {}
}

class AppSound implements SoundService {
  AppSound({required this.sfxEnabled, required this.musicEnabled, this.musicVolume = 0.18});

  /// Odczytywane przy każdym użyciu (ustawienia mogą się zmienić w trakcie).
  final bool Function() sfxEnabled, musicEnabled;
  final double musicVolume;

  AudioPlayer? _sfx, _music;
  bool _musicWanted = false;

  AudioPlayer _player() => AudioPlayer(handleInterruptions: false, handleAudioSessionActivation: false);

  @override
  Future<void> play(Sfx s) async {
    if (!sfxEnabled()) return;
    try {
      final p = _sfx ??= _player();
      await p.setVolume(0.7);
      await p.setAsset(switch (s) {
        Sfx.correct => 'assets/audio/dobrze.wav',
        Sfx.tryAgain => 'assets/audio/jeszcze.wav',
        Sfx.newStage => 'assets/audio/nowy_etap.wav',
      });
      await p.play();
    } catch (_) {
      // dźwięk efektu nie jest niezbędny – brak odtworzenia nie przerywa nauki
    }
  }

  @override
  Future<void> startMusic() async {
    _musicWanted = true;
    if (!musicEnabled()) return;
    try {
      final p = _music ??= _player();
      if (p.audioSource == null) {
        await p.setAsset('assets/audio/muzyka.wav');
        await p.setLoopMode(LoopMode.one);
      }
      await p.setVolume(musicVolume);
      p.play();
    } catch (_) {}
  }

  @override
  Future<void> pauseMusic() async {
    try {
      await _music?.pause();
    } catch (_) {}
  }

  @override
  Future<void> resumeMusic() async {
    if (_musicWanted && musicEnabled()) await startMusic();
  }

  @override
  Future<void> stopMusic() async {
    _musicWanted = false;
    try {
      await _music?.stop();
    } catch (_) {}
  }
}
