import 'package:flutter_test/flutter_test.dart';
import 'package:keyfinder/core/key_evidence.dart';
import 'package:keyfinder/core/key_profiles.dart';
import 'package:keyfinder/core/key_stabilizer.dart';
import 'helpers/chords.dart';

List<double> perfilLimpo(KeyCandidate k, {bool harmonic = false}) {
  final c = List<double>.filled(12, 0.02);
  final nat = naturalScaleOf(k).toList();
  final root = k.tonic;
  final third = k.major ? (k.tonic + 4) % 12 : (k.tonic + 3) % 12;
  final fifth = (k.tonic + 7) % 12;

  for (final n in nat) {
    if (n == root) {
      c[n] = 1.0;
    } else if (n == third || n == fifth) {
      c[n] = 0.8;
    } else {
      c[n] = 0.5;
    }
  }

  if (harmonic && !k.major) {
    final nat7 = (k.tonic + 10) % 12;
    final raised7 = (k.tonic + 11) % 12;
    c[raised7] = c[nat7];
    c[nat7] = 0.02;
  }

  final sum = c.reduce((a, b) => a + b);
  return [for (final v in c) v / sum];
}

void main() {
  const dMajor = KeyCandidate(2, true, 0.0);
  const aMajor = KeyCandidate(9, true, 0.0);
  const gMajor = KeyCandidate(7, true, 0.0);
  const bMinor = KeyCandidate(11, false, 0.0);
  const fsMinor = KeyCandidate(6, false, 0.0);

  group('key_evidence', () {
    test('12. newNoteEvidence(Ré maior, Lá maior)', () {
      // refraoB (F#m e A) não tem Sol# (só F#, A, C#, E)
      expect(newNoteEvidence(dMajor, aMajor, refraoB), isFalse);

      // Com Mi maior (E, G#, B) há Sol#
      final aReal = mix([(aMaj, 2), (dMaj, 1), (eMaj, 1), (aMaj, 2)]);
      expect(newNoteEvidence(dMajor, aMajor, aReal), isTrue);
    });

    test('13. newNoteEvidence(Ré maior, Sol maior)', () {
      // gSemDoSeq (G, Em, D, G) não tem Dó natural
      final gSemDoMix = mix([(gMaj, 2), (eMin, 1), (dMaj, 1), (gMaj, 2)]);
      expect(newNoteEvidence(dMajor, gMajor, gSemDoMix), isFalse);

      // gComDoSeq (G, C, D, G) tem Dó natural
      final gComDoMix = mix([(gMaj, 2), (cMaj, 1), (dMaj, 1), (gMaj, 2)]);
      expect(newNoteEvidence(dMajor, gMajor, gComDoMix), isTrue);
    });

    test('14. newNoteEvidence(Ré maior, Si menor)', () {
      // refraoB não tem Lá#
      expect(newNoteEvidence(dMajor, bMinor, refraoB), isFalse);

      // bmSeq tem F#7 com Lá# (sensível)
      final bmMix = mix([(bMin, 2), (gMaj, 1), (fSharp7, 1), (bMin, 2)]);
      expect(newNoteEvidence(dMajor, bMinor, bmMix), isTrue);
    });

    test('14b. A partir de Ré, o G# basta para Fá# menor (intencional)', () {
      final fsmSemEs = mix([(fSharpMin, 2), (dMaj, 1), (aMaj, 1), (eMaj, 1)]);
      expect(newNoteEvidence(dMajor, fsMinor, fsmSemEs), isTrue);
    });

    test('14c. Entre relativos, só a sensível decide', () {
      // Lá maior -> Fá# menor sem C#7 (sem E#)
      final fsmSemEs = mix([(fSharpMin, 2), (dMaj, 1), (eMaj, 1)]);
      expect(newNoteEvidence(aMajor, fsMinor, fsmSemEs), isFalse);

      // Lá maior -> Fá# menor com C#7 (com E#)
      final fsmComEs = mix([(fSharpMin, 2), (cSharp7, 1)]);
      expect(newNoteEvidence(aMajor, fsMinor, fsmComEs), isTrue);

      // Do menor para o relativo maior não há nota nova
      expect(newNoteEvidence(fsMinor, aMajor, fsmComEs), isFalse);
      expect(newNoteEvidence(fsMinor, aMajor, List.filled(12, 1.0)), isFalse);
    });

    test('14d. Cor dórica não é tom novo (3.5)', () {
      const ebMinor = KeyCandidate(3, false, 0.0);
      const dbMajor = KeyCandidate(1, true, 0.0);
      const abMajor = KeyCandidate(8, true, 0.0);

      // Ré♭ maior não traz nota nenhuma fora do menor de 9 notas
      expect(newNoteEvidence(ebMinor, dbMajor, List.filled(12, 1.0)), isFalse);

      // Lá♭ maior traz apenas Sol natural (7): com Sol = 0 é false, com Sol = 0.10 é true
      final pSemSol = List<double>.filled(12, 0.01);
      pSemSol[7] = 0.0;
      expect(newNoteEvidence(ebMinor, abMajor, pSemSol), isFalse);

      final pComSol = List<double>.filled(12, 0.01);
      pComSol[7] = 0.10;
      expect(newNoteEvidence(ebMinor, abMajor, pComSol), isTrue);
    });

    test('15. scaleOf(Ré maior) e scaleOf(Si menor)', () {
      expect(scaleOf(dMajor), equals({2, 4, 6, 7, 9, 11, 1}));
      expect(scaleOf(bMinor), equals({11, 1, 2, 4, 6, 7, 8, 9, 10}));
    });

    test('2a. Sol -> Mi m, perfil de Sol limpo + Do# e Re# a 25% da media -> false', () {
      const gMaj = KeyCandidate(7, true, 0.0);
      const eMin = KeyCandidate(4, false, 0.0);
      final p = perfilLimpo(gMaj);
      final mean = p.reduce((a, b) => a + b) / 12;
      final pLeak = List<double>.from(p);
      pLeak[1] = 0.25 * mean; // Do#
      pLeak[3] = 0.25 * mean; // Re#
      expect(newNoteEvidence(gMaj, eMin, pLeak), isFalse);
    });

    test('2b. Sol -> Mi m, perfil com Re# >= Re (Si maior recorrente) -> true', () {
      const gMaj = KeyCandidate(7, true, 0.0);
      const eMin = KeyCandidate(4, false, 0.0);
      final p = perfilLimpo(gMaj);
      final pBmaj = List<double>.from(p);
      pBmaj[3] = pBmaj[2]; // Re# (3) = Re (2)
      expect(newNoteEvidence(gMaj, eMin, pBmaj), isTrue);
    });

    test('2c. Re -> La com Sol# >= 0.8 Sol -> true; com Sol# a 50% de Sol -> false', () {
      final p = perfilLimpo(dMajor);
      final pTrue = List<double>.from(p);
      pTrue[8] = 0.85 * pTrue[7]; // Sol# >= 0.8 Sol
      expect(newNoteEvidence(dMajor, aMajor, pTrue), isTrue);

      final pFalse = List<double>.from(p);
      pFalse[8] = 0.50 * pFalse[7]; // Sol# = 50% de Sol
      expect(newNoteEvidence(dMajor, aMajor, pFalse), isFalse);
    });

    test('2d. Mi -> Fa# m com Re >= 0.8 Re# -> true', () {
      const eMaj = KeyCandidate(4, true, 0.0);
      const fsMin = KeyCandidate(6, false, 0.0);
      final p = perfilLimpo(eMaj);
      final pTrue = List<double>.from(p);
      pTrue[2] = 0.85 * pTrue[3]; // Re (2) >= 0.8 Re# (3)
      expect(newNoteEvidence(eMaj, fsMin, pTrue), isTrue);
    });

    test('2e. La -> Fa# m com perfil de La maior limpo -> false', () {
      expect(newNoteEvidence(aMajor, fsMinor, perfilLimpo(aMajor)), isFalse);
    });

    test('2f. Mib m -> Reb com Do natural forte (IV dorico) -> false', () {
      const ebMin = KeyCandidate(3, false, 0.0);
      const dbMaj = KeyCandidate(1, true, 0.0);
      final p = perfilLimpo(ebMin);
      final pDoric = List<double>.from(p);
      pDoric[0] = 0.5; // Do natural (0) forte
      expect(newNoteEvidence(ebMin, dbMaj, pDoric), isFalse);
    });

    test('2g. Sol -> La m com Fa a 60% de Fa# e Sol# a 50% de Sol -> false; com Fa >= 0.8 Fa# -> true', () {
      final p = perfilLimpo(gMajor);
      final pFalse = List<double>.from(p);
      pFalse[5] = 0.60 * pFalse[6]; // Fa (5) = 60% de Fa# (6)
      pFalse[8] = 0.50 * pFalse[7]; // Sol# (8) = 50% de Sol (7)
      expect(newNoteEvidence(gMajor, const KeyCandidate(9, false, 0.0), pFalse), isFalse);

      final pTrue = List<double>.from(p);
      pTrue[5] = 0.85 * pTrue[6]; // Fa >= 0.8 Fa#
      expect(newNoteEvidence(gMajor, const KeyCandidate(9, false, 0.0), pTrue), isTrue);
    });

    test('2h. diatonicNewNotesOf', () {
      const abMaj = KeyCandidate(8, true, 0.0);
      const fMin = KeyCandidate(5, false, 0.0);
      const ebMaj = KeyCandidate(3, true, 0.0);
      expect(diatonicNewNotesOf(abMaj, fMin), isEmpty);
      expect(diatonicNewNotesOf(abMaj, ebMaj), equals({2})); // Re natural
      expect(diatonicNewNotesOf(dMajor, fsMinor), equals({8})); // Sol#
    });

    group('Propriedades estruturais (144 pares)', () {
      final allKeys = [
        for (var t = 0; t < 12; t++) ...[
          KeyCandidate(t, true, 0.0),
          KeyCandidate(t, false, 0.0),
        ]
      ];

      final pairs = <(KeyCandidate, KeyCandidate)>[
        for (final cur in allKeys)
          for (final cand in allKeys)
            if (KeyStabilizer.isNeighbor(cur, cand)) (cur, cand)
      ];

      test('Verifica que sao exatamente 144 pares vizinhos', () {
        expect(pairs.length, equals(144));
      });

      test('2i. Para todo par vizinho e n em newNotesOf, displacedBy(n) e nao vazio e contido em scaleOf(atual)', () {
        for (final (cur, cand) in pairs) {
          final newNotes = newNotesOf(cur, cand);
          for (final n in newNotes) {
            final disp = displacedBy(n, cur, cand);
            expect(disp, isNotEmpty, reason: 'displacedBy($n, $cur, $cand) nao pode ser vazio');
            expect(scaleOf(cur).containsAll(disp), isTrue,
                reason: 'displacedBy($n, $cur, $cand) = $disp deve estar em scaleOf($cur)');
          }
        }
      });

      test('2j. Para n elevada do candidato menor, displacedBy(n) == {n - 1} e n - 1 em naturalScaleOf(candidato)', () {
        for (final (cur, cand) in pairs) {
          final raised = raisedOf(cand);
          for (final n in raised) {
            final disp = displacedBy(n, cur, cand);
            final expected = (n + 11) % 12;
            expect(disp, equals({expected}));
            expect(naturalScaleOf(cand).contains(expected), isTrue);
          }
        }
      });

      test('2k. Para n diatonica, displacedBy(n) intersecao naturalScaleOf(candidato) == vazio', () {
        for (final (cur, cand) in pairs) {
          final diatonic = diatonicNewNotesOf(cur, cand);
          for (final n in diatonic) {
            final disp = displacedBy(n, cur, cand);
            expect(disp.intersection(naturalScaleOf(cand)), isEmpty);
          }
        }
      });

      test('2l. Sem falso positivo: newNoteEvidence(atual, candidato, perfilLimpo(atual)) e false para todo par vizinho', () {
        for (final (cur, cand) in pairs) {
          final prof = perfilLimpo(cur);
          expect(newNoteEvidence(cur, cand, prof), isFalse,
              reason: 'Falso positivo para $cur -> $cand com perfil limpo de $cur');
        }
      });

      test('2m. Sem falso negativo onde ha nota nova diatonica: 96 pares sao true com perfilLimpo(candidato)', () {
        var diatonicPairsCount = 0;
        for (final (cur, cand) in pairs) {
          if (diatonicNewNotesOf(cur, cand).isNotEmpty) {
            diatonicPairsCount++;
            final prof = perfilLimpo(cand);
            expect(newNoteEvidence(cur, cand, prof), isTrue,
                reason: 'Falso negativo para $cur -> $cand com perfil limpo de $cand');
          }
        }
        expect(diatonicPairsCount, equals(96));
      });

      test('2m\'. Pares com notas novas so elevadas (24 pares): false com perfil natural, true com perfil harmonico; 24 pares sem notas novas: false', () {
        var onlyRaisedCount = 0;
        var noNewNotesCount = 0;
        for (final (cur, cand) in pairs) {
          final allNew = newNotesOf(cur, cand);
          final diatonic = diatonicNewNotesOf(cur, cand);
          if (allNew.isNotEmpty && diatonic.isEmpty) {
            onlyRaisedCount++;
            expect(newNoteEvidence(cur, cand, perfilLimpo(cand, harmonic: false)), isFalse);
            expect(newNoteEvidence(cur, cand, perfilLimpo(cand, harmonic: true)), isTrue);
          } else if (allNew.isEmpty) {
            noNewNotesCount++;
            expect(newNoteEvidence(cur, cand, perfilLimpo(cand, harmonic: false)), isFalse);
            expect(newNoteEvidence(cur, cand, perfilLimpo(cand, harmonic: true)), isFalse);
          }
        }
        expect(onlyRaisedCount, equals(24));
        expect(noNewNotesCount, equals(24));
      });

      test('2m\'\'. O atual em menor harmonico nao gera evidencia para vizinho nenhum', () {
        for (final (cur, cand) in pairs) {
          if (!cur.major) {
            final profHarm = perfilLimpo(cur, harmonic: true);
            expect(newNoteEvidence(cur, cand, profHarm), isFalse,
                reason: 'Menor harmonico de $cur gerou falsa evidencia para $cand');
          }
        }
      });

      test('2n. Paralelos Sol <-> Sol m', () {
        const gMaj = KeyCandidate(7, true, 0.0);
        const gMin = KeyCandidate(7, false, 0.0);
        expect(newNoteEvidence(gMaj, gMin, perfilLimpo(gMaj)), isFalse);
        expect(newNoteEvidence(gMaj, gMin, perfilLimpo(gMin)), isTrue);
        expect(newNoteEvidence(gMin, gMaj, perfilLimpo(gMin)), isFalse);
        expect(newNoteEvidence(gMin, gMaj, perfilLimpo(gMaj)), isTrue);
      });
    });
  });
}
