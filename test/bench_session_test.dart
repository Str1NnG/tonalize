import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyfinder/bench/bench_session.dart';
import 'package:keyfinder/bench/bench_song.dart';
import 'package:keyfinder/core/tonal_engine.dart';

void main() {
  group('Fase 5: Bancada, veredito, session.json e segmentos', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('bench_session_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('5.1 BenchSong: reference.segments[0] espelha reference.key e reference.mode', () {
      final song = BenchSong(
        number: 1,
        title: 'Teste',
        artist: 'Artista',
        youtube: '',
        durationSeconds: 120,
        referenceKey: 'D',
        referenceMode: 'major',
      );

      expect(song.referenceSegments.length, equals(1));
      expect(song.referenceSegments[0].key, equals('D'));
      expect(song.referenceSegments[0].mode, equals('major'));
      expect(song.referenceSegments[0].fromSeconds, equals(0.0));

      song.updateReference(key: 'G', mode: 'minor');
      expect(song.referenceSegments[0].key, equals('G'));
      expect(song.referenceSegments[0].mode, equals('minor'));
    });

    test('5.2 parseSegmentsInput: analisa múltiplos formatos de linha minuto:segundo -> tom', () {
      const input = '''
0:00 -> G
0:45 -> Em
1:30 -> C maior
2:15 -> D
3:00 -> F# menor
''';
      final segments = parseSegmentsInput(input);
      expect(segments.length, equals(5));

      expect(segments[0].fromSeconds, equals(0.0));
      expect(segments[0].key, equals('G'));
      expect(segments[0].mode, equals('major'));

      expect(segments[1].fromSeconds, equals(45.0));
      expect(segments[1].key, equals('E'));
      expect(segments[1].mode, equals('minor'));

      expect(segments[2].fromSeconds, equals(90.0));
      expect(segments[2].key, equals('C'));
      expect(segments[2].mode, equals('major'));

      expect(segments[3].fromSeconds, equals(135.0));
      expect(segments[3].key, equals('D'));
      expect(segments[3].mode, equals('major'));

      expect(segments[4].fromSeconds, equals(180.0));
      expect(segments[4].key, equals('F#'));
      expect(segments[4].mode, equals('minor'));
    });

    test('5.3 BenchSession: cria session.json parcial ("em andamento") e com silence_threshold_db', () async {
      final song = BenchSong(
        number: 2,
        title: 'Música Parcial',
        artist: 'Artista',
        youtube: '',
        durationSeconds: 200,
        referenceKey: 'A',
        referenceMode: 'minor',
      );

      final session = await BenchSession.start(
        song: song,
        benchRootDir: tempDir.path,
        configString: 'v3;w20;harm;aar;min-aar_b7;song60;far20;near45;tol0.8;floor0.25;drain0.5;strict0;bass0',
        silenceThresholdDb: -70.0,
      );

      expect(await session.sessionJsonFile.exists(), isTrue);
      final jsonContent = jsonDecode(await session.sessionJsonFile.readAsString()) as Map<String, dynamic>;

      expect(jsonContent['verdict']['result'], equals('em andamento'));
      expect(jsonContent['capture']['silence_threshold_db'], equals(-70.0));
      expect(jsonContent['reference']['key'], equals('A'));
      expect(jsonContent['reference']['mode'], equals('minor'));
      expect(jsonContent['reference']['segments'][0]['key'], equals('A'));
      expect(jsonContent['reference']['segments'][0]['mode'], equals('minor'));

      await session.completeSession(verdictResult: 'acertou', finalLabel: 'A Menor', finalSecond: 'C Maior');
    });

    test('5.4 BenchSession: silêncio final não zera o final_label para N/A', () async {
      final song = BenchSong(
        number: 3,
        title: 'Música Silêncio',
        artist: 'Artista',
        youtube: '',
        durationSeconds: 180,
        referenceKey: 'D',
        referenceMode: 'major',
      );

      final session = await BenchSession.start(
        song: song,
        benchRootDir: tempDir.path,
        configString: 'v3;w20;harm;aar;min-aar_b7;song60;far20;near45;tol0.8;floor0.25;drain0.5;strict0;bass0',
      );

      // Simula leitura ativa exibindo D Maior
      final readingActive = TonalReading(
        displayed: const KeyCandidate(2, true, 0.92),
        best: const KeyCandidate(2, true, 0.92),
        second: const KeyCandidate(9, true, 0.75),
        confidence: 0.92,
        nearby: const [],
        profile: List.filled(12, 0.0),
        evidenceSeconds: 0,
        secondsInWindow: 30,
        songSeconds: 30,
        event: MemoryEvent.none,
      );
      session.addReading(
        reading: readingActive,
        tAudioMs: 30000,
        labelChanges: 0,
        isSongMature: true,
      );

      expect(session.lastNonEmptyDisplayedLabel, equals('D Maior'));
      expect(session.lastNonEmptySecondLabel, equals('A Maior'));

      // Simula leitura após silêncio de 10s: displayed = null
      final readingSilent = TonalReading(
        displayed: null,
        best: const KeyCandidate(2, true, 0.10),
        second: const KeyCandidate(9, true, 0.08),
        confidence: 0.10,
        nearby: const [],
        profile: List.filled(12, 0.0),
        evidenceSeconds: 0,
        secondsInWindow: 0,
        songSeconds: 0,
        event: MemoryEvent.silenceReset,
      );
      session.addReading(
        reading: readingSilent,
        tAudioMs: 40000,
        labelChanges: 0,
        isSongMature: false,
      );

      // Finaliza sessão sem passar finalLabel (ou passando N/A)
      await session.completeSession(
        verdictResult: 'acertou',
        finalLabel: 'N/A',
        finalSecond: 'N/A',
      );

      final jsonContent = jsonDecode(await session.sessionJsonFile.readAsString()) as Map<String, dynamic>;
      expect(jsonContent['verdict']['final_label'], equals('D Maior'));
      expect(jsonContent['verdict']['final_second'], equals('A Maior'));
      expect(jsonContent['verdict']['final_label'], isNot(equals('N/A')));
      expect(jsonContent['verdict']['final_label'], isNot(isEmpty));
    });
  });
}
