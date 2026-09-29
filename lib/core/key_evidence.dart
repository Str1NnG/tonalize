import 'key_profiles.dart';

/// Escala de cada tom como conjunto de classes de altura, para a EVIDÊNCIA (a pontuação usa os perfis).
/// Menor = natural + 6ª elevada + 7ª elevada (9 notas): a sensível, porque a dominante com sensível é a forma
/// mais comum de confirmar um tom menor; e a 6ª elevada porque o IV grau maior (Lá♭ maior em Mi♭ menor, com
/// Dó natural) é cor corrente do gospel e da música popular em tom menor — sem ela, esse Dó natural contaria
/// como "nota nova" de Ré♭ maior e promoveria o VII grau como tom novo (3.5).
const _major = {0, 2, 4, 5, 7, 9, 11};
const _minor = {0, 2, 3, 5, 7, 8, 9, 10, 11};
Set<int> scaleOf(KeyCandidate k) =>
    {for (final d in (k.major ? _major : _minor)) (k.tonic + d) % 12};

/// As notas novas que [candidate] pede em relação a [current]. O que decide é sempre o par (tom atual, candidato):
///
///   newNotesOf(Ré, Lá)      = {G♯}       → o G♯ basta: a armadura mudou (2 → 3 sustenidos).
///   newNotesOf(Ré, Fá♯m)    = {G♯, E♯}   → o G♯ basta (maxOf): a armadura mudou; o E♯ é extra. Confirmar Fá♯ menor
///                                          a partir de RÉ sem o E♯ é intencional — numa região Fá♯m–D–A–E (menor
///                                          natural, comuníssima) exigir o E♯ deixaria o letreiro preso em Ré com a
///                                          armadura já em 3 sustenidos.
///   newNotesOf(Lá, Fá♯m)    = {E♯}       → entre relativos, só a sensível distingue: a partir de LÁ, Fá♯ menor
///                                          exige o E♯ (acorde de C♯7).
///   newNotesOf(Fá♯m, Lá)    = {}         → do menor para o relativo maior não há nota nova (o menor de 8 notas já
///                                          contém tudo): sem evidência possível, só o esquecimento ou o botão.
///   newNotesOf(Ré, Si m)    = {A♯}       → idem: a partir de Ré, Si menor exige a sensível.
///
/// A assimetria entre relativos é desejada: o padrão mais comum da música popular é verso no relativo menor e
/// refrão no maior, sem sensível — e nele o letreiro NÃO deve mudar. O custo é o medley para o relativo sem
/// sensível (Ré → música em Si menor só com Bm, G, D, A): o letreiro fica em Ré, a linha "agora" mostra Si menor,
/// e a resposta é o botão "Nova música". Fica registrado como limitação.
Set<int> newNotesOf(KeyCandidate current, KeyCandidate candidate) =>
    scaleOf(candidate).difference(scaleOf(current));

/// Há evidência de que [candidate] é um tom novo, e não só ênfase dentro da escala de [current]?
/// Compara a nota mais forte entre as que só existem na escala nova com a nota mais forte entre as que
/// só existem na escala atual. Ré→Lá: Sol♯ contra Sol. Ré→Sol: Dó contra Dó♯. Ré→Si menor: Lá♯ contra nada,
/// porque o Lá natural pertence às duas escalas (é o 7º grau natural do Si menor, presente no acorde de Lá
/// maior que o Si menor popular usa o tempo todo) — aí vale o piso: Lá♯ precisa ter ao menos 25% da energia
/// média. Se a escala nova não traz nota nenhuma (não acontece com os vizinhos definidos acima), não há como
/// haver evidência.
bool newNoteEvidence(
  KeyCandidate current,
  KeyCandidate candidate,
  List<double> profile, {
  double tolerance = 0.8,
  double floorFraction = 0.25,
}) {
  final a = scaleOf(current), b = scaleOf(candidate);
  final onlyNew = b.difference(a), onlyOld = a.difference(b);
  if (onlyNew.isEmpty) return false;
  double maxOf(Set<int> s) =>
      s.fold(0.0, (m, i) => profile[i] > m ? profile[i] : m);
  final mean = profile.reduce((x, y) => x + y) / 12;
  final reference = maxOf(onlyOld) > floorFraction * mean
      ? maxOf(onlyOld)
      : floorFraction * mean;
  return maxOf(onlyNew) >= tolerance * reference;
}
