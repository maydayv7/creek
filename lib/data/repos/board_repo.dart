import 'package:adobe/data/database.dart';

class BoardRepository {
  // Updated to accept optional categoryId
  Future<int> createBoard(String name, {int? categoryId}) async {
    final db = await AppDatabase.db;
    return await db.insert("boards", {
      "name": name,
      "category_id": categoryId, // Save the category link
      "createdAt": DateTime.now().toString()
    });
  }

  Future<List<Map<String, dynamic>>> getBoards() async {
    final db = await AppDatabase.db;
    return await db.query("boards", orderBy: "createdAt DESC");
  }

  Future<void> updateBoardName(int id, String newName) async {
    final db = await AppDatabase.db;
    await db.update(
      "boards",
      {"name": newName},
      where: "id = ?",
      whereArgs: [id],
    );
  }

  Future<void> deleteBoard(int id) async {
    final db = await AppDatabase.db;
    await db.delete("boards", where: "id = ?", whereArgs: [id]);
    // Remove associations (images stay in "All Images", but link to board is gone)
    await db.delete("board_images", where: "board_id = ?", whereArgs: [id]);
  }
}
