import 'dart:math' as math;

class ChromaAccumulator {
  ChromaAccumulator({
    this.windowSeconds = 20,
    this.halfLifeSeconds = 10,
    this.silenceResetSeconds = 4,
  });

  final double windowSeconds;
  final double halfLifeSeconds;
  final double silenceResetSeconds;

  final List<(Duration, List<double>)> _frames = [];

  Duration? get lastAt => _frames.isEmpty ? null : _frames.last.$1;

  /// Adiciona um frame. Retorna true se houve reinício automático por silêncio antes de adicionar.
  bool add(List<double> chroma, Duration at) {
    var reset = false;
    if (gapExceeded(at)) {
      clear();
      reset = true;
    }
    _frames.add((at, chroma));
    return reset;
  }

  bool gapExceeded(Duration now) =>
      lastAt != null &&
      (now - lastAt!).inMilliseconds > silenceResetSeconds * 1000;

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

  double get secondsInWindow => _frames.length < 2
      ? 0
      : (_frames.last.$1 - _frames.first.$1).inMilliseconds / 1000.0;

  void clear() => _frames.clear();
}
