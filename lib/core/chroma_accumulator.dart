import 'dart:math' as math;

class ChromaAccumulator {
  ChromaAccumulator({
    this.windowSeconds = 20,
    this.halfLifeSeconds = 10,
    this.silenceResetSeconds = 4,
    this.binSeconds = 0, // > 0: frames do mesmo intervalo são somados num só registro (memória longa fica leve)
  });

  final double windowSeconds;
  final double halfLifeSeconds;
  final double silenceResetSeconds;
  final double binSeconds;

  final List<(Duration, List<double>)> _frames = [];
  Duration? _lastFrameAt;

  Duration? get lastAt => _lastFrameAt;

  bool add(List<double> chroma, Duration at) {
    var reset = false;
    if (gapExceeded(at)) {
      clear();
      reset = true;
    }
    if (binSeconds > 0 &&
        _frames.isNotEmpty &&
        (at - _frames.last.$1).inMilliseconds < binSeconds * 1000) {
      final (t, acc) = _frames.last;
      _frames[_frames.length - 1] = (
        t,
        [for (var i = 0; i < 12; i++) acc[i] + chroma[i]]
      );
    } else {
      _frames.add((at, List<double>.from(chroma)));
    }
    _lastFrameAt = at;
    return reset;
  }

  bool gapExceeded(Duration now) =>
      _lastFrameAt != null &&
      (now - _lastFrameAt!).inMilliseconds > silenceResetSeconds * 1000;

  /// Soma ponderada por idade: peso = 0,5^(idade / meia-vida); frames mais velhos que a janela saem.
  List<double>? profile(Duration now) {
    _frames.removeWhere(
        (f) => (now - f.$1).inMilliseconds > windowSeconds * 1000);
    if (_frames.isEmpty) return null;
    final acc = List<double>.filled(12, 0);
    for (final (t, v) in _frames) {
      final age = (now - t).inMilliseconds / 1000.0;
      final w = math.pow(0.5, age / halfLifeSeconds).toDouble();
      for (var i = 0; i < 12; i++) {
        acc[i] += w * v[i];
      }
    }
    return acc;
  }

  double get secondsInWindow => _frames.isEmpty || _lastFrameAt == null
      ? 0
      : (_lastFrameAt! - _frames.first.$1).inMilliseconds / 1000.0;

  /// Recomeça com uma cópia dos registros de outra memória (reinício da memória da música a partir do trecho).
  void seedFrom(ChromaAccumulator other) {
    _frames
      ..clear()
      ..addAll(other._frames.map((f) => (f.$1, List<double>.from(f.$2))));
    _lastFrameAt = other._lastFrameAt;
  }

  void clear() {
    _frames.clear();
    _lastFrameAt = null;
  }
}
