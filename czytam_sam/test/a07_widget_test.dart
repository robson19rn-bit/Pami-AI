// (19) utrata polskiego głosu – jasny komunikat, brak udawania; (23) dostępność.
import 'package:czytam_sam/app_state.dart';
import 'package:czytam_sam/content/models.dart';
import 'package:czytam_sam/engine/session.dart';
import 'package:czytam_sam/engine/speech_policy.dart';
import 'package:czytam_sam/engine/types.dart';
import 'package:czytam_sam/services/speech_output.dart';
import 'package:czytam_sam/ui/screens/guardian_panel.dart';
import 'package:czytam_sam/ui/screens/home_screen.dart';
import 'package:czytam_sam/ui/screens/lesson_screen.dart';
import 'package:czytam_sam/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers/fakes.dart';
import 'helpers/fixtures.dart';

TaskSpec t1() => TaskSpec(
      id: 'x', type: TaskType.t1HearPoint, kind: ItemKind.letter, itemId: 'd', skill: Skill.recognizeName,
      instruction: 'Wskaż literę, którą usłyszysz.', promptSpeech: 'Wskaż literę de.', promptMode: PromptMode.tts, requiresHeardPrompt: true,
      options: ['b', 'd', 'p', 'm'], optionIds: ['b', 'd', 'p', 'm'], correctIndex: 1, hintText: 'dom');

Widget wrap(AppState s, Widget child) => AppScope(state: s, child: MaterialApp(theme: buildTheme(), home: child));

void main() {
  testWidgets('(19) brak polskiego głosu: komunikat i zablokowane odpowiedzi; nic nie jest zapisywane', (tester) async {
    final tts = FakeTts(result: PlaybackResult.unavailable);
    final s = (await tester.runAsync(() => testState(tts: tts)))!;
    final log = <Attempt>[];
    final c = SessionController(profileId: 'p', sessionId: 's', tasks: [t1()], sink: (a) async => log.add(a), guardianPresent: false, mode: EvaluationMode.guardian);
    await tester.pumpWidget(wrap(s, LessonScreen(controller: c, asrReady: false)));
    await tester.pumpAndSettle();
    expect(find.textContaining('NIE zostało odtworzone'), findsOneWidget);
    expect(find.textContaining('wstrzymane'), findsOneWidget);
    expect(tts.spoken, isEmpty, reason: 'nic nie zostało „udanie” odtworzone');
    final btn = tester.widget<OutlinedButton>(find.byKey(const ValueKey('opt1')));
    expect(btn.onPressed, isNull, reason: 'odpowiedzi zablokowane do czasu usłyszenia polecenia');
    await tester.tap(find.byKey(const ValueKey('opt1')), warnIfMissed: false);
    expect(log, isEmpty);
    // opiekun czyta polecenie → zadanie można kontynuować
    await tester.tap(find.text('Opiekun przeczytał polecenie'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('opt1')));
    await tester.pump();
    expect(log.single.outcome, Outcome.correct);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget, reason: 'wyraźne potwierdzenie dobrej odpowiedzi');
    await tester.pump(const Duration(seconds: 3)); // automatyczne przejście dalej po dobrej odpowiedzi
    await tester.pumpAndSettle();
  });

  testWidgets('(19b) działający lektor: polecenie odtworzone i odpowiedzi aktywne', (tester) async {
    final tts = FakeTts();
    final s = (await tester.runAsync(() => testState(tts: tts)))!;
    final c = SessionController(profileId: 'p', sessionId: 's', tasks: [t1()], sink: (a) async {}, guardianPresent: false, mode: EvaluationMode.guardian);
    await tester.pumpWidget(wrap(s, LessonScreen(controller: c, asrReady: false)));
    await tester.pumpAndSettle();
    expect(tts.spoken, ['Wskaż literę de.']);
    expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('opt1'))).onPressed, isNotNull);
    expect(find.textContaining('NIE zostało'), findsNothing);
  });

  testWidgets('po dobrej odpowiedzi: zielony znak, pochwała lektora i samo przejście do kolejnego zadania', (tester) async {
    final tts = FakeTts();
    final s = (await tester.runAsync(() async {
      final st = await testState(tts: tts);
      await st.setSetting('ttsOk', true);
      return st;
    }))!;
    final c = SessionController(profileId: 'p', sessionId: 's', tasks: [t1(), t1()], sink: (a) async {}, guardianPresent: false, mode: EvaluationMode.guardian);
    await tester.pumpWidget(wrap(s, LessonScreen(controller: c, asrReady: false)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('opt1')));
    await tester.pump();
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(tts.spoken.any((x) => praises.any(x.startsWith)), isTrue, reason: 'lektor mówi pochwałę: ${tts.spoken}');
    expect(c.position, 1, reason: 'przejście do następnego zadania bez dodatkowego klikania');
    expect(c.phase, Phase.awaitingTouch);
  });

  testWidgets('(23) ekran startowy: duże obszary dotyku i kontrast', (tester) async {
    final h = tester.ensureSemantics();
    final s = (await tester.runAsync(() => testState()))!;
    await tester.pumpWidget(wrap(s, const HomeScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Uczę się'), findsOneWidget);
    expect(find.text('Moje postępy'), findsOneWidget);
    expect(find.text('Ustawienia'), findsOneWidget);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    h.dispose();
  });

  testWidgets('(23b) ekran zadania: przyciski liter ≥ 48 dp i kontrast', (tester) async {
    final h = tester.ensureSemantics();
    final s = (await tester.runAsync(() => testState()))!;
    final c = SessionController(profileId: 'p', sessionId: 's', tasks: [t1()], sink: (a) async {}, guardianPresent: true, mode: EvaluationMode.guardian);
    await tester.pumpWidget(wrap(s, LessonScreen(controller: c, asrReady: false)));
    await tester.pumpAndSettle();
    final size = tester.getSize(find.byKey(const ValueKey('opt0')));
    expect(size.width, greaterThanOrEqualTo(96));
    expect(size.height, greaterThanOrEqualTo(96));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    h.dispose();
  });

  testWidgets('panel opiekuna: bez danych pokazuje komunikat zamiast pustych wykresów', (tester) async {
    final s = (await tester.runAsync(() => testState()))!;
    await tester.pumpWidget(wrap(s, const GuardianPanel()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Historia'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Brak historii'), findsOneWidget);
    await tester.tap(find.text('Mylone'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Brak zarejestrowanych pomyłek'), findsOneWidget);
  });

  testWidgets('panel opiekuna z danymi: litery, historia, plan', (tester) async {
    final s = (await tester.runAsync(() async {
      final st = await testState();
      for (final a in correctRun('m', Skill.recognizeName, 10, DateTime(2026, 1, 5, 10), 's1')) {
        await st.record(a);
      }
      await st.record(att('b', Skill.recognizeName, Outcome.incorrect, chosen: 'd', at: DateTime(2026, 1, 5, 11)));
      return st;
    }))!;
    tester.view.physicalSize = const Size(1600, 2400);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(wrap(s, const GuardianPanel()));
    await tester.pumpAndSettle();
    expect(find.textContaining('opanowane warunkowo'), findsWidgets);
    await tester.tap(find.text('Mylone'));
    await tester.pumpAndSettle();
    expect(find.text('b → d'), findsOneWidget);
    await tester.ensureVisible(find.text('Etapy i plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Etapy i plan'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Postęp do kolejnego etapu'), findsOneWidget);
    expect(find.textContaining('Alfabet (pewnie rozpoznawane litery)'), findsOneWidget);

  });
}
