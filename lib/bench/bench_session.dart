import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:keyfinder/core/tonal_engine.dart';
import 'package:keyfinder/services/audio_service.dart';
import 'bench_song.dart';

class BenchSession {
  final BenchSong song;
  final String benchRootDir;
  final String configString;
  final String deviceModel;
  final String androidVersion;
  final String appVersion;
  final String gitCommit;

  late final Directory sessionDir;
  late final File framesFile;
  late final File readingsFile;
  late final File marksFile;
  late final File sessionJsonFile;

  IOSink? _framesSink;
  IOSink? _readingsSink;
  IOSink? _marksSink;

  Timer? _flushTimer;

  int frameCount = 0;
  int readingCount = 0;
  int markCount = 0;

  final DateTime startTimeWall;
  DateTime? endTimeWall;

  // Janela deslizante dos últimos 3 segundos para a "foto do acorde final"
  final List<List<double>> _recentChromaWindow = [];
  final int _maxRecentFrames = 35; // ~3.2 segundos a 10.8 fps

  static const List<String> pitchNames = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'
  ];

  BenchSession._({
    required this.song,
    required this.benchRootDir,
    required this.configString,
    this.deviceModel = 'Poco X7 Pro',
    this.androidVersion = '15',
    this.appVersion = '1.3.5',
    this.gitCommit = 'v3.5.2',
    required this.startTimeWall,
  });

  static Future<BenchSession> start({
    required BenchSong song,
    required String benchRootDir,
    required String configString,
    String deviceModel = 'Poco X7 Pro',
    String androidVersion = '15',
    String appVersion = '1.3.5',
    String gitCommit = 'v3.5.2',
  }) async {
    final now = DateTime.now();
    final session = BenchSession._(
      song: song,
      benchRootDir: benchRootDir,
      configString: configString,
      deviceModel: deviceModel,
      androidVersion: androidVersion,
      appVersion: appVersion,
      gitCommit: gitCommit,
      startTimeWall: now,
    );

    await session._initFiles();
    return session;
  }

  Future<void> _initFiles() async {
    final numStr = song.number.toString().padLeft(2, '0');
    final timeStamp = DateFormat('yyyyMMdd-HHmmss').format(startTimeWall);
    final folderName = '${numStr}_${song.slug}_$timeStamp';

    sessionDir = Directory('$benchRootDir${Platform.pathSeparator}$folderName');
    if (!await sessionDir.exists()) {
      await sessionDir.create(recursive: true);
    }

    framesFile = File('${sessionDir.path}${Platform.pathSeparator}frames.csv');
    readingsFile = File('${sessionDir.path}${Platform.pathSeparator}readings.csv');
    marksFile = File('${sessionDir.path}${Platform.pathSeparator}marks.csv');
    sessionJsonFile = File('${sessionDir.path}${Platform.pathSeparator}session.json');

    _framesSink = framesFile.openWrite(mode: FileMode.writeOnlyAppend);
    _readingsSink = readingsFile.openWrite(mode: FileMode.writeOnlyAppend);
    _marksSink = marksFile.openWrite(mode: FileMode.writeOnlyAppend);

    // Escrever cabeçalhos
    _framesSink!.writeln(
      't_audio_ms,t_wall_ms,'
      'c0,c1,c2,c3,c4,c5,c6,c7,c8,c9,c10,c11,'
      'r0,r1,r2,r3,r4,r5,r6,r7,r8,r9,r10,r11,'
      'level_db,tonal,bass_pc,bass_prob,bass_hz,bass_prob_raw,bass_pitched',
    );

    _readingsSink!.writeln(
      't_audio_ms,t_wall_ms,displayed,passage,showPassage,best,second,rBest,'
      'rDisplayed,rSecond,confidence,nearby,challenge,challengeProgress,event,'
      'evidenceSeconds,songSeconds,passageSeconds,labelChanges,songMature,config',
    );

    _marksSink!.writeln('t_audio_ms,t_wall_ms,label');

    // Flush a cada 5 segundos
    _flushTimer = Timer.periodic(const Duration(seconds: 5), (_) => flush());
  }

  void addFrame(ChromaFrame frame) {
    if (_framesSink == null) return;
    frameCount++;

    final tWall = DateTime.now().millisecondsSinceEpoch;

    // c0..c11 (com subarmônicos - null se descartado)
    final cPart = frame.chroma != null
        ? frame.chroma!.map((v) => v.toStringAsFixed(5)).join(',')
        : ',,,,,,,,,,,';

    // r0..r11 (sem subarmônicos - modo legado)
    final rPart = frame.legacyChroma != null
        ? frame.legacyChroma!.map((v) => v.toStringAsFixed(5)).join(',')
        : ',,,,,,,,,,,';

    final pitchedInt = frame.bassPitched ? 1 : 0;

    _framesSink!.writeln(
      '${frame.tAudioMs},$tWall,'
      '$cPart,$rPart,'
      '${frame.spl.toStringAsFixed(2)},${frame.tonal.toStringAsFixed(3)},'
      '${frame.bassPc},${frame.bassProb.toStringAsFixed(4)},'
      '${frame.bassHz.toStringAsFixed(2)},${frame.bassProbRaw.toStringAsFixed(4)},$pitchedInt',
    );

    // Salvar na janela deslizante dos últimos 3 segundos
    if (frame.chroma != null) {
      _recentChromaWindow.add(List<double>.from(frame.chroma!));
      if (_recentChromaWindow.length > _maxRecentFrames) {
        _recentChromaWindow.removeAt(0);
      }
    }
  }

  void addReading({
    required TonalReading reading,
    required int tAudioMs,
    required int labelChanges,
    required bool isSongMature,
  }) {
    if (_readingsSink == null) return;
    readingCount++;

    final tWall = DateTime.now().millisecondsSinceEpoch;
    final displayedStr = reading.displayed?.label ?? '';
    final passageStr = reading.passage?.label ?? '';
    final showPassageInt = reading.showPassage ? 1 : 0;
    final bestStr = reading.best.label;
    final secondStr = reading.second.label;
    final rBestStr = reading.best.r.toStringAsFixed(4);

    final rDisp = reading.displayed != null
        ? (reading.displayed!.sameKey(reading.best)
            ? reading.best.r
            : (reading.displayed!.sameKey(reading.second)
                ? reading.second.r
                : reading.confidence))
        : 0.0;
    final rDispStr = rDisp.toStringAsFixed(4);
    final rSecondStr = reading.second.r.toStringAsFixed(4);
    final confStr = reading.confidence.toStringAsFixed(4);

    final nearbyStr = reading.nearby.map((c) => c.label).join(';');
    final challengeStr = reading.challenge?.key.label ?? '';
    final challengeProg = reading.challenge != null
        ? reading.challenge!.progress(Duration(milliseconds: tAudioMs))
        : 0.0;

    final eventStr = reading.event == MemoryEvent.none ? '' : reading.event.name;
    final matureInt = isSongMature ? 1 : 0;

    _readingsSink!.writeln(
      '$tAudioMs,$tWall,$displayedStr,$passageStr,$showPassageInt,'
      '$bestStr,$secondStr,$rBestStr,$rDispStr,$rSecondStr,$confStr,'
      '"$nearbyStr",$challengeStr,${challengeProg.toStringAsFixed(2)},$eventStr,'
      '${reading.evidenceSeconds.toStringAsFixed(2)},'
      '${reading.songSeconds.toStringAsFixed(2)},'
      '${reading.secondsInWindow.toStringAsFixed(2)},'
      '$labelChanges,$matureInt,"$configString"',
    );
  }

  void addMark(String label, {int tAudioMs = 0}) {
    if (_marksSink == null) return;
    markCount++;
    final tWall = DateTime.now().millisecondsSinceEpoch;
    _marksSink!.writeln('$tAudioMs,$tWall,"$label"');
  }

  List<String> getFinalBarsTop3() {
    if (_recentChromaWindow.isEmpty) return [];

    final sum = List<double>.filled(12, 0.0);
    for (final frame in _recentChromaWindow) {
      for (var i = 0; i < 12; i++) {
        sum[i] += frame[i];
      }
    }

    final indexed = List.generate(12, (i) => MapEntry(i, sum[i]));
    indexed.sort((a, b) => b.value.compareTo(a.value));

    return indexed.take(3).map((e) => pitchNames[e.key]).toList();
  }

  Future<void> flush() async {
    await _framesSink?.flush();
    await _readingsSink?.flush();
    await _marksSink?.flush();
  }

  Future<void> completeSession({
    required String verdictResult, // 'acertou' | 'errou' | 'parcial' | 'referencia_duvidosa' | 'descartar'
    required String finalLabel,
    required String finalSecond,
    String notes = '',
  }) async {
    endTimeWall = DateTime.now();
    _flushTimer?.cancel();

    await flush();

    await _framesSink?.close();
    await _readingsSink?.close();
    await _marksSink?.close();
    _framesSink = null;
    _readingsSink = null;
    _marksSink = null;

    final top3 = getFinalBarsTop3();

    final sessionMap = {
      'schema': 1,
      'song': song.toJson(),
      'reference': {
        'key': song.referenceKey,
        'mode': song.referenceMode,
        'source': song.referenceSource,
        'segments': song.referenceSegments.map((s) => s.toJson()).toList(),
        'notes': song.notes,
      },
      'capture': {
        'started_wall': startTimeWall.toIso8601String(),
        'ended_wall': endTimeWall!.toIso8601String(),
        'device': deviceModel,
        'android': androidVersion,
        'app_version': appVersion,
        'git': gitCommit,
        'config': configString,
        'playback': 'alto-falantes do notebook, volume fixo',
        'distance_cm': 40,
        'room': 'sala silenciosa',
      },
      'verdict': {
        'final_bars_top3': top3,
        'final_label': finalLabel,
        'final_second': finalSecond,
        'result': verdictResult,
        'notes': notes,
      },
      'counts': {
        'frames': frameCount,
        'readings': readingCount,
        'marks': markCount,
      }
    };

    const encoder = JsonEncoder.withIndent('  ');
    await sessionJsonFile.writeAsString(encoder.convert(sessionMap));
  }
}
