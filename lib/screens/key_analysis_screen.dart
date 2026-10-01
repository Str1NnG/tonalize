import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../bench/bench_session.dart';
import '../bench/bench_song.dart';
import '../core/tonal_engine.dart';
import '../helpers/database_helper.dart';
import '../services/audio_service.dart';
import '../widgets/chroma_bars.dart';

enum Sensitivity { baixo, medio, alto }

class KeyAnalysisScreen extends StatefulWidget {
  final BenchSong? benchSong;
  const KeyAnalysisScreen({super.key, this.benchSong});

  @override
  State<KeyAnalysisScreen> createState() => _KeyAnalysisScreenState();
}

class _KeyAnalysisScreenState extends State<KeyAnalysisScreen>
    with WidgetsBindingObserver {
  final AudioService _audioService = AudioService();
  TonalEngine _engine = TonalEngine();
  final Stopwatch _stopwatch = Stopwatch();

  bool _isListening = false;
  bool _fieldMode = false;
  Sensitivity _sensitivity = Sensitivity.medio;
  StreamSubscription<ChromaFrame>? _chromaSubscription;
  Timer? _evalTimer;
  TonalReading? _currentReading;

  // Bancada de testes
  BenchSession? _benchSession;
  int _lastAudioMs = 0;
  bool _sessionCompleted = false;

  // Parâmetros de calibração / experimento
  int _windowSeconds = 20;
  String _sessionId = '';
  String _configString = '';
  bool _logReadings = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPreferences();
    if (widget.benchSong != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isListening) {
          _startListening();
          setState(() {});
        }
      });
    }
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _fieldMode = prefs.getBool('field_mode') ?? false;
        _windowSeconds = prefs.getInt('window_s') ?? 20;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopListening();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _isListening) {
      _stopListening();
      if (mounted) setState(() {});
    }
  }

  void _toggleListening() {
    if (_isListening) {
      _stopListening();
    } else {
      _startListening();
    }
    setState(() {});
  }

  Future<void> _startListening() async {
    _isListening = true;
    _currentReading = null;
    _stopwatch.reset();
    _stopwatch.start();

    final prefs = await SharedPreferences.getInstance();
    final stabMode = prefs.getString('stab_mode') ?? 'v3';
    _windowSeconds = prefs.getInt('window_s') ?? 20;
    final useHarmonics = prefs.getBool('harmonics') ?? true;
    final profileName = prefs.getString('profiles') ?? 'aarden';
    _logReadings = prefs.getBool('log_readings') ?? false;
    final songMemoryEnabled = prefs.getBool('song_memory') ?? true;
    final songHalfLife = prefs.getInt('song_halflife_s') ?? 60;
    final songFar = prefs.getInt('song_far_s') ?? 20;
    final songNear = prefs.getInt('song_near_s') ?? 45;
    final evidenceTol = prefs.getDouble('evidence_tol') ?? 0.8;
    final evidenceFloor = prefs.getDouble('evidence_floor') ?? 0.25;
    final minSeconds = prefs.getInt('min_s') ?? 2;
    final evidenceDrain = prefs.getDouble('evidence_drain') ?? 0.5;
    final strictNotes = prefs.getBool('strict_notes') ?? false;
    final minorProfileName = prefs.getString('minor_profiles') ?? 'aar_b7';
    final bassShare = prefs.getDouble('bass_share') ?? 0.0;
    final bassEnabled = bassShare > 0;

    // Parse profile
    ProfileSet profiles = ProfileSet.aarden;
    final pLower = profileName.toLowerCase();
    if (pLower.startsWith('temp') && pLower.contains('kp')) {
      profiles = ProfileSet.temperleyKP;
    } else if (pLower.startsWith('temp')) {
      profiles = ProfileSet.temperley;
    } else if (pLower.contains('b7') || pLower == 'aar_b7') {
      profiles = ProfileSet.aardenB7;
    } else if (pLower.startsWith('aar')) {
      profiles = ProfileSet.aarden;
    } else if (pLower.startsWith('krum') || pLower == 'kk') {
      profiles = ProfileSet.krumhansl;
    }

    // Parse minor profile
    ProfileSet? minorProfiles;
    final mpLower = minorProfileName.toLowerCase();
    if (mpLower.contains('b7') || mpLower == 'aar_b7') {
      minorProfiles = ProfileSet.aardenB7;
    } else if (mpLower.startsWith('aar')) {
      minorProfiles = ProfileSet.aarden;
    } else if (mpLower.startsWith('krum') || mpLower == 'kk') {
      minorProfiles = ProfileSet.krumhansl;
    }

    _sessionId = DateTime.now().toIso8601String();
    final minorCode = (minorProfiles != null && minorProfiles != profiles)
        ? ';min-${minorProfiles.code}'
        : '';
    final songConfigStr = songMemoryEnabled
        ? 'song$songHalfLife;far$songFar;near$songNear;tol$evidenceTol;floor$evidenceFloor;drain$evidenceDrain'
        : 'nosong';
    final strictPart = ';strict${strictNotes ? "1" : "0"}';
    final bassPart = ';bass${bassShare == 0 ? "0" : bassShare}';
    _configString =
        '$stabMode;w$_windowSeconds;${useHarmonics ? "harm" : "noharm"};${profiles.code}$minorCode;$songConfigStr$strictPart$bassPart';

    final ChromaAccumulator accumulator;
    final KeyStabilizer stabilizer;

    if (stabMode == 'v1') {
      accumulator = ChromaAccumulator(
        windowSeconds: 10,
        halfLifeSeconds: 1e9,
        silenceResetSeconds: 4,
      );
      stabilizer = KeyStabilizer(
        minSeconds: minSeconds.toDouble(),
        baseMargin: 0,
        neighborMargin: 0,
        baseHoldSeconds: 1.5,
        neighborHoldSeconds: 1.5,
      );
    } else {
      accumulator = ChromaAccumulator(
        windowSeconds: _windowSeconds.toDouble(),
        halfLifeSeconds: _windowSeconds / 2.0,
        silenceResetSeconds: 4,
      );
      stabilizer = KeyStabilizer(
        minSeconds: minSeconds.toDouble(),
        baseMargin: 0.05,
        baseHoldSeconds: 4.0,
        neighborMargin: 0.08,
        neighborHoldSeconds: 6.0,
        requireNewNotes: strictNotes,
        evidenceTolerance: evidenceTol,
        evidenceFloor: evidenceFloor,
      );
    }

    final songConfig = SongMemoryConfig(
      enabled: songMemoryEnabled,
      halfLifeSeconds: songHalfLife.toDouble(),
      farResetSeconds: songFar.toDouble(),
      nearResetSeconds: songNear.toDouble(),
      evidenceTolerance: evidenceTol,
      evidenceFloor: evidenceFloor,
      evidenceDrain: evidenceDrain,
      bassShare: bassShare,
    );

    _engine = TonalEngine(
      passage: accumulator,
      passageStabilizer: stabilizer,
      scorer: KeyScorer(profiles: profiles, minorProfiles: minorProfiles),
      songConfig: songConfig,
    );

    if (widget.benchSong != null) {
      final benchDir = await _audioService.getBenchDir();
      _benchSession = await BenchSession.start(
        song: widget.benchSong!,
        benchRootDir: benchDir,
        configString: _configString,
      );
      _sessionCompleted = false;
    }

    await _audioService.startKey(
      sensitivity: _sensitivity.index,
      harmonics: useHarmonics ? 4 : 1,
      peakThreshold: useHarmonics ? 0.01 : 0.0,
      minTonalness: useHarmonics ? 1.5 : 0.0,
      bassEnabled: bassEnabled,
    );

    _chromaSubscription?.cancel();
    _chromaSubscription = _audioService.chromaStream().listen(
      (frame) {
        _lastAudioMs = frame.tAudioMs;
        _benchSession?.addFrame(frame);
        if (frame.chroma != null) {
          final at = frame.tAudioMs > 0
              ? Duration(milliseconds: frame.tAudioMs)
              : _stopwatch.elapsed;
          _engine.addFrame(
            frame.chroma!,
            at,
            bassPc: frame.bassPc,
            bassProb: frame.bassProb,
          );
        }
      },
      onError: (err) {
        debugPrint("Erro no stream de áudio: $err");
      },
    );

    _evalTimer?.cancel();
    _evalTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!_isListening) return;
      final at = _lastAudioMs > 0
          ? Duration(milliseconds: _lastAudioMs)
          : _stopwatch.elapsed;
      final reading = _engine.evaluate(at);

      // Bancada de testes: gravar reading
      if (reading != null && _benchSession != null) {
        _benchSession!.addReading(
          reading: reading,
          tAudioMs: _lastAudioMs,
          labelChanges: _engine.switches,
          isSongMature: _engine.isSongMature,
        );
      }

      // Avisos de eventos de memória (Fase 4.1)
      if (reading != null && reading.event != MemoryEvent.none) {
        if (reading.event == MemoryEvent.silenceReset) {
          _showSnackBar('Nova música? Leitura reiniciada');
        } else if (reading.event == MemoryEvent.farKeyConfirmed) {
          _showSnackBar('Tom mudou — memória da música reiniciada');
        } else if (reading.event == MemoryEvent.neighborKeyConfirmed) {
          _showSnackBar('Novo tom confirmado — memória reiniciada');
        }
      }

      // Registro de leituras para a monografia (Fase 4.2 / 4.3)
      if (reading != null && _logReadings) {
        final nowTs = _stopwatch.elapsedMilliseconds / 1000.0;
        final challengeStr = reading.challenge != null
            ? '${reading.challenge!.key.label}:${reading.challenge!.progress(_stopwatch.elapsed).toStringAsFixed(2)}'
            : '';
        final rDisp = reading.displayed != null
            ? (_engine.scorer.score(reading.profile).firstWhere(
                  (c) => c.sameKey(reading.displayed),
                  orElse: () => const KeyCandidate(0, true, 0.0),
                ).r)
            : 0.0;

        DatabaseHelper.instance.addReading(
          sessionId: _sessionId,
          ts: nowTs,
          displayed: reading.displayed?.label ?? '',
          passage: reading.passage?.label ?? '',
          songSeconds: reading.songSeconds,
          evidenceSeconds: reading.evidenceSeconds,
          event: reading.event == MemoryEvent.none ? '' : reading.event.name,
          best: reading.best.label,
          rBest: reading.best.r,
          rDisplayed: rDisp,
          challenge: challengeStr,
          config: _configString,
          bassPc: reading.bassPc,
        );
      }

      if (mounted) {
        setState(() {
          _currentReading = reading;
        });
      }
    });
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _onMarkTapped(String label) {
    if (_benchSession != null) {
      _benchSession!.addMark(label, tAudioMs: _lastAudioMs);
      _showSnackBar('Marcação: $label');
    }
  }

  Future<void> _handleExitWithoutEnding() async {
    if (_benchSession != null && !_sessionCompleted) {
      _sessionCompleted = true;
      if (_stopwatch.elapsed.inSeconds < 5) {
        try {
          if (await _benchSession!.sessionDir.exists()) {
            await _benchSession!.sessionDir.delete(recursive: true);
          }
        } catch (_) {}
      } else {
        await _benchSession!.completeSession(
          verdictResult: 'incompleta',
          finalLabel: _benchSession?.lastNonEmptyDisplayedLabel ?? _engine.displayed?.label ?? '',
          finalSecond: _benchSession?.lastNonEmptySecondLabel ?? _currentReading?.second.label ?? '',
          notes: 'Encerrado sem veredicto (saiu da tela)',
        );
      }
    }
  }

  Future<void> _showVerdictSheet() async {
    if (_benchSession == null || widget.benchSong == null) return;
    final song = widget.benchSong!;
    final displayedLabel = (_engine.displayed?.label != null && _engine.displayed!.label.isNotEmpty)
        ? _engine.displayed!.label
        : (_benchSession?.lastNonEmptyDisplayedLabel ?? 'N/A');
    final secondLabel = (_currentReading?.second.label != null && _currentReading!.second.label.isNotEmpty)
        ? _currentReading!.second.label
        : (_benchSession?.lastNonEmptySecondLabel ?? 'N/A');
    final top3 = _benchSession?.lastNonEmptyBarsTop3 ?? _benchSession?.getFinalBarsTop3() ?? [];
    final top3Str = top3.isNotEmpty ? top3.join(' · ') : '--';

    String verdict = 'acertou';
    final notesController = TextEditingController();

    String initialSegmentsText = '';
    if (song.referenceSegments.length > 1) {
      initialSegmentsText = song.referenceSegments.map((s) {
        final m = s.fromSeconds ~/ 60;
        final sec = (s.fromSeconds % 60).round().toString().padLeft(2, '0');
        return '$m:$sec -> ${s.key} ${s.mode == "minor" ? "menor" : "maior"}';
      }).join('\n');
    }
    final segmentsController = TextEditingController(text: initialSegmentsText);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final theme = Theme.of(context);
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Veredicto da Bancada',
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${song.number.toString().padLeft(2, '0')}. ${song.title}',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text('Referência esperada: ', style: TextStyle(fontWeight: FontWeight.w600)),
                              Text(song.displayReference, style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Text('Tom final exibido: ', style: TextStyle(fontWeight: FontWeight.w600)),
                              Text(displayedLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Text('2ª opção: ', style: TextStyle(fontWeight: FontWeight.w600)),
                              Text(secondLabel),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Text('Top 3 barras finais (3s): ', style: TextStyle(fontWeight: FontWeight.w600)),
                              Text(top3Str, style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Classificação:', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _verdictChip('acertou', 'Acertou', Colors.green, verdict, (val) => setSheetState(() => verdict = val)),
                        _verdictChip('errou', 'Errou', Colors.red, verdict, (val) => setSheetState(() => verdict = val)),
                        _verdictChip('parcial', 'Parcial', Colors.orange, verdict, (val) => setSheetState(() => verdict = val)),
                        _verdictChip('referencia_duvidosa', 'Ref. Duvidosa', Colors.purple, verdict, (val) => setSheetState(() => verdict = val)),
                        _verdictChip('descartar', 'Descartar', Colors.grey, verdict, (val) => setSheetState(() => verdict = val)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: segmentsController,
                      decoration: const InputDecoration(
                        labelText: 'Esta gravação tem mais de uma música ou muda de tom? (opcional)',
                        hintText: 'minuto:segundo -> tom\nEx: 0:00 -> Sol maior\n1:25 -> Mi menor',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: notesController,
                      decoration: const InputDecoration(
                        labelText: 'Notas / Observações (opcional)',
                        hintText: 'Ex: Começou em G, modulou para A...',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.check),
                        label: const Text('SALVAR SESSÃO', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          List<SongSegment>? newSegments;
                          if (segmentsController.text.trim().isNotEmpty) {
                            final parsed = parseSegmentsInput(
                              segmentsController.text.trim(),
                              fallbackKey: song.referenceKey,
                              fallbackMode: song.referenceMode,
                            );
                            if (parsed.isNotEmpty) {
                              if (parsed[0].fromSeconds == 0.0) {
                                song.updateReference(key: parsed[0].key, mode: parsed[0].mode);
                              } else {
                                parsed.insert(0, SongSegment(
                                  fromSeconds: 0.0,
                                  key: song.referenceKey,
                                  mode: song.referenceMode,
                                ));
                              }
                              newSegments = parsed;
                            }
                          }

                          _sessionCompleted = true;
                          await _benchSession!.completeSession(
                            verdictResult: verdict,
                            finalLabel: displayedLabel,
                            finalSecond: secondLabel,
                            segments: newSegments,
                            notes: notesController.text.trim(),
                          );
                          _stopListening();
                          if (context.mounted) {
                            Navigator.pop(context); // close sheet
                          }
                          if (mounted) {
                            Navigator.pop(this.context, true); // return to bench_screen
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _verdictChip(
    String key,
    String label,
    Color color,
    String current,
    ValueChanged<String> onSelect,
  ) {
    final isSelected = current == key;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: color.withValues(alpha: 0.25),
      side: BorderSide(color: isSelected ? color : Colors.grey.shade400),
      labelStyle: TextStyle(
        color: isSelected ? color : null,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      onSelected: (_) => onSelect(key),
    );
  }

  void _stopListening() {
    _isListening = false;
    _evalTimer?.cancel();
    _evalTimer = null;
    _chromaSubscription?.cancel();
    _chromaSubscription = null;
    _stopwatch.stop();
    _audioService.stop();
  }

  void _resetAnalysis() {
    _engine.reset();
    _stopwatch.reset();
    _stopwatch.start();
    setState(() {
      _currentReading = null;
    });
  }

  Future<void> _changeSensitivity(Sensitivity newSens) async {
    if (_sensitivity == newSens) return;
    setState(() {
      _sensitivity = newSens;
    });
    if (_isListening) {
      _stopListening();
      await _startListening();
      if (mounted) setState(() {});
    }
  }

  Future<void> _recordFieldAnswer(String answer) async {
    final displayedKey = _engine.displayed;
    if (displayedKey == null) return;

    final entry = FieldEntry(
      dateTime: DateTime.now().toIso8601String(),
      keyShown: displayedKey.label,
      passage: _currentReading?.passage?.label,
      secondShown: _currentReading?.second.label ?? '--',
      confidence: _currentReading?.confidence ?? 0.0,
      answer: answer,
    );

    await DatabaseHelper.instance.addFieldEntry(entry);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Avaliação gravada: ${displayedKey.label} ($answer)',
          ),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _showSensitivityDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Sensibilidade do Microfone'),
          children: Sensitivity.values.map((s) {
            final label = s.name[0].toUpperCase() + s.name.substring(1);
            // ignore: deprecated_member_use
            return RadioListTile<Sensitivity>(
              title: Text(label),
              subtitle: Text(
                s == Sensitivity.baixo
                    ? 'Ignora ruídos do ambiente'
                    : s == Sensitivity.medio
                        ? 'Padrão recomendado'
                        : 'Capta sons mais fracos',
                style: const TextStyle(fontSize: 12),
              ),
              value: s,
              // ignore: deprecated_member_use
              groupValue: _sensitivity,
              // ignore: deprecated_member_use
              onChanged: (val) {
                if (val != null) {
                  _changeSensitivity(val);
                  Navigator.pop(context);
                }
              },
            );
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayedKey = _engine.displayed;

    final String keyTonic;
    final String keyMode;
    if (_isListening && displayedKey == null) {
      keyTonic = "Ouvindo...";
      keyMode = "";
    } else if (displayedKey != null) {
      keyTonic = displayedKey.name;
      keyMode = displayedKey.mode;
    } else {
      keyTonic = "--";
      keyMode = "";
    }

    final double confidence = _currentReading?.confidence ?? 0.0;
    final List<double> profile =
        _currentReading?.profile ?? List<double>.filled(12, 0.0);

    // Linha de tons próximos (RF02 Fase 3)
    final String nearbyText;
    if (_currentReading != null) {
      final secondLabel = _currentReading!.second.label;
      final others = _currentReading!.nearby
          .skip(1)
          .map((k) => k.label)
          .join(', ');
      if (others.isNotEmpty) {
        nearbyText = "2ª opção: $secondLabel  ·  também: $others";
      } else {
        nearbyText = "2ª opção: $secondLabel";
      }
    } else {
      nearbyText = "2ª opção: --";
    }

    // Indicador de desafio (Fase 3)
    final challenge = _currentReading?.challenge;

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _handleExitWithoutEnding();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.benchSong != null
              ? "Bancada #${widget.benchSong!.number}"
              : "Análise de Tonalidade"),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            if (widget.benchSong != null)
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.amber.shade900,
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: _showVerdictSheet,
                  child: const Text(
                    'ENCERRAR',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.tune_outlined),
              tooltip: 'Sensibilidade',
              onPressed: _showSensitivityDialog,
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (widget.benchSong != null) ...[
                _buildBenchBanner(theme, widget.benchSong!),
                _buildBenchMarkChips(theme),
                const Divider(height: 1),
              ],
              const SizedBox(height: 8),
            // Seção Superior: Tonalidade Detectada
            Expanded(
              flex: 4,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      keyTonic,
                      style: TextStyle(
                        fontSize: keyTonic.length > 3 ? 52 : 96,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                        height: 1.0,
                      ),
                    ),
                    if (keyMode.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        keyMode,
                        style: TextStyle(
                          fontSize: 26,
                          color: theme.textTheme.bodyMedium?.color,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      displayedKey != null
                          ? 'relativo: ${displayedKey.relative.label}'
                          : 'relativo: --',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                        color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.8),
                      ),
                    ),
                    if (_currentReading?.showPassage == true &&
                        _currentReading?.passage != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'agora: ${_currentReading!.passage!.shortLabel}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.secondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    // Linha de Tons Próximos
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Text(
                        nearbyText,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: theme.textTheme.bodySmall?.color,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Barra de Confiança
                    SizedBox(
                      width: 180,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: confidence,
                          backgroundColor: theme.colorScheme.outlineVariant
                              .withValues(alpha: 0.3),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            theme.colorScheme.primary,
                          ),
                          minHeight: 7,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "${(confidence * 100).toStringAsFixed(0)}% de confiança",
                      style: theme.textTheme.bodySmall,
                    ),

                    // Indicador de Desafio em Andamento (Fase 3)
                    if (challenge != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "Confirmando ${challenge.key.label}… "
                              "${(_stopwatch.elapsed - challenge.since).inSeconds} s / "
                              "${challenge.hold.inSeconds} s",
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            SizedBox(
                              width: 140,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: challenge.progress(_stopwatch.elapsed),
                                  minHeight: 3,
                                  backgroundColor: theme.colorScheme.outlineVariant
                                      .withValues(alpha: 0.3),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Botões de Validação de Campo (RF06)
                    if (_fieldMode && displayedKey != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FilledButton.tonalIcon(
                            icon: const Icon(
                              Icons.check_circle_outline,
                              color: Colors.green,
                              size: 18,
                            ),
                            label: const Text(
                              'Acertou',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => _recordFieldAnswer('acertou'),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.tonalIcon(
                            icon: const Icon(
                              Icons.cancel_outlined,
                              color: Colors.red,
                              size: 18,
                            ),
                            label: const Text(
                              'Errou',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => _recordFieldAnswer('errou'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Seção Central: 12 Barras do Perfil Cromático
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0, bottom: 4.0),
                      child: Text(
                        "PERFIL CROMÁTICO (ÚLTIMOS ${_windowSeconds}s)",
                        style: theme.textTheme.labelSmall?.copyWith(
                          letterSpacing: 1.2,
                          color: theme.textTheme.bodySmall?.color,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ChromaBars(
                        profile: profile,
                        displayedKey: displayedKey,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Seção Inferior: Métrica de Sessão e Controles
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0, top: 4.0),
              child: Column(
                children: [
                  // Métrica de estabilidade (trocas: N · mm:ss · memória: mm:ss [· evidência: N s])
                  if (_isListening)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10.0),
                      child: Text(
                        "trocas: ${_engine.switches}  ·  ${_formatDuration(_stopwatch.elapsed)}  ·  memória: ${_formatDuration(Duration(seconds: (_currentReading?.songSeconds ?? 0.0).round()))}${_logReadings ? '  ·  evidência: ${(_currentReading?.evidenceSeconds ?? 0.0).toStringAsFixed(0)} s' : ''}",
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          color: theme.textTheme.bodySmall?.color
                              ?.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Botão de Nova Música (RF05)
                      IconButton.filledTonal(
                        icon: const Icon(Icons.refresh_rounded),
                        tooltip: 'Nova música',
                        iconSize: 30,
                        onPressed: _isListening ? _resetAnalysis : null,
                      ),
                      const SizedBox(width: 24),
                      // Botão Principal Iniciar/Parar (RF01)
                      GestureDetector(
                        onTap: _toggleListening,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            color: _isListening
                                ? Colors.red.shade700
                                : theme.colorScheme.primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: (_isListening
                                        ? Colors.red
                                        : theme.colorScheme.primary)
                                    .withValues(alpha: 0.35),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Icon(
                              _isListening
                                  ? Icons.stop_rounded
                                  : Icons.mic_rounded,
                              size: 42,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 24),
                      if (widget.benchSong != null)
                        IconButton.filledTonal(
                          icon: const Icon(Icons.flag_rounded),
                          tooltip: 'Encerrar sessão',
                          iconSize: 28,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.amber.shade900.withValues(alpha: 0.2),
                            foregroundColor: Colors.amber.shade900,
                          ),
                          onPressed: _showVerdictSheet,
                        )
                      else
                        const SizedBox(width: 48), // espaçador para balancear com o refresh
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildBenchBanner(ThemeData theme, BenchSong song) {
    final numStr = song.number.toString().padLeft(2, '0');
    final timeStr = _formatDuration(_stopwatch.elapsed);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.7),
      child: Row(
        children: [
          Icon(Icons.science, size: 18, color: theme.colorScheme.onPrimaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'BANCADA · $numStr · ${song.title} · ref. ${song.displayReference} · $timeStr',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBenchMarkChips(ThemeData theme) {
    const marks = ['intro', 'verso', 'refrão', 'ponte', 'modulação', 'nova música', 'fim'];
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: marks.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final label = marks[index];
          return ActionChip(
            label: Text(label, style: const TextStyle(fontSize: 11.5)),
            onPressed: _isListening ? () => _onMarkTapped(label) : null,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
          );
        },
      ),
    );
  }
}