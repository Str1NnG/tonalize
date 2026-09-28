import 'dart:math' as math;
import 'key_profiles.dart';

class TonalReading {
  final KeyCandidate best;
  final KeyCandidate second;
  final double confidence; // 0..1, a partir da diferença best.r - second.r
  final List<double> profile; // 12 valores, normalizados para máximo 1 (para as barras)
  final double secondsInWindow;

  const TonalReading({
    required this.best,
    required this.second,
    required this.confidence,
    required this.profile,
    required this.secondsInWindow,
  });
}

class _TimestampedFrame {
  final Duration at;
  final List<double> chroma;
  const _TimestampedFrame(this.at, this.chroma);
}

class TonalEngine {
  final double windowSeconds;
  final int stabilityCount;
  final double minSeconds;
  final double fullConfidenceGap;

  final List<_TimestampedFrame> _frames = [];

  KeyCandidate? _displayed;
  KeyCandidate? _candidate;
  int _candidateCount = 0;
  TonalReading? _lastReading;

  TonalEngine({
    this.windowSeconds = 10,
    this.stabilityCount = 3,
    this.minSeconds = 2,
    this.fullConfidenceGap = 0.25,
  });

  /// Tonalidade exibida na tela (só muda pela regra de estabilidade).
  KeyCandidate? get displayed => _displayed;

  /// Última leitura bruta (para segunda opção, confiança e barras).
  TonalReading? get lastReading => _lastReading;

  /// Adiciona um frame de 12 valores com seu timestamp.
  void addFrame(List<double> chroma, Duration at) {
    if (chroma.length != 12) return;
    _frames.add(_TimestampedFrame(at, List<double>.from(chroma)));
  }

  /// Avalia a janela atual e atualiza a tonalidade exibida e a última leitura.
  TonalReading? evaluate(Duration now) {
    final windowMicros = (windowSeconds * 1000000).round();
    _frames.removeWhere((f) => (now - f.at).inMicroseconds > windowMicros);

    if (_frames.isEmpty) {
      _lastReading = null;
      return null;
    }

    // 2. Soma dos frames por posição
    final sumProfile = List<double>.filled(12, 0.0);
    for (final frame in _frames) {
      for (var i = 0; i < 12; i++) {
        sumProfile[i] += frame.chroma[i];
      }
    }

    final totalSum = sumProfile.reduce((a, b) => a + b);
    final allEqual = sumProfile.every((v) => v == sumProfile.first);
    if (totalSum <= 0 || allEqual) {
      _lastReading = null;
      return null;
    }

    // 3. Calcular as 24 correlações (12 maiores, 12 menores)
    final candidates = <KeyCandidate>[];
    for (var tonic = 0; tonic < 12; tonic++) {
      final rMajor = pearson(sumProfile, rotated(kkMajor, tonic));
      candidates.add(KeyCandidate(tonic, true, rMajor));

      final rMinor = pearson(sumProfile, rotated(kkMinor, tonic));
      candidates.add(KeyCandidate(tonic, false, rMinor));
    }

    // 4. Ordenar por r decrescente
    candidates.sort((a, b) => b.r.compareTo(a.r));
    final best = candidates[0];
    final second = candidates[1];

    final confidence = (best.r <= 0)
        ? 0.0
        : ((best.r - second.r) / fullConfidenceGap).clamp(0.0, 1.0);

    // 6. secondsInWindow
    final secondsInWindow = _frames.length <= 1
        ? 0.0
        : (_frames.last.at - _frames.first.at).inMicroseconds / 1000000.0;

    // 5. Regra de estabilidade
    if (_displayed == null) {
      if (secondsInWindow >= minSeconds) {
        _displayed = best;
      }
    } else if (best.sameKey(_displayed)) {
      _candidate = null;
      _candidateCount = 0;
    } else if (best.sameKey(_candidate)) {
      _candidateCount++;
      if (_candidateCount >= stabilityCount) {
        _displayed = best;
        _candidate = null;
        _candidateCount = 0;
      }
    } else {
      _candidate = best;
      _candidateCount = 1;
    }

    // Perfil normalizado para máximo 1 (para visualização nas 12 barras)
    final maxVal = sumProfile.reduce(math.max);
    final normalizedProfile = maxVal > 0
        ? sumProfile.map((v) => v / maxVal).toList()
        : List<double>.filled(12, 0.0);

    final reading = TonalReading(
      best: best,
      second: second,
      confidence: confidence,
      profile: normalizedProfile,
      secondsInWindow: secondsInWindow,
    );

    _lastReading = reading;
    return reading;
  }

  /// RF05: zera janela, exibida, candidata e última leitura.
  void reset() {
    _frames.clear();
    _displayed = null;
    _candidate = null;
    _candidateCount = 0;
    _lastReading = null;
  }
}
