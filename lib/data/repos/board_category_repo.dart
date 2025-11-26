import 'package:adobe/data/database.dart';

class BoardCategoryRepository {
  Future<int> createCategory(String name) async {
    final db = await AppDatabase.db;
    return await db.insert('board_categories', {
      'name': name,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getAllCategories() async {
    final db = await AppDatabase.db;
    return await db.query('board_categories', orderBy: 'createdAt DESC');
  }

  Future<List<Map<String, dynamic>>> getBoardsByCategory(int categoryId) async {
    final db = await AppDatabase.db;
    return await db.query(
      'boards',
      where: 'category_id = ?',
      whereArgs: [categoryId],
      orderBy: 'createdAt DESC',
    );
  }
}