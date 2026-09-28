import 'dart:math' as math;

/// Nomes das notas no padrão das cifras (C, C#, D ...).
const List<String> noteNames = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B'
];

/// Perfis de Krumhansl-Kessler (Krumhansl, 1990), em Dó. Índice 0 = tônica.
const List<double> kkMajor = [
  6.35,
  2.23,
  3.48,
  2.33,
  4.38,
  4.09,
  2.52,
  5.19,
  2.39,
  3.66,
  2.29,
  2.88
];
const List<double> kkMinor = [
  6.33,
  2.68,
  3.52,
  5.38,
  2.60,
  3.53,
  2.54,
  4.75,
  3.98,
  2.69,
  3.34,
  3.17
];

/// Perfis de Temperley (1999), alternativa aos de Krumhansl-Kessler para a calibração.
const List<double> temperleyMajor = [
  5.0,
  2.0,
  3.5,
  2.0,
  4.5,
  4.0,
  2.0,
  4.5,
  2.0,
  3.5,
  1.5,
  4.0
];
const List<double> temperleyMinor = [
  5.0,
  2.0,
  3.5,
  4.5,
  2.0,
  4.0,
  2.0,
  4.5,
  3.5,
  2.0,
  1.5,
  4.0
];

enum ProfileSet { krumhansl, temperley }

/// Perfil da tonalidade cuja tônica é [tonic]: rotação circular. profile[tonic] recebe base[0].
List<double> rotated(List<double> base, int tonic) =>
    List<double>.generate(12, (j) => base[(j - tonic + 12) % 12]);

class KeyCandidate {
  final int tonic; // 0..11
  final bool major;
  final double r; // correlação de Pearson com o perfil observado

  const KeyCandidate(this.tonic, this.major, this.r);

  String get name => noteNames[tonic];
  String get mode => major ? 'Maior' : 'Menor';
  String get label => '$name $mode';

  bool sameKey(KeyCandidate? o) =>
      o != null && o.tonic == tonic && o.major == major;

  @override
  String toString() => 'KeyCandidate($label, r=$r)';
}

/// Correlação de Pearson entre dois vetores de 12 posições. Retorna 0 se algum for constante.
double pearson(List<double> x, List<double> y) {
  final n = x.length;
  double sx = 0, sy = 0, sxx = 0, syy = 0, sxy = 0;
  for (var i = 0; i < n; i++) {
    sx += x[i];
    sy += y[i];
    sxx += x[i] * x[i];
    syy += y[i] * y[i];
    sxy += x[i] * y[i];
  }
  final den = (n * sxx - sx * sx) * (n * syy - sy * sy);
  if (den <= 0) return 0.0;
  return (n * sxy - sx * sy) / math.sqrt(den);
}
