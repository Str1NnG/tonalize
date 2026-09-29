import 'package:flutter_test/flutter_test.dart';
import 'package:keyfinder/core/key_evidence.dart';
import 'package:keyfinder/core/key_profiles.dart';
import 'helpers/chords.dart';

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

    test('15. scaleOf(Ré maior) e scaleOf(Si menor)', () {
      expect(scaleOf(dMajor), equals({2, 4, 6, 7, 9, 11, 1}));
      expect(scaleOf(bMinor), equals({11, 1, 2, 4, 6, 7, 9, 10}));
    });
  });
}
