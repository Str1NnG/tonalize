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
    this.referenceSegments = const [],
    this.notes = '',
    this.isCaptured = false,
    this.capturedDate,
    this.capturedResult,
    this.capturedDir,
  });

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
