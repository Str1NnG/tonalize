/// Tríade como perfil de 12 notas: fundamental 1,0, terça 0,8, quinta 0,8; normalizado para soma 1.
List<double> tri(int root, int third, int fifth) {
  final c = List<double>.filled(12, 0);
  c[root % 12] += 1.0;
  c[third % 12] += 0.8;
  c[fifth % 12] += 0.8;
  final s = c.reduce((a, b) => a + b);
  return [for (final v in c) v / s];
}

final dMaj = tri(2, 6, 9);
final gMaj = tri(7, 11, 2);
final aMaj = tri(9, 1, 4);
final bMin = tri(11, 2, 6);
final fSharpMin = tri(6, 9, 1);
final eMin = tri(4, 7, 11);
final ebMaj = tri(3, 7, 10);
final abMaj = tri(8, 0, 3);
final bbMaj = tri(10, 2, 5);

/// Soma ponderada de acordes: [(acorde, peso)].
List<double> mix(List<(List<double>, double)> parts) {
  final c = List<double>.filled(12, 0);
  for (final (p, w) in parts) {
    for (var i = 0; i < 12; i++) {
      c[i] += w * p[i];
    }
  }
  final s = c.reduce((a, b) => a + b);
  return [for (final v in c) v / s];
}

final verso = mix([(dMaj, 2), (gMaj, 1), (aMaj, 1), (dMaj, 2)]); // D G A D
final refraoA = mix([(fSharpMin, 2), (bMin, 1), (gMaj, 1), (aMaj, 2)]); // F#m Bm G A
final refraoB = mix([(fSharpMin, 2), (aMaj, 2)]); // F#m A

final versoSeq = [(dMaj, 1.0), (gMaj, 0.5), (aMaj, 0.5), (dMaj, 1.0)];
final refraoBSeq = [(fSharpMin, 1.0), (aMaj, 1.0)];
final ebSeq = [(ebMaj, 1.0), (abMaj, 0.5), (bbMaj, 0.5), (ebMaj, 1.0)];
final gSeq = [(gMaj, 1.0), (eMin, 0.5), (dMaj, 0.5), (gMaj, 1.0)];
