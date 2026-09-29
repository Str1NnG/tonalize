// ignore_for_file: avoid_print
import 'dart:io';
import 'package:keyfinder/core/tonal_engine.dart';

void main(List<String> args) async {
  if (args.isEmpty || args.contains('-h') || args.contains('--help')) {
    print('Uso: dart run tool/replay.dart <pasta da sessão> [opções]');
    print('');
    print('Opções:');
    print('  --config <string>        Configuração completa (ex: "v2;w20;harm;tmp;min-aar;song60;...")');
    print('  --harmonics <on|legacy>  Usar harmônicos c0..c11 (on) ou legado r0..r11 (legacy)');
    print('  --bass-share <double>    Fração do baixo no perfil (padrão: 0.25)');
    print('  --bass-conf <double>     Limiar de confiança YIN para aceitar baixo (padrão: 0.85)');
    print('  --profiles <name>        Conjunto de perfis maiores (temperley, aarden, krumhansl, temperleyKP)');
    print('  --minor-profiles <name>  Conjunto de perfis menores (same, aarden, krumhansl, temperley, temperleyKP)');
    print('  --window-s <int>         Tamanho da janela do trecho em segundos (padrão: 20)');
    print('  --song-halflife-s <int>  Meia-vida da memória da música (padrão: 60)');
    print('  --out <arquivo>          Arquivo CSV de saída (padrão: <pasta>/timeline.csv)');
    print('  --check-fidelity         Compara timeline gerada com readings.csv existente');
    exit(args.isEmpty ? 1 : 0);
  }

  final sessionDirPath = args.firstWhere((a) => !a.startsWith('--'));
  final sessionDir = Directory(sessionDirPath);
  if (!await sessionDir.exists()) {
    stderr.writeln('Erro: Diretório de sessão não encontrado: $sessionDirPath');
    exit(1);
  }

  final framesFile = File('${sessionDir.path}${Platform.pathSeparator}frames.csv');
  if (!await framesFile.exists()) {
    stderr.writeln('Erro: frames.csv não encontrado em $sessionDirPath');
    exit(1);
  }

  // Parse arguments
  String? configStr = _getArg(args, '--config');
  String harmonics = _getArg(args, '--harmonics') ?? 'on';
  double bassShare = double.tryParse(_getArg(args, '--bass-share') ?? '') ?? 0.25;
  double bassConf = double.tryParse(_getArg(args, '--bass-conf') ?? '') ?? 0.85;
  String profileName = _getArg(args, '--profiles') ?? 'temperley';
  String minorProfileName = _getArg(args, '--minor-profiles') ?? 'aarden';
  int windowSeconds = int.tryParse(_getArg(args, '--window-s') ?? '') ?? 20;
  int songHalfLife = int.tryParse(_getArg(args, '--song-halflife-s') ?? '') ?? 60;
  int songFar = 12;
  int songNear = 45;
  double evidenceTol = 0.8;
  double evidenceFloor = 0.25;
  double evidenceDrain = 0.5;
  bool strictNotes = false;
  bool songMemoryEnabled = true;
  String stabMode = 'v2';

  // Se config foi passado, aplica defaults do config
  if (configStr != null && configStr.isNotEmpty) {
    final parts = configStr.split(';');
    for (final p in parts) {
      if (p == 'v1' || p == 'v2') stabMode = p;
      if (p.startsWith('w')) windowSeconds = int.tryParse(p.substring(1)) ?? windowSeconds;
      if (p == 'harm') harmonics = 'on';
      if (p == 'noharm' || p == 'legacy') harmonics = 'legacy';
      if (p == 'tmp' || p == 'temperley') profileName = 'temperley';
      if (p == 'tkp' || p == 'temperleykp') profileName = 'temperleyKP';
      if (p == 'aar' || p == 'aarden') profileName = 'aarden';
      if (p == 'kk' || p == 'krumhansl') profileName = 'krumhansl';
      if (p.startsWith('min-')) minorProfileName = p.substring(4);
      if (p.startsWith('song')) {
        songMemoryEnabled = true;
        songHalfLife = int.tryParse(p.substring(4)) ?? songHalfLife;
      }
      if (p == 'nosong') songMemoryEnabled = false;
      if (p.startsWith('far')) songFar = int.tryParse(p.substring(3)) ?? songFar;
      if (p.startsWith('near')) songNear = int.tryParse(p.substring(4)) ?? songNear;
      if (p.startsWith('tol')) evidenceTol = double.tryParse(p.substring(3)) ?? evidenceTol;
      if (p.startsWith('floor')) evidenceFloor = double.tryParse(p.substring(5)) ?? evidenceFloor;
      if (p.startsWith('drain')) evidenceDrain = double.tryParse(p.substring(5)) ?? evidenceDrain;
      if (p == 'strict') strictNotes = true;
      if (p.startsWith('bass')) bassShare = double.tryParse(p.substring(4)) ?? bassShare;
      if (p.startsWith('bconf')) bassConf = double.tryParse(p.substring(5)) ?? bassConf;
    }
  }

  final profiles = _parseProfile(profileName);
  final minorProfiles = _parseMinorProfile(minorProfileName, profiles);
  final useHarmonics = harmonics != 'legacy' && harmonics != 'off';

  final accumulator = ChromaAccumulator(
    windowSeconds: windowSeconds.toDouble(),
    halfLifeSeconds: windowSeconds / 2.0,
    silenceResetSeconds: 4,
  );

  final stabilizer = KeyStabilizer(
    minSeconds: 2.0,
    baseMargin: 0.05,
    baseHoldSeconds: 4.0,
    neighborMargin: 0.08,
    neighborHoldSeconds: 6.0,
    requireNewNotes: strictNotes,
    evidenceTolerance: evidenceTol,
    evidenceFloor: evidenceFloor,
  );

  final songConfig = SongMemoryConfig(
    enabled: songMemoryEnabled,
    halfLifeSeconds: songHalfLife.toDouble(),
    farResetSeconds: songFar.toDouble(),
    nearResetSeconds: songNear.toDouble(),
    evidenceTolerance: evidenceTol,
    evidenceFloor: evidenceFloor,
    evidenceDrain: evidenceDrain,
    bassShare: bassShare,
  );

  final engine = TonalEngine(
    passage: accumulator,
    passageStabilizer: stabilizer,
    scorer: KeyScorer(profiles: profiles, minorProfiles: minorProfiles),
    songConfig: songConfig,
  );

  final outPath = _getArg(args, '--out') ??
      '${sessionDir.path}${Platform.pathSeparator}timeline.csv';
  final outFile = File(outPath);
  final outSink = outFile.openWrite();

  outSink.writeln(
    't_audio_ms,t_wall_ms,displayed,passage,showPassage,best,second,rBest,'
    'rDisplayed,rSecond,confidence,nearby,challenge,challengeProgress,event,'
    'evidenceSeconds,songSeconds,passageSeconds,labelChanges,songMature,config',
  );

  final lines = await framesFile.readAsLines();
  if (lines.isEmpty) {
    stderr.writeln('Erro: frames.csv está vazio.');
    exit(1);
  }

  // Header line check
  final header = lines.first.split(',');
  int colTAudio = header.indexOf('t_audio_ms');
  int colTWall = header.indexOf('t_wall_ms');
  int colC0 = header.indexOf('c0');
  int colR0 = header.indexOf('r0');
  int colBassPc = header.indexOf('bass_pc');
  int colBassHz = header.indexOf('bass_hz');
  int colBassProbRaw = header.indexOf('bass_prob_raw');
  int colBassPitched = header.indexOf('bass_pitched');

  if (colTAudio < 0 || colC0 < 0) {
    colTAudio = 0;
    colTWall = 1;
    colC0 = 2;
    colR0 = 14;
    colBassPc = 28;
    colBassHz = 30;
    colBassProbRaw = 31;
    colBassPitched = 32;
  }

  int lastEvalAudioMs = -1;
  int evaluatedCount = 0;
  final generatedReadings = <int, String>{}; // t_audio_ms -> displayed

  final configOutputStr = configStr ??
      '$stabMode;w$windowSeconds;${useHarmonics ? "harm" : "legacy"};${profiles.code}${minorProfiles != null ? ";min-${minorProfiles.code}" : ""};bass$bassShare;bconf$bassConf';

  for (var i = 1; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;
    final parts = line.split(',');
    if (parts.length < 26) continue;

    final tAudioMs = int.tryParse(parts[colTAudio]) ?? 0;
    final tWallMs = int.tryParse(parts[colTWall]) ?? 0;

    // Chroma c0..c11 ou r0..r11
    final startCol = useHarmonics ? colC0 : colR0;
    List<double>? chroma;
    if (startCol >= 0 && parts.length >= startCol + 12 && parts[startCol].isNotEmpty) {
      chroma = List<double>.generate(12, (idx) => double.tryParse(parts[startCol + idx]) ?? 0.0);
    }

    // Baixo
    int effBassPc = -1;
    double effBassProb = 0.0;
    if (colBassPc >= 0 && colBassHz >= 0 && colBassProbRaw >= 0 && colBassPitched >= 0 && parts.length > colBassPitched) {
      final bPc = int.tryParse(parts[colBassPc]) ?? -1;
      final bHz = double.tryParse(parts[colBassHz]) ?? 0.0;
      final bProbRaw = double.tryParse(parts[colBassProbRaw]) ?? 0.0;
      final bPitched = (int.tryParse(parts[colBassPitched]) ?? 0) == 1;

      if (bPitched && bHz >= 35.0 && bHz <= 200.0 && bProbRaw >= bassConf) {
        effBassPc = bPc;
        effBassProb = bProbRaw;
      }
    }

    if (chroma != null) {
      engine.addFrame(
        chroma,
        Duration(milliseconds: tAudioMs),
        bassPc: effBassPc,
        bassProb: effBassProb,
      );
    }

    // Avaliação a cada ~500 ms de t_audio
    if (lastEvalAudioMs < 0 || (tAudioMs - lastEvalAudioMs) >= 500) {
      lastEvalAudioMs = tAudioMs;
      final reading = engine.evaluate(Duration(milliseconds: tAudioMs));
      if (reading != null) {
        evaluatedCount++;
        final displayedStr = reading.displayed?.label ?? '';
        generatedReadings[tAudioMs] = displayedStr;

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
        final matureInt = engine.isSongMature ? 1 : 0;

        outSink.writeln(
          '$tAudioMs,$tWallMs,$displayedStr,$passageStr,$showPassageInt,'
          '$bestStr,$secondStr,$rBestStr,$rDispStr,$rSecondStr,$confStr,'
          '"$nearbyStr",$challengeStr,${challengeProg.toStringAsFixed(2)},$eventStr,'
          '${reading.evidenceSeconds.toStringAsFixed(2)},'
          '${reading.songSeconds.toStringAsFixed(2)},'
          '${reading.secondsInWindow.toStringAsFixed(2)},'
          '${engine.labelChanges},$matureInt,"$configOutputStr"',
        );
      }
    }
  }

  await outSink.flush();
  await outSink.close();

  print('Replay concluído: $evaluatedCount avaliações salvas em $outPath');

  // Teste de fidelidade se readings.csv existir
  final readingsFile = File('${sessionDir.path}${Platform.pathSeparator}readings.csv');
  if (await readingsFile.exists()) {
    final rLines = await readingsFile.readAsLines();
    if (rLines.length > 1) {
      int matched = 0;
      int compared = 0;

      final rHeader = rLines.first.split(',');
      final rColTAudio = rHeader.indexOf('t_audio_ms');
      final rColDisp = rHeader.indexOf('displayed');

      for (var j = 1; j < rLines.length; j++) {
        final rParts = rLines[j].split(',');
        if (rParts.length <= rColDisp) continue;
        final tAud = int.tryParse(rParts[rColTAudio >= 0 ? rColTAudio : 0]) ?? 0;
        final appDisp = rParts[rColDisp >= 0 ? rColDisp : 2].trim();

        // Encontra a leitura de replay mais próxima em tempo (janela de 150ms)
        final closestKey = generatedReadings.keys.where((k) => (k - tAud).abs() <= 150).toList();
        if (closestKey.isNotEmpty) {
          closestKey.sort((a, b) => (a - tAud).abs().compareTo((b - tAud).abs()));
          final replayDisp = generatedReadings[closestKey.first] ?? '';
          compared++;
          if (replayDisp == appDisp) {
            matched++;
          }
        }
      }

      if (compared > 0) {
        final pct = (matched / compared) * 100.0;
        print('Teste de Fidelidade (comparação com readings.csv):');
        print('  Total comparado: $compared');
        print('  Acertos idênticos: $matched (${pct.toStringAsFixed(1)}%)');
        if (pct >= 95.0) {
          print('  Resultado: FIDELIDADE COMPROVADA ✔');
        } else {
          print('  Resultado: Alerta - divergência detectada na fidelidade');
        }
      }
    }
  }
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
