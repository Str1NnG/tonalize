import 'dart:async';
import 'package:flutter/material.dart';
import '../core/key_profiles.dart';
import '../core/tonal_engine.dart';
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
  final TonalEngine _engine = TonalEngine();
  final Stopwatch _stopwatch = Stopwatch();

  bool _isListening = false;
  Sensitivity _sensitivity = Sensitivity.medio;
  StreamSubscription<ChromaFrame>? _chromaSubscription;
  Timer? _evalTimer;
  TonalReading? _currentReading;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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

  void _startListening() {
    _isListening = true;
    _engine.reset();
    _currentReading = null;
    _stopwatch.reset();
    _stopwatch.start();

    _audioService.startKey(sensitivity: _sensitivity.index);

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
      _startListening();
      setState(() {});
    }
  }

  void _showSensitivityDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Sensibilidade do Microfone'),
          children: Sensitivity.values.map((s) {
            final label = s.name[0].toUpperCase() + s.name.substring(1);
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
              groupValue: _sensitivity,
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
    final String secondOption = _currentReading?.second.label ?? "--";
    final List<double> profile =
        _currentReading?.profile ?? List<double>.filled(12, 0.0);

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
            const SizedBox(height: 12),
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
                        fontSize: keyTonic.length > 3 ? 56 : 100,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                        height: 1.0,
                      ),
                    ),
                    if (keyMode.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        keyMode,
                        style: TextStyle(
                          fontSize: 28,
                          color: theme.textTheme.bodyMedium?.color,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    // 2ª Opção
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "2ª opção: ",
                          style: TextStyle(
                            fontSize: 14,
                            color: theme.textTheme.bodySmall?.color,
                          ),
                        ),
                        Text(
                          secondOption,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Barra de Confiança
                    SizedBox(
                      width: 180,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: confidence,
                          backgroundColor:
                              theme.colorScheme.outlineVariant.withOpacity(0.3),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            theme.colorScheme.primary,
                          ),
                          minHeight: 8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "${(confidence * 100).toStringAsFixed(0)}% de confiança",
                      style: theme.textTheme.bodySmall,
                    ),
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
                        "PERFIL CROMÁTICO (ÚLTIMOS 10s)",
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

            // Seção Inferior: Controles (Iniciar/Parar e Reiniciar)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Botão de Reiniciar Leitura (RF05)
                  IconButton.filledTonal(
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Reiniciar leitura',
                    iconSize: 32,
                    onPressed: _isListening ? _resetAnalysis : null,
                  ),
                  const SizedBox(width: 24),
                  // Botão Principal Iniciar/Parar (RF01)
                  GestureDetector(
                    onTap: _toggleListening,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 88,
                      height: 88,
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
                                .withOpacity(0.35),
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
                          size: 46,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  // Espaço para balanceamento simétrico
                  const SizedBox(width: 48),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}