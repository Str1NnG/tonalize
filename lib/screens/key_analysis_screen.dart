import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/tonal_engine.dart';
import '../helpers/database_helper.dart';
import '../services/audio_service.dart';
import '../widgets/chroma_bars.dart';

enum Sensitivity { baixo, medio, alto }

class KeyAnalysisScreen extends StatefulWidget {
  const KeyAnalysisScreen({super.key});

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
    final stabMode = prefs.getString('stab_mode') ?? 'v2';
    _windowSeconds = prefs.getInt('window_s') ?? 20;
    final useHarmonics = prefs.getBool('harmonics') ?? true;
    final profileName = prefs.getString('profiles') ?? 'Krumhansl';
    _logReadings = prefs.getBool('log_readings') ?? false;

    _sessionId = DateTime.now().toIso8601String();
    _configString = '$stabMode;w$_windowSeconds;${useHarmonics ? "harm" : "noharm"};${profileName == "Temperley" ? "temp" : "kk"}';

    final ProfileSet profiles = profileName == 'Temperley'
        ? ProfileSet.temperley
        : ProfileSet.krumhansl;

    final ChromaAccumulator accumulator;
    final KeyStabilizer stabilizer;

    if (stabMode == 'v1') {
      accumulator = ChromaAccumulator(
        windowSeconds: 10,
        halfLifeSeconds: 1e9,
        silenceResetSeconds: 4,
      );
      stabilizer = KeyStabilizer(
        minSeconds: 2,
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
        minSeconds: 2,
        baseMargin: 0.05,
        baseHoldSeconds: 4.0,
        neighborMargin: 0.08,
        neighborHoldSeconds: 6.0,
      );
    }

    _engine = TonalEngine(
      passage: accumulator,
      passageStabilizer: stabilizer,
      scorer: KeyScorer(profiles: profiles),
    );

    await _audioService.startKey(
      sensitivity: _sensitivity.index,
      harmonics: useHarmonics ? 4 : 1,
      peakThreshold: useHarmonics ? 0.01 : 0.0,
      minTonalness: useHarmonics ? 1.5 : 0.0,
    );

    _chromaSubscription?.cancel();
    _chromaSubscription = _audioService.chromaStream().listen(
      (frame) {
        _engine.addFrame(frame.chroma, _stopwatch.elapsed);
      },
      onError: (err) {
        debugPrint("Erro no stream de áudio: $err");
      },
    );

    _evalTimer?.cancel();
    _evalTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!_isListening) return;
      final reading = _engine.evaluate(_stopwatch.elapsed);

      if (reading != null && reading.autoReset) {
        _stopwatch.reset();
        _stopwatch.start();
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Nova música? Leitura reiniciada'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }

      // Registro de leituras para a monografia (Fase 4.2)
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
          best: reading.best.label,
          rBest: reading.best.r,
          rDisplayed: rDisp,
          challenge: challengeStr,
          config: _configString,
        );
      }

      if (mounted) {
        setState(() {
          _currentReading = reading;
        });
      }
    });
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

    return Scaffold(
      appBar: AppBar(
        title: const Text("Análise de Tonalidade"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
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
                  // Métrica de estabilidade (trocas: N · mm:ss)
                  if (_isListening)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10.0),
                      child: Text(
                        "trocas: ${_engine.switches}  ·  ${_formatDuration(_stopwatch.elapsed)}",
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
                      // Botão de Reiniciar Leitura (RF05)
                      IconButton.filledTonal(
                        icon: const Icon(Icons.refresh_rounded),
                        tooltip: 'Reiniciar leitura',
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
                      const SizedBox(width: 48), // espaçador para balancear com o refresh
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}