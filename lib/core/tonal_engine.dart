import 'dart:math' as math;
import 'chroma_accumulator.dart';
import 'key_evidence.dart';
import 'key_profiles.dart';
import 'key_scorer.dart';
import 'key_stabilizer.dart';

export 'chroma_accumulator.dart';
export 'key_evidence.dart';
export 'key_profiles.dart';
export 'key_scorer.dart';
export 'key_stabilizer.dart';

enum MemoryEvent {
  none,
  silenceReset,
  farKeyConfirmed,
  neighborKeyConfirmed,
  manualReset,
}

class SongMemoryConfig {
  const SongMemoryConfig({
    this.enabled = true,
    this.windowSeconds = 240, // teto da memória da música
    this.halfLifeSeconds = 60, // o que soou há 1 min pesa metade
    this.silenceResetSeconds = 6, // pausa entre músicas
    this.youngSeconds = 30, // memória jovem: segue o trecho até ter 30 s E concordar com ele
    this.youngMaxSeconds = 60, // ...ou, no máximo, até ter 60 s de áudio (teto: nunca copia o trecho para sempre)
    this.farResetSeconds = 20, // trecho num tom distante por 20 s -> a música mudou: reinicia a partir do trecho
    this.nearResetSeconds = 45, // trecho num tom vizinho COM notas novas por 45 s (acumulados) -> idem (0 = nunca)
    this.evidenceTolerance = 0.8, // ver newNoteEvidence
    this.evidenceFloor = 0.25,
    this.evidenceDrain = 0.5, // por segundo SEM nota nova (trecho ainda no vizinho), o contador perde 0,5 s; 0 = sem dreno
    this.baseHoldSeconds = 20, // regra própria da memória da música: lenta de propósito
    this.neighborHoldSeconds = 30,
    this.showPassageAfterSeconds = 4, // linha "agora" aparece após 4 s de discordância
    this.bassShare = 0.0,
  });

  final bool enabled;
  final double windowSeconds;
  final double halfLifeSeconds;
  final double silenceResetSeconds;
  final double youngSeconds;
  final double youngMaxSeconds;
  final double farResetSeconds;
  final double nearResetSeconds;
  final double evidenceTolerance;
  final double evidenceFloor;
  final double evidenceDrain;
  final double baseHoldSeconds;
  final double neighborHoldSeconds;
  final double showPassageAfterSeconds;
  final double bassShare;
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
  final double evidenceSeconds; // segundos acumulados de evidência de tom novo
  final int bassPc; // nota do baixo detectada (-1 se nenhuma)

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
    this.evidenceSeconds = 0.0,
    this.bassPc = -1,
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
      requireNewNotes: this.passageStabilizer.requireNewNotes,
      evidenceTolerance: songConfig.evidenceTolerance,
      evidenceFloor: songConfig.evidenceFloor,
    );
  }

  final ChromaAccumulator passage;
  final KeyStabilizer passageStabilizer;
  final KeyScorer scorer;
  final SongMemoryConfig songConfig;
  final double fullConfidenceGap;
  late final ChromaAccumulator song;
  late final KeyStabilizer songStabilizer;

  bool _songMature = false; // false: a memória da música ainda segue o trecho
  KeyCandidate? _held; // tom confirmado a ser segurado na fase jovem pós-confirmação
  KeyCandidate? _lastChallenger; // desafiante anterior para checar continuidade
  Duration? _farSince, _passageDiffersSince, _lastEvalAt, _reseededAt;
  Set<int>? _evidenceNotes; // notas novas a que o contador de evidência está ligado
  double _evidenceSeconds = 0; // tempo acumulado com o trecho num vizinho E notas novas presentes
  MemoryEvent _pending = MemoryEvent.none;
  KeyCandidate? _lastLabel;
  int labelChanges = 0; // trocas do letreiro principal, qualquer que seja o mecanismo
  int _lastBassPc = -1;

  TonalReading? _lastReading;
  TonalReading? get lastReading => _lastReading;
  KeyCandidate? get displayed =>
      songConfig.enabled ? songStabilizer.displayed : passageStabilizer.displayed;
  bool get isSongMature => _songMature;

  void addFrame(
    List<double> chroma,
    Duration at, {
    int bassPc = -1,
    double bassProb = 0.0,
  }) {
    if (chroma.length != 12) return;
    _lastBassPc = bassPc;
    final share = bassPc >= 0 ? songConfig.bassShare * bassProb : 0.0;
    final merged = share == 0
        ? chroma
        : [
            for (var i = 0; i < 12; i++)
              (1.0 - share) * chroma[i] + (i == bassPc ? share : 0.0),
          ];
    if (passage.add(merged, at)) passageStabilizer.reset();
    if (song.add(merged, at)) {
      _resetSongState();
      _pending = MemoryEvent.silenceReset;
    }
  }

  TonalReading? evaluate(Duration now) {
    var event = _pending;
    _pending = MemoryEvent.none;
    final dt = (_lastEvalAt == null || now < _lastEvalAt!)
        ? 0.0
        : _secs(now, _lastEvalAt!);
    _lastEvalAt = now;

    if (_farSince != null && now < _farSince!) _farSince = null;
    if (_passageDiffersSince != null && now < _passageDiffersSince!) {
      _passageDiffersSince = null;
    }

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
        0,
      );
      _lastReading = reading;
      return reading;
    }

    // 2. música
    if (song.gapExceeded(now)) {
      _resetSongState();
      _lastReading = null;
      return null; // "Ouvindo..." como no plano 2
    }
    final sProfile = song.profile(now);
    if (sProfile == null || _isFlat(sProfile)) {
      _lastReading = null;
      return null;
    }
    final sScores = scorer.score(sProfile);
    final p = passageStabilizer.displayed;
    if (!_songMature) {
      final youngTime = _reseededAt != null
          ? _secs(now, _reseededAt!)
          : song.secondsInWindow;
      if (_held != null) {
        songStabilizer.displayed = _held; // segura o tom confirmado
        songStabilizer.challenge = null;
        if (youngTime >= songConfig.youngSeconds &&
            sScores.first.sameKey(_held)) {
          _songMature = true;
          _held = null;
          _reseededAt = null;
        } else if (youngTime >= songConfig.youngMaxSeconds) {
          _songMature = true;
          songStabilizer.displayed = sScores.first;
          _held = null;
          _reseededAt = null;
        }
      } else {
        songStabilizer.displayed = p; // memória jovem inicial segue o trecho
        songStabilizer.challenge = null;
        if ((youngTime >= songConfig.youngSeconds &&
                p != null &&
                sScores.first.sameKey(p)) ||
            youngTime >= songConfig.youngMaxSeconds) {
          _songMature = true; // ...até concordar com ele, ou até o teto de 60 s
        }
      }
    } else {
      songStabilizer.update(
        now,
        sScores,
        song.secondsInWindow,
        profile: sProfile,
      );
    }

    // 3. reinícios por divergência entre trecho e música
    final s = songStabilizer.displayed;
    var reportedEvidence = 0.0;
    if (p != null && s != null && !p.sameKey(s)) {
      _passageDiffersSince ??= now;
      final notes = newNotesOf(s, p);
      final diatonic = diatonicNewNotesOf(s, p);
      if (_lastChallenger == null || !_lastChallenger!.sameKey(p)) {
        if (_evidenceNotes == null ||
            _evidenceNotes!.intersection(diatonic).isEmpty) {
          _evidenceSeconds = 0;
        }
        _evidenceNotes = notes;
        _lastChallenger = p;
      }
      if (KeyStabilizer.isNeighbor(s, p)) {
        _farSince = null;
        if (pProfile != null &&
            newNoteEvidence(
              s,
              p,
              pProfile,
              tolerance: songConfig.evidenceTolerance,
              floorFraction: songConfig.evidenceFloor,
            )) {
          _evidenceSeconds += dt; // só conta enquanto as notas novas estão lá
        } else {
          _evidenceSeconds = (_evidenceSeconds - songConfig.evidenceDrain * dt)
              .clamp(0.0, double.infinity); // ...e esvazia quando somem
        }
        reportedEvidence = _evidenceSeconds;
        if (songConfig.nearResetSeconds > 0 &&
            _evidenceSeconds >= songConfig.nearResetSeconds) {
          _reseed(p, now);
          event = MemoryEvent.neighborKeyConfirmed;
        }
      } else {
        _evidenceSeconds = 0;
        _evidenceNotes = null;
        _lastChallenger = null;
        _farSince ??= now;
        if (_secs(now, _farSince!) >= songConfig.farResetSeconds) {
          _reseed(p, now);
          event = MemoryEvent.farKeyConfirmed;
        }
      }
    } else {
      _farSince = null;
      _passageDiffersSince = null;
      _evidenceSeconds = 0;
      _evidenceNotes = null;
      _lastChallenger = null;
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
      reportedEvidence,
    );
    _lastReading = reading;
    return reading;
  }

  void _reseed(KeyCandidate confirmedKey, Duration now) {
    song.seedFrom(passage);
    _held = confirmedKey;
    _reseededAt = now;
    songStabilizer.displayed = confirmedKey;
    songStabilizer.challenge = null;
    _songMature = false; // volta a seguir o trecho até concordar
    _farSince = null;
    _passageDiffersSince = null;
    _evidenceSeconds = 0;
    _evidenceNotes = null;
    _lastChallenger = null;
  }

  void _resetSongState() {
    songStabilizer.reset();
    _songMature = false;
    _held = null;
    _reseededAt = null;
    _farSince = null;
    _passageDiffersSince = null;
    _evidenceSeconds = 0;
    _evidenceNotes = null;
    _lastChallenger = null;
    _lastBassPc = -1;
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
    double evidenceSeconds,
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
      secondsInWindow: seconds < 0 ? 0.0 : seconds,
      autoReset: event == MemoryEvent.silenceReset,
      passage: passageKey,
      showPassage: showPassage,
      event: event,
      songSeconds: song.secondsInWindow < 0 ? 0.0 : song.secondsInWindow,
      evidenceSeconds: evidenceSeconds,
      bassPc: _lastBassPc,
    );
  }

  /// RF05 / botão "Nova música": descarta as duas memórias.
  void reset() {
    passage.clear();
    song.clear();
    passageStabilizer.reset();
    _resetSongState();
    _lastLabel = null;
    labelChanges = 0;
    _pending = MemoryEvent.manualReset;
    _lastReading = null;
    _lastBassPc = -1;
  }

  int get switches => labelChanges; // mantém o nome usado pela tela
}
