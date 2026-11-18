/// Modele materiału dydaktycznego (czysty Dart – bez zależności od Fluttera).
library;

enum ItemKind { letter, grapheme, syllable, word, sentence, reading }

ItemKind itemKindFromName(String n) => ItemKind.values.byName(n);

class SoundRule {
  const SoundRule(this.ipa, this.context);
  final String ipa;
  final String context;
  factory SoundRule.fromJson(Map<String, dynamic> j) =>
      SoundRule(j['ipa'] as String, j['context'] as String);
}

/// Litera alfabetu (32 sztuki).
class Letter {
  Letter({
    required this.id,
    required this.upper,
    required this.lower,
    required this.name,
    required this.nameTts,
    required this.isVowel,
    required this.order,
    required this.sounds,
    required this.soundPrompt,
    required this.examples,
    required this.confusable,
    required this.ttsRisk,
  });
  final String id, upper, lower, name, nameTts, soundPrompt;
  final bool isVowel, ttsRisk;
  final int order;
  final List<SoundRule> sounds;
  final List<String> examples, confusable;

  factory Letter.fromJson(Map<String, dynamic> j) => Letter(
        id: j['id'] as String,
        upper: j['upper'] as String,
        lower: j['lower'] as String,
        name: j['name'] as String,
        nameTts: j['nameTts'] as String,
        isVowel: j['type'] == 'samogloska',
        order: j['order'] as int,
        sounds: [for (final s in j['sounds'] as List) SoundRule.fromJson(s as Map<String, dynamic>)],
        soundPrompt: j['soundPrompt'] as String,
        examples: List<String>.from(j['examples'] as List),
        confusable: List<String>.from(j['confusable'] as List),
        ttsRisk: j['ttsRisk'] as bool? ?? false,
      );
}

/// Grafem wieloliterowy: dwuznak (ch, cz, sz, rz, dz, dź, dż) lub zmiękczenie (ci, si, zi, ni, dzi).
class Grapheme {
  Grapheme({
    required this.id,
    required this.text,
    required this.kind,
    required this.letters,
    required this.sounds,
    required this.soundPrompt,
    required this.examples,
    required this.confusable,
    this.softOf,
    this.note,
  });
  final String id, text, kind, soundPrompt;
  final List<String> letters, examples, confusable;
  final List<SoundRule> sounds;
  final String? softOf, note;

  factory Grapheme.fromJson(Map<String, dynamic> j) => Grapheme(
        id: j['id'] as String,
        text: j['text'] as String,
        kind: j['kind'] as String,
        letters: List<String>.from(j['letters'] as List),
        sounds: [for (final s in j['sounds'] as List) SoundRule.fromJson(s as Map<String, dynamic>)],
        soundPrompt: j['soundPrompt'] as String,
        examples: List<String>.from(j['examples'] as List),
        confusable: List<String>.from(j['confusable'] as List),
        softOf: j['softOf'] as String?,
        note: j['note'] as String?,
      );
}

class Question {
  Question(this.question, this.options, this.answer);
  final String question, answer;
  final List<String> options;
  factory Question.fromJson(Map<String, dynamic> j) =>
      Question(j['question'] as String, List<String>.from(j['options'] as List), j['answer'] as String);
}

/// Jednostka do czytania: sylaba, wyraz, zdanie lub czytanka.
class ReadingUnit {
  ReadingUnit({
    required this.id,
    required this.kind,
    required this.text,
    required this.graphemes,
    required this.level,
    required this.goal,
    this.title,
    this.pronunciation,
    this.pronunciationNote,
    this.contextNote,
    this.needsReview = false,
    this.reviewNote,
    this.questions = const [],
  });
  final String id, text, goal;
  final ItemKind kind;
  final List<String> graphemes;
  final int level;
  final String? title, pronunciation, pronunciationNote, contextNote, reviewNote;
  final bool needsReview;
  final List<Question> questions;

  factory ReadingUnit.fromJson(ItemKind kind, Map<String, dynamic> j) {
    final qs = <Question>[];
    if (j['question'] != null) {
      qs.add(Question(j['question'] as String, List<String>.from(j['options'] as List), j['answer'] as String));
    }
    for (final q in (j['questions'] as List? ?? const [])) {
      qs.add(Question.fromJson(q as Map<String, dynamic>));
    }
    return ReadingUnit(
      id: j['id'] as String,
      kind: kind,
      text: j['text'] as String,
      graphemes: List<String>.from(j['graphemes'] as List),
      level: j['level'] as int,
      goal: j['goal'] as String,
      title: j['title'] as String?,
      pronunciation: j['pronunciation'] as String?,
      pronunciationNote: j['pronunciationNote'] as String?,
      contextNote: j['contextNote'] as String?,
      needsReview: j['needsReview'] as bool? ?? false,
      reviewNote: j['reviewNote'] as String?,
      questions: qs,
    );
  }
}

/// Cały materiał dydaktyczny (oddzielony od historii postępów).
class ContentBundle {
  ContentBundle({
    required this.letters,
    required this.graphemes,
    required this.syllables,
    required this.words,
    required this.sentences,
    required this.readings,
  }) {
    for (final l in letters) {
      _letters[l.id] = l;
    }
    for (final g in graphemes) {
      _graphemes[g.id] = g;
    }
    for (final u in [...syllables, ...words, ...sentences, ...readings]) {
      _units[u.id] = u;
    }
  }

  final List<Letter> letters;
  final List<Grapheme> graphemes;
  final List<ReadingUnit> syllables, words, sentences, readings;
  final Map<String, Letter> _letters = {};
  final Map<String, Grapheme> _graphemes = {};
  final Map<String, ReadingUnit> _units = {};

  Letter? letter(String id) => _letters[id];
  Grapheme? grapheme(String id) => _graphemes[id];
  ReadingUnit? unit(String id) => _units[id];
  bool isGraphemeId(String id) => _letters.containsKey(id) || _graphemes.containsKey(id);

  List<Letter> get lettersInOrder => [...letters]..sort((a, b) => a.order.compareTo(b.order));

  /// Tekst wyświetlany dla litery/grafemu.
  String displayOf(String graphemeId, {bool upper = false}) {
    final l = _letters[graphemeId];
    if (l != null) return upper ? l.upper : l.lower;
    return _graphemes[graphemeId]?.text ?? graphemeId;
  }

  ItemKind kindOf(String itemId) {
    if (_letters.containsKey(itemId)) return ItemKind.letter;
    if (_graphemes.containsKey(itemId)) return ItemKind.grapheme;
    return _units[itemId]?.kind ?? ItemKind.word;
  }

  /// Jednostki wchodzące do puli (bez pozycji oznaczonych do weryfikacji).
  Iterable<ReadingUnit> pool(ItemKind kind) {
    final src = switch (kind) {
      ItemKind.syllable => syllables,
      ItemKind.word => words,
      ItemKind.sentence => sentences,
      ItemKind.reading => readings,
      _ => const <ReadingUnit>[],
    };
    return src.where((u) => !u.needsReview);
  }

  static ContentBundle fromJsonMaps({
    required Map<String, dynamic> letters,
    required Map<String, dynamic> syllables,
    required Map<String, dynamic> words,
    required Map<String, dynamic> sentences,
    required Map<String, dynamic> readings,
  }) {
    List<ReadingUnit> units(ItemKind k, Map<String, dynamic> m, String key) =>
        [for (final e in m[key] as List) ReadingUnit.fromJson(k, e as Map<String, dynamic>)];
    return ContentBundle(
      letters: [for (final e in letters['letters'] as List) Letter.fromJson(e as Map<String, dynamic>)],
      graphemes: [for (final e in letters['graphemes'] as List) Grapheme.fromJson(e as Map<String, dynamic>)],
      syllables: units(ItemKind.syllable, syllables, 'syllables'),
      words: units(ItemKind.word, words, 'words'),
      sentences: units(ItemKind.sentence, sentences, 'sentences'),
      readings: units(ItemKind.reading, readings, 'readings'),
    );
  }
}
