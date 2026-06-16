// ARQUIVO ATUALIZADO: lib/screens/key_analysis_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import '../helpers/database_helper.dart';

enum Sensitivity { baixo, medio, alto }

class KeyAnalysisResult {
  final String keyName;
  final double confidence;
  final List<String> predominantNotes;
  KeyAnalysisResult({required this.keyName, required this.confidence, required this.predominantNotes});
}

class KeyAnalysisScreen extends StatefulWidget {
  const KeyAnalysisScreen({super.key});
  @override
  State<KeyAnalysisScreen> createState() => _KeyAnalysisScreenState();
}

class _KeyAnalysisScreenState extends State<KeyAnalysisScreen> {
  // Toda a lógica de detecção e estado permanece a mesma.
  // As mudanças são apenas no método build().
  static const _channel = MethodChannel('keyfinder');
  final List<String> _notes = const ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
  static const List<double> _krumhanslMajorProfile = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88];
  static const List<double> _krumhanslMinorProfile = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17];
  bool _isListening = false;
  List<String> _detectedNotesHistory = [];
  Map<String, int> _noteCounts = {};
  KeyAnalysisResult? _analysisResult;
  Timer? _analysisTimer;
  double _detectionInterval = 10.0;
  Set<Sensitivity> _sensitivitySelection = {Sensitivity.medio};
  bool _isPlaybackEnabled = false;
  String? _potentialNote;
  int _consecutiveDetections = 0;
  final int _requiredDetections = 6;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handlePlatformCall);
  }

  @override
  void dispose() {
    _stopListening();
    _analysisTimer?.cancel();
    super.dispose();
  }

  void _toggleListening() {
    setState(() {
      _isListening = !_isListening;
      if (_isListening) {
        _detectedNotesHistory.clear();
        _noteCounts.clear();
        _analysisResult = null;
        _potentialNote = null;
        _consecutiveDetections = 0;
        _startListening();
        _analysisTimer = Timer.periodic(Duration(seconds: _detectionInterval.toInt()), (timer) {
          if (_isListening) _analyzeNotes();
        });
      } else {
        _stopListening();
        _analysisTimer?.cancel();
      }
    });
  }

  Future<void> _startListening() async {
    final sensitivityLevel = _sensitivitySelection.first.index;
    try {
      await _channel.invokeMethod('startListening', {'sensitivity': sensitivityLevel, 'playbackEnabled': _isPlaybackEnabled});
    } on PlatformException catch (e) {
      print("Falha ao iniciar a escuta: '${e.message}'.");
    }
  }

  Future<void> _stopListening() async => await _channel.invokeMethod('stopListening');

  Future<dynamic> _handlePlatformCall(MethodCall call) async {
    if (call.method == 'pitchDetected' && _isListening && mounted) {
      final double pitchInHz = call.arguments;
      final String currentNoteName = _convertHzToNote(pitchInHz);
      if (currentNoteName.isEmpty) return;
      if (currentNoteName == _potentialNote) {
        _consecutiveDetections++;
      } else {
        _potentialNote = currentNoteName;
        _consecutiveDetections = 1;
      }
      if (_consecutiveDetections >= _requiredDetections) {
        if (_detectedNotesHistory.isEmpty || _detectedNotesHistory.last != _potentialNote) {
          setState(() {
            _detectedNotesHistory.add(_potentialNote!);
            _noteCounts[_potentialNote!] = (_noteCounts[_potentialNote!] ?? 0) + 1;
            if (_detectedNotesHistory.length > 50) {
              final oldNote = _detectedNotesHistory.removeAt(0);
              _noteCounts.update(oldNote, (value) => value > 1 ? value - 1 : 0);
            }
          });
        }
        _consecutiveDetections = 0;
      }
    }
  }

  String _convertHzToNote(double hz) {
    if (hz <= 0) return "";
    final double midiNote = 12 * (math.log(hz / 440) / math.log(2)) + 69;
    return _notes[midiNote.round() % 12];
  }

  void _analyzeNotes() {
    if (_detectedNotesHistory.toSet().length < 3) return;
    final musicProfile = List<double>.filled(12, 0);
    _noteCounts.forEach((note, count) {
      int index = _notes.indexOf(note);
      if (index != -1) { musicProfile[index] = count.toDouble(); }
    });
    String bestKey = 'N/A';
    double bestCorrelation = -1.0;
    for (int i = 0; i < 12; i++) {
      final majorProfileShifted = _rotateProfile(_krumhanslMajorProfile, i);
      final majorCorrelation = _calculateCorrelation(musicProfile, majorProfileShifted);
      if (majorCorrelation > bestCorrelation) {
        bestCorrelation = majorCorrelation;
        bestKey = "${_notes[i]} Maior";
      }
      final minorProfileShifted = _rotateProfile(_krumhanslMinorProfile, i);
      final minorCorrelation = _calculateCorrelation(musicProfile, minorProfileShifted);
      if (minorCorrelation > bestCorrelation) {
        bestCorrelation = minorCorrelation;
        bestKey = "${_notes[(i + 9) % 12]} Menor";
      }
    }
    Map<String, int> sortedNoteCounts = Map.fromEntries(_noteCounts.entries.toList()
      ..sort((e1, e2) => e2.value.compareTo(e1.value)));
    List<String> predominantNotes = sortedNoteCounts.keys.take(3).toList();
    final newResult = KeyAnalysisResult(
      keyName: bestKey,
      confidence: (bestCorrelation < 0 ? 0 : bestCorrelation) * 100,
      predominantNotes: predominantNotes,
    );
    if(mounted){
      setState(() { _analysisResult = newResult; });
    }
    DatabaseHelper.instance.addAnalysis(newResult);
  }

  List<double> _rotateProfile(List<double> profile, int shifts) {
    return List<double>.generate(profile.length, (i) => profile[(i - shifts + profile.length) % profile.length]);
  }

  double _calculateCorrelation(List<double> x, List<double> y) {
    if (x.length != y.length || x.isEmpty) return 0.0;
    int n = x.length;
    double sumX = x.reduce((a, b) => a + b);
    double sumY = y.reduce((a, b) => a + b);
    bool xIsFlat = x.every((val) => val == x.first);
    if (xIsFlat) return 0.0;
    double sumX2 = x.map((e) => e * e).reduce((a, b) => a + b);
    double sumY2 = y.map((e) => e * e).reduce((a, b) => a + b);
    double sumXY = 0.0;
    for (int i = 0; i < n; i++) { sumXY += x[i] * y[i]; }
    double numerator = n * sumXY - sumX * sumY;
    double denominator = math.sqrt((n * sumX2 - sumX * sumX) * (n * sumY2 - sumY * sumY));
    if (denominator == 0) return 0.0;
    return numerator / denominator;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyParts = _analysisResult?.keyName.split(' ') ?? ['--', ''];
    final keyName = keyParts.first;
    final keyMode = keyParts.length > 1 ? keyParts.last : '';
    final confidence = _analysisResult?.confidence ?? 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Analisador de Tom"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Configurações de Análise',
            onPressed: _isListening ? null : _showSettingsPanel,
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          // Conteúdo principal da tela
          Column(
            children: [
              // MUDANÇA 1: Adicionando a legenda para as notas detectadas
              Padding(
                padding: const EdgeInsets.only(top: 10.0),
                child: Text('NOTAS DETECTADAS', style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey.shade600, letterSpacing: 1.5)),
              ),
              _buildDetectedNotesChips(),

              const Spacer(),

              // Display Central com o resultado
              Column(
                children: [
                  Text(
                    keyName,
                    style: TextStyle(fontSize: 140, fontWeight: FontWeight.bold, color: theme.colorScheme.primary, height: 1.0),
                  ),
                  Text(
                    keyMode,
                    style: TextStyle(fontSize: 36, color: theme.textTheme.bodyMedium?.color, letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: 150,
                    child: LinearProgressIndicator(
                      value: confidence / 100,
                      backgroundColor: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                      valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "${confidence.toStringAsFixed(0)}% de Confiança",
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),

              const Spacer(),

              // Notas predominantes na parte de baixo
              _buildPredominantNotes(),
              const SizedBox(height: 160), // Espaço para o botão flutuante não cobrir
            ],
          ),

          // MUDANÇA 2: Botão de ação centralizado
          Positioned(
            bottom: 40,
            // Adicionamos left: 0 e right: 0 para que o Positioned ocupe toda a largura
            // e o Center dentro dele possa funcionar corretamente.
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _toggleListening,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: theme.scaffoldBackgroundColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _isListening ? Colors.red.withOpacity(0.4) : theme.colorScheme.primary.withOpacity(0.4),
                        blurRadius: 8, // Sombra mais suave
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (child, animation) {
                        return ScaleTransition(child: child, scale: animation);
                      },
                      child: Icon(
                        _isListening ? Icons.stop_rounded : Icons.play_arrow_rounded,
                        key: ValueKey<bool>(_isListening),
                        size: 60,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSettingsPanel() {
    var tempSensitivity = _sensitivitySelection;
    var tempInterval = _detectionInterval;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Configurações de Análise', style: Theme.of(context).textTheme.headlineSmall),
                  const Divider(height: 24),

                  ListTile(
                    leading: const Icon(Icons.mic_none_outlined),
                    title: const Text('Sensibilidade do Microfone'),
                    subtitle: Text(tempSensitivity.first.name[0].toUpperCase() + tempSensitivity.first.name.substring(1)),
                    onTap: () async {
                      final newSelection = await _showSensitivityDialog(tempSensitivity);
                      if (newSelection != null) {
                        setModalState(() => tempSensitivity = {newSelection});
                      }
                    },
                  ),

                  ListTile(
                    leading: const Icon(Icons.timer_outlined),
                    title: const Text('Intervalo de Análise'),
                    subtitle: Text("${tempInterval.round()} segundos"),
                    onTap: () async {
                      final newInterval = await _showIntervalDialog(tempInterval);
                      if (newInterval != null) {
                        setModalState(() => tempInterval = newInterval);
                      }
                    },
                  ),

                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        child: const Text('Salvar'),
                        onPressed: () {
                          setState(() {
                            _sensitivitySelection = tempSensitivity;
                            _detectionInterval = tempInterval;
                          });
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<Sensitivity?> _showSensitivityDialog(Set<Sensitivity> currentSelection) {
    return showDialog<Sensitivity>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Escolha a Sensibilidade'),
          children: Sensitivity.values.map((sensitivity) {
            return RadioListTile<Sensitivity>(
              title: Text(sensitivity.name[0].toUpperCase() + sensitivity.name.substring(1)),
              value: sensitivity,
              groupValue: currentSelection.first,
              onChanged: (value) {
                Navigator.pop(context, value);
              },
            );
          }).toList(),
        );
      },
    );
  }

  Future<double?> _showIntervalDialog(double currentInterval) {
    var tempInterval = currentInterval;
    return showDialog<double>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Defina o Intervalo'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("${tempInterval.round()} segundos"),
                  Slider(
                    value: tempInterval,
                    min: 5,
                    max: 30,
                    divisions: 5,
                    label: "${tempInterval.round()}s",
                    onChanged: (value) {
                      setDialogState(() => tempInterval = value);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                ElevatedButton(onPressed: () => Navigator.pop(context, tempInterval), child: const Text('OK')),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDetectedNotesChips() {
    return Container(
      height: 40,
      margin: const EdgeInsets.only(bottom: 16),
      child: _detectedNotesHistory.isEmpty
          ? Center(child: Text("Pressione INICIAR para começar a análise", style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color)))
          : ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        reverse: true,
        itemCount: _detectedNotesHistory.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Chip(
              label: Text(_detectedNotesHistory[index], style: const TextStyle(fontWeight: FontWeight.bold)),
              backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
              side: BorderSide(color: Theme.of(context).colorScheme.outline.withOpacity(0.5)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPredominantNotes() {
    final predominantNotes = _analysisResult?.predominantNotes ?? [];
    if (predominantNotes.isEmpty || !_isListening) return const SizedBox(height: 60);

    return SizedBox(
      height: 60,
      child: Column(
        children: [
          Text("Notas Predominantes", style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: predominantNotes.map((note) {
              return Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.7),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(note, style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSecondaryContainer)),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}