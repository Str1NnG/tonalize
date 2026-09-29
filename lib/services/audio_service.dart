import 'package:flutter/services.dart';

class ChromaFrame {
  final List<double>? chroma; // null se descartado por energia/tonalidade
  final List<double>? rawChroma;
  final List<double>? legacyChroma;
  final double spl;
  final int bassPc;
  final double bassProb;
  final int tAudioMs;
  final double tonal;
  final double bassHz;
  final double bassProbRaw;
  final bool bassPitched;

  const ChromaFrame(
    this.chroma,
    this.spl, {
    this.rawChroma,
    this.legacyChroma,
    this.bassPc = -1,
    this.bassProb = 0.0,
    this.tAudioMs = 0,
    this.tonal = 0.0,
    this.bassHz = 0.0,
    this.bassProbRaw = 0.0,
    this.bassPitched = false,
  });
}

class PitchEvent {
  final double hz;
  final double probability;
  const PitchEvent(this.hz, this.probability);
}

class AudioService {
  static const _control = MethodChannel('tonalize/control');
  static const _bench = MethodChannel('tonalize/bench');
  static const _chroma = EventChannel('tonalize/chroma');
  static const _pitch = EventChannel('tonalize/pitch');

  Stream<ChromaFrame>? _chromaStream;
  Stream<PitchEvent>? _pitchStream;

  Stream<ChromaFrame> chromaStream() {
    return _chromaStream ??= _chroma.receiveBroadcastStream().map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return ChromaFrame(
        (m['chroma'] as List?)?.map((v) => (v as num).toDouble()).toList(),
        (m['spl'] as num).toDouble(),
        rawChroma: (m['rawChroma'] as List?)?.map((v) => (v as num).toDouble()).toList(),
        legacyChroma: (m['legacyChroma'] as List?)?.map((v) => (v as num).toDouble()).toList(),
        bassPc: (m['bassPc'] as num?)?.toInt() ?? -1,
        bassProb: (m['bassProb'] as num?)?.toDouble() ?? 0.0,
        tAudioMs: (m['tAudioMs'] as num?)?.toInt() ?? 0,
        tonal: (m['tonal'] as num?)?.toDouble() ?? 0.0,
        bassHz: (m['bassHz'] as num?)?.toDouble() ?? 0.0,
        bassProbRaw: (m['bassProbRaw'] as num?)?.toDouble() ?? 0.0,
        bassPitched: m['bassPitched'] as bool? ?? false,
      );
    });
  }

  Stream<PitchEvent> pitchStream() {
    return _pitchStream ??= _pitch.receiveBroadcastStream().map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return PitchEvent(
        (m['hz'] as num).toDouble(),
        (m['probability'] as num).toDouble(),
      );
    });
  }

  Future<void> startKey({
    required int sensitivity,
    int? harmonics,
    double? peakThreshold,
    double? minTonalness,
    bool? bassEnabled,
  }) =>
      _control.invokeMethod(
        'start',
        {
          'mode': 'key',
          'sensitivity': sensitivity,
          if (harmonics != null) 'harmonics': harmonics,
          if (peakThreshold != null) 'peakThreshold': peakThreshold,
          if (minTonalness != null) 'minTonalness': minTonalness,
          if (bassEnabled != null) 'bassEnabled': bassEnabled,
        },
      );

  Future<void> startTuner() => _control.invokeMethod(
        'start',
        {'mode': 'tuner', 'sensitivity': 1},
      );

  Future<void> stop() => _control.invokeMethod('stop');

  // Métodos de Bancada (Bench Mode)
  Future<String> getBenchDir() async {
    final dir = await _bench.invokeMethod<String>('benchDir');
    return dir ?? '';
  }

  Future<bool> exportBench() async {
    final ok = await _bench.invokeMethod<bool>('exportBench');
    return ok ?? false;
  }

  Future<bool> exportSession(String sessionDir) async {
    final ok = await _bench.invokeMethod<bool>('exportSession', {'sessionDir': sessionDir});
    return ok ?? false;
  }
}
