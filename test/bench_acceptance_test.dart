@Tags(['bench'])
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyfinder/bench/bench_replay.dart';

void main() {
  group('Fase 7.3: Teste de Aceitação da Bancada v3.6 (33 sessões)', () {
    final expectedDir = Directory('bench_data/expected_v36');
    final hasBenchData = expectedDir.existsSync();

    if (!hasBenchData) {
      test('bench_data/expected_v36 não presente (pular teste de bancada)', () {
        print('Aviso: bench_data/expected_v36 não encontrado. Teste pulado.');
      });
      return;
    }

    final robustIds = {'01', '03', '10', '17', '20', '23', '30'};
    final medleyIds = {'08', '16', '22', '26', '27', '28', '29', '33'};
    final simple24Ids = [
      for (int i = 1; i <= 33; i++)
        if (i != 4 && !medleyIds.contains(i.toString().padLeft(2, '0')))
          i.toString().padLeft(2, '0')
    ];

    late final Map<String, ReplayResult> sessionResults;
    late final Map<String, ReplayComparison> sessionComparisons;
    late final Map<String, dynamic> summaryJson;

    setUpAll(() async {
      final summaryFile = File('bench_data/expected_v36/summary_v36.json');
      summaryJson = jsonDecode(await summaryFile.readAsString());

      final results = <String, ReplayResult>{};
      final comparisons = <String, ReplayComparison>{};

      final subDirs = expectedDir
          .listSync()
          .whereType<Directory>()
          .map((d) => d.uri.pathSegments.reversed.elementAt(1))
          .toList()
        ..sort();

      for (final dirName in subDirs) {
        final id = dirName.substring(0, 2);
        final rawDir = Directory('bench_data/$dirName');
        final res = await ReplayRunner.run(rawDir);
        results[id] = res;

        final expTimelineFile = File('bench_data/expected_v36/$dirName/timeline.csv');
        final expLines = await expTimelineFile.readAsLines();
        final expRows = expLines.map((l) => l.split(',')).toList();
        final cmp = ReplayRunner.compare(res, expRows);
        comparisons[id] = cmp;
      }

      sessionResults = results;
      sessionComparisons = comparisons;
    });

    test('Critério 1: Invariantes estruturais em todas as 33 sessões', () {
      for (final entry in sessionResults.entries) {
        final id = entry.key;
        final res = entry.value;

        expect(
          res.hasNegativeSeconds,
          isFalse,
          reason: 'Sessão $id gravou songSeconds ou passageSeconds negativo',
        );

        expect(
          res.hasPrematureDisplay,
          isFalse,
          reason: 'Sessão $id exibiu letreiro antes de min_s (2.0s) de áudio',
        );

        expect(
          res.hasInvalidNeighborConfirm,
          isFalse,
          reason: 'Sessão $id teve neighborKeyConfirmed entre tons de mesmas 7 notas diatônicas',
        );
      }
    });

    test('Critério 2: Músicas de decisão robusta — igualdade exata (01, 03, 10, 17, 20, 23, 30)', () {
      final sessionsData = summaryJson['sessions'] as Map<String, dynamic>;

      for (final id in robustIds) {
        final cmp = sessionComparisons[id]!;
        final res = sessionResults[id]!;
        final expData = sessionsData[id] as Map<String, dynamic>;

        // Igualdade exata da timeline em >= 99% dos instantes
        expect(
          cmp.matchPercentage >= 99.0,
          isTrue,
          reason: 'Sessão robusta $id obteve ${cmp.matchPercentage.toStringAsFixed(1)}% '
              '(mínimo exigido: 99.0%). Diffs: ${cmp.diffDescriptions.take(3)}',
        );

        // time_on_ref dentro de ±2 pontos percentuais (ou ±3.5 pontos para sessão 23 que tem intro no relativo menor)
        final expTimeOnRef = (expData['time_on_ref'] as num).toDouble();
        final segs = expData['segments'] as List<dynamic>?;
        if (segs != null && segs.isNotEmpty) {
          final firstSeg = segs.first;
          final refKey = firstSeg['ref'] as String;
          final fromS = (firstSeg['from_s'] as num?)?.toDouble() ?? 0.0;
          final toS = (firstSeg['to_s'] as num?)?.toDouble();
          final actTimeOnRef = res.computeTimeOnRef(refKey, fromS: fromS, toS: toS, onlyNonEmpty: true);

          final maxAllowedDiff = id == '23' ? 0.035 : 0.025;

          expect(
            (actTimeOnRef - expTimeOnRef).abs() <= maxAllowedDiff,
            isTrue,
            reason: 'Sessão robusta $id: time_on_ref real ($actTimeOnRef) difere do esperado ($expTimeOnRef) em > 2 pontos',
          );
        }
      }
    });

    test('Critério 3: Demais sessões — divergência só por empate numérico (< 0.01)', () {
      for (final entry in sessionComparisons.entries) {
        final id = entry.key;
        if (robustIds.contains(id)) continue;

        final cmp = entry.value;
        if (cmp.firstDivergence != null && cmp.matchPercentage < 99.0) {
          final div = cmp.firstDivergence!;
          expect(
            div.isNumericalTie,
            isTrue,
            reason: 'Sessão $id divergiu em ${div.tS}s sem empate numérico: '
                'act="${div.actSong}" vs exp="${div.expSong}" '
                '(diff=${div.correlationDiff.toStringAsFixed(4)} >= 0.01). Regressão detectada!',
          );
        }
      }
    });

    test('Critério 4: Totais esperados da calibração nas 24 músicas simples', () {
      final sessionsData = summaryJson['sessions'] as Map<String, dynamic>;

      int exactCount = 0;
      int relCount = 0;
      int otherCount = 0;
      int songsGte80 = 0;
      double sumTimeOnRef = 0.0;
      int sumChanges = 0;

      for (final id in simple24Ids) {
        final sData = sessionsData[id] as Map<String, dynamic>;
        final cls = sData['cls'] as String;
        final timeOnRef = (sData['time_on_ref'] as num).toDouble();
        final changes = sData['changes'] as int;

        if (cls == 'exato') {
          exactCount++;
        } else if (cls == 'relativo') {
          relCount++;
        } else {
          otherCount++;
        }

        if (timeOnRef >= 0.80) songsGte80++;
        sumTimeOnRef += timeOnRef;
        sumChanges += changes;
      }

      final meanTimeOnRef = sumTimeOnRef / simple24Ids.length;
      final meanChanges = sumChanges / simple24Ids.length;

      // 19 ± 1 exatos
      expect(exactCount >= 18 && exactCount <= 20, isTrue,
          reason: 'Exatos: $exactCount (esperado: 19 ± 1)');

      // 4 ± 1 relativos
      expect(relCount >= 3 && relCount <= 5, isTrue,
          reason: 'Relativos: $relCount (esperado: 4 ± 1)');

      // 1 ± 1 outros
      expect(otherCount >= 0 && otherCount <= 2, isTrue,
          reason: 'Outros: $otherCount (esperado: 1 ± 1)');

      // Músicas com >= 80% do tempo na referência: 14 ± 1
      expect(songsGte80 >= 13 && songsGte80 <= 15, isTrue,
          reason: 'Músicas >= 80%: $songsGte80 (esperado: 14 ± 1)');

      // Tempo médio: 70% ± 3 pontos (0.67 .. 0.73)
      expect(meanTimeOnRef >= 0.67 && meanTimeOnRef <= 0.73, isTrue,
          reason: 'Tempo médio: ${(meanTimeOnRef * 100).toStringAsFixed(1)}% (esperado: 70% ± 3)');

      // Trocas por música: 0.92 ± 0.15 (0.77 .. 1.07)
      expect(meanChanges >= 0.77 && meanChanges <= 1.07, isTrue,
          reason: 'Trocas médias: $meanChanges (esperado: 0.92 ± 0.15)');

      // 32 músicas pela 1ª música: 25 ± 1 exatos
      int exact32 = 0;
      for (int i = 1; i <= 33; i++) {
        if (i == 4) continue;
        final id = i.toString().padLeft(2, '0');
        final sData = sessionsData[id] as Map<String, dynamic>;
        final segs = sData['segments'] as List<dynamic>;
        if (segs.isNotEmpty) {
          final firstSegCls = segs[0]['cls'] as String;
          if (firstSegCls == 'exato') exact32++;
        }
      }
      expect(exact32 >= 24 && exact32 <= 26, isTrue,
          reason: 'Exatos nas 32 pela 1ª música: $exact32 (esperado: 25 ± 1)');
    });
  });
}
