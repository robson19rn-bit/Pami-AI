import 'package:material_ui/material_ui.dart';

import '../../engine/speech_policy.dart';
import '../../services/speech_input.dart';
import '../../services/speech_output.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'diagnosis_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

/// Pierwsze uruchomienie: profil, lektor, głośność, mikrofon, sposób oceny, diagnoza.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  int step = 0;
  final nameCtrl = TextEditingController();
  VoiceCheck? voice;
  PlaybackResult? playback;
  bool? heardOk;
  bool? modelInstalled;
  MicPermission? perm;
  String? micTest;
  bool micTestOk = false;
  EvaluationMode mode = EvaluationMode.guardian;

  @override
  Widget build(BuildContext context) {
    final steps = [_welcome, _voiceStep, _micStep, _modeStep, _finishStep];
    return Scaffold(
      appBar: AppBar(title: Text('Konfiguracja (${step + 1}/${steps.length})')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(padding: const EdgeInsets.all(20), children: [steps[step]()]),
          ),
        ),
      ),
    );
  }

  Widget _nav({bool canNext = true, String next = 'Dalej'}) => Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Row(children: [
          if (step > 0) OutlinedButton(onPressed: () => setState(() => step--), child: const Text('Wstecz')),
          const Spacer(),
          FilledButton(onPressed: canNext ? () => setState(() => step++) : null, child: Text(next)),
        ]),
      );

  Widget _welcome() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Witaj w aplikacji Czytam Sam', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        const Text(
            'Ta konfiguracja jest dla opiekuna. Aplikacja działa bez internetu, nie ma reklam, kont ani opłat. '
            'Dane zostają tylko na tym urządzeniu.',
            style: TextStyle(fontSize: 19)),
        const SizedBox(height: 16),
        TextField(
          controller: nameCtrl,
          style: const TextStyle(fontSize: 20),
          decoration: const InputDecoration(labelText: 'Imię lub przezwisko dziecka (opcjonalnie)', border: OutlineInputBorder()),
        ),
        _nav(),
      ]);

  Widget _voiceStep() {
    final s = AppScope.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Lektor i głośność', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      const Text('Ustaw głośność tabletu. Naciśnij „Odtwórz zdanie testowe” i powiedz, czy słychać wyraźny polski głos.', style: TextStyle(fontSize: 18)),
      const SizedBox(height: 12),
      FilledButton.icon(
        icon: const Icon(Icons.volume_up_rounded),
        label: const Text('Odtwórz zdanie testowe'),
        onPressed: () async {
          final v = await s.tts.check();
          final r = v.polishAvailable ? await s.tts.speak('Dzień dobry. Razem nauczymy się czytać.') : PlaybackResult.unavailable;
          setState(() {
            voice = v;
            playback = r;
          });
        },
      ),
      if (voice != null) ...[
        const SizedBox(height: 12),
        InfoCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(voice!.message, style: const TextStyle(fontSize: 17)),
            if (voice!.voices.isNotEmpty) Text('Polskie głosy: ${voice!.voices.take(4).join(', ')}', style: const TextStyle(fontSize: 15)),
            Text(
                playback == PlaybackResult.played
                    ? 'Silnik potwierdził rozpoczęcie mowy.'
                    : 'Silnik NIE potwierdził odtworzenia – polecenia będzie czytał opiekun.',
                style: const TextStyle(fontSize: 15)),
          ]),
        ),
        const SizedBox(height: 8),
        const Text('Czy usłyszałeś/aś poprawne polskie zdanie?', style: TextStyle(fontSize: 19)),
        Wrap(spacing: 8, children: [
          ChoiceChip(label: const Text('Tak, wyraźnie'), selected: heardOk == true, onSelected: (_) => setState(() => heardOk = true)),
          ChoiceChip(label: const Text('Nie'), selected: heardOk == false, onSelected: (_) => setState(() => heardOk = false)),
        ]),
        if (heardOk == false)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Bez lektora polecenia będzie czytał opiekun. Polski głos można doinstalować w Ustawieniach Androida → Zamiana tekstu na mowę.',
                style: TextStyle(fontSize: 16, color: Palette.warn)),
          ),
      ],
      const SizedBox(height: 8),
      const Text('Głoski lektor podaje w słowach (np. „na początku słowa mama”), bo w izolacji syntezatory wymawiają je błędnie. Dziecko może ćwiczyć samo; opiekun jest potrzebny tylko do krótkiej oceny wypowiedzi (Panel opiekuna → Ocena wypowiedzi).',
          style: TextStyle(fontSize: 15)),
      _nav(canNext: heardOk != null || voice?.polishAvailable == false),
    ]);
  }

  Widget _micStep() {
    final s = AppScope.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Mikrofon', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      const Text(
          'Rozpoznawanie mowy działa wyłącznie na tym urządzeniu (Vosk). Nagrania nie są zapisywane ani wysyłane. '
          'Model polskiej mowy (ok. 50 MB) trzeba jednorazowo zaimportować z pliku – instrukcja w Ustawieniach. '
          'Bez modelu wypowiedzi ocenia opiekun.',
          style: TextStyle(fontSize: 17)),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: () async {
          final m = await s.asr.modelInstalled();
          setState(() => modelInstalled = m);
          if (!m) return;
          final p = await s.asr.ensurePermission();
          setState(() => perm = p);
          if (p != MicPermission.granted) return;
          setState(() => micTest = 'Słucham… powiedz: „mama”.');
          final r = await s.asr.listen(['mama', 'tata', 'lato', '[unk]']);
          final v = classifyAsr(r, 'mama');
          setState(() {
            micTestOk = v == AsrVerdict.correct;
            micTest = switch (v) {
              AsrVerdict.correct => 'Rozpoznano „mama” z wysoką pewnością.',
              AsrVerdict.incorrect => 'Rozpoznano inne słowo: „${r.text}”.',
              AsrVerdict.nothingHeard => 'Mikrofon nic nie usłyszał.',
              AsrVerdict.uncertain => 'Wynik niepewny (${r.message ?? r.text}).',
            };
          });
        },
        child: const Text('Sprawdź mikrofon'),
      ),
      OutlinedButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen(initialSection: 'asr'))),
        child: const Text('Zaimportuj model mowy…'),
      ),
      if (modelInstalled != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: InfoCard(
            child: Text(
              !modelInstalled!
                  ? 'Model rozpoznawania mowy nie jest zainstalowany → tryb oceny przez opiekuna.'
                  : perm != MicPermission.granted && perm != null
                      ? 'Brak zgody na mikrofon → tryb oceny przez opiekuna.'
                      : (micTest ?? ''),
              style: const TextStyle(fontSize: 17),
            ),
          ),
        ),
      _nav(),
    ]);
  }

  Widget _modeStep() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Ocena wypowiedzi', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        RadioGroup<EvaluationMode>(
          groupValue: mode,
          onChanged: (v) => setState(() => mode = v ?? mode),
          child: Column(children: [
            const RadioListTile(
              value: EvaluationMode.guardian,
              title: Text('Ocenia opiekun (zalecane)'),
              subtitle: Text('Każdą wypowiedź dziecka zatwierdza dorosły: Poprawnie / Jeszcze nie / Powtórz / Nie można ocenić.'),
            ),
            RadioListTile(
              value: EvaluationMode.autoWhereReliable,
              enabled: micTestOk,
              title: const Text('Automatycznie dla sylab i wyrazów'),
              subtitle: Text(micTestOk
                  ? 'Sylaby i wyrazy rozpoznane z wysoką pewnością są zaliczane automatycznie. Litery i głoski zawsze ocenia opiekun. ASR nigdy sam nie wystawia oceny „błędnie”.'
                  : 'Niedostępne: test mikrofonu nie potwierdził działania rozpoznawania.'),
            ),
          ]),
        ),
        _nav(),
      ]);

  Widget _finishStep() {
    final s = AppScope.of(context);
    Future<void> save() async {
      await s.setChildName(nameCtrl.text);
      await s.setSetting('ttsOk', heardOk == true && playback == PlaybackResult.played);
      await s.setSetting('evaluationMode', mode.name);
      await s.setSetting('setupDone', true);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Diagnoza początkowa', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      const Text(
          'Sprawdzimy, które litery dziecko zna – osobno nazwę litery i jej głoskę. Zajmuje to ok. 10–15 minut; '
          'można przerwać i wrócić później (Ustawienia → Diagnoza).',
          style: TextStyle(fontSize: 18)),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: () async {
          final nav = Navigator.of(context);
          await save();
          nav.pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
          nav.push(MaterialPageRoute(builder: (_) => const DiagnosisScreen()));
        },
        child: const Text('Rozpocznij diagnozę'),
      ),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: () async {
          final nav = Navigator.of(context);
          await save();
          nav.pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
        },
        child: const Text('Pomiń na razie'),
      ),
    ]);
  }
}
