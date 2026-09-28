import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class FieldEntry {
  final int? id;
  final String dateTime;
  final String keyShown;
  final String secondShown;
  final double confidence;
  final String answer; // 'acertou' | 'errou'

  const FieldEntry({
    this.id,
    required this.dateTime,
    required this.keyShown,
    required this.secondShown,
    required this.confidence,
    required this.answer,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'dateTime': dateTime,
      'keyShown': keyShown,
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
      version: 2,
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
        secondShown TEXT NOT NULL,
        confidence REAL NOT NULL,
        answer TEXT NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('DROP TABLE IF EXISTS history');
      await _onCreate(db, newVersion);
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
}