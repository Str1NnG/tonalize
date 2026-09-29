import 'dart:math' as math;
import 'chroma_accumulator.dart';
import 'key_profiles.dart';
import 'key_scorer.dart';
import 'key_stabilizer.dart';

export 'chroma_accumulator.dart';
export 'key_profiles.dart';
export 'key_scorer.dart';
export 'key_stabilizer.dart';

enum MemoryEvent { none, silenceReset, farReset, nearReset, manualReset }

class SongMemoryConfig {
  const SongMemoryConfig({
    this.enabled = true,
    this.windowSeconds = 240, // teto da memória da música
    this.halfLifeSeconds = 60, // o que soou há 1 min pesa metade
    this.silenceResetSeconds = 6, // pausa entre músicas
    this.followPassageSeconds = 30, // memória jovem (início ou pós-reinício) segue o trecho
    this.farResetSeconds = 12, // trecho num tom distante por 12 s -> a música mudou: reinicia a partir do trecho
    this.nearResetSeconds = 45, // trecho num tom vizinho por 45 s -> idem (0 = nunca)
    this.baseHoldSeconds = 20, // regra própria da memória da música: lenta de propósito
    this.neighborHoldSeconds = 30,
    this.showPassageAfterSeconds = 4, // linha "agora" aparece após 4 s de discordância
  });

  final bool enabled;
  final double windowSeconds;
  final double halfLifeSeconds;
  final double silenceResetSeconds;
  final double followPassageSeconds;
  final double farResetSeconds;
  final double nearResetSeconds;
  final double baseHoldSeconds;
  final double neighborHoldSeconds;
  final double showPassageAfterSeconds;
}

class TonalReading {
  final KeyCandidate? displayed; // o que o letreiro mostra
  final KeyCandidate best; // vencedor bruto desta avaliação
  final KeyCandidate second; // melhor candidata diferente da exibida (2ª opção)
  final List<KeyCandidate> nearby; // as 3 melhores diferentes da exibida ("tons próximos")
  final double confidence; // (r da exibida - r da melhor outra) / fullConfidenceGap, 0..1
  final List<double> profile; // 12 valores normalizados para máximo 1 (barras)
  final Challenge? challenge; // desafio em andamento, para o indicador "confirmando..."
  final double secondsInWindow;
  final bool autoReset; // true na avaliação em que houve reinício por silêncio
  final KeyCandidate? passage; // tom do trecho (memória curta); null enquanto o trecho não tem leitura
  final bool showPassage; // trecho discorda da música há >= showPassageAfterSeconds
  final MemoryEvent event; // o que aconteceu nesta avaliação
  final double songSeconds; // segundos de áudio na memória da música

  const TonalReading({
    this.displayed,
    required this.best,
    required this.second,
    required this.nearby,
    required this.confidence,
    required this.profile,
    this.challenge,
    required this.secondsInWindow,
    this.autoReset = false,
    this.passage,
    this.showPassage = false,
    this.event = MemoryEvent.none,
    this.songSeconds = 0.0,
  });
}

class TonalEngine {
  TonalEngine({
    ChromaAccumulator? passage,
    KeyStabilizer? passageStabilizer,
    KeyScorer? scorer,
    this.songConfig = const SongMemoryConfig(),
    this.fullConfidenceGap = 0.25,
  })  : passage = passage ?? ChromaAccumulator(),
        passageStabilizer = passageStabilizer ?? KeyStabilizer(),
        scorer = scorer ?? KeyScorer() {
    song = ChromaAccumulator(
      windowSeconds: songConfig.windowSeconds,
      halfLifeSeconds: songConfig.halfLifeSeconds,
      silenceResetSeconds: songConfig.silenceResetSeconds,
      binSeconds: 1,
    );
    songStabilizer = KeyStabilizer(
      minSeconds: this.passageStabilizer.minSeconds,
      baseMargin: this.passageStabilizer.baseMargin,
      neighborMargin: this.passageStabilizer.neighborMargin,
      baseHoldSeconds: songConfig.baseHoldSeconds,
      neighborHoldSeconds: songConfig.neighborHoldSeconds,
      vetoByScaleNotes: this.passageStabilizer.vetoByScaleNotes,
      vetoTolerance: this.passageStabilizer.vetoTolerance,
    );
  }

  final ChromaAccumulator passage;
  final KeyStabilizer passageStabilizer;
  final KeyScorer scorer;
  final SongMemoryConfig songConfig;
  final double fullConfidenceGap;
  late final ChromaAccumulator song;
  late final KeyStabilizer songStabilizer;

  Duration? _farSince, _nearSince, _passageDiffersSince;
  MemoryEvent _pending = MemoryEvent.none;
  KeyCandidate? _lastLabel;
  int labelChanges = 0; // trocas do letreiro principal, qualquer que seja o mecanismo (métrica do experimento)

  TonalReading? _lastReading;
  TonalReading? get lastReading => _lastReading;
  KeyCandidate? get displayed =>
      songConfig.enabled ? songStabilizer.displayed : passageStabilizer.displayed;

  void addFrame(List<double> chroma, Duration at) {
    if (chroma.length != 12) return;
    if (passage.add(chroma, at)) passageStabilizer.reset();
    if (song.add(chroma, at)) {
      songStabilizer.reset();
      _clearTimers();
      _pending = MemoryEvent.silenceReset;
    }
  }

  TonalReading? evaluate(Duration now) {
    var event = _pending;
    _pending = MemoryEvent.none;

    // 1. trecho (igual ao plano 2)
    List<KeyCandidate>? pScores;
    List<double>? pProfile;
    if (passage.gapExceeded(now)) {
      passageStabilizer.reset();
    } else {
      pProfile = passage.profile(now);
      if (pProfile != null && !_isFlat(pProfile)) {
        pScores = scorer.score(pProfile);
        passageStabilizer.update(
          now,
          pScores,
          passage.secondsInWindow,
          profile: pProfile,
        );
      }
    }
    if (!songConfig.enabled) {
      if (pScores == null) return null;
      final reading = _reading(
        now,
        passageStabilizer,
        pScores,
        pProfile!,
        passage.secondsInWindow,
        event,
        passageStabilizer.displayed,
        false,
      );
      _lastReading = reading;
      return reading;
    }

    // 2. música
    List<KeyCandidate>? sScores;
    List<double>? sProfile;
    if (song.gapExceeded(now)) {
      songStabilizer.reset();
      _clearTimers();
      _lastReading = null;
      return null; // "Ouvindo..." como no plano 2
    }
    sProfile = song.profile(now);
    if (sProfile == null || _isFlat(sProfile)) {
      _lastReading = null;
      return null;
    }
    sScores = scorer.score(sProfile);
    if (song.secondsInWindow < songConfig.followPassageSeconds) {
      songStabilizer
        ..displayed = passageStabilizer.displayed
        ..challenge = null; // memória jovem segue o trecho
    } else {
      songStabilizer.update(
        now,
        sScores,
        song.secondsInWindow,
        profile: sProfile,
      );
    }

    // 3. reinícios por divergência entre trecho e música
    final p = passageStabilizer.displayed;
    final s = songStabilizer.displayed;
    if (p != null && s != null && !p.sameKey(s)) {
      _passageDiffersSince ??= now;
      if (KeyStabilizer.isNeighbor(s, p)) {
        _farSince = null;
        if (songConfig.nearResetSeconds > 0) {
          _nearSince ??= now;
          if (_secs(now, _nearSince!) >= songConfig.nearResetSeconds) {
            _reseed();
            event = MemoryEvent.nearReset;
          }
        }
      } else {
        _nearSince = null;
        _farSince ??= now;
        if (_secs(now, _farSince!) >= songConfig.farResetSeconds) {
          _reseed();
          event = MemoryEvent.farReset;
        }
      }
    } else {
      _clearTimers();
    }
    final showPassage = _passageDiffersSince != null &&
        _secs(now, _passageDiffersSince!) >= songConfig.showPassageAfterSeconds;

    final reading = _reading(
      now,
      songStabilizer,
      sScores,
      sProfile,
      song.secondsInWindow,
      event,
      passageStabilizer.displayed,
      showPassage,
    );
    _lastReading = reading;
    return reading;
  }

  void _reseed() {
    song.seedFrom(passage);
    songStabilizer
      ..displayed = passageStabilizer.displayed
      ..challenge = null;
    _clearTimers();
  }

  void _clearTimers() {
    _farSince = null;
    _nearSince = null;
    _passageDiffersSince = null;
  }

  double _secs(Duration now, Duration since) =>
      (now - since).inMilliseconds / 1000.0;

  bool _isFlat(List<double> profile) {
    final maxVal = profile.reduce(math.max);
    final minVal = profile.reduce(math.min);
    return maxVal <= 0 || (maxVal - minVal).abs() < 1e-6;
  }

  TonalReading _reading(
    Duration now,
    KeyStabilizer stab,
    List<KeyCandidate> scores,
    List<double> profile,
    double seconds,
    MemoryEvent event,
    KeyCandidate? passageKey,
    bool showPassage,
  ) {
    final displayed = stab.displayed;
    if ((displayed == null) != (_lastLabel == null) ||
        (displayed != null && !displayed.sameKey(_lastLabel))) {
      if (_lastLabel != null && displayed != null) labelChanges++;
      _lastLabel = displayed;
    }
    final ref = displayed ?? scores.first;
    final others = scores.where((c) => !c.sameKey(ref)).toList();
    final rRef = scores.firstWhere((c) => c.sameKey(ref)).r;
    final max = profile.reduce((a, b) => a > b ? a : b);
    return TonalReading(
      displayed: displayed,
      best: scores.first,
      second: others.isNotEmpty ? others.first : scores.first,
      nearby: others.take(3).toList(),
      confidence:
          ((rRef - (others.isNotEmpty ? others.first.r : 0.0)) / fullConfidenceGap)
              .clamp(0.0, 1.0),
      profile: [for (final v in profile) max > 0 ? v / max : 0.0],
      challenge: stab.challenge,
      secondsInWindow: seconds,
      autoReset: event == MemoryEvent.silenceReset,
      passage: passageKey,
      showPassage: showPassage,
      event: event,
      songSeconds: song.secondsInWindow,
    );
  }

  /// RF05 / botão "Nova música": descarta as duas memórias.
  void reset() {
    passage.clear();
    song.clear();
    passageStabilizer.reset();
    songStabilizer.reset();
    _clearTimers();
    _lastLabel = null;
    labelChanges = 0;
    _pending = MemoryEvent.manualReset;
    _lastReading = null;
  }

  int get switches => labelChanges; // mantém o nome usado pela tela
}
