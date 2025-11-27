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
      version: 4, // Incremented to 4 for Comments table
      onCreate: (db, version) async {
        // 1. Images Table
        await db.execute('''
          CREATE TABLE images (
            id TEXT PRIMARY KEY,
            filePath TEXT,
            createdAt TEXT,
            analysis_data TEXT
          )
        ''');

        // 2. Categories Table
        await db.execute('''
          CREATE TABLE board_categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            createdAt TEXT
          )
        ''');

        // 3. Boards Table
        await db.execute('''
          CREATE TABLE boards (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            category_id INTEGER,
            createdAt TEXT,
            FOREIGN KEY (category_id) REFERENCES board_categories (id)
          )
        ''');

        // 4. Junction Table
        await db.execute('''
          CREATE TABLE board_images (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            board_id INTEGER,
            image_id TEXT,
            createdAt TEXT
          )
        ''');

        // 5. Comments Table (New)
        await db.execute('''
          CREATE TABLE comments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            image_id TEXT,
            content TEXT,
            comment_type TEXT,
            createdAt TEXT,
            FOREIGN KEY (image_id) REFERENCES images (id) ON DELETE CASCADE
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // ... Previous migrations (v1->v2, v2->v3) ...
        if (oldVersion < 2) {
           final tableInfo = await db.rawQuery('PRAGMA table_info(images)');
           if (!tableInfo.any((c) => c['name'] == 'analysis_data')) {
             await db.execute('ALTER TABLE images ADD COLUMN analysis_data TEXT');
           }
        }

        if (oldVersion < 3) {
           await db.execute('''
            CREATE TABLE IF NOT EXISTS board_categories (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT,
              createdAt TEXT
            )
          ''');
          final tableInfo = await db.rawQuery('PRAGMA table_info(boards)');
          if (!tableInfo.any((c) => c['name'] == 'category_id')) {
            await db.execute('ALTER TABLE boards ADD COLUMN category_id INTEGER');
          }
        }

        // Migration v3 -> v4 (Comments)
        if (oldVersion < 4) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS comments (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              image_id TEXT,
              content TEXT,
              comment_type TEXT,
              createdAt TEXT,
              FOREIGN KEY (image_id) REFERENCES images (id) ON DELETE CASCADE
            )
          ''');
        }
      },
    );
  }
}