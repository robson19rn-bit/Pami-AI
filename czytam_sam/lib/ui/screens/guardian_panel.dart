import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../../content/models.dart';
import '../../engine/curriculum.dart';
import '../../engine/mastery.dart';
import '../../engine/report.dart';
import '../../engine/scheduler.dart';
import '../../engine/types.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Panel opiekuna – wszystkie liczby wyliczane z rzeczywistego dziennika prób.
class GuardianPanel extends StatelessWidget {
  const GuardianPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Panel opiekuna'),
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Litery'),
            Tab(text: 'Czytanie'),
            Tab(text: 'Mylone'),
            Tab(text: 'Historia'),
            Tab(text: 'Mowa i podpowiedzi'),
            Tab(text: 'Etapy i plan'),
          ]),
        ),
        body: const TabBarView(children: [_LettersTab(), _ReadingTab(), _ConfusionTab(), _HistoryTab(), _SpeechTab(), _PlanTab()]),
      ),
    );
  }
}

Color stateColor(MasteryState s) => switch (s) {
      MasteryState.nowe => const Color(0xFFEDEDED),
      MasteryState.uczone => const Color(0xFFFFF1DC),
      MasteryState.cwiczone => const Color(0xFFFFF8C5),
      MasteryState.opanowaneWarunkowo => const Color(0xFFDDEEDD),
      MasteryState.potwierdzone => const Color(0xFFB9E3C6),
      MasteryState.doPowtorzenia => const Color(0xFFFFD9D2),
    };

Widget stateChip(SkillStats st) => Tooltip(
      message: '${st.skill.label}: ${st.state.label}\n'
          'pierwsze próby: ${st.firstAttempts}, samodzielnie poprawne: ${st.independentCorrect}, błędy: ${st.independentErrors}\n'
          'po podpowiedzi poprawne: ${st.hintedCorrect}, brak dźwięku: ${st.noSpeech}, niepewne: ${st.uncertain}, nieocenione: ${st.notEvaluated}'
          '${st.avgResponseMs != null ? '\nśredni czas: ${(st.avgResponseMs! / 1000).toStringAsFixed(1)} s (tylko informacyjnie)' : ''}',
      child: Container(
        width: 112,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(color: stateColor(st.state), borderRadius: BorderRadius.circular(8)),
        child: Text('${st.state.label}\n${st.independentCorrect}/${st.independentCorrect + st.independentErrors}',
            style: const TextStyle(fontSize: 13, color: Palette.ink), textAlign: TextAlign.center),
      ),
    );

const _letterSkills = [Skill.recognizeName, Skill.sayName, Skill.recognizeSound, Skill.saySound, Skill.caseMatch];

class _LettersTab extends StatelessWidget {
  const _LettersTab();
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final idx = s.index;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const InfoCard(
          child: Text('Każda umiejętność jest liczona osobno. Liczby = poprawne samodzielnie / wszystkie samodzielne próby '
              '(bez prób po podpowiedzi i bez nieocenionej mowy). Przytrzymaj pole, aby zobaczyć szczegóły.', style: TextStyle(fontSize: 15)),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 8,
            dataRowMinHeight: 52,
            dataRowMaxHeight: 60,
            columns: [
              const DataColumn(label: Text('Litera')),
              for (final sk in _letterSkills) DataColumn(label: Text(sk.label)),
              const DataColumn(label: Text('Pełna znajomość')),
            ],
            rows: [
              for (final l in s.content.lettersInOrder)
                DataRow(cells: [
                  DataCell(Text('${l.upper} ${l.lower}', style: const TextStyle(fontSize: 24))),
                  for (final sk in _letterSkills) DataCell(stateChip(idx.of(l.id, sk))),
                  DataCell(Text(idx.letterFullyMastered(l.id) ? 'tak' : 'nie')),
                ]),
              for (final g in s.content.graphemes)
                DataRow(cells: [
                  DataCell(Text(g.text, style: const TextStyle(fontSize: 24))),
                  for (final sk in _letterSkills)
                    DataCell(sk == Skill.recognizeSound || sk == Skill.saySound ? stateChip(idx.of(g.id, sk)) : const Text('–')),
                  DataCell(Text(idx.soundReady(g.id) ? 'tak' : 'nie')),
                ]),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReadingTab extends StatelessWidget {
  const _ReadingTab();
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final cur = s.curriculum;
    Widget group(String title, ItemKind kind, List<Skill> skills) {
      final units = cur.units(kind, includeLocked: true);
      final open = units.where((u) => u.access != Access.locked).toList();
      return ExpansionTile(
        title: Text('$title: dostępne ${open.length} z ${units.length}', style: const TextStyle(fontSize: 19)),
        children: [
          for (final ua in open)
            ListTile(
              title: Text(ua.unit.title ?? ua.unit.text, style: const TextStyle(fontSize: 20)),
              subtitle: Text(ua.access == Access.manualAssisted ? 'z pomocą (ręczne, bez zaliczenia) – brakuje: ${ua.missing.join(', ')}' : 'poziom ${ua.unit.level}'),
              trailing: Wrap(children: [for (final sk in skills) stateChip(s.index.of(ua.unit.id, sk))]),
            ),
          if (open.isEmpty) const ListTile(title: Text('Jeszcze niedostępne – zobacz zakładkę „Etapy i plan”.')),
        ],
      );
    }

    return ListView(children: [
      group('Sylaby', ItemKind.syllable, [Skill.segment, Skill.readAloud]),
      group('Wyrazy', ItemKind.word, [Skill.readAloud, Skill.segment]),
      group('Zdania', ItemKind.sentence, [Skill.comprehension]),
      group('Czytanki', ItemKind.reading, [Skill.comprehension]),
    ]);
  }
}

class _ConfusionTab extends StatelessWidget {
  const _ConfusionTab();
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final r = s.report;
    final pairs = r.confusions.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    if (pairs.isEmpty) return const Center(child: Text('Brak zarejestrowanych pomyłek.', style: TextStyle(fontSize: 20)));
    final maxV = pairs.first.value;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('Mapa mylonych liter (cel → wybrane zamiast)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        for (final e in pairs)
          ListTile(
            leading: Text('${s.content.displayOf(e.key.$1)} → ${s.content.displayOf(e.key.$2)}', style: const TextStyle(fontSize: 26)),
            title: LinearProgressIndicator(value: e.value / maxV, minHeight: 12),
            trailing: Text('${e.value}×', style: const TextStyle(fontSize: 18)),
          ),
      ],
    );
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab();
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final r = s.report;
    if (r.byDay.isEmpty) return const Center(child: Text('Brak historii – dziecko jeszcze nie ćwiczyło.', style: TextStyle(fontSize: 20)));
    final days = r.byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    final weeks = <DateTime, Tally>{};
    for (final d in days) {
      final w = d.subtract(Duration(days: d.weekday - 1));
      final t = weeks.putIfAbsent(w, Tally.new);
      r.byDay[d]!.counts.forEach((k, v) => t.counts[k] = t.counts[k]! + v);
    }
    String f(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    DataTable table(String first, Map<DateTime, Tally> src, {bool withTime = false}) {
      final keys = src.keys.toList()..sort((a, b) => b.compareTo(a));
      return DataTable(columnSpacing: 12, columns: [
        DataColumn(label: Text(first)),
        const DataColumn(label: Text('Próby')),
        for (final c in ReportCategory.values) DataColumn(label: SizedBox(width: 90, child: Text(c.label, style: const TextStyle(fontSize: 13)))),
        if (withTime) const DataColumn(label: Text('Sesje / czas')),
      ], rows: [
        for (final k in keys)
          DataRow(cells: [
            DataCell(Text(f(k))),
            DataCell(Text('${src[k]!.total}')),
            for (final c in ReportCategory.values) DataCell(Text('${src[k]![c]}')),
            if (withTime) DataCell(Text('${r.sessionsByDay[k] ?? 0} / ${(r.sessionTimeByDay[k] ?? Duration.zero).inMinutes} min')),
          ]),
      ]);
    }

    return ListView(padding: const EdgeInsets.all(12), children: [
      const Text('Dziennie', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: table('Dzień', r.byDay, withTime: true)),
      const SizedBox(height: 16),
      const Text('Tygodniowo (od poniedziałku)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: table('Tydzień od', weeks)),
      const Text('Czas trwania sesji jest wyłącznie informacyjny – nie wpływa na ocenę ani awans.', style: TextStyle(fontSize: 14)),
    ]);
  }
}

class _SpeechTab extends StatelessWidget {
  const _SpeechTab();
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final r = s.report;
    String pct(double? v) => v == null ? 'brak danych' : '${(v * 100).round()}%';
    final ov = speechOverrides(s.actions);
    final speech = s.attempts.where((a) => a.skill.isSpeech).toList().reversed.take(40).toList();
    return ListView(padding: const EdgeInsets.all(12), children: [
      InfoCard(
        child: Text(
          'Mowa potwierdzona przez opiekuna: ${r.speech.confirmedByGuardian}\n'
          'Mowa zaliczona automatycznie (pewne rozpoznanie): ${r.speech.confirmedByAsr}\n'
          'Oceniona jako „jeszcze nie”: ${r.speech.judgedIncorrect}\n'
          'Niepewna / nieoceniona / nic nie usłyszano: ${r.speech.unconfirmed}',
          style: const TextStyle(fontSize: 17),
        ),
      ),
      InfoCard(
        child: Text(
          'Efekt podpowiedzi: poprawność samodzielna ${pct(r.accuracyIndependent)} (liczba prób: ${r.independentAttempts}), '
          'po podpowiedzi lub z pomocą ${pct(r.accuracyAfterHint)} (liczba prób: ${r.hintedAttempts}). '
          'Odpowiedzi po podpowiedzi nie liczą się do opanowania.',
          style: const TextStyle(fontSize: 17),
        ),
      ),
      const Padding(
        padding: EdgeInsets.all(8),
        child: Text('Ostatnie wypowiedzi – korekta oceny dodaje osobny wpis opiekuna; oryginalna próba zostaje bez zmian.', style: TextStyle(fontSize: 15)),
      ),
      for (final a in speech)
        ListTile(
          title: Text('${s.content.unit(a.itemId)?.text ?? s.content.displayOf(a.itemId)} – ${a.skill.label}'),
          subtitle: Text('${a.task.label}; zapis: ${a.outcome.label}${ov.containsKey(a.id) ? ', korekta opiekuna: ${ov[a.id]!.label}' : ''}'
              '${a.asrText != null && a.asrText!.isNotEmpty ? '; rozpoznano: „${a.asrText}”' : ''}'),
          trailing: PopupMenuButton<Outcome>(
            tooltip: 'Koryguj ocenę',
            onSelected: (o) => s.addAction(GuardianActionType.rateSpeech, target: a.id, value: o.name),
            itemBuilder: (_) => const [
              PopupMenuItem(value: Outcome.correct, child: Text('Poprawnie')),
              PopupMenuItem(value: Outcome.incorrect, child: Text('Jeszcze nie')),
              PopupMenuItem(value: Outcome.uncertain, child: Text('Nie można ocenić')),
            ],
          ),
        ),
    ]);
  }
}

class _PlanTab extends StatelessWidget {
  const _PlanTab();
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final cur = s.curriculum;
    final cap = Capabilities(guardianPresent: true, ttsOk: s.ttsOk, asrReady: false, ttsBadUnits: s.ttsBadUnits);
    final plan = planSession(candidates: buildCandidates(cur, cap), index: s.index, now: s.clock(), n: s.config.sessionLength, rng: Random(1));
    final manual = s.manualStages;
    String bucketLabel(Bucket b) => switch (b) { Bucket.due => 'zaległe/trudne', Bucket.current => 'bieżące', Bucket.consolidation => 'utrwalanie' };
    String itemLabel(String id) => s.content.unit(id)?.text ?? s.content.displayOf(id);
    return ListView(padding: const EdgeInsets.all(12), children: [
      const Text('Postęp do kolejnego etapu', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
      for (final e in cur.stageProgress().entries) ListTile(dense: true, title: Text(e.key), subtitle: Text(e.value.isEmpty ? '—' : e.value, style: const TextStyle(fontSize: 17))),
      const Divider(),
      const Text('Co program planuje ćwiczyć (sesja z opiekunem)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
      for (final p in plan)
        ListTile(
          dense: true,
          leading: Text(itemLabel(p.candidate.itemId), style: const TextStyle(fontSize: 22)),
          title: Text('${p.candidate.task.label} – ${p.candidate.skill.label}'),
          subtitle: Text('${bucketLabel(p.bucket)} · stan: ${s.index.state(p.candidate.itemId, p.candidate.skill).label}'),
        ),
      const Divider(),
      const Text('Ręczne odblokowanie etapu', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
      const Text('Materiał odblokowany ręcznie jest oznaczony „z pomocą – ręczne, bez zaliczenia”. Nie zmienia wyników diagnozy ani prób.', style: TextStyle(fontSize: 15)),
      for (final k in [ItemKind.syllable, ItemKind.word, ItemKind.sentence, ItemKind.reading])
        SwitchListTile(
          title: Text(switch (k) { ItemKind.syllable => 'Sylaby', ItemKind.word => 'Wyrazy', ItemKind.sentence => 'Zdania', _ => 'Czytanki' }),
          subtitle: Text(cur.stageReached(k) ? 'etap osiągnięty z wyników' : 'etap jeszcze nieosiągnięty'),
          value: manual.contains(k),
          onChanged: (v) => s.addAction(v ? GuardianActionType.manualUnlock : GuardianActionType.revokeUnlock, target: k.name),
        ),
    ]);
  }
}

