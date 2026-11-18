import 'package:material_ui/material_ui.dart';

import '../../content/models.dart';
import '../../engine/types.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Diagnoza początkowa prowadzona przez opiekuna: dla każdej litery osobno
/// NAZWA i GŁOSKA: zna / myli (z którą) / nie zna / pomiń. Można przerwać i wrócić.
class DiagnosisScreen extends StatefulWidget {
  const DiagnosisScreen({super.key});
  @override
  State<DiagnosisScreen> createState() => _DiagnosisScreenState();
}

class _DiagnosisScreenState extends State<DiagnosisScreen> {
  bool upper = false;
  bool? nameDone, soundDone;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final done = s.diagnosisDone;
    final remaining = s.content.lettersInOrder.where((l) => !done.contains(l.id)).toList();
    if (remaining.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Diagnoza')),
        body: const Padding(
          padding: EdgeInsets.all(24),
          child: Text('Diagnoza zakończona. Wyniki są widoczne w panelu opiekuna. Ćwiczenia dobiorą się automatycznie.', style: TextStyle(fontSize: 22)),
        ),
      );
    }
    final l = remaining.first;
    return Scaffold(
      appBar: AppBar(title: Text('Diagnoza – zostało ${remaining.length} z 32')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const InfoCard(
              child: Text(
                'Opiekunie: pokaż dziecku literę i zapytaj „Jaka to litera?”, potem „Jaką głoskę oznacza?”. '
                'Nie podpowiadaj. Zaznacz, co dziecko powiedziało SAMODZIELNIE. Możesz przerwać w dowolnej chwili.',
                style: TextStyle(fontSize: 17),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(upper ? l.upper : l.lower, style: const TextStyle(fontSize: 160, color: Palette.ink)),
            ),
            Center(
              child: TextButton(onPressed: () => setState(() => upper = !upper), child: Text(upper ? 'Pokaż małą' : 'Pokaż wielką')),
            ),
            Text('Nazwa litery (oczekiwana: „${l.name}”)', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            _row(l, Skill.sayName, nameDone, (v) => nameDone = v),
            const SizedBox(height: 12),
            Text('Głoska (oczekiwana: ${l.soundPrompt})', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            _row(l, Skill.saySound, soundDone, (v) => soundDone = v),
            const SizedBox(height: 24),
            Wrap(spacing: 12, runSpacing: 12, children: [
              FilledButton(
                onPressed: (nameDone != null && soundDone != null)
                    ? () async {
                        await s.markDiagnosed(l.id);
                        setState(() {
                          nameDone = null;
                          soundDone = null;
                        });
                      }
                    : null,
                child: const Text('Następna litera'),
              ),
              OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Przerwij – wrócę później')),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _row(Letter l, Skill skill, bool? done, void Function(bool) set) {
    final s = AppScope.read(context);
    Future<void> rec(Outcome o, {String? conf}) async {
      await s.recordDiagnosis(l.id, skill, o, confusedWith: conf);
      setState(() => set(true));
    }

    if (done == true) return const Padding(padding: EdgeInsets.all(8), child: Text('Zapisano ✓', style: TextStyle(fontSize: 18, color: Palette.good)));
    return Wrap(spacing: 8, runSpacing: 8, children: [
      FilledButton(onPressed: () => rec(Outcome.correct), child: const Text('Zna')),
      OutlinedButton(
        onPressed: () async {
          final other = await showDialog<String>(
            context: context,
            builder: (ctx) => SimpleDialog(
              title: const Text('Z którą literą myli?'),
              children: [
                Wrap(children: [
                  for (final x in s.content.lettersInOrder.where((x) => x.id != l.id))
                    SizedBox(width: 64, height: 64, child: TextButton(onPressed: () => Navigator.pop(ctx, x.id), child: Text(x.lower, style: const TextStyle(fontSize: 28)))),
                ]),
              ],
            ),
          );
          if (other != null) await rec(Outcome.incorrect, conf: other);
        },
        child: const Text('Myli z…'),
      ),
      OutlinedButton(onPressed: () => rec(Outcome.incorrect), child: const Text('Nie zna')),
      OutlinedButton(onPressed: () => rec(Outcome.uncertain), child: const Text('Nie można ocenić')),
    ]);
  }
}
