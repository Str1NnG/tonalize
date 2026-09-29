import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:keyfinder/bench/bench_song.dart';
import 'package:keyfinder/screens/key_analysis_screen.dart';
import 'package:keyfinder/services/audio_service.dart';

class BenchScreen extends StatefulWidget {
  const BenchScreen({super.key});

  @override
  State<BenchScreen> createState() => _BenchScreenState();
}

class _BenchScreenState extends State<BenchScreen> {
  final AudioService _audioService = AudioService();

  List<BenchSong> _songs = [];
  BenchSong? _selectedSong;
  bool _isLoading = true;
  String _benchDir = '';

  static const List<String> _noteOptions = [
    'C', 'C#', 'Db', 'D', 'Eb', 'E', 'F', 'F#', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B'
  ];

  @override
  void initState() {
    super.initState();
    _loadSongsAndScanBench();
  }

  Future<void> _loadSongsAndScanBench() async {
    setState(() => _isLoading = true);
    try {
      final jsonStr = await rootBundle.loadString('assets/bench/songs.json');
      final list = jsonDecode(jsonStr) as List;
      _songs = list
          .map((item) => BenchSong.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();

      _benchDir = await _audioService.getBenchDir();
      await _scanExistingSessions();

      if (_songs.isNotEmpty) {
        _selectedSong = _songs.firstWhere(
          (s) => !s.isCaptured,
          orElse: () => _songs.first,
        );
      }
    } catch (e) {
      debugPrint('Erro ao carregar músicas da bancada: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _scanExistingSessions() async {
    if (_benchDir.isEmpty) return;
    final dir = Directory(_benchDir);
    if (!await dir.exists()) return;

    try {
      final entities = await dir.list().toList();
      for (final entity in entities) {
        if (entity is Directory) {
          final sessionJson = File('${entity.path}${Platform.pathSeparator}session.json');
          if (await sessionJson.exists()) {
            try {
              final content = await sessionJson.readAsString();
              final map = jsonDecode(content) as Map<String, dynamic>;
              final songMap = map['song'] as Map<String, dynamic>?;
              final verdictMap = map['verdict'] as Map<String, dynamic>?;

              final songNum = songMap?['number'] as int?;
              final result = verdictMap?['result'] as String?;

              if (songNum != null) {
                final match = _songs.where((s) => s.number == songNum);
                if (match.isNotEmpty) {
                  final song = match.first;
                  song.isCaptured = true;
                  song.capturedDir = entity.path;
                  song.capturedResult = result;
                  final folderName = entity.path.split(Platform.pathSeparator).last;
                  final parts = folderName.split('_');
                  if (parts.length >= 3) {
                    song.capturedDate = parts.last;
                  }
                }
              }
            } catch (err) {
              debugPrint('Erro lendo session.json em ${entity.path}: $err');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Erro listando diretório da bancada: $e');
    }
  }

  Future<void> _exportBench() async {
    try {
      final ok = await _audioService.exportBench();
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhuma sessão encontrada para exportar')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao exportar: $e')),
        );
      }
    }
  }

  Future<void> _exportSession(String sessionDir) async {
    try {
      final ok = await _audioService.exportSession(sessionDir);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao exportar sessão')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao exportar: $e')),
        );
      }
    }
  }

  void _startCapture(BenchSong song) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => KeyAnalysisScreen(benchSong: song),
      ),
    );

    if (result == true) {
      await _loadSongsAndScanBench();
    }
  }

  @override
  Widget build(BuildContext context) {
    final capturedCount = _songs.where((s) => s.isCaptured).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bancada de Testes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Exportar bancada (.zip)',
            onPressed: capturedCount > 0 ? _exportBench : null,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Cartão com a música selecionada
                if (_selectedSong != null) _buildSelectedSongCard(_selectedSong!),

                // Barra de progresso da bancada
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Text(
                        'Progresso: $capturedCount / ${_songs.length} capturadas',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const Spacer(),
                      if (capturedCount > 0)
                        TextButton.icon(
                          icon: const Icon(Icons.archive_outlined, size: 18),
                          label: const Text('Exportar Zip'),
                          onPressed: _exportBench,
                        ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // Lista das músicas
                Expanded(
                  child: ListView.builder(
                    itemCount: _songs.length,
                    itemBuilder: (context, index) {
                      final s = _songs[index];
                      final isSelected = s.number == _selectedSong?.number;
                      return _buildSongTile(s, isSelected);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSelectedSongCard(BenchSong song) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.all(12),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  child: Text('${song.number}', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        song.artist,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.textTheme.bodySmall?.color),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Text(
                  song.formattedDuration,
                  style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Seleção / edição de Tom de Referência
            Row(
              children: [
                const Text('Tom de ref.: ', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _noteOptions.contains(song.referenceKey) ? song.referenceKey : _noteOptions.first,
                  isDense: true,
                  items: _noteOptions
                      .map((note) => DropdownMenuItem(value: note, child: Text(note)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => song.referenceKey = val);
                  },
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: song.referenceMode.toLowerCase() == 'minor' ? 'minor' : 'major',
                  isDense: true,
                  items: const [
                    DropdownMenuItem(value: 'major', child: Text('Maior')),
                    DropdownMenuItem(value: 'minor', child: Text('Menor')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => song.referenceMode = val);
                  },
                ),
                const Spacer(),
                if (song.isCaptured)
                  Chip(
                    label: Text(
                      song.capturedResult ?? 'capturada',
                      style: const TextStyle(fontSize: 11),
                    ),
                    backgroundColor: song.capturedResult == 'acertou'
                        ? Colors.green.withValues(alpha: 0.2)
                        : Colors.orange.withValues(alpha: 0.2),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Botão Iniciar Captura
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                icon: const Icon(Icons.mic),
                label: Text(song.isCaptured ? 'REPETIR CAPTURA' : 'INICIAR CAPTURA'),
                style: FilledButton.styleFrom(
                  backgroundColor: song.isCaptured ? Colors.orange.shade800 : colorScheme.primary,
                ),
                onPressed: () => _startCapture(song),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSongTile(BenchSong song, bool isSelected) {
    final theme = Theme.of(context);

    return ListTile(
      selected: isSelected,
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: song.isCaptured
            ? Colors.green
            : (isSelected ? theme.colorScheme.primary : theme.disabledColor.withValues(alpha: 0.3)),
        foregroundColor: Colors.white,
        child: song.isCaptured
            ? const Icon(Icons.check, size: 16)
            : Text('${song.number}', style: const TextStyle(fontSize: 12)),
      ),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
      ),
      subtitle: Text(
        '${song.formattedDuration} · Ref: ${song.displayReference} · ${song.artist}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: song.isCaptured && song.capturedDir != null
          ? IconButton(
              icon: const Icon(Icons.share, size: 20),
              tooltip: 'Exportar esta sessão',
              onPressed: () => _exportSession(song.capturedDir!),
            )
          : null,
      onTap: () {
        setState(() => _selectedSong = song);
      },
    );
  }
}
