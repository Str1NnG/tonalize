import 'package:flutter_test/flutter_test.dart';
import 'package:keyfinder/core/key_profiles.dart';
import 'package:keyfinder/core/tonal_engine.dart';

void feedFrames(
  TonalEngine engine,
  List<double> baseProfile,
  int tonic, {
  required double seconds,
  Duration startAt = Duration.zero,
  int stepMs = 100,
}) {
  final rot = rotated(baseProfile, tonic);
  final sum = rot.reduce((a, b) => a + b);
  final normalized = rot.map((v) => v / sum).toList();

  final totalSteps = (seconds * 1000 / stepMs).round();
  for (var i = 0; i <= totalSteps; i++) {
    final frameAt = startAt + Duration(milliseconds: i * stepMs);
    engine.addFrame(normalized, frameAt);
  }
}

void main() {
  group('Pearson correlation and Profiles', () {
    test('pearson com si mesmo é aproximadamente 1.0', () {
      final r = pearson(kkMajor, kkMajor);
      expect((r - 1.0).abs(), lessThan(1e-6));
    });

    test('vetor constante retorna correlação 0.0', () {
      final constant = List<double>.filled(12, 5.0);
      expect(pearson(constant, kkMajor), equals(0.0));
      expect(pearson(kkMajor, constant), equals(0.0));
    });

    test('vetor com todos zeros retorna 0.0', () {
      final zeros = List<double>.filled(12, 0.0);
      expect(pearson(zeros, kkMajor), equals(0.0));
    });
  });

  group('TonalEngine detection', () {
    test('Dó maior: 3s de kkMajor(0) resulta em C Maior', () {
      final engine = TonalEngine(minSeconds: 2);
      feedFrames(engine, kkMajor, 0, seconds: 3.0);

      final reading = engine.evaluate(const Duration(milliseconds: 3000));
      expect(reading, isNotNull);
      expect(reading!.best.label, equals('C Maior'));
      expect(engine.displayed?.label, equals('C Maior'));
      expect(reading.confidence, greaterThan(0.5));
    });

    test('Lá menor: 3s de kkMinor(9) resulta em A Menor (teste do bug corrigido)', () {
      final engine = TonalEngine(minSeconds: 2);
      feedFrames(engine, kkMinor, 9, seconds: 3.0);

      final reading = engine.evaluate(const Duration(milliseconds: 3000));
      expect(reading, isNotNull);
      expect(reading!.best.label, equals('A Menor'));
      expect(engine.displayed?.label, equals('A Menor'));
    });

    test('As 24 tonalidades são identificadas corretamente', () {
      for (var tonic = 0; tonic < 12; tonic++) {
        // Maior
        final engineMaj = TonalEngine(minSeconds: 2);
        feedFrames(engineMaj, kkMajor, tonic, seconds: 3.0);
        final readingMaj = engineMaj.evaluate(const Duration(milliseconds: 3000));
        expect(readingMaj, isNotNull);
        expect(readingMaj!.best.tonic, equals(tonic));
        expect(readingMaj.best.major, isTrue);
        expect(engineMaj.displayed?.label, equals('${noteNames[tonic]} Maior'));

        // Menor
        final engineMin = TonalEngine(minSeconds: 2);
        feedFrames(engineMin, kkMinor, tonic, seconds: 3.0);
        final readingMin = engineMin.evaluate(const Duration(milliseconds: 3000));
        expect(readingMin, isNotNull);
        expect(readingMin!.best.tonic, equals(tonic));
        expect(readingMin.best.major, isFalse);
        expect(engineMin.displayed?.label, equals('${noteNames[tonic]} Menor'));
      }
    });

    test('Mínimo de áudio: com 1s de frames evaluate gera leitura mas displayed é null', () {
      final engine = TonalEngine(minSeconds: 2);
      feedFrames(engine, kkMajor, 0, seconds: 1.0);

      final reading = engine.evaluate(const Duration(milliseconds: 1000));
      expect(reading, isNotNull);
      expect(reading!.best.label, equals('C Maior'));
      expect(engine.displayed, isNull);
    });

    test('Estabilidade: exige 3 leituras consecutivas para trocar a tonalidade exibida', () {
      final engine = TonalEngine(minSeconds: 2, stabilityCount: 3);
      // Estabelece Dó maior (2s de Dó)
      feedFrames(engine, kkMajor, 0, seconds: 2.0);
      engine.evaluate(const Duration(milliseconds: 2000));
      expect(engine.displayed?.label, equals('C Maior'));

      // Adiciona 4s de Sol maior (superando a energia de Dó na janela)
      feedFrames(engine, kkMajor, 7, seconds: 4.0, startAt: const Duration(milliseconds: 2100));

      // 1ª leitura com Sol maior vencendo
      final eval1 = engine.evaluate(const Duration(milliseconds: 6100));
      expect(eval1?.best.label, equals('G Maior'));
      expect(engine.displayed?.label, equals('C Maior')); // Ainda não troca!

      // 2ª leitura com Sol maior vencendo
      final eval2 = engine.evaluate(const Duration(milliseconds: 6600));
      expect(eval2?.best.label, equals('G Maior'));
      expect(engine.displayed?.label, equals('C Maior')); // Ainda não troca!

      // 3ª leitura consecutiva com Sol maior vencendo
      final eval3 = engine.evaluate(const Duration(milliseconds: 7100));
      expect(eval3?.best.label, equals('G Maior'));
      expect(engine.displayed?.label, equals('G Maior')); // Troca!
    });

    test('Estabilidade: contagem zera se voltar à tonalidade exibida', () {
      final engine = TonalEngine(minSeconds: 2, stabilityCount: 3);
      feedFrames(engine, kkMajor, 0, seconds: 2.0);
      engine.evaluate(const Duration(milliseconds: 2000));
      expect(engine.displayed?.label, equals('C Maior'));

      // Adiciona Sol suficiente para vencer Dó
      feedFrames(engine, kkMajor, 7, seconds: 3.0, startAt: const Duration(milliseconds: 2100));
      final eval1 = engine.evaluate(const Duration(milliseconds: 5100));
      expect(eval1?.best.label, equals('G Maior'));
      expect(engine.displayed?.label, equals('C Maior')); // 1ª leitura

      // Volta a adicionar Dó massivo para que Dó volte a vencer
      feedFrames(engine, kkMajor, 0, seconds: 5.0, startAt: const Duration(milliseconds: 5200));
      final eval2 = engine.evaluate(const Duration(milliseconds: 10200));
      expect(eval2?.best.label, equals('C Maior'));
      expect(engine.displayed?.label, equals('C Maior')); // Zera contagem de Sol

      // Próxima leitura com Sol volta para candidateCount = 1
      feedFrames(engine, kkMajor, 7, seconds: 8.0, startAt: const Duration(milliseconds: 10300));
      final eval3 = engine.evaluate(const Duration(milliseconds: 18300));
      expect(eval3?.best.label, equals('G Maior'));
      expect(engine.displayed?.label, equals('C Maior')); // Apenas 1 leitura, não troca ainda!
    });

    test('Janela: frames descartados após windowSeconds retornam null mas mantêm displayed', () {
      final engine = TonalEngine(windowSeconds: 10, minSeconds: 2);
      feedFrames(engine, kkMajor, 0, seconds: 3.0);
      engine.evaluate(const Duration(milliseconds: 3000));
      expect(engine.displayed?.label, equals('C Maior'));

      // Avaliação em t = 20s (sem novos frames há 17s)
      final readingAfter = engine.evaluate(const Duration(seconds: 20));
      expect(readingAfter, isNull);
      expect(engine.displayed?.label, equals('C Maior'));
    });

    test('Reset: zera tudo', () {
      final engine = TonalEngine(minSeconds: 2);
      feedFrames(engine, kkMajor, 0, seconds: 3.0);
      engine.evaluate(const Duration(milliseconds: 3000));
      expect(engine.displayed, isNotNull);

      engine.reset();
      expect(engine.displayed, isNull);
      expect(engine.lastReading, isNull);
      expect(engine.evaluate(const Duration(milliseconds: 4000)), isNull);
    });
  });
}
