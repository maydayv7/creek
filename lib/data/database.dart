// lib/data/database.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class AppDatabase {
  static Database? _db;

  static Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _init();
    return _db!;
  }

  static Future<Database> _init() async {
    final path = join(await getDatabasesPath(), 'pinterest.db');

    return await openDatabase(
      path,
      version: 2, // Incremented version to trigger migration
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE images (
            id TEXT PRIMARY KEY,
            filePath TEXT,
            createdAt TEXT,
            analysis_data TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE boards (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            createdAt TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE board_images (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            board_id INTEGER,
            image_id TEXT,
            createdAt TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Migrate from version 1 to version 2: Add analysis_data column
        if (oldVersion < 2) {
          // Check if column exists before adding
          final tableInfo = await db.rawQuery('PRAGMA table_info(images)');
          final hasAnalysisData = tableInfo.any(
            (column) => column['name'] == 'analysis_data',
          );

          if (!hasAnalysisData) {
            await db.execute('''
              ALTER TABLE images ADD COLUMN analysis_data TEXT
            ''');
          }
        }
      },
    );
  }
}
