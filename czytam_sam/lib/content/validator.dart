/// Walidacja materiału dydaktycznego. Błąd = pozycja nie może trafić do lekcji.
library;

import 'models.dart';
import 'tokenizer.dart';

class ContentIssue {
  ContentIssue(this.itemId, this.message, {this.isError = true});
  final String itemId, message;
  final bool isError;
  @override
  String toString() => '${isError ? 'BŁĄD' : 'UWAGA'} [$itemId]: $message';
}

/// Wzorce, w których litery czyta się osobno (np. marznąć, odzież, podzielić),
/// więc automatyczny podział na dwuznaki byłby błędny.
final _forbiddenPatterns = [
  RegExp(r'marz[nł]'),
  RegExp(r'murzyn'),
  RegExp(r'^odz'),
  RegExp(r'^podz'),
  RegExp(r'^nadz'),
  RegExp(r'^zmarz'),
];

const expectedAlphabet = [
  'a', 'ą', 'b', 'c', 'ć', 'd', 'e', 'ę', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'ł', //
  'm', 'n', 'ń', 'o', 'ó', 'p', 'r', 's', 'ś', 't', 'u', 'w', 'y', 'z', 'ź', 'ż',
];

const minimums = {ItemKind.syllable: 60, ItemKind.word: 100, ItemKind.sentence: 30, ItemKind.reading: 10};

List<ContentIssue> validateContent(ContentBundle c) {
  final issues = <ContentIssue>[];
  void err(String id, String m) => issues.add(ContentIssue(id, m));

  // Alfabet: dokładnie 32 litery, w tej kolejności, poprawne pary wielka/mała.
  final ids = c.letters.map((l) => l.id).toList()..sort((a, b) => expectedAlphabet.indexOf(a).compareTo(expectedAlphabet.indexOf(b)));
  if (c.letters.length != 32) err('alfabet', 'oczekiwano 32 liter, jest ${c.letters.length}');
  for (final id in expectedAlphabet) {
    if (c.letter(id) == null) err('alfabet', 'brak litery „$id”');
  }
  if (ids.toSet().length != ids.length) err('alfabet', 'zduplikowane identyfikatory liter');
  final orders = <int>{};
  for (final l in c.letters) {
    if (l.lower != l.id) err(l.id, 'mała litera różni się od identyfikatora');
    if (l.upper != l.lower.toUpperCase()) err(l.id, 'wielka litera ${l.upper} nie odpowiada ${l.lower}');
    if (l.name.trim().isEmpty) err(l.id, 'brak nazwy litery');
    if (l.sounds.isEmpty) err(l.id, 'brak opisu głosek');
    if (l.examples.isEmpty) err(l.id, 'brak przykładów');
    if (!orders.add(l.order)) err(l.id, 'powtórzona pozycja w kolejności nauki');
    for (final x in l.confusable) {
      if (!c.isGraphemeId(x)) err(l.id, 'nieznana litera myląca „$x”');
    }
    for (final e in l.examples) {
      if (!e.toLowerCase().contains(l.lower)) err(l.id, 'przykład „$e” nie zawiera litery');
    }
  }
  for (final g in c.graphemes) {
    if (!multiGraphemes.contains(g.id)) err(g.id, 'grafem nie jest obsługiwany przez tokenizator');
    for (final l in g.letters) {
      if (c.letter(l) == null) err(g.id, 'składowa „$l” nie jest literą');
    }
    for (final e in g.examples) {
      if (!tokenizeGraphemes(e).contains(g.id)) err(g.id, 'przykład „$e” nie zawiera grafemu');
    }
  }

  // Jednostki do czytania.
  final seen = <String>{};
  final all = [...c.syllables, ...c.words, ...c.sentences, ...c.readings];
  for (final u in all) {
    if (!seen.add(u.id)) err(u.id, 'zduplikowany identyfikator');
    if (u.needsReview) {
      issues.add(ContentIssue(u.id, 'oznaczone do weryfikacji – wyłączone z puli (${u.reviewNote ?? ''})', isError: false));
      continue;
    }
    final computed = uniqueGraphemes(u.text);
    final declared = u.graphemes.toSet();
    if (computed.toSet().difference(declared).isNotEmpty || declared.difference(computed.toSet()).isNotEmpty) {
      err(u.id, 'zadeklarowane grafemy $declared ≠ wyliczone ${computed.toSet()}');
    }
    for (final g in u.graphemes) {
      if (!c.isGraphemeId(g)) err(u.id, 'nieznany grafem „$g”');
    }
    for (final p in _forbiddenPatterns) {
      for (final w in u.text.toLowerCase().split(RegExp(r'[^a-ząćęłńóśźż]+'))) {
        if (p.hasMatch(w)) err(u.id, 'wyraz „$w” wymaga wyjątku w czytaniu dwuznaku');
      }
    }
    if (u.level < 1) err(u.id, 'brak poziomu trudności');
    if (u.goal.trim().isEmpty) err(u.id, 'brak celu');
    if ((u.kind == ItemKind.syllable || u.kind == ItemKind.word) && (u.pronunciation == null || u.pronunciation!.isEmpty)) {
      err(u.id, 'brak wymowy');
    }
    if (u.kind == ItemKind.sentence || u.kind == ItemKind.reading) {
      if (u.questions.isEmpty) err(u.id, 'brak pytania sprawdzającego zrozumienie');
      for (final q in u.questions) {
        if (!q.options.contains(q.answer)) err(u.id, 'odpowiedź „${q.answer}” spoza opcji');
        if (q.options.toSet().length != q.options.length) err(u.id, 'powtórzone opcje odpowiedzi');
        if (q.options.length < 2) err(u.id, 'za mało opcji odpowiedzi');
      }
    }
  }
  for (final e in minimums.entries) {
    final n = c.pool(e.key).length;
    if (n < e.value) err(e.key.name, 'w puli jest $n pozycji, wymagane minimum ${e.value}');
  }
  // Czytanki mają rosnącą trudność.
  for (var i = 1; i < c.readings.length; i++) {
    if (c.readings[i].level <= c.readings[i - 1].level) err(c.readings[i].id, 'czytanki nie mają rosnącej trudności');
  }
  return issues;
}
