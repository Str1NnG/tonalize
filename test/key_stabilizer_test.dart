import 'package:flutter_test/flutter_test.dart';
import 'package:keyfinder/core/key_profiles.dart';
import 'package:keyfinder/core/key_stabilizer.dart';

void main() {
  List<KeyCandidate> buildScores({
    required KeyCandidate top,
    required double rTop,
    required KeyCandidate second,
    required double rSecond,
  }) {
    final list = <KeyCandidate>[
      KeyCandidate(top.tonic, top.major, rTop),
      KeyCandidate(second.tonic, second.major, rSecond),
    ];
    for (var t = 0; t < 12; t++) {
      for (final isMaj in [true, false]) {
        if ((t == top.tonic && isMaj == top.major) ||
            (t == second.tonic && isMaj == second.major)) {
          continue;
        }
        list.add(KeyCandidate(t, isMaj, 0.0));
      }
    }
    list.sort((a, b) => b.r.compareTo(a.r));
    return list;
  }

  const dMajor = KeyCandidate(2, true, 0.0); // D Maior
  const aMajor = KeyCandidate(9, true, 0.0); // A Maior (quinta acima, vizinho)
  const gMajor = KeyCandidate(7, true, 0.0); // G Maior (quinta abaixo, vizinho)
  const bMinor = KeyCandidate(11, false, 0.0); // B Menor (relativa, vizinho)
  const dMinor = KeyCandidate(2, false, 0.0); // D Menor (paralela, vizinho)
  const ebMajor = KeyCandidate(3, true, 0.0); // D# / Eb Maior (distante)
  const eMajor = KeyCandidate(4, true, 0.0); // E Maior (distante)
  const fsMinor = KeyCandidate(6, false, 0.0); // F# Menor (iii de D)
  const eMinor = KeyCandidate(4, false, 0.0); // E Menor (ii de D)
  const aMinor = KeyCandidate(9, false, 0.0); // A Menor (distante)
  const fMajor = KeyCandidate(5, true, 0.0); // F Maior (distante)
  const csMinor = KeyCandidate(1, false, 0.0); // C# Menor (distante)
  const bMajor = KeyCandidate(11, true, 0.0); // B Maior (paralela de Bm)
  const cMajor = KeyCandidate(0, true, 0.0); // C Maior (distante)

  group('KeyStabilizer isNeighbor', () {
    test('identifica vizinhos e não-vizinhos a partir de Ré maior e Si menor', () {
      // Verdadeiros a partir de Ré maior: A, G, Bm, F#m, Em, Dm
      expect(KeyStabilizer.isNeighbor(dMajor, aMajor), isTrue); // V
      expect(KeyStabilizer.isNeighbor(dMajor, gMajor), isTrue); // IV
      expect(KeyStabilizer.isNeighbor(dMajor, bMinor), isTrue); // vi
      expect(KeyStabilizer.isNeighbor(dMajor, fsMinor), isTrue); // iii
      expect(KeyStabilizer.isNeighbor(dMajor, eMinor), isTrue); // ii
      expect(KeyStabilizer.isNeighbor(dMajor, dMinor), isTrue); // paralelo

      // Falsos a partir de Ré maior: E, Am, F, C#m, E♭
      expect(KeyStabilizer.isNeighbor(dMajor, eMajor), isFalse);
      expect(KeyStabilizer.isNeighbor(dMajor, aMinor), isFalse);
      expect(KeyStabilizer.isNeighbor(dMajor, fMajor), isFalse);
      expect(KeyStabilizer.isNeighbor(dMajor, csMinor), isFalse);
      expect(KeyStabilizer.isNeighbor(dMajor, ebMajor), isFalse);

      // Verdadeiros a partir de Si menor: D, F#m, Em, G, A, B (maior)
      expect(KeyStabilizer.isNeighbor(bMinor, dMajor), isTrue); // III
      expect(KeyStabilizer.isNeighbor(bMinor, fsMinor), isTrue); // v
      expect(KeyStabilizer.isNeighbor(bMinor, eMinor), isTrue); // iv
      expect(KeyStabilizer.isNeighbor(bMinor, gMajor), isTrue); // VI
      expect(KeyStabilizer.isNeighbor(bMinor, aMajor), isTrue); // VII
      expect(KeyStabilizer.isNeighbor(bMinor, bMajor), isTrue); // paralelo

      // Falsos a partir de Si menor: C, Am
      expect(KeyStabilizer.isNeighbor(bMinor, cMajor), isFalse);
      expect(KeyStabilizer.isNeighbor(bMinor, aMinor), isFalse);
    });
  });

  group('KeyStabilizer regras de troca', () {
    test('1. Vizinho com margem pequena não troca', () {
      final stabilizer = KeyStabilizer();
      // Inicializar com D Maior
      stabilizer.update(
        const Duration(seconds: 2),
        buildScores(top: dMajor, rTop: 0.8, second: aMajor, rSecond: 0.7),
        2.0,
      );
      expect(stabilizer.displayed?.label, 'D Maior');

      // A vence D por 0.03 durante 10s (20 updates de 500ms)
      for (var ms = 2500; ms <= 12500; ms += 500) {
        stabilizer.update(
          Duration(milliseconds: ms),
          buildScores(top: aMajor, rTop: 0.83, second: dMajor, rSecond: 0.80),
          10.0,
        );
      }

      expect(stabilizer.displayed?.label, 'D Maior');
      expect(stabilizer.challenge, isNull);
    });

    test('2. Vizinho com margem suficiente e tempo suficiente troca', () {
      final stabilizer = KeyStabilizer();
      stabilizer.update(
        Duration.zero,
        buildScores(top: dMajor, rTop: 0.8, second: aMajor, rSecond: 0.7),
        2.0,
      );
      expect(stabilizer.displayed?.label, 'D Maior');

      // A vence D por 0.10 (margem >= 0.08)
      // 5.5s (ainda não atinge 6.0s hold)
      for (var ms = 500; ms <= 5500; ms += 500) {
        stabilizer.update(
          Duration(milliseconds: ms),
          buildScores(top: aMajor, rTop: 0.90, second: dMajor, rSecond: 0.80),
          10.0,
        );
      }
      expect(stabilizer.displayed?.label, 'D Maior');
      expect(stabilizer.challenge, isNotNull);
      expect(stabilizer.challenge!.progress(const Duration(milliseconds: 5500)), lessThan(1.0));

      // Chega em 6.5s -> deve trocar para A Maior
      for (var ms = 6000; ms <= 6500; ms += 500) {
        stabilizer.update(
          Duration(milliseconds: ms),
          buildScores(top: aMajor, rTop: 0.90, second: dMajor, rSecond: 0.80),
          10.0,
        );
      }
      expect(stabilizer.displayed?.label, 'A Maior');
      expect(stabilizer.challenge, isNull);
    });

    test('3. Distante troca com a regra base (0.05 por 4s)', () {
      final stabilizer = KeyStabilizer();
      stabilizer.update(
        Duration.zero,
        buildScores(top: dMajor, rTop: 0.8, second: ebMajor, rSecond: 0.7),
        2.0,
      );
      expect(stabilizer.displayed?.label, 'D Maior');

      // Eb vence D por 0.06 durante 4s
      for (var ms = 500; ms <= 4500; ms += 500) {
        stabilizer.update(
          Duration(milliseconds: ms),
          buildScores(top: ebMajor, rTop: 0.86, second: dMajor, rSecond: 0.80),
          10.0,
        );
      }
      expect(stabilizer.displayed?.label, 'D# Maior');
      expect(stabilizer.switches, 1);
    });

    test('4. Vantagem que oscila reinicia a contagem', () {
      final stabilizer = KeyStabilizer();
      stabilizer.update(
        Duration.zero,
        buildScores(top: dMajor, rTop: 0.8, second: aMajor, rSecond: 0.7),
        2.0,
      );

      // A vence por 0.10 por 3s
      for (var ms = 500; ms <= 3000; ms += 500) {
        stabilizer.update(
          Duration(milliseconds: ms),
          buildScores(top: aMajor, rTop: 0.90, second: dMajor, rSecond: 0.80),
          10.0,
        );
      }
      expect(stabilizer.challenge, isNotNull);

      // Cai para 0.02 em uma avaliação
      stabilizer.update(
        const Duration(milliseconds: 3500),
        buildScores(top: aMajor, rTop: 0.82, second: dMajor, rSecond: 0.80),
        10.0,
      );
      expect(stabilizer.challenge, isNull);

      // Volta a 0.10 por 3s (total 3s do novo desafio, precisa de 6s para vizinho)
      for (var ms = 4000; ms <= 7000; ms += 500) {
        stabilizer.update(
          Duration(milliseconds: ms),
          buildScores(top: aMajor, rTop: 0.90, second: dMajor, rSecond: 0.80),
          10.0,
        );
      }
      expect(stabilizer.displayed?.label, 'D Maior');
      expect(stabilizer.challenge, isNotNull);
    });

    test('5. Primeira exibição respeita minSeconds', () {
      final stabilizer = KeyStabilizer();
      stabilizer.update(
        const Duration(seconds: 1),
        buildScores(top: dMajor, rTop: 0.8, second: aMajor, rSecond: 0.7),
        1.0,
      );
      expect(stabilizer.displayed, isNull);

      stabilizer.update(
        const Duration(seconds: 2),
        buildScores(top: dMajor, rTop: 0.8, second: aMajor, rSecond: 0.7),
        2.0,
      );
      expect(stabilizer.displayed?.label, 'D Maior');
    });

    test('6. Contador de trocas e reset', () {
      final stabilizer = KeyStabilizer();
      stabilizer.update(
        Duration.zero,
        buildScores(top: dMajor, rTop: 0.8, second: ebMajor, rSecond: 0.7),
        2.0,
      );
      expect(stabilizer.switches, 0);

      // Força troca
      for (var ms = 500; ms <= 4500; ms += 500) {
        stabilizer.update(
          Duration(milliseconds: ms),
          buildScores(top: ebMajor, rTop: 0.86, second: dMajor, rSecond: 0.80),
          10.0,
        );
      }
      expect(stabilizer.switches, 1);

      stabilizer.reset();
      expect(stabilizer.switches, 0);
      expect(stabilizer.displayed, isNull);
      expect(stabilizer.challenge, isNull);
    });
  });
}
