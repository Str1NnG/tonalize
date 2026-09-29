import 'package:flutter/services.dart';

class ChromaFrame {
  final List<double> chroma;
  final double spl;
  final int bassPc;
  final double bassProb;
  const ChromaFrame(
    this.chroma,
    this.spl, {
    this.bassPc = -1,
    this.bassProb = 0.0,
  });
}

class PitchEvent {
  final double hz;
  final double probability;
  const PitchEvent(this.hz, this.probability);
}

class AudioService {
  static const _control = MethodChannel('tonalize/control');
  static const _chroma = EventChannel('tonalize/chroma');
  static const _pitch = EventChannel('tonalize/pitch');

  Stream<ChromaFrame>? _chromaStream;
  Stream<PitchEvent>? _pitchStream;

  Stream<ChromaFrame> chromaStream() {
    return _chromaStream ??= _chroma.receiveBroadcastStream().map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return ChromaFrame(
        (m['chroma'] as List).map((v) => (v as num).toDouble()).toList(),
        (m['spl'] as num).toDouble(),
        bassPc: (m['bassPc'] as num?)?.toInt() ?? -1,
        bassProb: (m['bassProb'] as num?)?.toDouble() ?? 0.0,
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
}
