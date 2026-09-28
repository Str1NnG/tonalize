import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import '../services/audio_service.dart';

class PitchData {
  final String note;
  final String octave;
  final int cents;
  final double hertz;
  PitchData({
    required this.note,
    required this.octave,
    required this.cents,
    required this.hertz,
  });
}

class TunerScreen extends StatefulWidget {
  const TunerScreen({super.key});

  @override
  State<TunerScreen> createState() => _TunerScreenState();
}

class _TunerScreenState extends State<TunerScreen>
    with SingleTickerProviderStateMixin {
  final AudioService _audioService = AudioService();
  StreamSubscription<PitchEvent>? _pitchSubscription;

  PitchData? _pitchData;
  final List<String> _notes = const [
    "C",
    "C#",
    "D",
    "D#",
    "E",
    "F",
    "F#",
    "G",
    "G#",
    "A",
    "A#",
    "B"
  ];
  late AnimationController _animationController;
  Animation<double>? _centsAnimation;
  final Queue<double> _hzHistory = Queue<double>();
  final int _hzHistorySize = 1;
  bool _wasTunedPreviously = false;
  Timer? _idleTimer;
  bool _isActivelyDetecting = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _startTuning();
  }

  @override
  void dispose() {
    _stopTuning();
    _animationController.dispose();
    _idleTimer?.cancel();
    super.dispose();
  }

  void _startTuning() {
    _pitchSubscription?.cancel();
    _pitchSubscription = _audioService.pitchStream().listen(
      _handlePitchEvent,
      onError: (err) {
        debugPrint("Erro no stream do afinador: $err");
      },
    );
    _audioService.startTuner();
  }

  void _stopTuning() {
    _pitchSubscription?.cancel();
    _pitchSubscription = null;
    _audioService.stop();
  }

  Future<void> _handlePitchEvent(PitchEvent event) async {
    if (!mounted) return;
    _idleTimer?.cancel();

    final double pitchInHz = event.hz;
    _hzHistory.add(pitchInHz);
    if (_hzHistory.length > _hzHistorySize) {
      _hzHistory.removeFirst();
    }
    final double averageHz =
        _hzHistory.reduce((a, b) => a + b) / _hzHistory.length;

    final newPitchData = _convertHzToPitchData(averageHz);

    if (newPitchData != null) {
      final currentCents =
          _centsAnimation?.value ?? newPitchData.cents.toDouble();
      _centsAnimation = Tween<double>(
        begin: currentCents,
        end: newPitchData.cents.clamp(-50.0, 50.0).toDouble(),
      ).animate(
        CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
      );
      _animationController.forward(from: 0.0);

      final isNowTuned = newPitchData.cents.abs() < 5;
      if (isNowTuned && !_wasTunedPreviously) {
        bool? hasVibrator = await Vibration.hasVibrator();
        if (hasVibrator ?? false) {
          Vibration.vibrate(duration: 50, amplitude: 128);
        }
      }
      _wasTunedPreviously = isNowTuned;
    } else {
      _wasTunedPreviously = false;
    }

    if (mounted) {
      setState(() {
        _pitchData = newPitchData ?? _pitchData;
        _isActivelyDetecting = newPitchData != null;
      });
    }

    _idleTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _isActivelyDetecting = false;
        });
      }
    });
  }

  PitchData? _convertHzToPitchData(double hz) {
    if (hz <= 0) return null;
    final double midiNote = 12 * (math.log(hz / 440) / math.log(2)) + 69;
    final int midiNoteRounded = midiNote.round();
    final int octave = (midiNoteRounded / 12).floor() - 1;
    final String noteName = _notes[((midiNoteRounded % 12) + 12) % 12];
    final double perfectFrequency =
        440 * math.pow(2, (midiNoteRounded - 69) / 12).toDouble();
    final int cents =
        (1200 * math.log(hz / perfectFrequency) / math.log(2)).round();
    return PitchData(
      note: noteName,
      octave: octave.toString(),
      cents: cents,
      hertz: hz,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isTuned = _isActivelyDetecting &&
        _pitchData != null &&
        _pitchData!.cents.abs() < 5;

    final Color inactiveColor = Colors.grey.shade600;
    final Color outOfTuneColor = Colors.orange.shade400;
    final Color inTuneColor = Colors.green.shade400;

    Color pointerColor;
    Color arcFillColor;

    if (!_isActivelyDetecting) {
      pointerColor = inactiveColor;
      arcFillColor = Colors.transparent;
    } else if (isTuned) {
      pointerColor = inTuneColor;
      arcFillColor = inTuneColor;
    } else {
      pointerColor = outOfTuneColor;
      arcFillColor = outOfTuneColor;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Afinador"),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          const Spacer(flex: 2),
          SizedBox(
            width: 300,
            height: 150,
            child: AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                return CustomPaint(
                  painter: TunerArcPainter(
                    pointerAngle: _centsAnimation?.value ?? 0.0,
                    arcColor: arcFillColor,
                    pointerColor: pointerColor,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _pitchData?.note ?? '--',
                style: TextStyle(
                  fontSize: 120,
                  fontWeight: FontWeight.bold,
                  color: pointerColor,
                  height: 1.0,
                ),
              ),
              Text(
                _pitchData?.octave ?? '',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: pointerColor,
                ),
              ),
            ],
          ),
          const Spacer(flex: 3),
          SizedBox(
            height: 60,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isActivelyDetecting && !isTuned && _pitchData != null)
                  Text(
                    "${_pitchData!.cents > 0 ? '+' : ''}${_pitchData!.cents} cents",
                    style: TextStyle(
                      color: pointerColor,
                      fontSize: 22,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                const SizedBox(height: 5),
                Text(
                  _pitchData != null
                      ? "${_pitchData!.hertz.toStringAsFixed(2)} Hz"
                      : "Aguardando som...",
                  style: TextStyle(
                    color: _isActivelyDetecting ? pointerColor : Colors.white70,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

class TunerArcPainter extends CustomPainter {
  final double pointerAngle;
  final Color arcColor;
  final Color pointerColor;

  TunerArcPainter({
    required this.pointerAngle,
    required this.arcColor,
    required this.pointerColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final radius = size.width / 2;
    const startAngle = -math.pi;
    const sweepAngle = math.pi;

    final borderPaint = Paint()
      ..color = Colors.grey.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      borderPaint,
    );

    if (arcColor != Colors.transparent) {
      final fillPaint = Paint()
        ..color = arcColor.withOpacity(0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        fillPaint,
      );
    }

    final double centsAsAngle =
        pointerAngle.clamp(-50, 50) * (math.pi / 2.5) / 50;
    final angle = -(math.pi / 2) + centsAsAngle;

    final needlePaint = Paint()
      ..color = pointerColor
      ..strokeWidth = 3;

    final needleStart = center;
    final needleEnd = Offset(
      center.dx + (radius - 15) * math.cos(angle),
      center.dy + (radius - 15) * math.sin(angle),
    );

    canvas.drawLine(needleStart, needleEnd, needlePaint);
  }

  @override
  bool shouldRepaint(covariant TunerArcPainter oldDelegate) {
    return oldDelegate.pointerAngle != pointerAngle ||
        oldDelegate.arcColor != arcColor ||
        oldDelegate.pointerColor != pointerColor;
  }
}