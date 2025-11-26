// lib/data/repos/board_repo.dart

import 'package:adobe/data/database.dart';

class BoardRepository {
  Future<int> createBoard(String name) async {
    final db = await AppDatabase.db;
    return await db.insert("boards", {
      "name": name,
      "createdAt": DateTime.now().toString()
    });
  }

  Future<List<Map<String, dynamic>>> getBoards() async {
    final db = await AppDatabase.db;
    return await db.query("boards");
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
