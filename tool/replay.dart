// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:keyfinder/bench/bench_replay.dart';

void main(List<String> args) async {
  if (args.isEmpty || args.contains('-h') || args.contains('--help')) {
    print('Uso: dart run tool/replay.dart <pasta da sessão> [opções]');
    print('');
    print('Opções:');
    print('  --config <string>        Configuração completa (ex: "v3;w20;harm;aar;min-aar_b7;song60;far20;...")');
    print('  --profiles <name>        Perfis maiores (aarden, temperley, krumhansl, temperleyKP)');
    print('  --minor-profiles <name>  Perfis menores (aar_b7, aarden, temperley, krumhansl, same)');
    print('  --song-far-s <int>       Tempo de reset para tom distante (padrão: 20)');
    print('  --bass-share <double>    Fração do baixo no perfil (padrão: 0.0)');
    print('  --harmonics <on|legacy>  Usar harmônicos c0..c11 (on) ou legado r0..r11 (legacy)');
    print('  --out <arquivo>          Arquivo CSV de saída (padrão: <pasta>/timeline.csv)');
    print('  --detailed               Grava colunas detalhadas na timeline (rBest, rSecond, etc.)');
    print('  --check-fidelity         Compara timeline gerada com readings.csv existente');
    print('  --check-expected <path>  Compara timeline com arquivo timeline.csv de referência');
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

  final config = ReplayConfig.fromArgs(args);
  final detailed = args.contains('--detailed');
  final outPath = _getArg(args, '--out') ??
      '${sessionDir.path}${Platform.pathSeparator}timeline.csv';

  print('Executando replay para: ${sessionDir.path}');
  print('Configuração: ${config.configString}');

  final result = await ReplayRunner.run(sessionDir, config: config);

  // Escreve timeline.csv
  final outFile = File(outPath);
  final sink = outFile.openWrite();
  if (detailed) {
    sink.writeln('t_s,passage,song,evidence_s,event,r_best,r_second,r_displayed,best,second');
  } else {
    sink.writeln('t_s,passage,song,evidence_s,event');
  }
  for (final row in result.rows) {
    sink.writeln(row.toCsvLine(detailed: detailed));
  }
  await sink.flush();
  await sink.close();

  print('Timeline salva em: $outPath (${result.rows.length} avaliações)');

  // Resumo
  print('');
  print('=== Resumo da Sessão ===');
  print('  Letreiro final: ${result.finalLabel.isEmpty ? "N/A" : result.finalLabel}');
  print('  Trocas de letreiro: ${result.labelChanges}');
  print('  Eventos de memória: ${result.events.length}');
  for (final ev in result.events) {
    print('    - $ev');
  }

  // Segmentos e time_on_ref se session.json ou expected.json existir
  final sessionJsonFile = File('${sessionDir.path}${Platform.pathSeparator}session.json');
  final expectedJsonFile = File('${sessionDir.path}${Platform.pathSeparator}expected.json');

  if (await sessionJsonFile.exists()) {
    try {
      final json = jsonDecode(await sessionJsonFile.readAsString());
      final ref = json['reference'] as Map<String, dynamic>?;
      if (ref != null) {
        final segments = ref['segments'] as List<dynamic>?;
        if (segments != null && segments.isNotEmpty) {
          print('  Tempo na referência por segmento (session.json):');
          for (final seg in segments) {
            final key = seg['key'] ?? '';
            final mode = seg['mode'] ?? 'major';
            final short = '$key${mode == "minor" || mode == "Menor" ? "m" : ""}';
            final fromS = (seg['from_seconds'] as num?)?.toDouble() ?? 0.0;
            final toS = (seg['to_seconds'] as num?)?.toDouble();
            final timePct = result.computeTimeOnRef(short, fromS: fromS, toS: toS) * 100.0;
            print('    - $short [${fromS.toStringAsFixed(1)}s .. ${toS?.toStringAsFixed(1) ?? "fim"}s]: ${timePct.toStringAsFixed(1)}%');
          }
        }
      }
    } catch (_) {}
  } else if (await expectedJsonFile.exists()) {
    try {
      final json = jsonDecode(await expectedJsonFile.readAsString());
      final segments = json['segments'] as List<dynamic>?;
      if (segments != null && segments.isNotEmpty) {
        print('  Tempo na referência por segmento (expected.json):');
        for (final seg in segments) {
          final refKey = seg['ref'] ?? '';
          final fromS = (seg['from_s'] as num?)?.toDouble() ?? 0.0;
          final toS = (seg['to_s'] as num?)?.toDouble();
          final timePct = result.computeTimeOnRef(refKey, fromS: fromS, toS: toS) * 100.0;
          print('    - $refKey [${fromS.toStringAsFixed(1)}s .. ${toS?.toStringAsFixed(1) ?? "fim"}s]: ${timePct.toStringAsFixed(1)}%');
        }
      }
    } catch (_) {}
  }

  // Verificação contra timeline de referência
  final checkExpectedPath = _getArg(args, '--check-expected');
  if (checkExpectedPath != null) {
    final expFile = File(checkExpectedPath);
    if (await expFile.exists()) {
      final expLines = await expFile.readAsLines();
      final expRows = expLines.map((l) => l.split(',')).toList();
      final cmp = ReplayRunner.compare(result, expRows);
      print('');
      print('=== Comparação com Esperado ($checkExpectedPath) ===');
      print('  Total comparado: ${cmp.totalCompared}');
      print('  Acertos exatos: ${cmp.matches} (${cmp.matchPercentage.toStringAsFixed(1)}%)');
      if (cmp.firstDivergence != null) {
        print('  Primeira divergência: ${cmp.firstDivergence}');
      }
    }
  }

  // Verificação de fidelidade contra readings.csv se solicitado
  if (args.contains('--check-fidelity')) {
    final readingsFile = File('${sessionDir.path}${Platform.pathSeparator}readings.csv');
    if (await readingsFile.exists()) {
      final rLines = await readingsFile.readAsLines();
      if (rLines.length > 1) {
        int matched = 0;
        int compared = 0;

        final rHeader = rLines.first.split(',');
        final rColTAudio = rHeader.indexOf('t_audio_ms');
        final rColDisp = rHeader.indexOf('displayed');

        final replayMap = {
          for (final row in result.rows)
            (row.tS * 1000).round(): row.song
        };

        for (var j = 1; j < rLines.length; j++) {
          final rParts = rLines[j].split(',');
          if (rParts.length <= rColDisp) continue;
          final tAud = int.tryParse(rParts[rColTAudio >= 0 ? rColTAudio : 0]) ?? 0;
          final appDisp = rParts[rColDisp >= 0 ? rColDisp : 2].trim();

          final closestKey = replayMap.keys.where((k) => (k - tAud).abs() <= 250).toList();
          if (closestKey.isNotEmpty) {
            closestKey.sort((a, b) => (a - tAud).abs().compareTo((b - tAud).abs()));
            final replayDisp = replayMap[closestKey.first] ?? '';
            compared++;
            if (replayDisp == appDisp || (replayDisp.isEmpty && appDisp.isEmpty)) {
              matched++;
            }
          }
        }

        if (compared > 0) {
          final pct = (matched / compared) * 100.0;
          print('');
          print('=== Teste de Fidelidade (comparação com readings.csv) ===');
          print('  Total comparado: $compared');
          print('  Acertos: $matched (${pct.toStringAsFixed(1)}%)');
        }
      }
    }
  }
}

String? _getArg(List<String> args, String name) {
  for (var i = 0; i < args.length; i++) {
    if (args[i] == name && i + 1 < args.length) return args[i + 1];
    if (args[i].startsWith('$name=')) return args[i].substring(name.length + 1);
  }
  return null;
}
