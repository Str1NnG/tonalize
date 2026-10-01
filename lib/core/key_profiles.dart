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

/// Krumhansl-Kessler (1982/1990), em Dó. Índice 0 = tônica.
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

/// Temperley-Kostka-Payne (Temperley, 2007), derivados de um corpus de exemplos de harmonia.
const List<double> temperleyKPMajor = [
  0.748,
  0.060,
  0.488,
  0.082,
  0.670,
  0.460,
  0.096,
  0.715,
  0.104,
  0.366,
  0.057,
  0.400
];
const List<double> temperleyKPMinor = [
  0.712,
  0.084,
  0.474,
  0.618,
  0.049,
  0.460,
  0.105,
  0.747,
  0.404,
  0.067,
  0.133,
  0.330
];

/// Aarden-Essen (Aarden, 2003), derivados da coleção de canções folclóricas de Essen.
/// Diferença enorme entre notas da escala (>= 4.95) e de fora (<= 0.29): quase um teste de pertinência à escala.
const List<double> aardenMajor = [
  17.7661,
  0.145624,
  14.9265,
  0.160186,
  19.8049,
  11.3587,
  0.291248,
  22.062,
  0.145624,
  8.15494,
  0.232998,
  4.95122
];
const List<double> aardenMinor = [
  18.2648,
  0.737619,
  14.0499,
  16.8599,
  0.702494,
  14.4362,
  0.702494,
  18.6161,
  4.56621,
  1.93186,
  7.37619,
  1.75623
];

/// Aarden-Essen com a 7ª menor (b7) reforçada (índice 10 = 15.0).
/// Resolve músicas no modo menor natural que usam o acorde VII ou b7 melódico.
const List<double> aardenMinorB7 = [
  18.2648,
  0.737619,
  14.0499,
  16.8599,
  0.702494,
  14.4362,
  0.702494,
  18.6161,
  4.56621,
  1.93186,
  15.0,
  1.75623
];

enum ProfileSet { krumhansl, temperley, temperleyKP, aarden, aardenB7 }

extension ProfileSetData on ProfileSet {
  List<double> get major => switch (this) {
        ProfileSet.krumhansl => kkMajor,
        ProfileSet.temperley => temperleyMajor,
        ProfileSet.temperleyKP => temperleyKPMajor,
        ProfileSet.aarden => aardenMajor,
        ProfileSet.aardenB7 => aardenMajor,
      };

  List<double> get minor => switch (this) {
        ProfileSet.krumhansl => kkMinor,
        ProfileSet.temperley => temperleyMinor,
        ProfileSet.temperleyKP => temperleyKPMinor,
        ProfileSet.aarden => aardenMinor,
        ProfileSet.aardenB7 => aardenMinorB7,
      };

  /// Código curto para a coluna `config` das leituras.
  String get code => switch (this) {
        ProfileSet.krumhansl => 'kk',
        ProfileSet.temperley => 'tmp',
        ProfileSet.temperleyKP => 'tkp',
        ProfileSet.aarden => 'aar',
        ProfileSet.aardenB7 => 'aar_b7',
      };

  String get label => switch (this) {
        ProfileSet.krumhansl => 'Krumhansl-Kessler',
        ProfileSet.temperley => 'Temperley (1999)',
        ProfileSet.temperleyKP => 'Temperley-Kostka-Payne',
        ProfileSet.aarden => 'Aarden-Essen',
        ProfileSet.aardenB7 => 'Aarden-Essen (b7)',
      };
}

/// Perfil da tonalidade cuja tônica é [tonic]: rotação circular. profile[tonic] recebe base[0].
List<double> rotated(List<double> base, int tonic) =>
    List<double>.generate(12, (j) => base[(j - tonic + 12) % 12]);

class KeyCandidate {
  final int tonic; // 0..11
  final bool major;
  final double r; // correlação de Pearson com o perfil observado

  const KeyCandidate(this.tonic, this.major, this.r);

  String get name {
    if (major) {
      return switch (tonic) {
        1 => 'Db',
        3 => 'Eb',
        6 => 'Gb',
        8 => 'Ab',
        10 => 'Bb',
        _ => noteNames[tonic],
      };
    } else {
      return switch (tonic) {
        3 => 'Eb',
        10 => 'Bb',
        _ => noteNames[tonic],
      };
    }
  }
  String get mode => major ? 'Maior' : 'Menor';
  String get label => '$name $mode';
  String get shortLabel => '$name${major ? "" : "m"}';

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
