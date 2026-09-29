import 'package:flutter_test/flutter_test.dart';
import 'package:keyfinder/core/tonal_engine.dart';
import 'helpers/chords.dart';

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

    test('Silêncio prolongado (> 6s) aciona reinício automático e zera displayed', () {
      final engine = TonalEngine();
      feedFrames(engine, kkMajor, 0, seconds: 3.0);
      final r1 = engine.evaluate(const Duration(milliseconds: 3000));
      expect(r1, isNotNull);
      expect(engine.displayed?.label, equals('C Maior'));

      // 6.5s depois do último frame (3.0s + 6.5s = 9.5s)
      final r2 = engine.evaluate(const Duration(milliseconds: 9500));
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

  group('Dual memory (Plano 3)', () {
    test('1. Refrão não derruba o tom da música', () {
      final engine = TonalEngine();
      feed(engine, versoSeq, 40);
      final (reading, _) = feed(engine, refraoBSeq, 40, start: 40);
      expect(reading, isNotNull);
      expect(reading!.displayed?.label, equals('D Maior'));
      expect(reading.passage?.label, equals('A Maior'));
      expect(reading.showPassage, isTrue);
      expect(engine.labelChanges, equals(0));
    });

    test('2. Sem a memória da música o letreiro cai', () {
      final engine = TonalEngine(
        songConfig: const SongMemoryConfig(enabled: false),
      );
      feed(engine, versoSeq, 40);
      final (reading, _) = feed(engine, refraoBSeq, 40, start: 40);
      expect(reading, isNotNull);
      expect(reading!.displayed?.label, equals('A Maior'));
    });

    test('3. Modulação distante', () {
      final engine = TonalEngine();
      feed(engine, versoSeq, 40);
      final (r48, ev1) = feed(engine, ebSeq, 8, start: 40);
      expect(r48?.displayed?.label, equals('D Maior'));

      final (r70, ev2) = feed(engine, ebSeq, 22, start: 48);
      expect(r70?.displayed?.label, equals('D# Maior'));
      final allEvents = [...ev1, ...ev2];
      expect(allEvents.contains(MemoryEvent.farReset), isTrue);
    });

    test('4. Vamp longo vira o tom', () {
      final engine = TonalEngine();
      feed(engine, versoSeq, 40);
      final (r100, ev1) = feed(engine, refraoBSeq, 60, start: 40);
      expect(r100?.displayed?.label, equals('D Maior'));

      final (r130, ev2) = feed(engine, refraoBSeq, 30, start: 100);
      expect(r130?.displayed?.label, equals('A Maior'));
      final allEvents = [...ev1, ...ev2];
      expect(allEvents.contains(MemoryEvent.nearReset), isTrue);

      // Com nearResetSeconds: 0, não vira
      final engineNoNear = TonalEngine(
        songConfig: const SongMemoryConfig(nearResetSeconds: 0),
      );
      feed(engineNoNear, versoSeq, 40);
      final (rNoNear, _) = feed(engineNoNear, refraoBSeq, 90, start: 40);
      expect(rNoNear?.displayed?.label, equals('D Maior'));
    });

    test('5. Silêncio de 7 s reinicia as duas memórias', () {
      final engine = TonalEngine();
      feed(engine, versoSeq, 30);
      // 7s de silêncio (30s a 37s), depois 8s de ebSeq até 45s
      final (r45, ev) = feed(engine, ebSeq, 8, start: 37);
      expect(r45?.displayed?.label, equals('D# Maior'));
      expect(ev.contains(MemoryEvent.silenceReset), isTrue);
    });

    test('6. Silêncio de 5 s reinicia só o trecho', () {
      final engine = TonalEngine();
      feed(engine, versoSeq, 30);
      // 5s de silêncio (30s a 35s), depois 1s de versoSeq até 36s
      final (r36, _) = feed(engine, versoSeq, 1, start: 35);
      expect(r36, isNotNull);
      expect(r36!.passage, isNull);
      expect(r36.displayed?.label, equals('D Maior'));

      // Mais 4s até 40s: os dois são Ré Maior
      final (r40, _) = feed(engine, versoSeq, 4, start: 36);
      expect(r40?.passage?.label, equals('D Maior'));
      expect(r40?.displayed?.label, equals('D Maior'));
    });

    test('7. Início: com 2.5s de áudio já tem tom exibido', () {
      final engine = TonalEngine();
      final (r25, _) = feed(engine, versoSeq, 2.5);
      expect(r25?.displayed?.label, equals('D Maior'));
    });

    test('8. Nova música em tom vizinho sem pausa', () {
      final engine = TonalEngine();
      feed(engine, versoSeq, 40);
      final (r80, _) = feed(engine, gSeq, 40, start: 40);
      expect(r80?.passage?.label, equals('G Maior'));
      expect(r80?.displayed?.label, equals('D Maior'));

      final (r120, _) = feed(engine, gSeq, 40, start: 80);
      expect(r120?.displayed?.label, equals('G Maior'));
    });

    test('9. labelChanges métrica', () {
      final engine = TonalEngine();
      feed(engine, versoSeq, 40);
      feed(engine, ebSeq, 30, start: 40); // até 70s
      expect(engine.labelChanges, equals(1));
      engine.reset();
      expect(engine.labelChanges, equals(0));
    });
  });
}
