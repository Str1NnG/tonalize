import 'key_evidence.dart';
import 'key_profiles.dart';

class Challenge {
  final KeyCandidate key;
  final Duration since;
  final Duration hold;

  const Challenge(this.key, this.since, this.hold);

  double progress(Duration now) =>
      ((now - since).inMilliseconds / hold.inMilliseconds).clamp(0.0, 1.0);
}

class KeyStabilizer {
  KeyStabilizer({
    this.minSeconds = 2.0, // áudio mínimo antes da primeira exibição
    this.baseMargin = 0.05, // desafiante distante: vencer por 0,05 durante 4 s
    this.baseHoldSeconds = 4.0,
    this.neighborMargin = 0.08, // desafiante vizinho (quinta, relativa, paralela): 0,08 durante 6 s
    this.neighborHoldSeconds = 6.0,
    this.requireNewNotes = false,
    this.evidenceTolerance = 0.8,
    this.evidenceFloor = 0.25,
  });

  final double minSeconds;
  final double baseMargin;
  final double baseHoldSeconds;
  final double neighborMargin;
  final double neighborHoldSeconds;
  final bool requireNewNotes;
  final double evidenceTolerance;
  final double evidenceFloor;

  KeyCandidate? displayed;
  Challenge? challenge;
  int switches = 0; // trocas do letreiro desde o último reset (métrica "trocas por minuto")

  /// [scores]: as 24 candidatas ordenadas por r decrescente.
  /// [profile] é o perfil que gerou [scores]; só é usado quando requireNewNotes = true.
  void update(Duration now, List<KeyCandidate> scores, double secondsInWindow,
      {List<double>? profile}) {
    if (scores.isEmpty) return;
    final best = scores.first;
    if (displayed == null) {
      if (secondsInWindow >= minSeconds) displayed = best;
      return;
    }
    if (best.sameKey(displayed)) {
      challenge = null;
      return;
    }
    final rDisplayed = scores.firstWhere((c) => c.sameKey(displayed)).r;
    final neighbor = isNeighbor(displayed!, best);
    final margin = neighbor ? neighborMargin : baseMargin;
    final hold = Duration(
        milliseconds:
            ((neighbor ? neighborHoldSeconds : baseHoldSeconds) * 1000).round());
    if (best.r - rDisplayed < margin) {
      challenge = null;
      return;
    } // vantagem insuficiente: sem desafio

    // Modo estrito da Fase 5: sem nota nova, recusa desafiante vizinho
    if (requireNewNotes &&
        neighbor &&
        profile != null &&
        !newNoteEvidence(displayed!, best, profile,
            tolerance: evidenceTolerance, floorFraction: evidenceFloor)) {
      challenge = null;
      return;
    }

    if (challenge == null || !challenge!.key.sameKey(best)) {
      // novo desafio começa a contar
      challenge = Challenge(best, now, hold);
      return;
    }
    if (now - challenge!.since >= hold) {
      // sustentou a vantagem: troca
      displayed = best;
      switches++;
      challenge = null;
    }
  }

  void reset() {
    displayed = null;
    challenge = null;
    switches = 0;
  }

  /// Tons vizinhos (no máximo um acidente de diferença) e o paralelo.
  /// Maior: V, IV, vi, iii, ii e o menor paralelo. Menor: III, v, iv, VI, VII e o maior paralelo.
  static bool isNeighbor(KeyCandidate a, KeyCandidate b) {
    final d = (b.tonic - a.tonic + 12) % 12;
    if (a.major == b.major) return d == 7 || d == 5;
    if (d == 0) return true;
    return a.major
        ? (d == 9 || d == 4 || d == 2)
        : (d == 3 || d == 8 || d == 10);
  }
}
