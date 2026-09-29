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
        expect(engineMaj.displayed?.label, equals('${KeyCandidate(tonic, true, 0).name} Maior'));

        // Menor
        final engineMin = TonalEngine();
        feedFrames(engineMin, kkMinor, tonic, seconds: 3.0);
        final readingMin = engineMin.evaluate(const Duration(milliseconds: 3000));
        expect(readingMin, isNotNull);
        expect(readingMin!.best.tonic, equals(tonic));
        expect(readingMin.best.major, isFalse);
        expect(engineMin.displayed?.label, equals('${KeyCandidate(tonic, false, 0).name} Menor'));
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
      final res = feed(engine, refraoBSeq, 40, start: 40);
      final reading = res.reading;
      expect(reading, isNotNull);
      expect(reading!.displayed?.label, equals('D Maior'));
      expect(reading.passage?.label, equals('A Maior'));
      expect(reading.showPassage, isTrue);
      expect(engine.labelChanges, equals(0));
      expect(res.events.contains(MemoryEvent.neighborKeyConfirmed), isFalse);
    });

    test('2. Sem a memória da música o letreiro cai', () {
      final engine = TonalEngine(
        songConfig: const SongMemoryConfig(enabled: false),
      );
      feed(engine, versoSeq, 40);
      final res = feed(engine, refraoBSeq, 40, start: 40);
      final reading = res.reading;
      expect(reading, isNotNull);
      expect(reading!.displayed?.label, equals('A Maior'));
    });

    test('3. Modulação distante', () {
      final engine = TonalEngine();
      feed(engine, versoSeq, 40);
      final r48 = feed(engine, ebSeq, 8, start: 40);
      expect(r48.reading?.displayed?.label, equals('D Maior'));

      final r70 = feed(engine, ebSeq, 22, start: 48);
      expect(r70.reading?.displayed?.label, equals('Eb Maior'));
      final allEvents = [...r48.events, ...r70.events];
      expect(allEvents.contains(MemoryEvent.farKeyConfirmed), isTrue);
      expect(engine.labelChanges, equals(1));
    });

    test('4. Vamp longo sem nota nova não vira o tom pelo caminho rápido', () {
      final engine = TonalEngine();
      feed(engine, versoSeq, 40);
      final res1 = feed(engine, refraoBSeq, 90, start: 40); // t = 130s
      expect(res1.reading?.displayed?.label, equals('D Maior'));
      expect(res1.events.contains(MemoryEvent.neighborKeyConfirmed), isFalse);

      final res2 = feed(engine, refraoBSeq, 70, start: 130); // t = 200s
      expect(res2.reading?.displayed?.label, equals('A Maior'));
      expect(
        [...res1.events, ...res2.events].contains(MemoryEvent.neighborKeyConfirmed),
        isFalse,
      );

      final engineSlow = TonalEngine(
        songConfig: const SongMemoryConfig(halfLifeSeconds: 120),
      );
      feed(engineSlow, versoSeq, 40);
      final resSlow = feed(engineSlow, refraoBSeq, 125, start: 40); // t = 165s
      expect(resSlow.reading?.displayed?.label, equals('D Maior'));
    });

    test('4b. Dominante secundária não é modulação', () {
      final engine1 = TonalEngine();
      feed(engine1, versoSeq, 40);
      final pat1 = [(dMaj, 1.0), (eSete, 1.0), (aMaj, 1.0), (dMaj, 1.0)];
      final res1 = feed(engine1, pat1, 60, start: 40);
      for (final (_, passage, displayed, evidence) in res1.timeline) {
        expect(passage?.label, equals('D Maior'));
        expect(displayed?.label, equals('D Maior'));
        expect(evidence, equals(0.0));
      }
      expect(res1.events.contains(MemoryEvent.neighborKeyConfirmed), isFalse);

      final engine2 = TonalEngine();
      feed(engine2, versoSeq, 40);
      final pat2 = [(dMaj, 1.0), (bMin, 1.0), (eSete, 1.0), (aMaj, 1.0)];
      final res2 = feed(engine2, pat2, 60, start: 40);
      for (final (_, passage, displayed, evidence) in res2.timeline) {
        expect(passage?.label, equals('D Maior'));
        expect(displayed?.label, equals('D Maior'));
        expect(evidence, equals(0.0));
      }
      expect(res2.events.contains(MemoryEvent.neighborKeyConfirmed), isFalse);
    });

    test('4c. Dreno da evidência', () {
      List<double> makeAChroma({required bool notePresent}) {
        final c = List<double>.filled(12, 0.02);
        c[9] = 0.25; // A
        c[1] = 0.20; // C#
        c[4] = 0.20; // E
        if (notePresent) {
          c[8] = 0.10; // G# (nota nova)
          c[7] = 0.01; // G
        } else {
          c[8] = 0.01; // G#
          c[7] = 0.10; // G
        }
        final s = c.reduce((a, b) => a + b);
        return [for (final v in c) v / s];
      }

      // 1. Com evidenceDrain: 0.5
      final engineDrain05 = TonalEngine(
        songConfig: const SongMemoryConfig(evidenceDrain: 0.5),
      );
      feed(engineDrain05, versoSeq, 40);
      // Estabelece o trecho parado em Lá maior antes da alternância
      engineDrain05.passageStabilizer.displayed = const KeyCandidate(9, true, 0.85);

      var confirmedTime05 = -1.0;
      for (var i = 1; i <= 340; i++) {
        final dt = i * 0.5;
        final nowSeconds = 40.0 + dt;
        final cycle = (dt - 0.25) % 20.0;
        final notePresent = cycle < 10.0;
        final chroma = makeAChroma(notePresent: notePresent);
        final tDuration = Duration(milliseconds: (nowSeconds * 1000).round());
        engineDrain05.passage.clear();
        engineDrain05.passage.add(chroma, tDuration);
        engineDrain05.song.add(dMaj, tDuration);
        final r = engineDrain05.evaluate(tDuration);
        if (r != null &&
            r.event == MemoryEvent.neighborKeyConfirmed &&
            confirmedTime05 < 0) {
          confirmedTime05 = dt;
        }
      }
      expect(confirmedTime05, closeTo(150.0, 5.0));

      // 2. Com evidenceDrain: 1.5
      final engineDrain15 = TonalEngine(
        songConfig: const SongMemoryConfig(evidenceDrain: 1.5),
      );
      feed(engineDrain15, versoSeq, 40);
      engineDrain15.passageStabilizer.displayed = const KeyCandidate(9, true, 0.85);

      var maxEvidence15 = 0.0;
      for (var i = 1; i <= 340; i++) {
        final dt = i * 0.5;
        final nowSeconds = 40.0 + dt;
        final cycle = (dt - 0.25) % 20.0;
        final notePresent = cycle < 10.0;
        final chroma = makeAChroma(notePresent: notePresent);
        final tDuration = Duration(milliseconds: (nowSeconds * 1000).round());
        engineDrain15.passage.clear();
        engineDrain15.passage.add(chroma, tDuration);
        engineDrain15.song.add(dMaj, tDuration);
        final r = engineDrain15.evaluate(tDuration);
        if (r != null && r.evidenceSeconds > maxEvidence15) {
          maxEvidence15 = r.evidenceSeconds;
        }
      }
      expect(maxEvidence15, lessThanOrEqualTo(10.0 + 1e-6));
    });

    test('4d. Evidência não passa de um vizinho para outro', () {
      final engine = TonalEngine();
      feed(engine, versoSeq, 40);
      final resG = feed(engine, gComDoSeq, 30, start: 40); // 40s a 70s
      final resA = feed(engine, aComMiSeq, 70, start: 70); // 70s a 140s

      final solEntry = resG.timeline.firstWhere((e) => e.$2?.label == 'G Maior');
      expect(solEntry.$1, closeTo(57.0, 3.0));

      final laEntry = resA.timeline.firstWhere((e) => e.$2?.label == 'A Maior');
      expect(laEntry.$1, closeTo(87.0, 3.0));
      expect(laEntry.$4, lessThanOrEqualTo(1.0));

      final confirmEvent = resA.timedEvents.firstWhere(
        (e) => e.$2 == MemoryEvent.neighborKeyConfirmed,
        orElse: () => (-1.0, MemoryEvent.none),
      );
      expect(confirmEvent.$1, closeTo(131.0, 5.0));
      expect(confirmEvent.$1 - laEntry.$1, greaterThanOrEqualTo(44.0));
    });

    test('4e. Evidência continua entre vizinhos que pedem as mesmas notas', () {
      final engine = TonalEngine();
      feed(engine, versoSeq, 40);
      final resA = feed(engine, aComMiSeq, 25, start: 40); // 40s a 65s
      final fsmSeq = [
        (fSharpMin, 1.0),
        (cSharp7, 0.5),
        (bMin, 0.5),
        (fSharpMin, 1.0),
      ];
      final resFsm = feed(engine, fsmSeq, 50, start: 65); // 65s a 115s

      final laEntry = resA.timeline.firstWhere((e) => e.$2?.label == 'A Maior');
      expect(laEntry.$1, closeTo(56.0, 3.0));

      final fsmEntry = resFsm.timeline.firstWhere((e) => e.$2?.label == 'F# Menor');
      expect(fsmEntry.$1, closeTo(87.0, 4.0));
      expect(fsmEntry.$4, greaterThan(25.0));

      final confirmEvent = resFsm.timedEvents.firstWhere(
        (e) => e.$2 == MemoryEvent.neighborKeyConfirmed,
      );
      expect(confirmEvent.$1, closeTo(101.0, 4.0));

      final readingAtConfirm = resFsm.timeline.firstWhere(
        (e) => e.$1 == confirmEvent.$1,
      );
      expect(readingAtConfirm.$4, closeTo(45.0, 1.0));
    });

    test('5. Modulação vizinha real, com a nota nova', () {
      // A com Mi
      final engineA = TonalEngine();
      feed(engineA, versoSeq, 40);
      final r80A = feed(engineA, aComMiSeq, 40, start: 40);
      expect(r80A.reading?.passage?.label, equals('A Maior'));
      expect(r80A.reading?.displayed?.label, equals('D Maior'));

      final r120A = feed(engineA, aComMiSeq, 40, start: 80);
      expect(r120A.reading?.displayed?.label, equals('A Maior'));
      expect(
        [...r80A.events, ...r120A.events].contains(MemoryEvent.neighborKeyConfirmed),
        isTrue,
      );

      // G com Do
      final engineG = TonalEngine();
      feed(engineG, versoSeq, 40);
      final resG = feed(engineG, gComDoSeq, 80, start: 40);
      expect(resG.reading?.displayed?.label, equals('G Maior'));
      expect(resG.events.contains(MemoryEvent.neighborKeyConfirmed), isTrue);

      // Bm com F#7
      final engineBm = TonalEngine();
      feed(engineBm, versoSeq, 40);
      final resBm = feed(engineBm, bmSeq, 80, start: 40);
      expect(resBm.reading?.displayed?.label, equals('B Menor'));
      expect(resBm.events.contains(MemoryEvent.neighborKeyConfirmed), isTrue);
    });

    test('6. Vizinho sem nota nova só pelo esquecimento', () {
      final engine = TonalEngine();
      feed(engine, versoSeq, 40);
      final r120 = feed(engine, gSemDoSeq, 80, start: 40); // t = 120s
      expect(r120.reading?.displayed?.label, equals('D Maior'));
      expect(r120.events.contains(MemoryEvent.neighborKeyConfirmed), isFalse);

      final r150 = feed(engine, gSemDoSeq, 30, start: 120); // t = 150s
      expect(r150.reading?.displayed?.label, equals('G Maior'));
    });

    test('7. Silêncio de 7 s reinicia as duas memórias', () {
      final engine = TonalEngine();
      feed(engine, versoSeq, 30);
      feedSilence(engine, 7, start: 30); // 30s a 37s
      final res = feed(engine, ebSeq, 8, start: 37); // até 45s
      expect(res.reading?.displayed?.label, equals('Eb Maior'));
      expect(engine.song.secondsInWindow, closeTo(8.0, 1.0));
      expect(res.events.contains(MemoryEvent.silenceReset), isTrue);
    });

    test('8. Silêncio de 5 s reinicia só o trecho', () {
      final engine = TonalEngine();
      feed(engine, versoSeq, 40);
      feedSilence(engine, 5, start: 40); // 40s a 45s
      final r46 = feed(engine, versoSeq, 1, start: 45); // 45s a 46s
      expect(r46.reading, isNotNull);
      expect(r46.reading!.passage, isNull);
      expect(r46.reading!.displayed?.label, equals('D Maior'));

      final r50 = feed(engine, versoSeq, 4, start: 46); // até 50s
      expect(r50.reading?.passage?.label, equals('D Maior'));
      expect(r50.reading?.displayed?.label, equals('D Maior'));
    });

    test('9. Início: com 2.5s de versoSeq, displayed = Ré maior', () {
      final engine = TonalEngine();
      final res = feed(engine, versoSeq, 2.5);
      expect(res.reading?.displayed?.label, equals('D Maior'));
    });

    test('9b. Teto da memória jovem: amadurece aos 60s mesmo sem concordar com trecho', () {
      final forced = _ForcedKeyStabilizer(const KeyCandidate(2, true, 0.9));
      final engine = TonalEngine(passageStabilizer: forced);

      feed(engine, refraoBSeq, 59.0);
      expect(engine.isSongMature, isFalse);
      expect(engine.displayed?.label, equals('D Maior'));

      feed(engine, refraoBSeq, 2.0, start: 59.0); // t = 61.0s
      expect(engine.isSongMature, isTrue);
    });

    test('10. Introdução numa região vizinha', () {
      final engine = TonalEngine();
      feed(engine, introGSeq, 20); // 0 a 20s
      final r30 = feed(engine, versoSeq, 10, start: 20); // 20 a 30s
      expect(r30.reading?.displayed?.label, isNot(equals('D Maior')));

      final r50 = feed(engine, versoSeq, 20, start: 30); // 30 a 50s
      expect(r50.reading?.passage?.label, equals('D Maior'));

      final r90 = feed(engine, versoSeq, 40, start: 50); // 50 a 90s
      expect(r90.reading?.displayed?.label, equals('D Maior'));
    });

    test('11. labelChanges e reset()', () {
      final engine = TonalEngine();
      feed(engine, versoSeq, 40);
      feed(engine, ebSeq, 30, start: 40); // até 70s
      expect(engine.labelChanges, equals(1));
      engine.reset();
      expect(engine.labelChanges, equals(0));
      final resAfterReset = feed(engine, versoSeq, 2.5, start: 70);
      expect(resAfterReset.events.contains(MemoryEvent.manualReset), isTrue);
    });

    test('19. Tônica só no baixo', () {
      final tecladoSemBaixo = mix([
        (tri(6, 10, 5), 2), // vozes superiores de Mi♭m(add9) sem Mi♭
        (gbMaj, 1),
        (dbMaj, 1),
        (tri(11, 3, 8), 1), // Lá♭m sem raiz
        (tri(10, 1, 5), 1), // Si♭m
      ]);

      // Com bassShare = 0.25
      final engineWithBass = TonalEngine(
        scorer: KeyScorer(
          profiles: ProfileSet.temperley,
          minorProfiles: ProfileSet.aarden,
        ),
        songConfig: const SongMemoryConfig(bassShare: 0.25),
      );

      final engineWithoutBass = TonalEngine(
        scorer: KeyScorer(
          profiles: ProfileSet.temperley,
          minorProfiles: ProfileSet.aarden,
        ),
        songConfig: const SongMemoryConfig(bassShare: 0.0),
      );

      final steps = (40.0 / 0.5).round();
      for (var i = 1; i <= steps; i++) {
        final t = i * 0.5;
        final tDuration = Duration(milliseconds: (t * 1000).round());
        engineWithBass.addFrame(
          tecladoSemBaixo,
          tDuration,
          bassPc: 3,
          bassProb: 0.95,
        );
        engineWithoutBass.addFrame(
          tecladoSemBaixo,
          tDuration,
          bassPc: 3,
          bassProb: 0.95,
        );
        engineWithBass.evaluate(tDuration);
        engineWithoutBass.evaluate(tDuration);
      }

      // Com bassShare = 0.25, displayed é Mi♭ (Ré♯) menor aos 40 s
      expect(engineWithBass.displayed?.tonic, equals(3));
      expect(engineWithBass.displayed?.major, isFalse);

      // Com bassShare = 0, displayed NÃO é Mi♭ menor (fica Sol♭/Fá♯ maior ou Ré♭/Dó♯ maior)
      expect(
        engineWithoutBass.displayed == null ||
            engineWithoutBass.displayed!.tonic != 3 ||
            engineWithoutBass.displayed!.major,
        isTrue,
      );
      expect(engineWithoutBass.displayed?.tonic, equals(6));
    });

    test('20. Sem baixo detectado nada muda: bassPc: -1', () {
      final engine1 = TonalEngine(
        songConfig: const SongMemoryConfig(bassShare: 0.25),
      );
      final engine2 = TonalEngine(
        songConfig: const SongMemoryConfig(bassShare: 0.0),
      );

      final c = tri(2, 6, 9);
      for (var i = 1; i <= 20; i++) {
        final t = Duration(milliseconds: i * 500);
        engine1.addFrame(c, t, bassPc: -1, bassProb: 0.0);
        engine2.addFrame(c, t, bassPc: -1, bassProb: 0.0);
      }
      final r1 = engine1.evaluate(const Duration(seconds: 10));
      final r2 = engine2.evaluate(const Duration(seconds: 10));
      expect(r1?.profile, equals(r2?.profile));
      expect(r1?.displayed?.label, equals(r2?.displayed?.label));
    });

    test('21. Regressão do verso com baixo nas raízes', () {
      final cycle = [
        (dMaj, 2, 0.95),
        (dMaj, 2, 0.95),
        (gMaj, 7, 0.95),
        (aMaj, 9, 0.95),
        (dMaj, 2, 0.95),
        (dMaj, 2, 0.95),
      ];

      final engineBass = TonalEngine(
        songConfig: const SongMemoryConfig(bassShare: 0.25),
      );
      final engineNoBass = TonalEngine(
        songConfig: const SongMemoryConfig(bassShare: 0.0),
      );

      final steps = (30.0 / 0.5).round();
      for (var i = 1; i <= steps; i++) {
        final t = i * 0.5;
        final item = cycle[(i - 1) % cycle.length];
        final tDuration = Duration(milliseconds: (t * 1000).round());
        engineBass.addFrame(
          item.$1,
          tDuration,
          bassPc: item.$2,
          bassProb: item.$3,
        );
        engineNoBass.addFrame(
          item.$1,
          tDuration,
          bassPc: item.$2,
          bassProb: item.$3,
        );
        engineBass.evaluate(tDuration);
        engineNoBass.evaluate(tDuration);
      }

      expect(engineBass.displayed?.label, equals('D Maior'));
      expect(engineNoBass.displayed?.label, equals('D Maior'));
      expect(
        engineBass.lastReading!.confidence,
        greaterThanOrEqualTo(engineNoBass.lastReading!.confidence),
      );
    });
  });
}

class _ForcedKeyStabilizer extends KeyStabilizer {
  _ForcedKeyStabilizer(this.forced);
  final KeyCandidate forced;

  @override
  KeyCandidate? get displayed => forced;

  @override
  void update(Duration now, List<KeyCandidate> scores, double secondsInWindow, {List<double>? profile}) {}
}
