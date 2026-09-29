// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:keyfinder/core/tonal_engine.dart';

class SessionData {
  final String dirPath;
  final Map<String, dynamic> sessionJson;
  final List<BenchFrameData> frames;

  SessionData({
    required this.dirPath,
    required this.sessionJson,
    required this.frames,
  });

  int get songNumber =>
      (sessionJson['song']?['number'] as int?) ?? 0;
  String get songTitle =>
      (sessionJson['song']?['title'] as String?) ?? 'Sem título';
  String get refKey =>
      (sessionJson['reference']?['key'] as String?) ?? '';
  String get refMode =>
      (sessionJson['reference']?['mode'] as String?) ?? 'major';
  List<dynamic> get segments =>
      (sessionJson['reference']?['segments'] as List?) ?? [];
}

class BenchFrameData {
  final int tAudioMs;
  final List<double>? chroma; // com harmônicos
  final List<double>? legacyChroma; // sem harmônicos
  final int bassPc;
  final double bassHz;
  final double bassProbRaw;
  final bool bassPitched;

  const BenchFrameData({
    required this.tAudioMs,
    required this.chroma,
    required this.legacyChroma,
    required this.bassPc,
    required this.bassHz,
    required this.bassProbRaw,
    required this.bassPitched,
  });
}

class GridConfig {
  final String profile;
  final String minorProfile;
  final double bassShare;
  final double evidenceFloor;
  final double songNearS;
  final bool strictNotes;

  // Fixos
  final int windowS;
  final int songHalfLifeS;
  final int songFarS;
  final double evidenceTol;
  final double evidenceDrain;
  final bool harmonics;
  final double bassConf;

  GridConfig({
    required this.profile,
    required this.minorProfile,
    required this.bassShare,
    required this.evidenceFloor,
    required this.songNearS,
    required this.strictNotes,
    this.windowS = 20,
    this.songHalfLifeS = 60,
    this.songFarS = 12,
    this.evidenceTol = 0.8,
    this.evidenceDrain = 0.5,
    this.harmonics = true,
    this.bassConf = 0.85,
  });

  String toConfigString() {
    return 'w$windowS;${harmonics ? "harm" : "legacy"};$profile;min-$minorProfile;'
        'song$songHalfLifeS;far$songFarS;near${songNearS.toInt()};'
        'tol$evidenceTol;floor$evidenceFloor;drain$evidenceDrain;'
        '${strictNotes ? "strict;" : ""}bass$bassShare;bconf$bassConf';
  }
}

class SongEvalResult {
  final int songNumber;
  final String songTitle;
  final int finalOk;
  final double timeOk;
  final double tFirstOk;
  final int changes;
  final double partial;
  final double relativeErr;
  final double modDelay;

  SongEvalResult({
    required this.songNumber,
    required this.songTitle,
    required this.finalOk,
    required this.timeOk,
    required this.tFirstOk,
    required this.changes,
    required this.partial,
    required this.relativeErr,
    required this.modDelay,
  });
}

class ConfigSummary {
  final GridConfig config;
  final List<SongEvalResult> songResults;

  ConfigSummary({required this.config, required this.songResults});

  int get songsOk => songResults.where((r) => r.timeOk >= 0.8).length;
  double get meanTimeOk => songResults.isEmpty
      ? 0.0
      : songResults.map((r) => r.timeOk).reduce((a, b) => a + b) / songResults.length;
  double get meanChanges => songResults.isEmpty
      ? 0.0
      : songResults.map((r) => r.changes).reduce((a, b) => a + b) / songResults.length;
  double get meanPartial => songResults.isEmpty
      ? 0.0
      : songResults.map((r) => r.partial).reduce((a, b) => a + b) / songResults.length;
  double get meanFinalOk => songResults.isEmpty
      ? 0.0
      : songResults.map((r) => r.finalOk).reduce((a, b) => a + b) / songResults.length;
}

void main(List<String> args) async {
  if (args.isEmpty || args.contains('-h') || args.contains('--help')) {
    print('Uso: dart run tool/calibrate.dart <pasta tonalize_bench> [--grid grid.yaml] [--out resultados.csv]');
    exit(args.isEmpty ? 1 : 0);
  }

  final benchDirPath = args.firstWhere((a) => !a.startsWith('--'));
  final benchDir = Directory(benchDirPath);
  if (!await benchDir.exists()) {
    stderr.writeln('Erro: Diretório da bancada não encontrado: $benchDirPath');
    exit(1);
  }

  final gridPath = _getArg(args, '--grid') ?? 'tool/grid.yaml';
  final outPath = _getArg(args, '--out') ?? 'resultados.csv';

  print('=== Tonalize Offline Calibration Tool ===');
  print('Diretório da bancada: $benchDirPath');
  print('Arquivo de grade: $gridPath');
  print('Arquivo de saída: $outPath');

  // 1. Carregar grade de parâmetros
  final gridFile = File(gridPath);
  if (!await gridFile.exists()) {
    stderr.writeln('Erro: Arquivo de grade não encontrado: $gridPath');
    exit(1);
  }
  final gridYamlContent = await gridFile.readAsString();
  final configs = _parseGridYaml(gridYamlContent);
  print('Total de configurações na grade: ${configs.length}');

  // 2. Carregar sessões válidas da bancada
  final sessions = await _loadSessions(benchDir);
  if (sessions.isEmpty) {
    stderr.writeln('Aviso: Nenhuma sessão válida com session.json e frames.csv encontrada em $benchDirPath');
    exit(0);
  }
  print('Sessões carregadas: ${sessions.length} músicas');

  // 3. Executar calibração
  print('Iniciando replay de ${configs.length} configurações em ${sessions.length} músicas...');
  final stopwatch = Stopwatch()..start();

  final summaries = <ConfigSummary>[];
  var configIdx = 0;

  for (final cfg in configs) {
    configIdx++;
    if (configIdx % 50 == 0 || configIdx == 1 || configIdx == configs.length) {
      final elapsed = stopwatch.elapsedMilliseconds / 1000.0;
      final speed = configIdx / (elapsed > 0 ? elapsed : 1);
      print('Progresso: $configIdx / ${configs.length} configs ($speed configs/s)...');
    }

    final songResults = <SongEvalResult>[];
    for (final session in sessions) {
      final res = _evaluateSession(session, cfg);
      songResults.add(res);
    }
    summaries.add(ConfigSummary(config: cfg, songResults: songResults));
  }

  // 4. Ranqueamento
  summaries.sort((a, b) {
    // 1. Maior songs_ok
    if (b.songsOk != a.songsOk) return b.songsOk.compareTo(a.songsOk);
    // 2. Maior mean_time_ok
    if ((b.meanTimeOk - a.meanTimeOk).abs() > 1e-4) {
      return b.meanTimeOk.compareTo(a.meanTimeOk);
    }
    // 3. Menor mean_changes
    return a.meanChanges.compareTo(b.meanChanges);
  });

  // 5. Escrever resultados.csv
  final outFile = File(outPath);
  final outSink = outFile.openWrite();

  outSink.writeln('=== RESUMO DAS CONFIGURACOES RANQUEADAS ===');
  outSink.writeln('rank,config,songs_ok,mean_time_ok,mean_final_ok,mean_changes,mean_partial');
  for (var r = 0; r < summaries.length; r++) {
    final s = summaries[r];
    outSink.writeln(
      '${r + 1},"${s.config.toConfigString()}",${s.songsOk},'
      '${s.meanTimeOk.toStringAsFixed(4)},${s.meanFinalOk.toStringAsFixed(4)},'
      '${s.meanChanges.toStringAsFixed(2)},${s.meanPartial.toStringAsFixed(4)}',
    );
  }

  outSink.writeln('');
  outSink.writeln('=== DETALHES POR MUSICA (CONFIGURACAO VENCEDORA) ===');
  outSink.writeln('song_number,song_title,final_ok,time_ok,t_first_ok,changes,partial,relative_err,mod_delay');
  if (summaries.isNotEmpty) {
    for (final sr in summaries.first.songResults) {
      outSink.writeln(
        '${sr.songNumber},"${sr.songTitle}",${sr.finalOk},'
        '${sr.timeOk.toStringAsFixed(4)},${sr.tFirstOk.toStringAsFixed(1)},'
        '${sr.changes},${sr.partial.toStringAsFixed(4)},'
        '${sr.relativeErr.toStringAsFixed(4)},${sr.modDelay.toStringAsFixed(1)}',
      );
    }
  }

  await outSink.flush();
  await outSink.close();

  // 6. Salvar calibracao.json com a vencedora
  if (summaries.isNotEmpty) {
    final winner = summaries.first;
    final calibJson = {
      'generated_at': DateTime.now().toIso8601String(),
      'benchmark_songs': sessions.length,
      'evaluated_configs': configs.length,
      'winning_config': {
        'config_string': winner.config.toConfigString(),
        'profiles': winner.config.profile,
        'minor_profiles': winner.config.minorProfile,
        'bass_share': winner.config.bassShare,
        'evidence_floor': winner.config.evidenceFloor,
        'song_near_s': winner.config.songNearS,
        'strict_notes': winner.config.strictNotes,
        'window_s': winner.config.windowS,
        'song_halflife_s': winner.config.songHalfLifeS,
        'song_far_s': winner.config.songFarS,
        'evidence_tol': winner.config.evidenceTol,
        'evidence_drain': winner.config.evidenceDrain,
        'harmonics': winner.config.harmonics,
        'bass_conf': winner.config.bassConf,
      },
      'metrics': {
        'songs_ok': winner.songsOk,
        'mean_time_ok': winner.meanTimeOk,
        'mean_final_ok': winner.meanFinalOk,
        'mean_changes': winner.meanChanges,
        'mean_partial': winner.meanPartial,
      }
    };
    final calibFile = File('calibracao.json');
    await calibFile.writeAsString(const JsonEncoder.withIndent('  ').convert(calibJson));
    print('Configuração vencedora salva em calibracao.json ✔');
  }

  stopwatch.stop();
  print('Concluído em ${stopwatch.elapsedMilliseconds / 1000.0}s!');
  print('');
  print('=== TOP 5 CONFIGURAÇÕES ===');
  for (var i = 0; i < summaries.take(5).length; i++) {
    final s = summaries[i];
    print(
      '#${i + 1}: ${s.config.toConfigString()} -> '
      'songs_ok: ${s.songsOk}/${sessions.length}, '
      'time_ok: ${(s.meanTimeOk * 100).toStringAsFixed(1)}%, '
      'final_ok: ${(s.meanFinalOk * 100).toStringAsFixed(1)}%, '
      'changes: ${s.meanChanges.toStringAsFixed(1)}',
    );
  }
}

SongEvalResult _evaluateSession(SessionData session, GridConfig cfg) {
  final profiles = _parseProfile(cfg.profile);
  final minorProfiles = _parseMinorProfile(cfg.minorProfile, profiles);

  final accumulator = ChromaAccumulator(
    windowSeconds: cfg.windowS.toDouble(),
    halfLifeSeconds: cfg.windowS / 2.0,
    silenceResetSeconds: 4,
  );

  final stabilizer = KeyStabilizer(
    minSeconds: 2.0,
    baseMargin: 0.05,
    baseHoldSeconds: 4.0,
    neighborMargin: 0.08,
    neighborHoldSeconds: 6.0,
    requireNewNotes: cfg.strictNotes,
    evidenceTolerance: cfg.evidenceTol,
    evidenceFloor: cfg.evidenceFloor,
  );

  final songConfig = SongMemoryConfig(
    enabled: true,
    halfLifeSeconds: cfg.songHalfLifeS.toDouble(),
    farResetSeconds: cfg.songFarS.toDouble(),
    nearResetSeconds: cfg.songNearS.toDouble(),
    evidenceTolerance: cfg.evidenceTol,
    evidenceFloor: cfg.evidenceFloor,
    evidenceDrain: cfg.evidenceDrain,
    bassShare: cfg.bassShare,
  );

  final engine = TonalEngine(
    passage: accumulator,
    passageStabilizer: stabilizer,
    scorer: KeyScorer(profiles: profiles, minorProfiles: minorProfiles),
    songConfig: songConfig,
  );

  int lastEvalAudioMs = -1;
  final readings = <Map<String, dynamic>>[];

  for (final frame in session.frames) {
    final tAudioMs = frame.tAudioMs;
    final chroma = cfg.harmonics ? frame.chroma : frame.legacyChroma;

    int effBassPc = -1;
    double effBassProb = 0.0;
    if (frame.bassPitched &&
        frame.bassHz >= 35.0 &&
        frame.bassHz <= 200.0 &&
        frame.bassProbRaw >= cfg.bassConf) {
      effBassPc = frame.bassPc;
      effBassProb = frame.bassProbRaw;
    }

    if (chroma != null) {
      engine.addFrame(
        chroma,
        Duration(milliseconds: tAudioMs),
        bassPc: effBassPc,
        bassProb: effBassProb,
      );
    }

    if (lastEvalAudioMs < 0 || (tAudioMs - lastEvalAudioMs) >= 500) {
      lastEvalAudioMs = tAudioMs;
      final r = engine.evaluate(Duration(milliseconds: tAudioMs));
      if (r != null) {
        readings.add({
          't_s': tAudioMs / 1000.0,
          'displayed': r.displayed,
          'second': r.second,
        });
      }
    }
  }

  // Métricas
  // Ignorar os 10s iniciais de áudio (aquecimento / piso de ruído)
  final evalReadings = readings.where((r) => (r['t_s'] as double) >= 10.0).toList();

  int totalEvaluated = 0;
  int correctCount = 0;
  int partialCount = 0;
  int relativeErrCount = 0;
  int wrongCount = 0;
  double tFirstOk = -1.0;

  for (final r in evalReadings) {
    final tSeconds = r['t_s'] as double;
    final disp = r['displayed'] as KeyCandidate?;
    final second = r['second'] as KeyCandidate;

    final (targetKey, targetMode) = _getTargetKeyForTime(session, tSeconds);

    if (disp != null) {
      totalEvaluated++;
      final isMatch = _isKeyMatch(disp, targetKey, targetMode);
      if (isMatch) {
        correctCount++;
        if (tFirstOk < 0) tFirstOk = tSeconds;
      } else {
        wrongCount++;
        if (_isKeyMatch(second, targetKey, targetMode)) {
          partialCount++;
        }
        if (_isRelativeKey(disp, targetKey, targetMode)) {
          relativeErrCount++;
        }
      }
    }
  }

  // final_ok
  int finalOk = 0;
  if (evalReadings.isNotEmpty) {
    final lastR = evalReadings.last;
    final lastDisp = lastR['displayed'] as KeyCandidate?;
    final (targetKey, targetMode) = _getTargetKeyForTime(session, lastR['t_s'] as double);
    if (lastDisp != null && _isKeyMatch(lastDisp, targetKey, targetMode)) {
      finalOk = 1;
    }
  }

  final timeOk = totalEvaluated > 0 ? (correctCount / totalEvaluated) : 0.0;
  final partial = wrongCount > 0 ? (partialCount / wrongCount) : 0.0;
  final relativeErr = wrongCount > 0 ? (relativeErrCount / wrongCount) : 0.0;

  // mod_delay para modulações/segmentos adicionais
  double modDelay = 0.0;
  if (session.segments.length > 1) {
    // Para o 2º segmento em diante
    for (var sIdx = 1; sIdx < session.segments.length; sIdx++) {
      final seg = session.segments[sIdx] as Map<String, dynamic>;
      final segFromS = (seg['from_s'] as num?)?.toDouble() ?? 0.0;
      final segKey = (seg['key'] as String?) ?? '';
      final segMode = (seg['mode'] as String?) ?? 'major';

      final segReadings = readings.where((r) => (r['t_s'] as double) >= segFromS).toList();
      for (final sr in segReadings) {
        final d = sr['displayed'] as KeyCandidate?;
        if (d != null && _isKeyMatch(d, segKey, segMode)) {
          modDelay += ((sr['t_s'] as double) - segFromS);
          break;
        }
      }
    }
  }

  return SongEvalResult(
    songNumber: session.songNumber,
    songTitle: session.songTitle,
    finalOk: finalOk,
    timeOk: timeOk,
    tFirstOk: tFirstOk >= 0 ? tFirstOk : 999.0,
    changes: engine.labelChanges,
    partial: partial,
    relativeErr: relativeErr,
    modDelay: modDelay,
  );
}

(String, String) _getTargetKeyForTime(SessionData session, double tSeconds) {
  if (session.segments.isNotEmpty) {
    final sorted = List<Map<String, dynamic>>.from(
      session.segments.whereType<Map<String, dynamic>>(),
    )..sort((a, b) => ((b['from_s'] as num?) ?? 0).compareTo((a['from_s'] as num?) ?? 0));

    for (final seg in sorted) {
      final fromS = ((seg['from_s'] as num?) ?? 0).toDouble();
      if (tSeconds >= fromS) {
        return (seg['key']?.toString() ?? '', seg['mode']?.toString() ?? 'major');
      }
    }
  }
  return (session.refKey, session.refMode);
}

bool _isKeyMatch(KeyCandidate candidate, String refKey, String refMode) {
  if (refKey.isEmpty) return false;
  final refTonic = _tonicFromName(refKey);
  if (refTonic < 0) return false;

  final isMajor = refMode.toLowerCase().contains('maj') || refMode.toLowerCase().contains('maior');
  return candidate.tonic == refTonic && candidate.major == isMajor;
}

bool _isRelativeKey(KeyCandidate candidate, String refKey, String refMode) {
  if (refKey.isEmpty) return false;
  final refTonic = _tonicFromName(refKey);
  if (refTonic < 0) return false;

  final refIsMajor = refMode.toLowerCase().contains('maj') || refMode.toLowerCase().contains('maior');

  // Relativo de Maior é Menor com tônica = (refTonic + 9) % 12
  // Relativo de Menor é Maior com tônica = (refTonic + 3) % 12
  if (refIsMajor) {
    final relTonic = (refTonic + 9) % 12;
    return candidate.tonic == relTonic && !candidate.major;
  } else {
    final relTonic = (refTonic + 3) % 12;
    return candidate.tonic == relTonic && candidate.major;
  }
}

int _tonicFromName(String name) {
  final clean = name.trim().replaceAll('m', '').replaceAll('M', '');
  final map = {
    'C': 0, 'B#': 0,
    'C#': 1, 'DB': 1, 'Db': 1,
    'D': 2,
    'D#': 3, 'EB': 3, 'Eb': 3,
    'E': 4, 'FB': 4, 'Fb': 4,
    'F': 5, 'E#': 5,
    'F#': 6, 'GB': 6, 'Gb': 6,
    'G': 7,
    'G#': 8, 'AB': 8, 'Ab': 8,
    'A': 9,
    'A#': 10, 'BB': 10, 'Bb': 10,
    'B': 11, 'CB': 11, 'Cb': 11,
  };
  return map[clean] ?? -1;
}

Future<List<SessionData>> _loadSessions(Directory benchDir) async {
  final list = <SessionData>[];
  final entities = await benchDir.list().toList();

  for (final entity in entities) {
    if (entity is Directory) {
      final sessionJsonFile = File('${entity.path}${Platform.pathSeparator}session.json');
      final framesFile = File('${entity.path}${Platform.pathSeparator}frames.csv');

      if (await sessionJsonFile.exists() && await framesFile.exists()) {
        try {
          final jsonContent = await sessionJsonFile.readAsString();
          final sessionMap = jsonDecode(jsonContent) as Map<String, dynamic>;

          // Ignorar se o veredito foi descartar
          final verdict = sessionMap['verdict']?['result'] as String?;
          if (verdict == 'descartar') continue;

          // Carregar frames.csv em memória
          final frames = await _parseFramesCsv(framesFile);
          if (frames.isNotEmpty) {
            list.add(SessionData(
              dirPath: entity.path,
              sessionJson: sessionMap,
              frames: frames,
            ));
          }
        } catch (e) {
          stderr.writeln('Aviso: Erro ao ler sessão em ${entity.path}: $e');
        }
      }
    }
  }

  list.sort((a, b) => a.songNumber.compareTo(b.songNumber));
  return list;
}

Future<List<BenchFrameData>> _parseFramesCsv(File file) async {
  final frames = <BenchFrameData>[];
  final lines = await file.readAsLines();
  if (lines.length <= 1) return frames;

  final header = lines.first.split(',');
  int colTAudio = header.indexOf('t_audio_ms');
  int colC0 = header.indexOf('c0');
  int colR0 = header.indexOf('r0');
  int colBassPc = header.indexOf('bass_pc');
  int colBassHz = header.indexOf('bass_hz');
  int colBassProbRaw = header.indexOf('bass_prob_raw');
  int colBassPitched = header.indexOf('bass_pitched');

  if (colTAudio < 0 || colC0 < 0) {
    colTAudio = 0;
    colC0 = 2;
    colR0 = 14;
    colBassPc = 28;
    colBassHz = 30;
    colBassProbRaw = 31;
    colBassPitched = 32;
  }

  for (var i = 1; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;
    final parts = line.split(',');
    if (parts.length < 26) continue;

    final tAudioMs = int.tryParse(parts[colTAudio]) ?? 0;

    List<double>? chroma;
    if (colC0 >= 0 && parts.length >= colC0 + 12 && parts[colC0].isNotEmpty) {
      chroma = List<double>.generate(12, (idx) => double.tryParse(parts[colC0 + idx]) ?? 0.0);
    }

    List<double>? legacyChroma;
    if (colR0 >= 0 && parts.length >= colR0 + 12 && parts[colR0].isNotEmpty) {
      legacyChroma = List<double>.generate(12, (idx) => double.tryParse(parts[colR0 + idx]) ?? 0.0);
    }

    int bPc = -1;
    double bHz = 0.0;
    double bProbRaw = 0.0;
    bool bPitched = false;

    if (colBassPc >= 0 && parts.length > colBassPitched) {
      bPc = int.tryParse(parts[colBassPc]) ?? -1;
      bHz = double.tryParse(parts[colBassHz]) ?? 0.0;
      bProbRaw = double.tryParse(parts[colBassProbRaw]) ?? 0.0;
      bPitched = (int.tryParse(parts[colBassPitched]) ?? 0) == 1;
    }

    frames.add(BenchFrameData(
      tAudioMs: tAudioMs,
      chroma: chroma,
      legacyChroma: legacyChroma,
      bassPc: bPc,
      bassHz: bHz,
      bassProbRaw: bProbRaw,
      bassPitched: bPitched,
    ));
  }

  return frames;
}

List<GridConfig> _parseGridYaml(String content) {
  final lines = content.split('\n');
  List<String> profiles = ['temperley'];
  List<String> minorProfiles = ['same'];
  List<double> bassShares = [0.25];
  List<double> evidenceFloors = [0.25];
  List<double> songNears = [45.0];
  List<bool> strictNotes = [false];

  int windowS = 20;
  int songHalfLifeS = 60;
  int songFarS = 12;
  double evidenceTol = 0.8;
  double evidenceDrain = 0.5;
  bool harmonics = true;
  double bassConf = 0.85;

  for (final l in lines) {
    final line = l.trim();
    if (line.isEmpty || line.startsWith('#')) continue;

    if (line.startsWith('profiles:')) {
      profiles = _parseList(line);
    } else if (line.startsWith('minor_profiles:')) {
      minorProfiles = _parseList(line);
    } else if (line.startsWith('bass_share:')) {
      bassShares = _parseList(line).map((v) => double.tryParse(v) ?? 0.0).toList();
    } else if (line.startsWith('evidence_floor:')) {
      evidenceFloors = _parseList(line).map((v) => double.tryParse(v) ?? 0.0).toList();
    } else if (line.startsWith('song_near_s:')) {
      songNears = _parseList(line).map((v) => double.tryParse(v) ?? 0.0).toList();
    } else if (line.startsWith('strict_notes:')) {
      strictNotes = _parseList(line).map((v) => v.toLowerCase() == 'true').toList();
    } else if (line.startsWith('window_s:')) {
      windowS = int.tryParse(line.split(':').last.trim()) ?? windowS;
    } else if (line.startsWith('song_halflife_s:')) {
      songHalfLifeS = int.tryParse(line.split(':').last.trim()) ?? songHalfLifeS;
    } else if (line.startsWith('song_far_s:')) {
      songFarS = int.tryParse(line.split(':').last.trim()) ?? songFarS;
    } else if (line.startsWith('evidence_tol:')) {
      evidenceTol = double.tryParse(line.split(':').last.trim()) ?? evidenceTol;
    } else if (line.startsWith('evidence_drain:')) {
      evidenceDrain = double.tryParse(line.split(':').last.trim()) ?? evidenceDrain;
    } else if (line.startsWith('harmonics:')) {
      harmonics = line.split(':').last.trim().toLowerCase() != 'legacy' &&
          line.split(':').last.trim().toLowerCase() != 'off';
    } else if (line.startsWith('bass_conf:')) {
      bassConf = double.tryParse(line.split(':').last.trim()) ?? bassConf;
    }
  }

  final configs = <GridConfig>[];
  for (final p in profiles) {
    for (final mp in minorProfiles) {
      for (final bs in bassShares) {
        for (final ef in evidenceFloors) {
          for (final sn in songNears) {
            for (final st in strictNotes) {
              configs.add(GridConfig(
                profile: p,
                minorProfile: mp,
                bassShare: bs,
                evidenceFloor: ef,
                songNearS: sn,
                strictNotes: st,
                windowS: windowS,
                songHalfLifeS: songHalfLifeS,
                songFarS: songFarS,
                evidenceTol: evidenceTol,
                evidenceDrain: evidenceDrain,
                harmonics: harmonics,
                bassConf: bassConf,
              ));
            }
          }
        }
      }
    }
  }

  return configs;
}

List<String> _parseList(String line) {
  final start = line.indexOf('[');
  final end = line.indexOf(']');
  if (start >= 0 && end > start) {
    final sub = line.substring(start + 1, end);
    return sub.split(',').map((s) => s.trim().replaceAll('"', '').replaceAll("'", '')).toList();
  }
  return [];
}

String? _getArg(List<String> args, String name) {
  for (var i = 0; i < args.length; i++) {
    if (args[i] == name && i + 1 < args.length) {
      return args[i + 1];
    }
    if (args[i].startsWith('$name=')) {
      return args[i].substring(name.length + 1);
    }
  }
  return null;
}

ProfileSet _parseProfile(String name) {
  final lower = name.toLowerCase();
  if (lower.startsWith('temp') && lower.contains('kp')) return ProfileSet.temperleyKP;
  if (lower.startsWith('tkp')) return ProfileSet.temperleyKP;
  if (lower.startsWith('temp') || lower.startsWith('tmp')) return ProfileSet.temperley;
  if (lower.startsWith('aar')) return ProfileSet.aarden;
  if (lower.startsWith('krum') || lower == 'kk') return ProfileSet.krumhansl;
  return ProfileSet.temperley;
}

ProfileSet? _parseMinorProfile(String name, ProfileSet majorDefault) {
  final lower = name.toLowerCase();
  if (lower == 'same') return majorDefault;
  if (lower.startsWith('temp') && lower.contains('kp')) return ProfileSet.temperleyKP;
  if (lower.startsWith('tkp')) return ProfileSet.temperleyKP;
  if (lower.startsWith('temp') || lower.startsWith('tmp')) return ProfileSet.temperley;
  if (lower.startsWith('aar')) return ProfileSet.aarden;
  if (lower.startsWith('krum') || lower == 'kk') return ProfileSet.krumhansl;
  return null;
}
