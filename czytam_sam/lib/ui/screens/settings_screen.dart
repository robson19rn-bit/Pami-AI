import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../app_state.dart';
import '../../data/backup.dart';
import '../../engine/mastery.dart';
import '../../services/speech_output.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'diagnosis_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.initialSection});
  final String? initialSection;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? modelInstalled;
  String? asrMsg;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final m = await AppScope.read(context).asr.modelInstalled();
      if (mounted) setState(() => modelInstalled = m);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Ustawienia')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _section('Profil dziecka', [
              ListTile(
                title: Text(s.childName ?? '(bez imienia)'),
                subtitle: const Text('Imię jest opcjonalne i zostaje tylko na tym urządzeniu.'),
                trailing: const Icon(Icons.edit),
                onTap: () => _editName(s),
              ),
              ListTile(
                title: const Text('Diagnoza początkowa'),
                subtitle: Text('Zdiagnozowano ${s.diagnosisDone.length} z 32 liter. Można wrócić w dowolnej chwili.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DiagnosisScreen())),
              ),
            ]),
            _section('Lektor (polecenia głosowe)', [
              SwitchListTile(
                value: s.ttsOk,
                title: const Text('Używaj lektora systemowego'),
                subtitle: const Text('Wyłącz, jeśli głos jest niewyraźny – polecenia będzie czytał opiekun.'),
                onChanged: (v) => s.setSetting('ttsOk', v),
              ),
              ListTile(
                title: Text('Tempo mowy: ${s.ttsRate.toStringAsFixed(2)}'),
                subtitle: Slider(
                  value: s.ttsRate,
                  min: 0.25,
                  max: 0.7,
                  divisions: 9,
                  onChanged: (v) async {
                    await s.setSetting('ttsRate', v);
                    await s.tts.setRate(v);
                  },
                ),
              ),
              ListTile(
                title: const Text('Sprawdź lektora i nazwy liter'),
                subtitle: Text('Odsłuchaj każdą nazwę litery i oznacz błędnie czytane. Oznaczone: ${s.ttsBadUnits.length}.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VoiceCheckScreen())),
              ),
            ]),
            _section('Dźwięki', [
              SwitchListTile(
                value: s.musicOn,
                title: const Text('Spokojna muzyczka w tle'),
                subtitle: const Text('Cicha, własna melodia; wycisza się, gdy mówi lektor i gdy słucha mikrofon.'),
                onChanged: (v) => s.setSetting('musicOn', v),
              ),
              SwitchListTile(
                value: s.sfxOn,
                title: const Text('Dźwięk przy odpowiedzi'),
                subtitle: const Text('Krótki sygnał po dobrej odpowiedzi i łagodny po pomyłce.'),
                onChanged: (v) => s.setSetting('sfxOn', v),
              ),
            ]),
            _section('Rozpoznawanie mowy (lokalne)', [
              ListTile(
                title: Text(modelInstalled == null
                    ? 'Sprawdzanie…'
                    : modelInstalled!
                        ? 'Model mowy zainstalowany'
                        : 'Model mowy NIE jest zainstalowany'),
                subtitle: const Text(
                    'Model: vosk-model-small-pl-0.22 (licencja Apache-2.0, ok. 50 MB). Pobierz plik ZIP na tablet ze strony '
                    'alphacephei.com/vosk/models, a potem wybierz go tutaj. Rozpoznawanie działa bez internetu; '
                    'nagrania nie są zapisywane.'),
              ),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton(onPressed: busy ? null : () => _importModel(s), child: const Text('Importuj model z pliku ZIP')),
                if (modelInstalled == true)
                  OutlinedButton(
                    onPressed: () async {
                      await s.asr.removeModel();
                      setState(() => modelInstalled = false);
                    },
                    child: const Text('Usuń model'),
                  ),
              ]),
              if (asrMsg != null) Padding(padding: const EdgeInsets.all(8), child: Text(asrMsg!, style: const TextStyle(fontSize: 16))),
              RadioGroup<String>(
                groupValue: s.evaluationMode.name,
                onChanged: (v) => s.setSetting('evaluationMode', v ?? 'guardian'),
                child: Column(children: [
                  const RadioListTile(value: 'guardian', title: Text('Wypowiedzi ocenia opiekun')),
                  RadioListTile(
                    value: 'autoWhereReliable',
                    enabled: modelInstalled == true,
                    title: const Text('Sylaby i wyrazy: automatycznie, gdy rozpoznanie jest pewne'),
                    subtitle: const Text('Litery i głoski zawsze ocenia opiekun.'),
                  ),
                ]),
              ),
            ]),
            _section('Parametry nauki (zaawansowane)', [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('Wartości domyślne są przykładowe i można je zmienić – nie są uniwersalną normą naukową.', style: TextStyle(fontSize: 15)),
              ),
              _configEditor(s),
            ]),
            _section('Kopia zapasowa', [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('Kopia zawiera historię prób i ustawienia (bez nagrań głosu – aplikacja ich nie przechowuje). '
                    'Zrób kopię przed zmianą telefonu lub przed instalacją wersji podpisanej innym kluczem.', style: TextStyle(fontSize: 15)),
              ),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton(onPressed: () => _export(s), child: const Text('Eksportuj do pliku')),
                OutlinedButton(onPressed: () => _import(s), child: const Text('Importuj z pliku')),
              ]),
            ]),
            _section('Reset', [
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: Palette.warn),
                onPressed: () => _reset(s),
                child: const Text('Usuń postępy tego profilu…'),
              ),
            ]),
            _section('Informacje', [
              ListTile(
                title: const Text('Licencje'),
                subtitle: const Text('Aplikacja: MIT. Biblioteki i model mowy – patrz lista.'),
                onTap: () => showLicensePage(context: context, applicationName: 'Czytam Sam', applicationVersion: appVersion),
              ),
              const ListTile(
                title: Text('Prywatność'),
                subtitle: Text('Brak reklam, telemetrii, kont i opłat. Aplikacja nie ma uprawnienia do internetu.'),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Card(
          color: Palette.surface,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(padding: const EdgeInsets.all(8), child: Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
              ...children,
            ]),
          ),
        ),
      );

  Future<void> _editName(AppState s) async {
    final c = TextEditingController(text: s.childName ?? '');
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Imię lub przezwisko'),
        content: TextField(controller: c, autofocus: true),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anuluj')), FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Zapisz'))],
      ),
    );
    if (r != null) await s.setChildName(r);
  }

  Widget _configEditor(AppState s) {
    final c = s.config.toJson();
    const labels = {
      'recognitionMinAttempts': 'Rozpoznanie: min. liczba prób',
      'recognitionMinAccuracy': 'Rozpoznanie: min. poprawność (0–1) w ostatnich 10',
      'speechMinAttempts': 'Mowa: min. liczba prób',
      'speechMinCorrect': 'Mowa: min. poprawnych (z ostatnich 5)',
      'minSessions': 'Potwierdzenie: min. liczba sesji',
      'minDays': 'Potwierdzenie: min. liczba dni',
      'shareDue': 'Udział zadań zaległych/trudnych (0–1)',
      'shareCurrent': 'Udział zadań bieżących (0–1)',
      'shareConsolidation': 'Udział utrwalania (0–1)',
      'maxActiveNewLetters': 'Ile nowych liter naraz',
      'sessionLength': 'Liczba zadań w sesji',
    };
    return Column(children: [
      for (final e in labels.entries)
        ListTile(
          dense: true,
          title: Text(e.value),
          trailing: Text('${c[e.key]}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          onTap: () async {
            final ctrl = TextEditingController(text: '${c[e.key]}');
            final v = await showDialog<String>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(e.value),
                content: TextField(controller: ctrl, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anuluj')), FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Zapisz'))],
              ),
            );
            final n = num.tryParse((v ?? '').replaceAll(',', '.'));
            if (n == null || n < 0) return;
            final m = Map<String, Object>.from(c)..[e.key] = n;
            await s.setSetting('config', MasteryConfig.fromJson(m).toJson());
          },
        ),
      TextButton(onPressed: () => s.setSetting('config', const MasteryConfig().toJson()), child: const Text('Przywróć domyślne')),
    ]);
  }

  Future<void> _importModel(AppState s) async {
    final f = await FilePicker.pickFile(type: FileType.any, dialogTitle: 'Wybierz plik vosk-model-small-pl-0.22.zip');
    if (f == null) return;
    setState(() {
      busy = true;
      asrMsg = 'Instalowanie modelu… (może potrwać minutę)';
    });
    try {
      var path = f.path;
      if (path == null) {
        final tmp = await getTemporaryDirectory();
        path = p.join(tmp.path, 'vosk-import.zip');
        await File(path).writeAsBytes(await f.readAsBytes(), flush: true);
      }
      final err = await s.asr.installModel(path);
      final ok = await s.asr.modelInstalled();
      setState(() {
        modelInstalled = ok;
        asrMsg = err ?? 'Model zainstalowany. Sprawdź działanie w kreatorze lub podczas ćwiczeń.';
      });
    } catch (e) {
      setState(() => asrMsg = 'Nie udało się zaimportować: $e');
    } finally {
      setState(() => busy = false);
    }
  }

  Future<void> _export(AppState s) async {
    final json = await s.exportJson();
    final now = s.clock();
    final name = 'czytam-sam-kopia-${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.json';
    final uri = await FilePicker.saveFile(fileName: name, bytes: utf8.encode(json), mimeType: 'application/json', dialogTitle: 'Zapisz kopię');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(uri == null ? 'Anulowano.' : 'Zapisano kopię: $name')));
  }

  Future<void> _import(AppState s) async {
    final f = await FilePicker.pickFile(type: FileType.any, dialogTitle: 'Wybierz plik kopii (.json)');
    if (f == null) return;
    final text = utf8.decode(await f.readAsBytes(), allowMalformed: true);
    final check = verifyBackup(text);
    if (!mounted) return;
    if (!check.ok) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(title: const Text('Plik nieprawidłowy'), content: Text(check.problems.join('\n')), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))]),
      );
      return;
    }
    final go = await confirm(context, 'Importować kopię?',
        'Plik jest poprawny (prób: ${check.counts['attempts']}, sesji: ${check.counts['sessions']}). Zdarzenia, które już są w aplikacji, zostaną pominięte – nic się nie zdubluje.');
    if (!go) return;
    final r = await s.importJson(text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Zaimportowano. Nowe próby: ${r.added['attempts']}, pominięte: ${r.skipped['attempts']}.')));
  }

  Future<void> _reset(AppState s) async {
    if (!await confirm(context, 'Usunąć postępy?', 'Wszystkie próby, sesje i oceny tego profilu zostaną usunięte. Zalecamy najpierw wykonać eksport kopii.',
        yes: 'Dalej', no: 'Anuluj')) {
      return;
    }
    if (!mounted) return;
    final ctrl = TextEditingController();
    final typed = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Potwierdzenie (krok 2 z 2)'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Wpisz słowo USUŃ, aby potwierdzić.'),
          TextField(controller: ctrl, autofocus: true),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anuluj')), FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Usuń'))],
      ),
    );
    if (typed?.trim().toUpperCase() != 'USUŃ') return;
    await s.resetProfile();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Postępy usunięte.')));
  }
}

/// Opiekun odsłuchuje nazwy liter i oznacza te, które lektor czyta błędnie.
class VoiceCheckScreen extends StatelessWidget {
  const VoiceCheckScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final bad = s.ttsBadUnits;
    return Scaffold(
      appBar: AppBar(title: const Text('Sprawdzenie lektora')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const InfoCard(child: Text('Naciśnij literę, aby usłyszeć polecenie. Jeśli nazwa brzmi źle, oznacz ją – wtedy polecenia z tą literą będzie czytał opiekun.', style: TextStyle(fontSize: 16))),
          for (final l in s.content.lettersInOrder)
            ListTile(
              leading: Text('${l.upper} ${l.lower}', style: const TextStyle(fontSize: 28)),
              title: Text('nazwa: „${l.name}”'),
              subtitle: l.ttsRisk ? const Text('Krótka nazwa – sprawdź szczególnie uważnie.') : null,
              onTap: () async {
                final r = await s.tts.speak('Wskaż literę ${l.nameTts}.');
                if (r != PlaybackResult.played && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lektor nie odtworzył dźwięku.')));
                }
              },
              trailing: FilterChip(
                label: Text(bad.contains(l.id) ? 'czyta źle' : 'w porządku'),
                selected: bad.contains(l.id),
                onSelected: (v) {
                  final n = {...bad};
                  v ? n.add(l.id) : n.remove(l.id);
                  s.setSetting('ttsBadUnits', n.toList());
                },
              ),
            ),
        ],
      ),
    );
  }
}

