class SongSegment {
  final double fromSeconds;
  final String key;
  final String mode; // 'major' | 'minor'

  const SongSegment({
    required this.fromSeconds,
    required this.key,
    required this.mode,
  });

  factory SongSegment.fromJson(Map<String, dynamic> json) {
    return SongSegment(
      fromSeconds: (json['from_s'] as num?)?.toDouble() ?? 0.0,
      key: json['key'] as String? ?? 'C',
      mode: json['mode'] as String? ?? 'major',
    );
  }

  Map<String, dynamic> toJson() => {
        'from_s': fromSeconds,
        'key': key,
        'mode': mode,
      };
}

class BenchSong {
  final int number;
  final String title;
  final String artist;
  final String youtube;
  final int durationSeconds;
  String referenceKey;
  String referenceMode; // 'major' | 'minor'
  final String referenceSource;
  final List<SongSegment> referenceSegments;
  final String notes;

  // Status de captura (preenchido ao escanear o diretório de bancada)
  bool isCaptured;
  String? capturedDate;
  String? capturedResult;
  String? capturedDir;

  BenchSong({
    required this.number,
    required this.title,
    required this.artist,
    required this.youtube,
    required this.durationSeconds,
    required this.referenceKey,
    required this.referenceMode,
    this.referenceSource = 'Cifra Club',
    List<SongSegment>? referenceSegments,
    this.notes = '',
    this.isCaptured = false,
    this.capturedDate,
    this.capturedResult,
    this.capturedDir,
  }) : referenceSegments = referenceSegments != null ? List<SongSegment>.from(referenceSegments) : [] {
    if (this.referenceSegments.isEmpty) {
      this.referenceSegments.add(SongSegment(
        fromSeconds: 0.0,
        key: referenceKey,
        mode: referenceMode,
      ));
    } else {
      this.referenceSegments[0] = SongSegment(
        fromSeconds: this.referenceSegments[0].fromSeconds,
        key: referenceKey,
        mode: referenceMode,
      );
    }
  }

  void updateReference({String? key, String? mode}) {
    if (key != null) referenceKey = key;
    if (mode != null) referenceMode = mode;
    if (referenceSegments.isNotEmpty) {
      referenceSegments[0] = SongSegment(
        fromSeconds: referenceSegments[0].fromSeconds,
        key: referenceKey,
        mode: referenceMode,
      );
    } else {
      referenceSegments.add(SongSegment(
        fromSeconds: 0.0,
        key: referenceKey,
        mode: referenceMode,
      ));
    }
  }

  String get displayReference =>
      '$referenceKey ${referenceMode.toLowerCase() == "major" ? "Maior" : "Menor"}';

  String get formattedDuration {
    final m = durationSeconds ~/ 60;
    final s = durationSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String get slug {
    final clean = title
        .toLowerCase()
        .replaceAll(RegExp(r'[áàãâä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[íìîï]'), 'i')
        .replaceAll(RegExp(r'[óòõôö]'), 'o')
        .replaceAll(RegExp(r'[úùûü]'), 'u')
        .replaceAll(RegExp(r'[ç]'), 'c')
        .replaceAll(RegExp(r'[^a-z0-9]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return clean.isEmpty ? 'song' : clean;
  }

  factory BenchSong.fromJson(Map<String, dynamic> json) {
    final ref = json['reference'] as Map<String, dynamic>? ?? {};
    final segmentsJson = (ref['segments'] as List?) ?? [];
    final segments = segmentsJson
        .map((s) => SongSegment.fromJson(Map<String, dynamic>.from(s as Map)))
        .toList();

    return BenchSong(
      number: json['number'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      youtube: json['youtube'] as String? ?? '',
      durationSeconds: json['duration_s'] as int? ?? 0,
      referenceKey: ref['key'] as String? ?? 'C',
      referenceMode: ref['mode'] as String? ?? 'major',
      referenceSource: ref['source'] as String? ?? 'Cifra Club',
      referenceSegments: segments,
      notes: ref['notes'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'number': number,
        'title': title,
        'artist': artist,
        'youtube': youtube,
        'duration_s': durationSeconds,
        'reference': {
          'key': referenceKey,
          'mode': referenceMode,
          'source': referenceSource,
          'segments': referenceSegments.map((s) => s.toJson()).toList(),
          'notes': notes,
        },
      };
}

/// Analisa linhas no formato "minuto:segundo -> tom" ou "segundos -> tom"
/// para preenchimento de reference.segments no pós-captura (Fase 5 / Adendo 1).
List<SongSegment> parseSegmentsInput(
  String input, {
  String fallbackKey = 'C',
  String fallbackMode = 'major',
}) {
  final lines = input.split('\n');
  final result = <SongSegment>[];
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;

    String timePart = '';
    String keyPart = '';

    if (trimmed.contains('->') || trimmed.contains('→')) {
      final parts = trimmed.contains('->') ? trimmed.split('->') : trimmed.split('→');
      timePart = parts[0].trim();
      keyPart = parts[1].trim();
    } else {
      final spaceIdx = trimmed.indexOf(' ');
      if (spaceIdx > 0) {
        timePart = trimmed.substring(0, spaceIdx).trim();
        keyPart = trimmed.substring(spaceIdx + 1).trim();
      } else {
        continue;
      }
    }

    double fromS = 0.0;
    if (timePart.contains(':')) {
      final colonParts = timePart.split(':');
      final m = double.tryParse(colonParts[0].trim()) ?? 0.0;
      final s = double.tryParse(colonParts[1].trim()) ?? 0.0;
      fromS = m * 60 + s;
    } else {
      final cleaned = timePart.replaceAll(RegExp(r'[^0-9.]'), '');
      fromS = double.tryParse(cleaned) ?? 0.0;
    }

    if (keyPart.isEmpty) continue;

    String mode = 'major';
    String key = keyPart;

    final lower = keyPart.toLowerCase();
    if (lower.contains('menor') || lower.contains('minor')) {
      mode = 'minor';
      key = keyPart.replaceAll(RegExp(r'menor|minor', caseSensitive: false), '').trim();
    } else if (lower.contains('maior') || lower.contains('major')) {
      mode = 'major';
      key = keyPart.replaceAll(RegExp(r'maior|major', caseSensitive: false), '').trim();
    } else if (keyPart.length > 1 && keyPart.endsWith('m') && !keyPart.endsWith('bm')) {
      mode = 'minor';
      key = keyPart.substring(0, keyPart.length - 1).trim();
    }

    if (key.isNotEmpty) {
      if (key.length == 1) {
        key = key.toUpperCase();
      } else if (key.length >= 2) {
        key = key[0].toUpperCase() + key.substring(1);
      }
    } else {
      key = fallbackKey;
    }

    result.add(SongSegment(fromSeconds: fromS, key: key, mode: mode));
  }

  result.sort((a, b) => a.fromSeconds.compareTo(b.fromSeconds));
  return result;
}
