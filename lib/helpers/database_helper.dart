// ARQUIVO ATUALIZADO: lib/helpers/database_helper.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../screens/key_analysis_screen.dart';

class AnalysisHistory {
  final int? id;
  final String keyName;
  final double confidence;
  final String predominantNotes;
  final String dateTime;

  AnalysisHistory({
    this.id,
    required this.keyName,
    required this.confidence,
    required this.predominantNotes,
    required this.dateTime,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'keyName': keyName,
      'confidence': confidence,
      'predominantNotes': predominantNotes,
      'dateTime': dateTime,
    };
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
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE history(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        keyName TEXT NOT NULL,
        confidence REAL NOT NULL,
        predominantNotes TEXT NOT NULL,
        dateTime TEXT NOT NULL
      )
    ''');
  }

  Future<void> addAnalysis(KeyAnalysisResult result) async {
    final db = await instance.database;
    await db.insert(
      'history',
      AnalysisHistory(
        keyName: result.keyName,
        confidence: result.confidence,
        predominantNotes: result.predominantNotes.join(', '),
        dateTime: DateTime.now().toIso8601String(),
      ).toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<AnalysisHistory>> getHistory() async {
    final db = await instance.database;
    final maps = await db.query('history', orderBy: 'id DESC');
    return List.generate(maps.length, (i) {
      return AnalysisHistory(
        id: maps[i]['id'] as int,
        keyName: maps[i]['keyName'] as String,
        confidence: maps[i]['confidence'] as double,
        predominantNotes: maps[i]['predominantNotes'] as String,
        dateTime: maps[i]['dateTime'] as String,
      );
    });
  }

  // MUDANÇA 1: NOVA FUNÇÃO PARA APAGAR UM ITEM
  Future<void> deleteAnalysis(int id) async {
    final db = await instance.database;
    await db.delete(
      'history',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // MUDANÇA 2: NOVA FUNÇÃO PARA LIMPAR TODO O HISTÓRICO
  Future<void> clearHistory() async {
    final db = await instance.database;
    await db.delete('history');
  }
}