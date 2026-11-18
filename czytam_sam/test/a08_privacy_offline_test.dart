// (20) tryb samolotowy / brak sieci; (24) brak reklam, telemetrii, logowania i płatnych wywołań.
import 'dart:io';

import 'package:czytam_sam/engine/session.dart';
import 'package:czytam_sam/engine/types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';

/// Każda próba połączenia sieciowego kończy test błędem i jest liczona.
class _NoNetwork extends HttpOverrides {
  int attempts = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw const SocketException('Tryb samolotowy: sieć niedostępna');
  }
}

void main() {
  test('(20) pełny przebieg działa bez sieci: materiał, sesja, zapis, raport, kopia', () async {
    final net = _NoNetwork();
    await HttpOverrides.runZoned(() async {
      final s = await testState();
      await s.setSetting('ttsOk', true);
      final c = await s.startSession(guardianPresent: true, asrReady: false);
      expect(c.total, greaterThan(0));
      var n = 0;
      while (!c.finished && n++ < 20) {
        final t = c.current!;
        c.promptDelivered();
        if (c.phase == Phase.awaitingTouch) {
          if (t.type == TaskType.t5Segment) {
            await c.submitTiles();
          } else {
            await c.touch(t.correctIndex);
          }
        }
        if (c.phase == Phase.awaitingSpeech) {
          await c.speechFinished(null);
          await c.guardianRate(GuardianVerdict.correct);
        }
        c.next();
      }
      await s.endSession(c.completedTasks);
      expect(s.attempts, isNotEmpty);
      final json = await s.exportJson();
      final other = await testState();
      await other.importJson(json);
      expect(other.attempts.length, s.attempts.length);
      expect(s.report.total.total, s.attempts.length);
    }, createHttpClient: net.createHttpClient);
    expect(net.attempts, 0, reason: 'aplikacja nie może próbować łączyć się z siecią');
  });

  test('(24) brak bibliotek reklam, telemetrii, kont, płatności i klientów HTTP', () {
    final lock = File('pubspec.lock').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    const forbidden = [
      'firebase', 'google_mobile_ads', 'admob', 'unity_ads', 'facebook', 'analytics', 'crashlytics', 'sentry',
      'mixpanel', 'amplitude', 'appsflyer', 'in_app_purchase', 'purchases_flutter', 'revenuecat', 'google_sign_in',
      'sign_in_with_apple', 'supabase', 'dio', 'package:http', '\n  http:', 'speech_to_text', 'onesignal', 'posthog',
    ];
    for (final f in forbidden) {
      expect(lock.toLowerCase().contains(f), isFalse, reason: 'pubspec.lock zawiera „$f”');
      expect(pubspec.toLowerCase().contains(f), isFalse, reason: 'pubspec.yaml zawiera „$f”');
    }
  });

  test('(24b) kod aplikacji nie wykonuje połączeń sieciowych', () {
    final files = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
    for (final f in files) {
      final src = f.readAsStringSync();
      for (final bad in ['HttpClient(', 'package:http/', 'Socket.connect', 'WebSocket', 'Uri.https(', 'http://', 'https://']) {
        expect(src.contains(bad), isFalse, reason: '${f.path} zawiera „$bad”');
      }
    }
    final kotlin = File('android/app/src/main/kotlin/pl/czytamsam/czytam_sam/MainActivity.kt').readAsStringSync();
    for (final bad in ['HttpURLConnection', 'URL(', 'OkHttp', 'Socket(']) {
      expect(kotlin.contains(bad), isFalse, reason: 'MainActivity.kt zawiera „$bad”');
    }
  });

  test('(24c) manifest wydania nie żąda internetu; mikrofon zadeklarowany, kopia systemowa wyłączona', () {
    final m = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(m.contains('android.permission.INTERNET'), isFalse);
    expect(m.contains('android.permission.RECORD_AUDIO'), isTrue);
    expect(m.contains('android:allowBackup="false"'), isTrue);
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle.contains('applicationId = "pl.czytamsam.app"'), isTrue, reason: 'stały identyfikator aplikacji');
  });
}
