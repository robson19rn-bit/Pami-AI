/// Klasyfikacja wyniku rozpoznawania mowy i polityka oceny wypowiedzi.
///
/// ZASADY:
/// * Wykrycie dźwięku (VAD) NIE oznacza poprawnej odpowiedzi.
/// * Automatyczne zaliczenie tylko przy rozpoznaniu oczekiwanego tekstu z wysoką
///   pewnością i tylko dla sylab/wyrazów w trybie automatycznym. Pojedyncze litery
///   i głoski ZAWSZE ocenia opiekun (model nie jest wiarygodny dla krótkich głosek).
/// * ASR nigdy sam nie wystawia oceny „błędnie” – niepewność kieruje do powtórzenia
///   lub do opiekuna.
library;

import '../content/models.dart';
import 'types.dart';

enum AsrStatus { ok, noSpeech, error, noModel, noPermission }

class AsrWord {
  const AsrWord(this.word, this.conf);
  final String word;
  final double conf;
}

class AsrResult {
  const AsrResult(this.status, {this.text = '', this.words = const [], this.message});
  final AsrStatus status;
  final String text;
  final List<AsrWord> words;
  final String? message;

  double? get confidence => words.isEmpty ? null : words.map((w) => w.conf).reduce((a, b) => a < b ? a : b);

  factory AsrResult.fromMap(Map<dynamic, dynamic> m) => AsrResult(
        AsrStatus.values.byName(m['status'] as String? ?? 'error'),
        text: (m['text'] as String? ?? '').trim(),
        words: [
          for (final w in (m['words'] as List? ?? const []))
            AsrWord((w as Map)['word'] as String, ((w['conf'] as num?) ?? 0).toDouble())
        ],
        message: m['message'] as String?,
      );
}

/// (1) poprawna z dostateczną pewnością, (2) niepoprawna, (3) nic nie usłyszano, (4) niepewne/problem techniczny.
enum AsrVerdict { correct, incorrect, nothingHeard, uncertain }

String normalizeSpeech(String s) =>
    s.toLowerCase().replaceAll('[unk]', ' ').replaceAll(RegExp(r'[^a-ząćęłńóśźż ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

AsrVerdict classifyAsr(AsrResult r, String expected, {double threshold = 0.85}) {
  switch (r.status) {
    case AsrStatus.noSpeech:
      return AsrVerdict.nothingHeard;
    case AsrStatus.error:
    case AsrStatus.noModel:
    case AsrStatus.noPermission:
      return AsrVerdict.uncertain;
    case AsrStatus.ok:
      break;
  }
  final text = normalizeSpeech(r.text);
  if (text.isEmpty) {
    // Coś było słychać (np. [unk]), ale nie da się tego ocenić.
    return r.text.contains('[unk]') ? AsrVerdict.uncertain : AsrVerdict.nothingHeard;
  }
  final conf = r.confidence;
  if (conf == null || conf < threshold) return AsrVerdict.uncertain;
  return text == normalizeSpeech(expected) ? AsrVerdict.correct : AsrVerdict.incorrect;
}

enum EvaluationMode {
  /// Każdą wypowiedź ocenia opiekun (domyślnie).
  guardian,

  /// Sylaby i wyrazy: automatyczne zaliczenie przy pewnym rozpoznaniu; reszta – opiekun.
  autoWhereReliable,
}

enum SpeechDecisionKind { recordCorrect, askGuardian, retry, recordNotEvaluated, recordNoSpeech, recordUncertain }

class SpeechDecision {
  const SpeechDecision(this.kind, this.message);
  final SpeechDecisionKind kind;
  final String message;
}

/// Co zrobić z wynikiem ASR.
SpeechDecision decideSpeech({
  required AsrVerdict? verdict,
  required ItemKind kind,
  required Skill skill,
  required EvaluationMode mode,
  required bool guardianPresent,
  required int retriesSoFar,
}) {
  final autoAllowed = mode == EvaluationMode.autoWhereReliable &&
      (kind == ItemKind.syllable || kind == ItemKind.word) &&
      skill == Skill.readAloud;
  if (verdict == AsrVerdict.nothingHeard) {
    if (retriesSoFar < 1) return const SpeechDecision(SpeechDecisionKind.retry, 'Nic nie usłyszałem. Spróbuj powiedzieć jeszcze raz, trochę głośniej.');
    if (guardianPresent) return const SpeechDecision(SpeechDecisionKind.askGuardian, 'Mikrofon nic nie usłyszał. Opiekunie, oceń wypowiedź.');
    return const SpeechDecision(SpeechDecisionKind.recordNoSpeech, 'Nie udało się usłyszeć odpowiedzi. Wrócimy do tego później.');
  }
  if (verdict == AsrVerdict.correct && autoAllowed) {
    return const SpeechDecision(SpeechDecisionKind.recordCorrect, 'Dobrze!');
  }
  if (guardianPresent) {
    return const SpeechDecision(SpeechDecisionKind.askGuardian, 'Opiekunie, oceń wypowiedź.');
  }
  if (verdict == AsrVerdict.uncertain || verdict == AsrVerdict.incorrect) {
    if (retriesSoFar < 1) return const SpeechDecision(SpeechDecisionKind.retry, 'Nie jestem pewien, co usłyszałem. Powiedz jeszcze raz.');
    return const SpeechDecision(SpeechDecisionKind.recordUncertain, 'Nie mogę tego ocenić. Wrócimy do tego później.');
  }
  return const SpeechDecision(SpeechDecisionKind.recordNotEvaluated, 'Dziękuję, że mówisz na głos!');
}
