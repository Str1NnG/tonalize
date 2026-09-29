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

      // Sem ênfase na tônica, todos dão Sol♭ maior (tonic 6, major):
      for (final profileSet in ProfileSet.values) {
        final top = KeyScorer(profiles: profileSet).score(baladaSemEnfase).first;
        expect(top.tonic, 6);
        expect(top.major, isTrue);
      }
    });
  });
}
