import 'package:flutter_test/flutter_test.dart';
import 'package:keyfinder/core/key_profiles.dart';
import 'package:keyfinder/core/key_scorer.dart';
import 'helpers/chords.dart';

void main() {
  group('KeyScorer profiles evaluation', () {
    test('1. Os 24 tons são reconhecidos com cada conjunto', () {
      for (final profileSet in ProfileSet.values) {
        final scorer = KeyScorer(profiles: profileSet);
        for (var tonic = 0; tonic < 12; tonic++) {
          // Maior
          final majProf = rotated(profileSet.major, tonic);
          final bestMaj = scorer.score(majProf).first;
          expect(bestMaj.tonic, tonic, reason: 'Failed for ${profileSet.label} tonic $tonic Major');
          expect(bestMaj.major, isTrue);
          expect((bestMaj.r - 1.0).abs(), lessThan(1e-4));

          // Menor
          final minProf = rotated(profileSet.minor, tonic);
          final bestMin = scorer.score(minProf).first;
          expect(bestMin.tonic, tonic, reason: 'Failed for ${profileSet.label} tonic $tonic Minor');
          expect(bestMin.major, isFalse);
          expect((bestMin.r - 1.0).abs(), lessThan(1e-4));
        }
      }
    });

    test('2. Refrão com Bm e G: Temperley acha Ré Maior; Krumhansl dá Fá# Menor', () {
      final scorerTemperley = KeyScorer(profiles: ProfileSet.temperley);
      final scorerKrumhansl = KeyScorer(profiles: ProfileSet.krumhansl);

      final topTemperley = scorerTemperley.score(refraoA).first;
      final topKrumhansl = scorerKrumhansl.score(refraoA).first;

      expect(topTemperley.label, 'D Maior');
      expect(topKrumhansl.label, 'F# Menor');
    });

    test('3. Só refrão (F#m e A): nenhum perfil acha Ré Maior em primeiro', () {
      for (final profileSet in ProfileSet.values) {
        final scorer = KeyScorer(profiles: profileSet);
        final top = scorer.score(refraoB).first;
        expect(top.label != 'D Maior', isTrue,
            reason: '${profileSet.label} não deveria colocar Ré em 1º só com F#m e A');
        expect(top.label == 'A Maior' || top.label == 'F# Menor', isTrue);
      }
    });

    test('4. Verso (D G A D): todos os conjuntos dão Ré maior em primeiro', () {
      for (final profileSet in ProfileSet.values) {
        final scorer = KeyScorer(profiles: profileSet);
        final top = scorer.score(verso).first;
        expect(top.label, 'D Maior',
            reason: '${profileSet.label} deveria identificar Ré maior no verso');
      }
    });

    test('4b. Menor natural (3.4.4): baladaEbm favorece Ebm em Aarden/Krumhansl e empata em Temperley', () {
      final scorerAarden = KeyScorer(profiles: ProfileSet.aarden);
      final scorerKrumhansl = KeyScorer(profiles: ProfileSet.krumhansl);
      final scorerTemperley = KeyScorer(profiles: ProfileSet.temperley);

      final scoresAarden = scorerAarden.score(baladaEbm);
      expect(scoresAarden.first.tonic, 3);
      expect(scoresAarden.first.major, isFalse);
      expect(scoresAarden[0].r - scoresAarden[1].r, greaterThanOrEqualTo(0.10));

      final scoresKrumhansl = scorerKrumhansl.score(baladaEbm);
      expect(scoresKrumhansl.first.tonic, 3);
      expect(scoresKrumhansl.first.major, isFalse);
      expect(scoresKrumhansl[0].r - scoresKrumhansl[1].r, greaterThanOrEqualTo(0.10));

      final scoresTemperley = scorerTemperley.score(baladaEbm);
      expect(scoresTemperley.first.tonic, 3);
      expect(scoresTemperley.first.major, isFalse);
      expect((scoresTemperley[0].r - scoresTemperley[1].r).abs(), lessThan(0.01));

      // Sem ênfase na tônica, os perfis clássicos dão Sol♭ maior (tonic 6, major):
      for (final profileSet in [ProfileSet.krumhansl, ProfileSet.temperley, ProfileSet.aarden]) {
        final top = KeyScorer(profiles: profileSet).score(baladaSemEnfase).first;
        expect(top.tonic, 6);
        expect(top.major, isTrue);
      }
    });

    test('5. Perfil aardenMinorB7 e ProfileSet.aardenB7 estrutura básica', () {
      expect(aardenMinorB7[10], equals(15.0));
      for (var i = 0; i < 12; i++) {
        if (i != 10) {
          expect(aardenMinorB7[i], equals(aardenMinor[i]));
        }
      }
      expect(ProfileSet.aardenB7.code, equals('aar_b7'));
      expect(ProfileSet.aardenB7.major, equals(aardenMajor));
      expect(ProfileSet.aardenB7.minor, equals(aardenMinorB7));
    });

    test('5a. Laço Bm-G-D-A: aar/aar dá Ré; aar/aar_b7 dá Si m', () {
      // Dó♯ 1, Ré 3, Mi 1, Fá♯ 2, Sol 1, Lá 2, Si 2
      final vec5a = [0.0, 1.0, 3.0, 0.0, 1.0, 0.0, 2.0, 1.0, 0.0, 2.0, 0.0, 2.0];
      final scorerAar = KeyScorer(profiles: ProfileSet.aarden, minorProfiles: ProfileSet.aarden);
      final scorerAarB7 = KeyScorer(profiles: ProfileSet.aarden, minorProfiles: ProfileSet.aardenB7);

      final topAar = scorerAar.score(vec5a).first;
      expect(topAar.label, equals('D Maior'));
      expect(topAar.r, closeTo(0.861, 0.01));

      final scoresAarB7 = scorerAarB7.score(vec5a);
      final topAarB7 = scoresAarB7.first;
      expect(topAarB7.label, equals('B Menor'));
      expect(topAarB7.r, closeTo(0.897, 0.01));
      final dMajScore = scoresAarB7.firstWhere((k) => k.label == 'D Maior');
      expect(dMajScore.r, closeTo(0.861, 0.01));
    });

    test('5b. Dó maior com tônica reforçada: Dó em ambos', () {
      // Dó 3, Ré 1, Mi 2, Fá 1, Sol 2, Lá 1, Si 1
      final vec5b = [3.0, 0.0, 1.0, 0.0, 2.0, 1.0, 0.0, 2.0, 0.0, 1.0, 0.0, 1.0];
      final scorerAar = KeyScorer(profiles: ProfileSet.aarden, minorProfiles: ProfileSet.aarden);
      final scorerAarB7 = KeyScorer(profiles: ProfileSet.aarden, minorProfiles: ProfileSet.aardenB7);

      expect(scorerAar.score(vec5b).first.label, equals('C Maior'));

      final scoresAarB7 = scorerAarB7.score(vec5b);
      expect(scoresAarB7.first.label, equals('C Maior'));
      expect(scoresAarB7.first.r, closeTo(0.905, 0.01));
      final aMinScore = scoresAarB7.firstWhere((k) => k.label == 'A Menor');
      expect(aMinScore.r, closeTo(0.831, 0.01));
    });

    test('5c. Limitação documentada: C-G-Am-F tem mesmo vetor que Am-G-C-F; aar_b7 dá Lá m', () {
      // Dó 3, Ré 1, Mi 2, Fá 1, Sol 2, Lá 2, Si 1
      // Laço Dó-Sol-Lá m-Fá com tempos iguais sem ênfase na tônica é lido como o relativo menor
      final vec5c = [3.0, 0.0, 1.0, 0.0, 2.0, 1.0, 0.0, 2.0, 0.0, 2.0, 0.0, 1.0];
      final scorerAarB7 = KeyScorer(profiles: ProfileSet.aarden, minorProfiles: ProfileSet.aardenB7);
      expect(scorerAarB7.score(vec5c).first.label, equals('A Menor'));
    });

    test('5d. Lá menor com sensível: Lá m em ambos', () {
      // Lá 3, Dó 2, Mi 3, Sol♯ 1, Si 1, Ré 1, Fá 1
      final vec5d = [2.0, 0.0, 1.0, 0.0, 3.0, 1.0, 0.0, 0.0, 1.0, 3.0, 0.0, 1.0];
      final scorerAar = KeyScorer(profiles: ProfileSet.aarden, minorProfiles: ProfileSet.aarden);
      final scorerAarB7 = KeyScorer(profiles: ProfileSet.aarden, minorProfiles: ProfileSet.aardenB7);

      expect(scorerAar.score(vec5d).first.label, equals('A Menor'));
      expect(scorerAarB7.score(vec5d).first.label, equals('A Menor'));
    });

    test('6. KeyCandidate.relative calcula o relativo direto (maior +9 menor, menor +3 maior)', () {
      const cMaj = KeyCandidate(0, true, 1.0);
      expect(cMaj.relative.label, equals('A Menor'));
      expect(cMaj.relative.relative.label, equals('C Maior'));

      const aMin = KeyCandidate(9, false, 1.0);
      expect(aMin.relative.label, equals('C Maior'));

      const dMaj = KeyCandidate(2, true, 1.0);
      expect(dMaj.relative.label, equals('B Menor'));

      const ebMin = KeyCandidate(3, false, 1.0);
      expect(ebMin.relative.label, equals('Gb Maior'));

      const ebMaj = KeyCandidate(3, true, 1.0);
      expect(ebMaj.relative.label, equals('C Menor'));
    });
  });
}
