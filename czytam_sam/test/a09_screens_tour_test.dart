// Przegląd wszystkich ekranów i typów zadań na telefonie i tablecie:
// test nie dopuszcza żadnego błędu układu (np. przepełnienia) ani wyjątku.
// Zrzuty ekranów: SCREENSHOT_DIR=/ścieżka flutter test test/a09_screens_tour_test.dart
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:czytam_sam/app_state.dart';
import 'package:czytam_sam/content/models.dart';
import 'package:czytam_sam/engine/curriculum.dart';
import 'package:czytam_sam/engine/scheduler.dart';
import 'package:czytam_sam/engine/session.dart';
import 'package:czytam_sam/engine/speech_policy.dart';
import 'package:czytam_sam/engine/types.dart';
import 'package:czytam_sam/services/speech_output.dart';
import 'package:czytam_sam/ui/screens/diagnosis_screen.dart';
import 'package:czytam_sam/ui/screens/guardian_panel.dart';
import 'package:czytam_sam/ui/screens/home_screen.dart';
import 'package:czytam_sam/ui/screens/lesson_screen.dart';
import 'package:czytam_sam/ui/screens/settings_screen.dart';
import 'package:czytam_sam/ui/screens/setup_screen.dart';
import 'package:czytam_sam/ui/theme.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers/fakes.dart';
import 'helpers/fixtures.dart';

const sizes = {'telefon': Size(412, 915), 'tablet-poziomo': Size(1280, 800), 'tablet-pionowo': Size(800, 1280)};
final shotDir = Platform.environment['SCREENSHOT_DIR'];

Future<void> _loadFonts() async {
  final base = '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/sdk/flutter'}/bin/cache/artifacts/material_fonts';
  if (!Directory(base).existsSync()) return;
  final roboto = FontLoader('Roboto');
  for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']) {
    roboto.addFont(Future.value(ByteData.sublistView(File('$base/$f').readAsBytesSync())));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(File('$base/MaterialIcons-Regular.otf').readAsBytesSync())));
  await icons.load();
}

final _boundary = GlobalKey();

Widget wrap(AppState s, Widget child) => RepaintBoundary(
      key: _boundary,
      child: AppScope(state: s, child: MaterialApp(theme: buildTheme(), debugShowCheckedModeBanner: false, home: child)),
    );

/// Sprawdza brak wyjątków i (opcjonalnie) zapisuje zrzut.
Future<void> check(WidgetTester tester, String name, List<String> errors) async {
  await tester.pumpAndSettle();
  final e = tester.takeException();
  if (e != null) errors.add('$name: $e');
  if (shotDir == null) return;
  await tester.runAsync(() async {
    final b = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 1);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$shotDir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(_loadFonts);

  for (final entry in sizes.entries) {
    final tag = entry.key;
    testWidgets('przegląd ekranów: $tag', (tester) async {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final errors = <String>[];
      final s = (await tester.runAsync(() async {
        final st = await testState(tts: FakeTts(), clock: () => DateTime(2026, 9, 3, 16));
        await st.setSetting('ttsOk', true);
        await st.setChildName('Ola');
        final d1 = DateTime(2026, 9, 1, 16), d2 = DateTime(2026, 9, 2, 16);
        for (final l in ['m', 'a', 'l', 'o']) {
          for (final sk in [Skill.recognizeName, Skill.recognizeSound, Skill.caseMatch]) {
            for (final a in [...correctRun(l, sk, 10, d1, 's1'), ...correctRun(l, sk, 1, d2, 's2')]) {
              await st.record(a);
            }
          }
          for (final sk in [Skill.sayName, Skill.saySound]) {
            for (final a in [...correctRun(l, sk, 5, d1, 's1'), ...correctRun(l, sk, 1, d2, 's2')]) {
              await st.record(a);
            }
          }
        }
        for (final a in [
          att('b', Skill.recognizeName, Outcome.incorrect, chosen: 'd', at: d2),
          att('d', Skill.recognizeName, Outcome.incorrect, chosen: 'b', at: d2),
          att('b', Skill.sayName, Outcome.uncertain, at: d2, evidence: Evidence.asr),
          att('b', Skill.sayName, Outcome.correct, at: d2, hinted: true),
        ]) {
          await st.record(a);
        }
        return st;
      }))!;

      // Ekran startowy
      await tester.pumpWidget(wrap(s, const HomeScreen()));
      await check(tester, '$tag-01-start', errors);

      // Kreator pierwszego uruchomienia – wszystkie kroki
      await tester.pumpWidget(wrap(s, const SetupScreen()));
      await check(tester, '$tag-02-kreator-1', errors);
      await tester.tap(find.text('Dalej'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Odtwórz zdanie testowe'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tak, wyraźnie'));
      await check(tester, '$tag-03-kreator-lektor', errors);
      await tester.ensureVisible(find.text('Dalej'));
      await tester.tap(find.text('Dalej'));
      await check(tester, '$tag-04-kreator-mikrofon', errors);
      await tester.ensureVisible(find.text('Dalej'));
      await tester.tap(find.text('Dalej'));
      await check(tester, '$tag-05-kreator-ocena', errors);
      await tester.ensureVisible(find.text('Dalej'));
      await tester.tap(find.text('Dalej'));
      await check(tester, '$tag-06-kreator-diagnoza', errors);

      // Diagnoza
      await tester.pumpWidget(wrap(s, const DiagnosisScreen()));
      await check(tester, '$tag-07-diagnoza', errors);

      // Zadania T1–T7
      final cur = Curriculum(s.content, s.index);
      const cap = Capabilities(guardianPresent: false, ttsOk: true);
      final builder = TaskBuilder(content: s.content, curriculum: cur, cap: cap, rng: Random(3));
      TaskSpec task(String id, ItemKind k, Skill sk, TaskType t) => builder.build(Planned(Candidate(id, k, sk, t), Bucket.current));
      final tasks = {
        'T1-nazwa': task('m', ItemKind.letter, Skill.recognizeName, TaskType.t1HearPoint),
        'T1-gloska': task('b', ItemKind.letter, Skill.recognizeSound, TaskType.t1HearPoint),
        'T2': task('a', ItemKind.letter, Skill.recognizeName, TaskType.t2PointSay),
        'T3': task('ż', ItemKind.letter, Skill.sayName, TaskType.t3SeeName),
        'T4': task('ł', ItemKind.letter, Skill.caseMatch, TaskType.t4Case),
        'T5': task('syl_ma', ItemKind.syllable, Skill.segment, TaskType.t5Segment),
        'T6': task('w_kukurydza', ItemKind.word, Skill.readAloud, TaskType.t6ReadAloud),
        'T7-zdanie': task('s_30', ItemKind.sentence, Skill.comprehension, TaskType.t7Comprehension),
        'T7-czytanka': task('r_10', ItemKind.reading, Skill.comprehension, TaskType.t7Comprehension),
      };
      var i = 10;
      for (final e in tasks.entries) {
        final c = SessionController(profileId: 'p', sessionId: 's', tasks: [e.value], sink: (a) async {}, guardianPresent: true, mode: EvaluationMode.guardian);
        await tester.pumpWidget(wrap(s, LessonScreen(key: UniqueKey(), controller: c, asrReady: false)));
        await check(tester, '$tag-${i++}-${e.key}', errors);
        if (e.key == 'T1-gloska') {
          await tester.tap(find.byKey(ValueKey('opt${(e.value.correctIndex + 1) % e.value.options.length}')));
          await check(tester, '$tag-${i++}-${e.key}-po-bledzie', errors);
        }
        if (e.key == 'T2') {
          await tester.tap(find.byKey(ValueKey('opt${e.value.correctIndex}')));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Powiedziałem/am'));
          await tester.tap(find.text('Powiedziałem/am'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.textContaining('przytrzymaj'));
          await tester.longPress(find.textContaining('przytrzymaj'));
          await check(tester, '$tag-${i++}-${e.key}-ocena-opiekuna', errors);
        }
        if (e.key == 'T1-nazwa') {
          await tester.tap(find.text('Podpowiedź'));
          await check(tester, '$tag-${i++}-${e.key}-podpowiedz', errors);
        }
      }

      // Brak lektora
      final silent = (await tester.runAsync(() => testState(tts: FakeTts(result: PlaybackResult.unavailable))))!;
      final c = SessionController(profileId: 'p', sessionId: 's', tasks: [tasks['T1-nazwa']!], sink: (a) async {}, guardianPresent: false, mode: EvaluationMode.guardian);
      await tester.pumpWidget(wrap(silent, LessonScreen(key: UniqueKey(), controller: c, asrReady: false)));
      await check(tester, '$tag-${i++}-brak-lektora', errors);

      await tester.pumpWidget(wrap(s, const SummaryScreen(tasks: 12)));
      await check(tester, '$tag-30-podsumowanie', errors);

      // Panel opiekuna – wszystkie zakładki
      await tester.pumpWidget(wrap(s, const GuardianPanel()));
      await check(tester, '$tag-40-panel-litery', errors);
      var n = 41;
      for (final tab in ['Czytanie', 'Mylone', 'Historia', 'Mowa i podpowiedzi', 'Etapy i plan']) {
        await tester.ensureVisible(find.text(tab));
        await tester.pumpAndSettle();
        await tester.tap(find.text(tab));
        await check(tester, '$tag-${n++}-panel-$tab', errors);
      }

      await tester.pumpWidget(wrap(s, const SettingsScreen()));
      await check(tester, '$tag-50-ustawienia', errors);
      await tester.pumpWidget(wrap(s, const VoiceCheckScreen()));
      await check(tester, '$tag-51-sprawdzenie-lektora', errors);

      expect(errors, isEmpty, reason: errors.join('\n\n'));
    });
  }
}
