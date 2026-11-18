/// Podział polskiego tekstu na grafemy (litery, dwuznaki, zmiękczenia).
///
/// Zasada: najdłuższe dopasowanie od lewej. „dzi” > „dz”, „dź”, „dż”, „ch”,
/// „cz”, „sz”, „rz”, „ci”, „si”, „zi”, „ni” > pojedyncza litera.
/// Wyjątki (np. „marznąć”, „odzież”, w których litery czyta się osobno)
/// celowo NIE występują w puli materiału – walidator to pilnuje listą
/// zakazanych wzorców.
library;

const multiGraphemes = ['dzi', 'ch', 'cz', 'sz', 'rz', 'dz', 'dź', 'dż', 'ci', 'si', 'zi', 'ni'];

const polishLetters = 'aąbcćdeęfghijklłmnńoóprsśtuwyzźż';

bool isPolishLetter(String ch) => polishLetters.contains(ch.toLowerCase());

List<String> tokenizeGraphemes(String text) {
  final w = text.toLowerCase();
  final out = <String>[];
  var i = 0;
  while (i < w.length) {
    final ch = w[i];
    if (!isPolishLetter(ch)) {
      i++;
      continue;
    }
    String? m;
    for (final g in multiGraphemes) {
      if (w.startsWith(g, i)) {
        m = g;
        break;
      }
    }
    if (m != null) {
      out.add(m);
      i += m.length;
    } else {
      out.add(ch);
      i++;
    }
  }
  return out;
}

List<String> uniqueGraphemes(String text) {
  final out = <String>[];
  for (final g in tokenizeGraphemes(text)) {
    if (!out.contains(g)) out.add(g);
  }
  return out;
}
