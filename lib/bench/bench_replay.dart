import 'dart:io';
import 'package:keyfinder/core/tonal_engine.dart';

/// Configuração do Replay alinhada aos padrões calibrados da v3.6.
class ReplayConfig {
  final ProfileSet profiles;
  final ProfileSet minorProfiles;
  final double windowSeconds;
  final double halfLifeSeconds;
  final double silenceResetSeconds;
  final double songHalfLifeSeconds;
  final double songFarResetSeconds;
  final double songNearResetSeconds;
  final double evidenceTolerance;
  final double evidenceFloor;
  final double evidenceDrain;
  final bool strictNotes;
  final double bassShare;
  final double bassConfidence;
  final bool useHarmonics;
  final double evalDtSeconds;
  final String stabMode;

  const ReplayConfig({
    this.profiles = ProfileSet.aarden,
    this.minorProfiles = ProfileSet.aardenB7,
    this.windowSeconds = 20.0,
    this.halfLifeSeconds = 10.0,
    this.silenceResetSeconds = 4.0,
    this.songHalfLifeSeconds = 60.0,
    this.songFarResetSeconds = 20.0,
    this.songNearResetSeconds = 45.0,
    this.evidenceTolerance = 0.8,
    this.evidenceFloor = 0.25,
    this.evidenceDrain = 0.5,
    this.strictNotes = false,
    this.bassShare = 0.0,
    this.bassConfidence = 0.85,
    this.useHarmonics = true,
    this.evalDtSeconds = 0.5,
    this.stabMode = 'v3',
  });

  String get configString =>
      '$stabMode;w${windowSeconds.toInt()};'
      '${useHarmonics ? "harm" : "legacy"};'
      '${profiles.code};min-${minorProfiles.code};'
      'song${songHalfLifeSeconds.toInt()};'
      'far${songFarResetSeconds.toInt()};'
      'near${songNearResetSeconds.toInt()};'
      'tol$evidenceTolerance;floor$evidenceFloor;drain$evidenceDrain;'
      'strict${strictNotes ? 1 : 0};bass${bassShare.toStringAsFixed(bassShare == 0 ? 0 : 2)}';

  static ReplayConfig fromArgs(List<String> args) {
    String? configStr;
    String harmonics = 'on';
    double bassShare = 0.0;
    double bassConf = 0.85;
    String profileName = 'aar';
    String minorProfileName = 'aar_b7';
    int windowSeconds = 20;
    int songHalfLife = 60;
    int songFar = 20;
    int songNear = 45;
    double evidenceTol = 0.8;
    double evidenceFloor = 0.25;
    double evidenceDrain = 0.5;
    bool strictNotes = false;
    String stabMode = 'v3';

    for (var i = 0; i < args.length; i++) {
      if (args[i] == '--config' && i + 1 < args.length) configStr = args[i + 1];
      if (args[i] == '--harmonics' && i + 1 < args.length) harmonics = args[i + 1];
      if (args[i] == '--bass-share' && i + 1 < args.length) bassShare = double.tryParse(args[i + 1]) ?? bassShare;
      if (args[i] == '--bass-conf' && i + 1 < args.length) bassConf = double.tryParse(args[i + 1]) ?? bassConf;
      if (args[i] == '--profiles' && i + 1 < args.length) profileName = args[i + 1];
      if (args[i] == '--minor-profiles' && i + 1 < args.length) minorProfileName = args[i + 1];
      if (args[i] == '--window-s' && i + 1 < args.length) windowSeconds = int.tryParse(args[i + 1]) ?? windowSeconds;
      if (args[i] == '--song-halflife-s' && i + 1 < args.length) songHalfLife = int.tryParse(args[i + 1]) ?? songHalfLife;
      if (args[i] == '--song-far-s' && i + 1 < args.length) songFar = int.tryParse(args[i + 1]) ?? songFar;
    }

    if (configStr != null && configStr.isNotEmpty) {
      final parts = configStr.split(';');
      for (final p in parts) {
        if (p == 'v1' || p == 'v2' || p == 'v3') stabMode = p;
        if (p.startsWith('w')) windowSeconds = int.tryParse(p.substring(1)) ?? windowSeconds;
        if (p == 'harm') harmonics = 'on';
        if (p == 'noharm' || p == 'legacy') harmonics = 'legacy';
        if (p == 'tmp' || p == 'temperley') profileName = 'temperley';
        if (p == 'tkp' || p == 'temperleykp') profileName = 'temperleyKP';
        if (p == 'aar' || p == 'aarden') profileName = 'aarden';
        if (p == 'kk' || p == 'krumhansl') profileName = 'krumhansl';
        if (p.startsWith('min-')) minorProfileName = p.substring(4);
        if (p.startsWith('song')) songHalfLife = int.tryParse(p.substring(4)) ?? songHalfLife;
        if (p.startsWith('far')) songFar = int.tryParse(p.substring(3)) ?? songFar;
        if (p.startsWith('near')) songNear = int.tryParse(p.substring(4)) ?? songNear;
        if (p.startsWith('tol')) evidenceTol = double.tryParse(p.substring(3)) ?? evidenceTol;
        if (p.startsWith('floor')) evidenceFloor = double.tryParse(p.substring(5)) ?? evidenceFloor;
        if (p.startsWith('drain')) evidenceDrain = double.tryParse(p.substring(5)) ?? evidenceDrain;
        if (p == 'strict' || p == 'strict1') strictNotes = true;
        if (p == 'strict0') strictNotes = false;
        if (p.startsWith('bass')) bassShare = double.tryParse(p.substring(4)) ?? bassShare;
        if (p.startsWith('bconf')) bassConf = double.tryParse(p.substring(5)) ?? bassConf;
      }
    }

    final pMaj = _parseProfile(profileName);
    final pMin = _parseMinorProfile(minorProfileName, pMaj);

    return ReplayConfig(
      profiles: pMaj,
      minorProfiles: pMin,
      windowSeconds: windowSeconds.toDouble(),
      halfLifeSeconds: windowSeconds / 2.0,
      songHalfLifeSeconds: songHalfLife.toDouble(),
      songFarResetSeconds: songFar.toDouble(),
      songNearResetSeconds: songNear.toDouble(),
      evidenceTolerance: evidenceTol,
      evidenceFloor: evidenceFloor,
      evidenceDrain: evidenceDrain,
      strictNotes: strictNotes,
      bassShare: bassShare,
      bassConfidence: bassConf,
      useHarmonics: harmonics != 'legacy' && harmonics != 'off',
      stabMode: stabMode,
    );
  }

  static ProfileSet _parseProfile(String name) {
    final lower = name.toLowerCase();
    if (lower.startsWith('temp') && lower.contains('kp')) return ProfileSet.temperleyKP;
    if (lower.startsWith('tkp')) return ProfileSet.temperleyKP;
    if (lower.startsWith('temp') || lower.startsWith('tmp')) return ProfileSet.temperley;
    if (lower.startsWith('aar')) return ProfileSet.aarden;
    if (lower.startsWith('krum') || lower == 'kk') return ProfileSet.krumhansl;
    return ProfileSet.aarden;
  }

  static ProfileSet _parseMinorProfile(String name, ProfileSet majorDefault) {
    final lower = name.toLowerCase();
    if (lower == 'same' || lower == 'igual') return majorDefault;
    if (lower.startsWith('aar') && (lower.contains('b7') || lower.contains('7'))) {
      return ProfileSet.aardenB7;
    }
    if (lower.startsWith('temp') && lower.contains('kp')) return ProfileSet.temperleyKP;
    if (lower.startsWith('tkp')) return ProfileSet.temperleyKP;
    if (lower.startsWith('temp') || lower.startsWith('tmp')) return ProfileSet.temperley;
    if (lower.startsWith('aar')) return ProfileSet.aarden;
    if (lower.startsWith('krum') || lower == 'kk') return ProfileSet.krumhansl;
    return ProfileSet.aardenB7;
  }
}

/// Registro de um instante do replay (passo de 0,5s).
class ReplayRow {
  final double tS;
  final String passage;
  final String song;
  final double evidenceS;
  final String event;

  // Informações detalhadas
  final KeyCandidate? best;
  final KeyCandidate? second;
  final double rBest;
  final double rSecond;
  final double rDisplayed;
  final double songSeconds;
  final double passageSeconds;
  final Map<String, double> songCandidateScores;

  const ReplayRow({
    required this.tS,
    required this.passage,
    required this.song,
    required this.evidenceS,
    required this.event,
    this.best,
    this.second,
    this.rBest = 0.0,
    this.rSecond = 0.0,
    this.rDisplayed = 0.0,
    this.songSeconds = 0.0,
    this.passageSeconds = 0.0,
    this.songCandidateScores = const {},
  });

  String toCsvLine({bool detailed = false}) {
    final tStr = tS.toStringAsFixed(1);
    final evStr = evidenceS.toStringAsFixed(1);
    if (!detailed) {
      return '$tStr,$passage,$song,$evStr,$event';
    }
    final bStr = best?.sharpShortLabel ?? '';
    final sStr = second?.sharpShortLabel ?? '';
    final rbStr = rBest.toStringAsFixed(4);
    final rsStr = rSecond.toStringAsFixed(4);
    final rdStr = rDisplayed.toStringAsFixed(4);
    return '$tStr,$passage,$song,$evStr,$event,$rbStr,$rsStr,$rdStr,$bStr,$sStr';
  }
}

/// Resultado completo da execução do replay em uma sessão.
class ReplayResult {
  final String sessionPath;
  final List<ReplayRow> rows;
  final List<String> events;
  final String finalLabel;
  final int labelChanges;
  final bool hasNegativeSeconds;
  final bool hasPrematureDisplay;
  final bool hasInvalidNeighborConfirm;
  final double endOfMusicS;

  const ReplayResult({
    required this.sessionPath,
    required this.rows,
    required this.events,
    required this.finalLabel,
    required this.labelChanges,
    required this.hasNegativeSeconds,
    required this.hasPrematureDisplay,
    required this.hasInvalidNeighborConfirm,
    this.endOfMusicS = 0.0,
  });

  /// Calcula a fração do tempo em que o letreiro exibido coincidiu com a referência do trecho.
  /// Por padrão, avalia dos 10 s até o fim da música (excluindo cauda de silêncio final).
  double computeTimeOnRef(
    String refKey, {
    double fromS = 10.0,
    double? toS,
    bool onlyNonEmpty = false,
  }) {
    final effectiveToS = toS ?? (endOfMusicS > 0.0 ? endOfMusicS : null);
    int totalCount = 0;
    int matchCount = 0;
    for (final row in rows) {
      if (row.tS < fromS) continue;
      if (effectiveToS != null && row.tS > effectiveToS + 0.05) break;
      if (onlyNonEmpty && row.song.isEmpty) continue;
      totalCount++;
      if (row.song == refKey) {
        matchCount++;
      }
    }
    return totalCount > 0 ? matchCount / totalCount : 0.0;
  }
}

/// Divergência no primeiro instante detectado.
class DivergencePoint {
  final double tS;
  final String actSong;
  final String expSong;
  final double actCorrelation;
  final double expCorrelation;
  final double correlationDiff;
  final bool isNumericalTie; // diff < 0.01
  final String? timeShiftedEvent;
  final bool isAdmitted;

  const DivergencePoint({
    required this.tS,
    required this.actSong,
    required this.expSong,
    required this.actCorrelation,
    required this.expCorrelation,
    required this.correlationDiff,
    required this.isNumericalTie,
    this.timeShiftedEvent,
    required this.isAdmitted,
  });

  @override
  String toString() {
    final s = 't=${tS.toStringAsFixed(1)}s: atual="$actSong" (r=${actCorrelation.toStringAsFixed(4)}) vs '
        'esperado="$expSong" (r=${expCorrelation.toStringAsFixed(4)}), '
        'diff correlações = ${correlationDiff.toStringAsFixed(4)}';
    if (timeShiftedEvent != null) {
      return '$s ($timeShiftedEvent)';
    }
    return '$s (empate numérico: $isNumericalTie)';
  }
}

/// Comparação instante a instante com uma timeline esperada.
class ReplayComparison {
  final int totalCompared;
  final int matches;
  final double matchPercentage;
  final DivergencePoint? firstDivergence;
  final List<String> diffDescriptions;

  const ReplayComparison({
    required this.totalCompared,
    required this.matches,
    required this.matchPercentage,
    this.firstDivergence,
    required this.diffDescriptions,
  });
}

/// Executor do replay alimentando o TonalEngine puro Dart.
class ReplayRunner {
  static Future<ReplayResult> run(
    Directory sessionDir, {
    ReplayConfig config = const ReplayConfig(),
  }) async {
    final framesFile = File('${sessionDir.path}${Platform.pathSeparator}frames.csv');
    if (!await framesFile.exists()) {
      throw FileSystemException('frames.csv não encontrado', framesFile.path);
    }

    final lines = await framesFile.readAsLines();
    if (lines.length < 2) {
      return ReplayResult(
        sessionPath: sessionDir.path,
        rows: [],
        events: [],
        finalLabel: '',
        labelChanges: 0,
        hasNegativeSeconds: false,
        hasPrematureDisplay: false,
        hasInvalidNeighborConfirm: false,
      );
    }

    final header = lines.first.split(',');
    int colTAudio = header.indexOf('t_audio_ms');
    int colC0 = header.indexOf('c0');
    int colR0 = header.indexOf('r0');
    int colBassPc = header.indexOf('bass_pc');
    int colBassHz = header.indexOf('bass_hz');
    int colBassProbRaw = header.indexOf('bass_prob_raw');
    int colBassPitched = header.indexOf('bass_pitched');

    if (colTAudio < 0) colTAudio = 0;
    if (colC0 < 0) colC0 = 2;
    if (colR0 < 0) colR0 = 14;

    final startChromaCol = config.useHarmonics ? colC0 : colR0;

    final accumulator = ChromaAccumulator(
      windowSeconds: config.windowSeconds,
      halfLifeSeconds: config.halfLifeSeconds,
      silenceResetSeconds: config.silenceResetSeconds,
    );

    final stabilizer = KeyStabilizer(
      minSeconds: 2.0,
      baseMargin: 0.05,
      baseHoldSeconds: 4.0,
      neighborMargin: 0.08,
      neighborHoldSeconds: 6.0,
      requireNewNotes: config.strictNotes,
      evidenceTolerance: config.evidenceTolerance,
      evidenceFloor: config.evidenceFloor,
    );

    final songConfig = SongMemoryConfig(
      enabled: true,
      halfLifeSeconds: config.songHalfLifeSeconds,
      farResetSeconds: config.songFarResetSeconds,
      nearResetSeconds: config.songNearResetSeconds,
      evidenceTolerance: config.evidenceTolerance,
      evidenceFloor: config.evidenceFloor,
      evidenceDrain: config.evidenceDrain,
      bassShare: config.bassShare,
    );

    final engine = TonalEngine(
      passage: accumulator,
      passageStabilizer: stabilizer,
      scorer: KeyScorer(profiles: config.profiles, minorProfiles: config.minorProfiles),
      songConfig: songConfig,
    );

    // Mapeia lacunas de silêncio
    final songSilenceGaps = <(int, int)>[];
    final passageSilenceGaps = <(int, int)>[];
    for (var i = 1; i < lines.length - 1; i++) {
      final p1 = lines[i].split(',');
      final p2 = lines[i + 1].split(',');
      final t1 = int.parse(p1[colTAudio]);
      final t2 = int.parse(p2[colTAudio]);
      if (t2 - t1 > 6000) songSilenceGaps.add((t1, t2));
      if (t2 - t1 > 4000) passageSilenceGaps.add((t1, t2));
    }

    bool inSilence(int ms, bool isMature) {
      final gaps = isMature ? songSilenceGaps : passageSilenceGaps;
      for (final (t1, t2) in gaps) {
        if (ms > t1 && ms < t2) return true;
      }
      return false;
    }

    final firstLineParts = lines[1].split(',');
    final firstAudioMs = int.parse(firstLineParts[colTAudio]);
    final lastLineParts = lines.last.split(',');
    final lastAudioMs = int.parse(lastLineParts[colTAudio]);

    final totalDurationS = lastAudioMs / 1000.0;
    final cutoff80S = totalDurationS * 0.8;
    double endOfMusicS = totalDurationS;

    for (var i = 1; i < lines.length - 1; i++) {
      final p1 = lines[i].split(',');
      final p2 = lines[i + 1].split(',');
      final t1 = int.parse(p1[colTAudio]) / 1000.0;
      final t2 = int.parse(p2[colTAudio]) / 1000.0;
      if (t2 - t1 >= 5.0 && t1 >= cutoff80S) {
        endOfMusicS = t1;
        break;
      }
    }

    double t0 = (firstAudioMs / 100.0).round() / 10.0;
    int frameIdx = 1;
    final rows = <ReplayRow>[];
    final events = <String>[];
    bool hasNegativeSeconds = false;
    bool hasPrematureDisplay = false;
    bool hasInvalidNeighborConfirm = false;
    String lastNonEmptyDisplayed = '';
    KeyCandidate? prevDisplayed;

    for (double t = t0; t * 1000.0 <= lastAudioMs + 100; t = double.parse((t + config.evalDtSeconds).toStringAsFixed(1))) {
      while (frameIdx < lines.length) {
        final parts = lines[frameIdx].split(',');
        final tAudioMs = int.parse(parts[colTAudio]);
        final frameS = double.parse((tAudioMs / 1000.0).toStringAsFixed(1));
        if (frameS > t) break;

        if (startChromaCol >= 0 && parts.length >= startChromaCol + 12 && parts[startChromaCol].isNotEmpty) {
          final chroma = List<double>.generate(12, (idx) => double.tryParse(parts[startChromaCol + idx]) ?? 0.0);

          int effBassPc = -1;
          double effBassProb = 0.0;
          if (config.bassShare > 0.0 && colBassPc >= 0 && parts.length > colBassPitched) {
            final bPc = int.tryParse(parts[colBassPc]) ?? -1;
            final bHz = double.tryParse(parts[colBassHz]) ?? 0.0;
            final bProbRaw = double.tryParse(parts[colBassProbRaw]) ?? 0.0;
            final bPitched = (int.tryParse(parts[colBassPitched]) ?? 0) == 1;
            if (bPitched && bHz >= 35.0 && bHz <= 200.0 && bProbRaw >= config.bassConfidence) {
              effBassPc = bPc;
              effBassProb = bProbRaw;
            }
          }

          engine.addFrame(
            chroma,
            Duration(milliseconds: tAudioMs),
            bassPc: effBassPc,
            bassProb: effBassProb,
          );
        }
        frameIdx++;
      }

      final targetMs = (t * 1000.0).round();
      final isSilent = inSilence(targetMs, engine.isSongMature);
      final reading = isSilent ? null : engine.evaluate(Duration(milliseconds: targetMs));

      final passageLabel = reading?.passage?.sharpShortLabel ?? '';
      final songLabel = reading?.displayed?.sharpShortLabel ?? '';
      final evS = reading?.evidenceSeconds ?? 0.0;
      final eventStr = reading?.event == null || reading!.event == MemoryEvent.none ? '' : reading.event.name;

      if (reading != null) {
        if (reading.songSeconds < -0.001 || reading.secondsInWindow < -0.001) {
          hasNegativeSeconds = true;
        }
        if (reading.displayed != null && reading.secondsInWindow < 1.99) {
          hasPrematureDisplay = true;
        }
        if (reading.displayed != null) {
          lastNonEmptyDisplayed = reading.displayed!.sharpShortLabel;
        }
        if (reading.event != MemoryEvent.none) {
          events.add('${t.toStringAsFixed(1)}s: ${reading.event.name}');
          if (reading.event == MemoryEvent.neighborKeyConfirmed && prevDisplayed != null && reading.passage != null) {
            final curDiatonic = naturalScaleOf(prevDisplayed);
            final candDiatonic = naturalScaleOf(reading.passage!);
            if (curDiatonic.containsAll(candDiatonic) && candDiatonic.containsAll(curDiatonic)) {
              hasInvalidNeighborConfirm = true;
            }
          }
        }
        prevDisplayed = reading.displayed;
      }

      final rDisp = reading?.displayed != null
          ? (reading!.displayed!.sameKey(reading.best)
              ? reading.best.r
              : (reading.displayed!.sameKey(reading.second)
                  ? reading.second.r
                  : reading.confidence))
          : 0.0;

      Map<String, double> songCandidateScores = const {};
      if (engine.song.lastAt != null) {
        final songProf = engine.song.profile(Duration(milliseconds: targetMs));
        if (songProf != null) {
          final scs = engine.scorer.score(songProf);
          songCandidateScores = {for (final s in scs) s.sharpShortLabel: s.r};
        }
      }

      rows.add(ReplayRow(
        tS: t,
        passage: passageLabel,
        song: songLabel,
        evidenceS: evS,
        event: eventStr,
        best: reading?.best,
        second: reading?.second,
        rBest: reading?.best.r ?? 0.0,
        rSecond: reading?.second.r ?? 0.0,
        rDisplayed: rDisp,
        songSeconds: reading?.songSeconds ?? 0.0,
        passageSeconds: reading?.secondsInWindow ?? 0.0,
        songCandidateScores: songCandidateScores,
      ));
    }

    return ReplayResult(
      sessionPath: sessionDir.path,
      rows: rows,
      events: events,
      finalLabel: lastNonEmptyDisplayed,
      labelChanges: engine.labelChanges,
      hasNegativeSeconds: hasNegativeSeconds,
      hasPrematureDisplay: hasPrematureDisplay,
      hasInvalidNeighborConfirm: hasInvalidNeighborConfirm,
      endOfMusicS: endOfMusicS,
    );
  }

  /// Compara o resultado do replay com a timeline esperada.
  static ReplayComparison compare(ReplayResult actual, List<List<String>> expectedRows) {
    final expectedMap = <double, List<String>>{};
    for (var i = 1; i < expectedRows.length; i++) {
      final r = expectedRows[i];
      if (r.isEmpty) continue;
      final t = double.tryParse(r[0]);
      if (t != null) {
        expectedMap[double.parse(t.toStringAsFixed(1))] = r;
      }
    }

    int totalCompared = 0;
    int matches = 0;
    DivergencePoint? firstDivergence;
    final diffs = <String>[];

    for (final act in actual.rows) {
      final tKey = double.parse(act.tS.toStringAsFixed(1));
      if (!expectedMap.containsKey(tKey)) continue;

      totalCompared++;
      final exp = expectedMap[tKey]!;
      final expSong = exp.length > 2 ? exp[2] : '';

      if (act.song == expSong) {
        matches++;
      } else {
        // Calcula correlação na memória da música dos dois letreiros em disputa
        final rAct = act.songCandidateScores[act.song] ?? 0.0;
        final rExp = act.songCandidateScores[expSong] ?? 0.0;
        final diff = (rAct - rExp).abs();
        final isTie = diff < 0.01;

        // Checa se a divergência coincide com farKeyConfirmed/neighborKeyConfirmed deslocado no tempo
        String? shiftedEvent;
        for (final row in actual.rows) {
          if ((row.tS - act.tS).abs() <= 10.0) {
            if (row.event == 'farKeyConfirmed' || row.event == 'neighborKeyConfirmed') {
              if (row.song == expSong || row.passage == expSong) {
                final delta = (row.tS - act.tS).abs();
                shiftedEvent = 'evento deslocado: ${row.event} para ${row.song} em t=${row.tS.toStringAsFixed(1)}s no Dart '
                    'vs transição para $expSong em t=${act.tS.toStringAsFixed(1)}s no esperado (deslocamento: ${delta.toStringAsFixed(1)}s)';
                break;
              }
            }
          }
        }
        if (shiftedEvent == null) {
          for (var i = 1; i < expectedRows.length; i++) {
            final r = expectedRows[i];
            if (r.length < 5) continue;
            final t = double.tryParse(r[0]) ?? 0.0;
            final ev = r[4].trim();
            final song = r.length > 2 ? r[2].trim() : '';
            if ((t - act.tS).abs() <= 10.0 && (ev == 'farKeyConfirmed' || ev == 'neighborKeyConfirmed')) {
              if (song == act.song || song == expSong) {
                final delta = (t - act.tS).abs();
                shiftedEvent = 'evento deslocado: $ev para $song em t=${t.toStringAsFixed(1)}s no esperado '
                    'vs transição em t=${act.tS.toStringAsFixed(1)}s no Dart (deslocamento: ${delta.toStringAsFixed(1)}s)';
                break;
              }
            }
          }
        }

        final isAdmitted = isTie || shiftedEvent != null;

        firstDivergence ??= DivergencePoint(
          tS: act.tS,
          actSong: act.song,
          expSong: expSong,
          actCorrelation: rAct,
          expCorrelation: rExp,
          correlationDiff: diff,
          isNumericalTie: isTie,
          timeShiftedEvent: shiftedEvent,
          isAdmitted: isAdmitted,
        );
        diffs.add('t=${act.tS.toStringAsFixed(1)}: act="${act.song}" (r=${rAct.toStringAsFixed(4)}) vs exp="$expSong" (r=${rExp.toStringAsFixed(4)}) (diff=${diff.toStringAsFixed(4)})');
      }
    }

    final pct = totalCompared > 0 ? (matches / totalCompared) * 100.0 : 100.0;
    return ReplayComparison(
      totalCompared: totalCompared,
      matches: matches,
      matchPercentage: pct,
      firstDivergence: firstDivergence,
      diffDescriptions: diffs,
    );
  }
}
