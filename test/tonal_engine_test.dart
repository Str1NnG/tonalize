import 'package:flutter_test/flutter_test.dart';
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
      final engine = TonalEngine();
      feedFrames(engine, kkMajor, 0, seconds: 3.0);

      final reading = engine.evaluate(const Duration(milliseconds: 3000));
      expect(reading, isNotNull);
      expect(reading!.best.label, equals('C Maior'));
      expect(engine.displayed?.label, equals('C Maior'));
      expect(reading.confidence, greaterThan(0.5));
    });

    test('Lá menor: 3s de kkMinor(9) resulta em A Menor (teste do bug corrigido)', () {
      final engine = TonalEngine();
      feedFrames(engine, kkMinor, 9, seconds: 3.0);

      final reading = engine.evaluate(const Duration(milliseconds: 3000));
      expect(reading, isNotNull);
      expect(reading!.best.label, equals('A Menor'));
      expect(engine.displayed?.label, equals('A Menor'));
    });

    test('As 24 tonalidades são identificadas corretamente', () {
      for (var tonic = 0; tonic < 12; tonic++) {
        // Maior
        final engineMaj = TonalEngine();
        feedFrames(engineMaj, kkMajor, tonic, seconds: 3.0);
        final readingMaj = engineMaj.evaluate(const Duration(milliseconds: 3000));
        expect(readingMaj, isNotNull);
        expect(readingMaj!.best.tonic, equals(tonic));
        expect(readingMaj.best.major, isTrue);
        expect(engineMaj.displayed?.label, equals('${noteNames[tonic]} Maior'));

        // Menor
        final engineMin = TonalEngine();
        feedFrames(engineMin, kkMinor, tonic, seconds: 3.0);
        final readingMin = engineMin.evaluate(const Duration(milliseconds: 3000));
        expect(readingMin, isNotNull);
        expect(readingMin!.best.tonic, equals(tonic));
        expect(readingMin.best.major, isFalse);
        expect(engineMin.displayed?.label, equals('${noteNames[tonic]} Menor'));
      }
    });

    test('Mínimo de áudio: com 1s de frames evaluate gera leitura mas displayed é null', () {
      final engine = TonalEngine();
      feedFrames(engine, kkMajor, 0, seconds: 1.0);

      final reading = engine.evaluate(const Duration(milliseconds: 1000));
      expect(reading, isNotNull);
      expect(reading!.best.label, equals('C Maior'));
      expect(engine.displayed, isNull);
    });

    test('nearby tem 3 elementos e nenhum é a exibida', () {
      final engine = TonalEngine();
      feedFrames(engine, kkMajor, 0, seconds: 3.0);

      final reading = engine.evaluate(const Duration(milliseconds: 3000))!;
      expect(reading.nearby.length, 3);
      for (final n in reading.nearby) {
        expect(n.sameKey(reading.displayed), isFalse);
      }
    });

    test('Silêncio prolongado (> 4s) aciona reinício automático e zera displayed', () {
      final engine = TonalEngine();
      feedFrames(engine, kkMajor, 0, seconds: 3.0);
      final r1 = engine.evaluate(const Duration(milliseconds: 3000));
      expect(r1, isNotNull);
      expect(engine.displayed?.label, equals('C Maior'));

      // 4.5s depois do último frame (3.0s + 4.5s = 7.5s)
      final r2 = engine.evaluate(const Duration(milliseconds: 7500));
      expect(r2, isNull);
      expect(engine.displayed, isNull);
    });

    test('Reset manual: zera tudo', () {
      final engine = TonalEngine();
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
