import 'key_profiles.dart';

// lib/core/key_evidence.dart — v3.6
const _major = {0, 2, 4, 5, 7, 9, 11};
const _minorNatural = {0, 2, 3, 5, 7, 8, 10};
const _minorRaised = {9, 11}; // 6ª e 7ª elevadas

Set<int> _rot(Set<int> s, int tonic) => {for (final d in s) (tonic + d) % 12};
Set<int> naturalScaleOf(KeyCandidate k) =>
    _rot(k.major ? _major : _minorNatural, k.tonic);
Set<int> raisedOf(KeyCandidate k) =>
    k.major ? const <int>{} : _rot(_minorRaised, k.tonic);

/// 7 notas para maior, 9 para menor — igual à 3.5. É a escala usada para o tom ATUAL.
Set<int> scaleOf(KeyCandidate k) => naturalScaleOf(k).union(raisedOf(k));

/// Notas que [candidate] pede e [current] não tem. Inalterado em relação à 3.5.
Set<int> newNotesOf(KeyCandidate current, KeyCandidate candidate) =>
    scaleOf(candidate).difference(scaleOf(current));

/// Notas novas DIATÔNICAS de [candidate] — as que mudam a armadura. Só estas carregam
/// evidência de um desafiante para outro (fase 3).
Set<int> diatonicNewNotesOf(KeyCandidate current, KeyCandidate candidate) =>
    naturalScaleOf(candidate).difference(scaleOf(current));

/// Nota(s) da escala atual que a nota nova [n] desloca:
///   elevada (6ª/7ª de um menor) → o meio-tom abaixo: Dó♯←Dó, Ré♯←Ré, Mi♯←Mi;
///   diatônica → a nota que sai da escala, se for vizinha de meio-tom: Fá♯←Fá (Dó→Sol),
///               Fá←Fá♯ (Sol→Lá m), Ré←Ré♯ (Mi→Fá♯ m), Sol♯←Sol (Ré→Lá).
Set<int> displacedBy(int n, KeyCandidate current, KeyCandidate candidate) {
  if (raisedOf(candidate).contains(n)) return {(n + 11) % 12};
  final leaving = naturalScaleOf(current).difference(naturalScaleOf(candidate));
  return {
    for (final m in [(n + 11) % 12, (n + 1) % 12])
      if (leaving.contains(m)) m
  };
}

/// Há evidência de que [candidate] é um tom novo? Verdadeiro se ALGUMA nota nova tem
/// energia ≥ tolerance × max(energia da nota que ela desloca, piso).
bool newNoteEvidence(
  KeyCandidate current,
  KeyCandidate candidate,
  List<double> profile, {
  double tolerance = 0.8,
  double floorFraction = 0.25,
}) {
  final onlyNew = newNotesOf(current, candidate);
  if (onlyNew.isEmpty) return false;
  final floor = floorFraction * (profile.reduce((x, y) => x + y) / 12);
  for (final n in onlyNew) {
    var reference = floor;
    for (final d in displacedBy(n, current, candidate)) {
      if (profile[d] > reference) reference = profile[d];
    }
    if (profile[n] >= tolerance * reference) return true;
  }
  return false;
}
