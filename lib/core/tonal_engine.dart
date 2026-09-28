import 'dart:math' as math;
import 'chroma_accumulator.dart';
import 'key_profiles.dart';
import 'key_scorer.dart';
import 'key_stabilizer.dart';

export 'chroma_accumulator.dart';
export 'key_profiles.dart';
export 'key_scorer.dart';
export 'key_stabilizer.dart';

class TonalReading {
  final KeyCandidate? displayed; // o que o letreiro mostra
  final KeyCandidate best; // vencedor bruto desta avaliação
  final KeyCandidate second; // melhor candidata diferente da exibida (2ª opção)
  final List<KeyCandidate> nearby; // as 3 melhores diferentes da exibida ("tons próximos")
  final double confidence; // (r da exibida - r da melhor outra) / fullConfidenceGap, 0..1
  final List<double> profile; // 12 valores normalizados para máximo 1 (barras)
  final Challenge? challenge; // desafio em andamento, para o indicador "confirmando..."
  final double secondsInWindow;
  final bool autoReset; // true na avaliação em que houve reinício por silêncio

  const TonalReading({
    this.displayed,
    required this.best,
    required this.second,
    required this.nearby,
    required this.confidence,
    required this.profile,
    this.challenge,
    required this.secondsInWindow,
    this.autoReset = false,
  });
}

class TonalEngine {
  TonalEngine({
    ChromaAccumulator? accumulator,
    KeyStabilizer? stabilizer,
    KeyScorer? scorer,
    this.fullConfidenceGap = 0.25,
  })  : accumulator = accumulator ?? ChromaAccumulator(),
        stabilizer = stabilizer ?? KeyStabilizer(),
        scorer = scorer ?? KeyScorer();

  final ChromaAccumulator accumulator;
  final KeyStabilizer stabilizer;
  final KeyScorer scorer;
  final double fullConfidenceGap;

  bool _justAutoReset = false;
  TonalReading? _lastReading;

  KeyCandidate? get displayed => stabilizer.displayed;
  TonalReading? get lastReading => _lastReading;
  int get switches => stabilizer.switches;

  void addFrame(List<double> chroma, Duration at) {
    if (chroma.length != 12) return;
    final didReset = accumulator.add(chroma, at);
    if (didReset) {
      stabilizer.reset();
      _justAutoReset = true;
    }
  }

  TonalReading? evaluate(Duration now) {
    if (accumulator.gapExceeded(now)) {
      reset();
      return null;
    }
    final rawProfile = accumulator.profile(now);
    if (rawProfile == null) return null;

    final maxVal = rawProfile.reduce(math.max);
    final minVal = rawProfile.reduce(math.min);
    if (maxVal <= 0 || (maxVal - minVal).abs() < 1e-6) {
      return null;
    }

    final scores = scorer.score(rawProfile);
    if (scores.isEmpty) return null;

    stabilizer.update(now, scores, accumulator.secondsInWindow);

    final best = scores.first;
    final displayedKey = stabilizer.displayed;

    // second e nearby são candidatas diferentes da exibida (ou de best se exibida for null)
    final refKey = displayedKey ?? best;
    final others = scores.where((c) => !c.sameKey(refKey)).toList();
    final second = others.isNotEmpty ? others.first : best;
    final nearby = others.take(3).toList();

    // confidence: usa o r da exibida (ou de best se ainda não houver exibida)
    final refR = refKey.r;
    final otherR = second.r;
    final confidence = ((refR - otherR) / fullConfidenceGap).clamp(0.0, 1.0);

    final normProfile = maxVal > 0
        ? rawProfile.map((v) => (v / maxVal).clamp(0.0, 1.0)).toList()
        : List<double>.filled(12, 0.0);

    final reading = TonalReading(
      displayed: displayedKey,
      best: best,
      second: second,
      nearby: nearby,
      confidence: confidence,
      profile: normProfile,
      challenge: stabilizer.challenge,
      secondsInWindow: accumulator.secondsInWindow,
      autoReset: _justAutoReset,
    );

    _justAutoReset = false;
    _lastReading = reading;
    return reading;
  }

  void reset() {
    accumulator.clear();
    stabilizer.reset();
    _lastReading = null;
    _justAutoReset = false;
  }
}
