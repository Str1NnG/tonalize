import 'package:keyfinder/core/tonal_engine.dart';

/// Tríade como perfil de 12 notas: fundamental 1,0, terça 0,8, quinta 0,8; normalizado para soma 1.
List<double> tri(int root, int third, int fifth) {
  final c = List<double>.filled(12, 0);
  c[root % 12] += 1.0;
  c[third % 12] += 0.8;
  c[fifth % 12] += 0.8;
  final s = c.reduce((a, b) => a + b);
  return [for (final v in c) v / s];
}

/// Tétrade (para o F♯7, C♯7, E7): fundamental 1,0, demais 0,8.
List<double> tetra(int root, int third, int fifth, int seventh) {
  final c = List<double>.filled(12, 0);
  c[root % 12] += 1.0;
  c[third % 12] += 0.8;
  c[fifth % 12] += 0.8;
  c[seventh % 12] += 0.8;
  final s = c.reduce((a, b) => a + b);
  return [for (final v in c) v / s];
}

final dMaj = tri(2, 6, 9), gMaj = tri(7, 11, 2), aMaj = tri(9, 1, 4), bMin = tri(11, 2, 6);
final fSharpMin = tri(6, 9, 1), eMin = tri(4, 7, 11), eMaj = tri(4, 8, 11), cMaj = tri(0, 4, 7);
final ebMaj = tri(3, 7, 10), abMaj = tri(8, 0, 3), bbMaj = tri(10, 2, 5);
final fSharp7 = tetra(6, 10, 1, 4);
final cSharp7 = tetra(1, 5, 8, 11); // C♯ E♯ G♯ B — dominante de Fá♯ menor
final eSete = tetra(4, 8, 11, 2); // E G♯ B D — dominante de Lá maior
final ebMin = tri(3, 6, 10),
    bMaj = tri(11, 3, 6),
    gbMaj = tri(6, 10, 1),
    dbMaj = tri(1, 5, 8),
    abMin = tri(8, 11, 3);
final baladaEbm = mix([(ebMin, 4), (bMaj, 1), (gbMaj, 1), (dbMaj, 1), (abMin, 1)]);
final baladaSemEnfase = mix([(ebMin, 1), (bMaj, 1), (gbMaj, 1), (dbMaj, 1)]);

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
final refraoASeq = [(fSharpMin, 1.0), (bMin, 0.5), (gMaj, 0.5), (aMaj, 1.0)];
final ebSeq = [(ebMaj, 1.0), (abMaj, 0.5), (bbMaj, 0.5), (ebMaj, 1.0)];
final gComDoSeq = [(gMaj, 1.0), (cMaj, 0.5), (dMaj, 0.5), (gMaj, 1.0)]; // Sol maior de verdade (traz o Dó)
final gSemDoSeq = [(gMaj, 1.0), (eMin, 0.5), (dMaj, 0.5), (gMaj, 1.0)]; // sem nota nova: indecidível pelas notas
final aComMiSeq = [(aMaj, 1.0), (dMaj, 0.5), (eMaj, 0.5), (aMaj, 1.0)]; // Lá maior de verdade (traz o Sol♯)
final bmSeq = [(bMin, 1.0), (gMaj, 0.5), (fSharp7, 0.5), (bMin, 1.0)]; // Si menor com sensível (Lá♯)
final introGSeq = [(gMaj, 1.0), (eMin, 1.0)];

class FeedResult {
  final TonalReading? reading;
  final List<(double, MemoryEvent)> timedEvents;
  final List<(double, KeyCandidate?, KeyCandidate?, double)> timeline;

  const FeedResult({
    required this.reading,
    required this.timedEvents,
    required this.timeline,
  });

  List<MemoryEvent> get events => timedEvents.map((e) => e.$2).toList();
  bool hasEvent(MemoryEvent e) => events.contains(e);
}

/// Alimenta o motor com o padrão em ciclos a cada 0.5 s.
FeedResult feed(
  TonalEngine engine,
  List<(List<double>, double)> pattern,
  double seconds, {
  double start = 0,
}) {
  final cycleDuration = pattern.map((p) => p.$2).reduce((a, b) => a + b);
  TonalReading? lastReading;
  final timedEvents = <(double, MemoryEvent)>[];
  final timeline = <(double, KeyCandidate?, KeyCandidate?, double)>[];

  final steps = (seconds / 0.5).round();
  for (var i = 1; i <= steps; i++) {
    final t = i * 0.5;
    final pos = ((t - 0.25) % cycleDuration);
    var acc = 0.0;
    List<double> chord = pattern.first.$1;
    for (final p in pattern) {
      acc += p.$2;
      if (pos < acc) {
        chord = p.$1;
        break;
      }
    }
    final nowSeconds = start + t;
    final tDuration = Duration(milliseconds: (nowSeconds * 1000).round());
    engine.addFrame(chord, tDuration);
    final r = engine.evaluate(tDuration);
    if (r != null) {
      lastReading = r;
      timeline.add((nowSeconds, r.passage, r.displayed, r.evidenceSeconds));
      if (r.event != MemoryEvent.none) {
        timedEvents.add((nowSeconds, r.event));
      }
    }
  }
  return FeedResult(
    reading: lastReading,
    timedEvents: timedEvents,
    timeline: timeline,
  );
}

FeedResult feedSilence(
  TonalEngine engine,
  double seconds, {
  double start = 0,
}) {
  TonalReading? lastReading;
  final timedEvents = <(double, MemoryEvent)>[];
  final timeline = <(double, KeyCandidate?, KeyCandidate?, double)>[];

  final steps = (seconds / 0.5).round();
  for (var i = 1; i <= steps; i++) {
    final t = i * 0.5;
    final nowSeconds = start + t;
    final tDuration = Duration(milliseconds: (nowSeconds * 1000).round());
    final r = engine.evaluate(tDuration);
    if (r != null) {
      lastReading = r;
      timeline.add((nowSeconds, r.passage, r.displayed, r.evidenceSeconds));
      if (r.event != MemoryEvent.none) {
        timedEvents.add((nowSeconds, r.event));
      }
    }
  }
  return FeedResult(
    reading: lastReading,
    timedEvents: timedEvents,
    timeline: timeline,
  );
}

