import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/key_profiles.dart';
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
  final TonalEngine _engine = TonalEngine();
  final Stopwatch _stopwatch = Stopwatch();

  bool _isListening = false;
  bool _fieldMode = false;
  Sensitivity _sensitivity = Sensitivity.medio;
  StreamSubscription<ChromaFrame>? _chromaSubscription;
  Timer? _evalTimer;
  TonalReading? _currentReading;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadFieldMode();
  }

  Future<void> _loadFieldMode() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _fieldMode = prefs.getBool('field_mode') ?? false;
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
                    const SizedBox(height: 14),
                    // 2ª Opção
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "2ª opção: ",
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.textTheme.bodySmall?.color,
                          ),
                        ),
                        Text(
                          secondOption,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
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
                          minHeight: 7,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "${(confidence * 100).toStringAsFixed(0)}% de confiança",
                      style: theme.textTheme.bodySmall,
                    ),

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
              padding: const EdgeInsets.symmetric(vertical: 20.0),
              child: Row(
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
                          size: 42,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
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