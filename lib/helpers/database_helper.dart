import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class FieldEntry {
  final int? id;
  final String dateTime;
  final String keyShown;
  final String? passage;
  final String secondShown;
  final double confidence;
  final String answer; // 'acertou' | 'errou'

  const FieldEntry({
    this.id,
    required this.dateTime,
    required this.keyShown,
    this.passage,
    required this.secondShown,
    required this.confidence,
    required this.answer,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'dateTime': dateTime,
      'keyShown': keyShown,
      'passage': passage,
      'secondShown': secondShown,
      'confidence': confidence,
      'answer': answer,
    };
  }

  factory FieldEntry.fromMap(Map<String, dynamic> map) {
    return FieldEntry(
      id: map['id'] as int?,
      dateTime: map['dateTime'] as String,
      keyShown: map['keyShown'] as String,
      passage: map['passage'] as String?,
      secondShown: map['secondShown'] as String,
      confidence: (map['confidence'] as num).toDouble(),
      answer: map['answer'] as String,
    );
  }
}

class DatabaseHelper {
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;
  Future<Database> get database async => _database ??= await _initDatabase();

  Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, 'keyfinder.db');
    return await openDatabase(
      path,
      version: 5,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE field_log(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        dateTime TEXT NOT NULL,
        keyShown TEXT NOT NULL,
        passage TEXT,
        secondShown TEXT NOT NULL,
        confidence REAL NOT NULL,
        answer TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE readings(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sessionId TEXT NOT NULL,
        ts REAL NOT NULL,
        displayed TEXT NOT NULL,
        passage TEXT,
        songSeconds REAL,
        evidenceSeconds REAL,
        event TEXT,
        best TEXT NOT NULL,
        rBest REAL NOT NULL,
        rDisplayed REAL NOT NULL,
        challenge TEXT NOT NULL,
        config TEXT NOT NULL,
        bassPc INTEGER
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('DROP TABLE IF EXISTS history');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS field_log(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          dateTime TEXT NOT NULL,
          keyShown TEXT NOT NULL,
          secondShown TEXT NOT NULL,
          confidence REAL NOT NULL,
          answer TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS readings(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sessionId TEXT NOT NULL,
          ts REAL NOT NULL,
          displayed TEXT NOT NULL,
          best TEXT NOT NULL,
          rBest REAL NOT NULL,
          rDisplayed REAL NOT NULL,
          challenge TEXT NOT NULL,
          config TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE readings ADD COLUMN passage TEXT;');
      await db.execute('ALTER TABLE readings ADD COLUMN songSeconds REAL;');
      await db.execute('ALTER TABLE readings ADD COLUMN evidenceSeconds REAL;');
      await db.execute('ALTER TABLE readings ADD COLUMN event TEXT;');
      await db.execute('ALTER TABLE field_log ADD COLUMN passage TEXT;');
    }
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE readings ADD COLUMN bassPc INTEGER;');
    }
  }

  Future<int> addFieldEntry(FieldEntry entry) async {
    final db = await database;
    return await db.insert(
      'field_log',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<FieldEntry>> getFieldEntries() async {
    final db = await database;
    final maps = await db.query('field_log', orderBy: 'id DESC');
    return maps.map((m) => FieldEntry.fromMap(m)).toList();
  }

  Future<void> deleteFieldEntry(int id) async {
    final db = await database;
    await db.delete(
      'field_log',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearFieldEntries() async {
    final db = await database;
    await db.delete('field_log');
  }

  // Métodos para readings da avaliação de pesquisa (Fase 4.2 / Plano 3)
  Future<int> addReading({
    required String sessionId,
    required double ts,
    required String displayed,
    String? passage,
    double? songSeconds,
    double? evidenceSeconds,
    String? event,
    required String best,
    required double rBest,
    required double rDisplayed,
    required String challenge,
    required String config,
    int? bassPc,
  }) async {
    final db = await database;
    return await db.insert('readings', {
      'sessionId': sessionId,
      'ts': ts,
      'displayed': displayed,
      'passage': passage ?? '',
      'songSeconds': songSeconds ?? 0.0,
      'evidenceSeconds': evidenceSeconds ?? 0.0,
      'event': event ?? '',
      'best': best,
      'rBest': rBest,
      'rDisplayed': rDisplayed,
      'challenge': challenge,
      'config': config,
      'bassPc': bassPc ?? -1,
    });
  }

  Future<String?> getLastSessionId() async {
    final db = await database;
    final res = await db.rawQuery('SELECT sessionId FROM readings ORDER BY id DESC LIMIT 1');
    if (res.isNotEmpty) {
      return res.first['sessionId'] as String?;
    }
    return null;
  }

  Future<String> exportReadingsCsv([String? sessionId]) async {
    final db = await database;
    final targetSession = sessionId ?? await getLastSessionId();
    if (targetSession == null) return '';

    final rows = await db.query(
      'readings',
      where: 'sessionId = ?',
      whereArgs: [targetSession],
      orderBy: 'ts ASC',
    );

    final buffer = StringBuffer();
    buffer.writeln('sessionId,ts,displayed,passage,songSeconds,evidenceSeconds,event,best,rBest,rDisplayed,challenge,config,bassPc');
    for (final r in rows) {
      buffer.writeln(
        '${r['sessionId']},${r['ts']},${r['displayed']},${r['passage'] ?? ''},${r['songSeconds'] ?? 0.0},${r['evidenceSeconds'] ?? 0.0},${r['event'] ?? ''},${r['best']},${r['rBest']},${r['rDisplayed']},${r['challenge']},${r['config']},${r['bassPc'] ?? -1}',
      );
    }
    return buffer.toString();
  }
}