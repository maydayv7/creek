import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import 'models/project_model.dart';
import 'models/image_model.dart';
import 'models/file_model.dart';
import 'models/note_model.dart';

class AppDatabase {
  static Database? _db;
  static const String _dbName = 'database_v6.db';

  static Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _init();
    return _db!;
  }

  static Future<Database> _init() async {
    final path = join(await getDatabasesPath(), _dbName);

    return await openDatabase(
      path,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        // 1. PROJECTS
        await db.execute('''
          CREATE TABLE projects (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            description TEXT,
            parent_id INTEGER, 
            global_stylesheet TEXT,
            last_accessed_at TEXT,
            created_at TEXT,
            FOREIGN KEY (parent_id) REFERENCES projects (id) ON DELETE CASCADE
          )
        ''');

        // Create Inbox Project (ID 0) for Drafts
        await db.rawInsert(
          '''
          INSERT INTO projects (id, title, description, last_accessed_at, created_at)
          VALUES (0, 'Inbox', 'Holding area for shared images', ?, ?)
        ''',
          [DateTime.now().toIso8601String(), DateTime.now().toIso8601String()],
        );

        // 2. IMAGES (Moodboard)
        await db.execute('''
          CREATE TABLE images (
            id TEXT PRIMARY KEY,
            project_id INTEGER NOT NULL,
            file_path TEXT NOT NULL,
            name TEXT,
            tags TEXT DEFAULT '[]', 
            analysis_data TEXT,
            created_at TEXT,
            status TEXT DEFAULT 'pending',
            FOREIGN KEY (project_id) REFERENCES projects (id) ON DELETE CASCADE
          )
        ''');

        // 3. FILES (Project Work)
        await db.execute('''
          CREATE TABLE files (
            id TEXT PRIMARY KEY,
            project_id INTEGER NOT NULL,
            file_path TEXT NOT NULL,
            name TEXT,
            description TEXT,
            tags TEXT DEFAULT '[]',
            last_updated TEXT,
            created_at TEXT,
            FOREIGN KEY (project_id) REFERENCES projects (id) ON DELETE CASCADE
          )
        ''');

        // 4. NOTES
        await db.execute('''
          CREATE TABLE notes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            image_id TEXT NOT NULL,
            content TEXT NOT NULL,
            category TEXT NOT NULL,
            created_at TEXT,
            norm_x REAL DEFAULT 0.5,
            norm_y REAL DEFAULT 0.5,
            norm_width REAL DEFAULT 0.0,
            norm_height REAL DEFAULT 0.0,
            analysis_data TEXT,
            crop_file_path TEXT,
            status TEXT DEFAULT 'pending',
            FOREIGN KEY (image_id) REFERENCES images (id) ON DELETE CASCADE
          )
        ''');
      },
    );
  }
}
