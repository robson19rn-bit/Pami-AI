import 'dart:async';

import 'package:material_ui/material_ui.dart' hide Feedback;

import '../../app_state.dart';
import '../../content/models.dart';
import '../../engine/session.dart';
import '../../engine/speech_policy.dart';
import '../../engine/types.dart';
import '../../services/sound.dart';
import '../../services/speech_input.dart';
import '../../services/speech_output.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// „Uczę się”: dziecko ćwiczy samo, lektor prowadzi całą lekcję.
/// Gdy polski lektor nie działa, dorosły musi czytać polecenia (jasny komunikat).
Future<void> startLesson(BuildContext context, {bool assessment = false}) async {
  final s = AppScope.read(context);
  var guardian = assessment;
  if (!assessment && !s.ttsOk) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lektor nie jest włączony'),
        content: const Text('Bez polskiego lektora polecenia musi czytać dorosły. '
            'Lektora włączysz w Ustawieniach (dla dorosłych).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Dorosły przeczyta polecenia')),
        ],
      ),
    );
    if (ok != true) return;
    guardian = true;
  }
  if (!context.mounted) return;
  final asrReady = await s.asr.modelInstalled();
  final ctrl = await s.startSession(guardianPresent: guardian, asrReady: asrReady, assessment: assessment);
  if (!context.mounted) return;
  if (ctrl.total == 0) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Na razie nie ma czego oceniać – dziecko najpierw poćwiczy samo.')));
    await s.endSession(0);
    return;
  }
  await Navigator.push(context, MaterialPageRoute(builder: (_) => LessonScreen(controller: ctrl, asrReady: asrReady, assessment: assessment)));
}

class LessonScreen extends StatefulWidget {
  const LessonScreen({super.key, required this.controller, required this.asrReady, this.assessment = false});
  final SessionController controller;
  final bool asrReady;

  /// Sesja oceny z opiekunem – panel oceny od razu otwarty.
  final bool assessment;

  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

enum MicState { idle, listening, off }

class _LessonScreenState extends State<LessonScreen> {
  SessionController get c => widget.controller;
  late AppState app;
  String? hint;
  String? promptError;
  bool speaking = false;
  bool guardianPanelOpen = false;
  MicState mic = MicState.idle;
  String? micNote;
  bool _started = false;
  Feedback? _handledFeedback;
  Set<String> _openBefore = const {};

  Set<String> _openUnits() => {
        for (final k in [ItemKind.syllable, ItemKind.word, ItemKind.sentence, ItemKind.reading])
          for (final u in app.curriculum.units(k)) u.unit.id
      };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    app = AppScope.read(context);
    if (!_started) {
      _started = true;
      _openBefore = _openUnits();
      app.sound.startMusic();
      WidgetsBinding.instance.addPostFrameCallback((_) => _onTaskShown());
    }
  }

  @override
  void dispose() {
    app.tts.stop();
    app.asr.cancel();
    app.sound.stopMusic();
    super.dispose();
  }

  /// Mówi tekst lektorem, wyciszając na ten czas muzykę.
  Future<PlaybackResult> _say(String text) async {
    await app.sound.pauseMusic();
    final r = await app.tts.speak(text);
    if (mounted) await app.sound.resumeMusic();
    return r;
  }

  /// Reakcja na każdą odpowiedź: dźwięk + słowa lektora; po dobrej odpowiedzi samo „Dalej”.
  Future<void> _reactToFeedback(Feedback f) async {
    if (f.correct == true) await app.sound.play(Sfx.correct);
    if (f.correct == false) await app.sound.play(Sfx.tryAgain);
    if (f.spoken != null && app.ttsOk) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted || c.feedback != f) return;
      await _say(f.spoken!);
    }
    if (f.correct == true && c.phase == Phase.feedback) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (mounted && c.feedback == f && c.phase == Phase.feedback) await _next();
    }
  }

  Future<void> _onTaskShown() async {
    hint = null;
    promptError = null;
    guardianPanelOpen = widget.assessment;
    micNote = null;
    final t = c.current;
    if (t == null) return _finish();
    setState(() {});
    if (t.promptMode == PromptMode.tts) await _speakPrompt();
  }

  Future<void> _speakPrompt() async {
    final t = c.current;
    if (t == null) return;
    if (t.promptMode == PromptMode.guardian) {
      setState(() {});
      return;
    }
    setState(() => speaking = true);
    final r = await _say(t.promptSpeech);
    if (!mounted) return;
    setState(() {
      speaking = false;
      if (r == PlaybackResult.played) {
        c.promptDelivered();
        promptError = null;
      } else {
        c.promptNotDelivered();
        promptError = r == PlaybackResult.unavailable
            ? 'Brak polskiego lektora – polecenie NIE zostało odtworzone.'
            : 'Lektor nie odtworzył polecenia (cisza).';
      }
    });
  }

  bool _finishing = false;
  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    await app.endSession(c.completedTasks);
    await app.sound.stopMusic();
    if (!mounted) return;
    final newIds = _openUnits().difference(_openBefore);
    final unlocked = [for (final id in newIds) app.content.unit(id)!]..sort((a, b) => a.level.compareTo(b.level));
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => SummaryScreen(tasks: c.completedTasks, unlocked: unlocked)));
  }

  Future<void> _next() async {
    c.next();
    if (c.finished) return _finish();
    await _onTaskShown();
  }

  Future<void> _listen() async {
    final t = c.current!;
    if (!widget.asrReady) {
      await c.speechFinished(null);
      setState(() {});
      return;
    }
    var perm = await app.asr.permissionStatus();
    if (perm != MicPermission.granted) perm = await app.asr.ensurePermission();
    if (perm != MicPermission.granted) {
      setState(() {
        mic = MicState.off;
        micNote = 'Brak zgody na mikrofon – wypowiedź oceni opiekun (lub zostanie oznaczona jako nieoceniona).';
      });
      await c.speechFinished(const AsrResult(AsrStatus.noPermission));
      setState(() {});
      return;
    }
    setState(() => mic = MicState.listening);
    final grammar = _grammarFor(t);
    await app.sound.pauseMusic();
    final r = await app.asr.listen(grammar, maxMs: 6000);
    await app.sound.resumeMusic();
    if (!mounted) return;
    setState(() {
      mic = MicState.idle;
      micNote = r.status == AsrStatus.ok
          ? 'Rozpoznano: „${r.text}”${r.confidence != null ? ' (pewność ${(r.confidence! * 100).round()}%)' : ''}'
          : r.status == AsrStatus.noSpeech
          ? 'Mikrofon nic nie usłyszał.'
          : 'Problem z rozpoznawaniem: ${r.message ?? r.status.name}';
    });
    await c.speechFinished(r);
    if (mounted) setState(() {});
  }

  /// Słownik dla ASR: oczekiwana odpowiedź + inne możliwe wypowiedzi + [unk],
  /// aby model nie był „zmuszony” do wybrania poprawnej odpowiedzi.
  List<String> _grammarFor(TaskSpec t) {
    final out = <String>{};
    if (t.expectedSpeech != null) out.add(t.expectedSpeech!.toLowerCase());
    if (t.kind == ItemKind.letter || t.kind == ItemKind.grapheme) {
      for (final l in app.content.letters) {
        out.add(l.name);
      }
    } else {
      final pool = [...app.content.syllables, ...app.content.words]..shuffle(app.rng);
      for (final u in pool.take(30)) {
        out.add(u.text);
      }
    }
    return [...out, '[unk]'];
  }

  @override
  Widget build(BuildContext context) {
    final t = c.current;
    if (t == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final f = c.feedback;
    if (f != null && !identical(f, _handledFeedback)) {
      _handledFeedback = f;
      WidgetsBinding.instance.addPostFrameCallback((_) => _reactToFeedback(f));
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _finish();
      },
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight - 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: c.total == 0 ? 0 : (c.position + (c.phase == Phase.feedback ? 1 : 0)) / c.total,
                        minHeight: 10,
                        backgroundColor: Palette.soft,
                        color: Palette.primary,
                        semanticsLabel: 'postęp lekcji',
                      ),
                    ),
                    const SizedBox(height: 6),
                    _topBar(t),
                    const SizedBox(height: 12),
                    Text(
                      t.instruction,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
                    ),
                    if (t.assisted)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: InfoCard(
                          color: Color(0xFFFFF1DC),
                          child: Text(
                            'Materiał z pomocą – etap odblokowany ręcznie, bez zaliczenia. Zawiera głoski, których dziecko jeszcze nie opanowało.',
                            style: TextStyle(fontSize: 16, color: Palette.warn),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    if (t.promptMode == PromptMode.guardian && c.phase == Phase.awaitingPrompt) _guardianPromptCard(t),
                    if (promptError != null && c.phase == Phase.awaitingPrompt) _promptErrorCard(t),
                    if (t.display != null) _display(t),
                    if (t.question != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          t.question!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                        ),
                      ),
                    const SizedBox(height: 12),
                    if (t.hasTouch) _answers(t),
                    if (c.phase == Phase.awaitingSpeech || c.phase == Phase.awaitingGuardian) _speechArea(t),
                    if (hint != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: InfoCard(child: Text('Podpowiedź: $hint', style: const TextStyle(fontSize: 20))),
                      ),
                    if (c.feedback != null) _feedbackCard(),
                    if (t.activeSpeechSkill != null && (c.phase == Phase.awaitingSpeech || c.phase == Phase.awaitingGuardian))
                      _guardianRating(t),
                    const SizedBox(height: 16),
                    if (c.phase == Phase.feedback)
                      FilledButton.icon(onPressed: _next, icon: const Icon(Icons.arrow_forward_rounded), label: const Text('Dalej')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Zwarty pasek narzędzi: 4 akcje w jednym rzędzie (ikona + krótki podpis), bez rozpraszania.
  Widget _topBar(TaskSpec t) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      _tool(Icons.volume_up_rounded, 'Powtórz', speaking ? null : _speakPrompt),
      _tool(Icons.lightbulb_outline_rounded, 'Podpowiedź', c.canRequestHint ? () => setState(() => hint = c.requestHint()) : null),
      _tool(
        Icons.schedule_rounded,
        'Później',
        c.phase == Phase.feedback
            ? null
            : () {
                c.postpone();
                _onTaskShown();
              },
      ),
      _tool(Icons.close_rounded, 'Przerwij', () async {
        if (await confirm(context, 'Zakończyć?', 'Postęp jest zapisany. Możesz wrócić w każdej chwili.')) {
          c.abort();
          await _finish();
        }
      }),
    ],
  );

  Widget _tool(IconData icon, String label, VoidCallback? onTap) {
    final color = onTap == null ? const Color(0xFF7B8794) : Palette.primary;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 72, minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 30, color: color),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(fontSize: 15, color: color, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _guardianPromptCard(TaskSpec t) => InfoCard(
    color: const Color(0xFFFFF1DC),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Opiekunie, przeczytaj dziecku na głos:', style: TextStyle(fontSize: 16, color: Palette.warn)),
        const SizedBox(height: 4),
        Text(t.promptSpeech, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        if (t.skill == Skill.recognizeSound || t.type == TaskType.t5Segment)
          const Text('Wymawiaj krótko, bez dodawania „y” (np. „m”, nie „my”).', style: TextStyle(fontSize: 15)),
        const SizedBox(height: 8),
        FilledButton(onPressed: () => setState(c.promptDelivered), child: const Text('Przeczytałem/am polecenie')),
      ],
    ),
  );

  Widget _promptErrorCard(TaskSpec t) => InfoCard(
    color: const Color(0xFFFFE4E1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          promptError!,
          style: const TextStyle(fontSize: 18, color: Palette.warn, fontWeight: FontWeight.w600),
        ),
        const Text('Zadanie „ze słuchu” jest wstrzymane, dopóki polecenie nie zostanie usłyszane.', style: TextStyle(fontSize: 16)),
        const SizedBox(height: 8),
        Text('Opiekun może przeczytać: „${t.promptSpeech}”', style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(onPressed: _speakPrompt, child: const Text('Spróbuj lektora jeszcze raz')),
            FilledButton(onPressed: () => setState(c.promptDelivered), child: const Text('Opiekun przeczytał polecenie')),
          ],
        ),
      ],
    ),
  );

  Widget _display(TaskSpec t) {
    final big = t.kind == ItemKind.letter || t.kind == ItemKind.grapheme || t.kind == ItemKind.syllable;
    final size = t.kind == ItemKind.reading
        ? 28.0
        : t.kind == ItemKind.sentence
        ? 34.0
        : big
        ? 120.0
        : 72.0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Palette.soft, width: 2),
      ),
      child: Text(
        t.display!,
        textAlign: t.kind == ItemKind.reading ? TextAlign.left : TextAlign.center,
        style: TextStyle(fontSize: size, height: 1.35, fontWeight: FontWeight.w500, color: Palette.ink),
      ),
    );
  }

  Widget _answers(TaskSpec t) {
    final enabled = c.phase == Phase.awaitingTouch;
    if (t.type == TaskType.t5Segment) return _tiles(t, enabled);
    final visible = c.visibleOptionIndexes();
    final isText = t.type == TaskType.t7Comprehension;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final i in visible)
          Opacity(
            // przed usłyszeniem polecenia przyciski są wyraźnie wyszarzone (nieaktywne)
            opacity: c.phase == Phase.awaitingPrompt ? 0.35 : 1,
            child: SizedBox(
              width: isText ? 260 : 120,
              height: isText ? 72 : 120,
              child: OutlinedButton(
                key: ValueKey('opt$i'),
                onPressed: enabled
                    ? () async {
                        await c.touch(i);
                        setState(() {});
                      }
                    : null,
                style: OutlinedButton.styleFrom(
                  backgroundColor: _optionColor(t, i),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  side: const BorderSide(color: Palette.border, width: 2),
                  padding: const EdgeInsets.all(4),
                ),
                child: Text(
                  t.options[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: isText ? 24 : 64, color: Palette.ink),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Color _optionColor(TaskSpec t, int i) {
    if (c.phase == Phase.awaitingTouch || c.phase == Phase.awaitingPrompt) return Palette.surface;
    if (i == t.correctIndex) return const Color(0xFFD7F0DD);
    return Palette.surface;
  }

  Widget _tiles(TaskSpec t, bool enabled) => Column(
    children: [
      Container(
        constraints: const BoxConstraints(minHeight: 96),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Palette.border),
        ),
        child: Center(
          child: Text(c.selectedTiles.map((i) => t.options[i]).join(' '), style: const TextStyle(fontSize: 56, color: Palette.ink)),
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        alignment: WrapAlignment.center,
        children: [
          for (var i = 0; i < t.options.length; i++)
            SizedBox(
              width: 96,
              height: 96,
              child: OutlinedButton(
                onPressed: enabled ? () => setState(() => c.tapTile(i)) : null,
                style: OutlinedButton.styleFrom(
                  backgroundColor: Palette.surface,
                  side: const BorderSide(color: Palette.border, width: 2),
                ),
                child: Text(t.options[i], style: const TextStyle(fontSize: 44, color: Palette.ink)),
              ),
            ),
        ],
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        children: [
          OutlinedButton.icon(
            onPressed: enabled ? () => setState(c.undoTile) : null,
            icon: const Icon(Icons.backspace_outlined),
            label: const Text('Cofnij'),
          ),
          FilledButton.icon(
            onPressed: enabled && c.selectedTiles.length == t.correctSequence.length
                ? () async {
                    await c.submitTiles();
                    setState(() {});
                  }
                : null,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Gotowe'),
          ),
        ],
      ),
    ],
  );

  Widget _speechArea(TaskSpec t) {
    final listening = mic == MicState.listening;
    final micLabel = !widget.asrReady
        ? 'Rozpoznawanie mowy nie jest zainstalowane – mów na głos, oceni opiekun.'
        : listening
        ? 'Słucham…'
        : mic == MicState.off
        ? 'Mikrofon wyłączony.'
        : 'Naciśnij i powiedz odpowiedź.';
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: InfoCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  listening ? Icons.mic_rounded : (widget.asrReady ? Icons.mic_none_rounded : Icons.mic_off_rounded),
                  size: 36,
                  color: listening ? Palette.good : Palette.ink,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(micLabel, style: const TextStyle(fontSize: 20))),
              ],
            ),
            if (micNote != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(micNote!, style: const TextStyle(fontSize: 16)),
              ),
            const SizedBox(height: 12),
            if (c.phase == Phase.awaitingSpeech)
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: listening ? null : _listen,
                    icon: Icon(widget.asrReady ? Icons.mic_rounded : Icons.record_voice_over_rounded),
                    label: Text(widget.asrReady ? 'Mów' : 'Powiedziałem/am'),
                  ),
                  OutlinedButton(
                    onPressed: listening
                        ? null
                        : () async {
                            await c.skipSpeech();
                            setState(() {});
                          },
                    child: const Text('Pomiń mówienie'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Panel oceny opiekuna – ukryty, otwierany przytrzymaniem przycisku.
  Widget _guardianRating(TaskSpec t) {
    if (!c.guardianPresent) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: guardianPanelOpen
          ? InfoCard(
              color: const Color(0xFFEDE7F6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Ocena opiekuna – oczekiwano: ${t.guardianExpected ?? t.expectedSpeech ?? ''}',
                    style: const TextStyle(fontSize: 17),
                  ),
                  if (c.lastAsr?.status == AsrStatus.ok)
                    Text('Sugestia rozpoznawania (niewiążąca): „${c.lastAsr!.text}”', style: const TextStyle(fontSize: 15)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final v in GuardianVerdict.values)
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: v == GuardianVerdict.correct ? Palette.good : Palette.primary),
                          onPressed: () async {
                            await c.guardianRate(v);
                            setState(() => guardianPanelOpen = v == GuardianVerdict.repeat ? false : guardianPanelOpen);
                          },
                          child: Text(switch (v) {
                            GuardianVerdict.correct => 'Poprawnie',
                            GuardianVerdict.notYet => 'Jeszcze nie',
                            GuardianVerdict.repeat => 'Powtórz',
                            GuardianVerdict.cannotAssess => 'Nie można ocenić',
                          }),
                        ),
                    ],
                  ),
                ],
              ),
            )
          : Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onLongPress: () => setState(() => guardianPanelOpen = true),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Palette.border),
                  ),
                  child: Text(
                    c.phase == Phase.awaitingGuardian ? 'Opiekunie: przytrzymaj, aby ocenić' : 'Opiekun (przytrzymaj)',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _feedbackCard() {
    final f = c.feedback!;
    final color = f.correct == true
        ? const Color(0xFFD7F0DD)
        : f.correct == false
        ? const Color(0xFFFFF1DC)
        : Palette.soft;
    final icon = f.correct == true
        ? const Icon(Icons.check_circle_rounded, size: 56, color: Palette.good)
        : f.correct == false
        ? const Icon(Icons.replay_circle_filled_rounded, size: 56, color: Palette.warn)
        : const Icon(Icons.record_voice_over_rounded, size: 48, color: Palette.primary);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: InfoCard(
        color: color,
        child: Row(children: [
          icon,
          const SizedBox(width: 14),
          Expanded(child: Text(f.message, style: TextStyle(fontSize: f.correct == true ? 28 : 22, fontWeight: f.correct == true ? FontWeight.w700 : FontWeight.w400))),
        ]),
      ),
    );
  }
}

class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key, required this.tasks, this.unlocked = const []});
  final int tasks;

  /// Jednostki odblokowane w tej lekcji (nowy etap) – ogłaszane z pochwałą.
  final List<ReadingUnit> unlocked;
  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  bool _spoken = false;

  String _kindPl(ItemKind k) => switch (k) {
        ItemKind.syllable => 'sylaby',
        ItemKind.word => 'wyrazy',
        ItemKind.sentence => 'zdania',
        _ => 'czytanki',
      };

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final tasks = widget.tasks;
    final byKind = <ItemKind, List<ReadingUnit>>{};
    for (final u in widget.unlocked) {
      (byKind[u.kind] ??= []).add(u);
    }
    if (!_spoken) {
      _spoken = true;
      () async {
        if (byKind.isNotEmpty) {
          await s.sound.play(Sfx.newStage);
          final first = byKind.entries.first;
          await s.tts.speak('Brawo! Nowy etap. Możesz już ćwiczyć ${_kindPl(first.key)}: ${first.value.take(4).map((u) => u.title ?? u.text).join(', ')}.');
        } else {
          await s.tts.speak(tasks > 0 ? 'Dziękuję za dzisiejszą pracę.' : 'Do zobaczenia.');
        }
      }();
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(byKind.isNotEmpty ? Icons.emoji_events_rounded : Icons.wb_sunny_rounded, size: 96, color: byKind.isNotEmpty ? const Color(0xFFE09B2D) : Palette.primary),
                const SizedBox(height: 16),
                Text(tasks > 0 ? 'Dziękuję za dzisiejszą pracę!' : 'Do zobaczenia!',
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Text(tasks > 0 ? 'Wykonane zadania: $tasks. Wszystko jest zapisane.' : 'Postęp jest zapisany.',
                    style: const TextStyle(fontSize: 22), textAlign: TextAlign.center),
                for (final e in byKind.entries)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: InfoCard(
                      color: const Color(0xFFFFF4DC),
                      child: Column(children: [
                        Text('Nowy etap! Możesz już ćwiczyć ${_kindPl(e.key)}:', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        Text(e.value.take(12).map((u) => u.title ?? u.text).join('   '),
                            style: const TextStyle(fontSize: 30, color: Palette.primary), textAlign: TextAlign.center),
                      ]),
                    ),
                  ),
                const SizedBox(height: 32),
                FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Wróć do menu')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
