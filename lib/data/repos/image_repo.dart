// lib/data/repos/image_repo.dart

import 'package:adobe/data/database.dart';

class ImageRepository {
  Future<void> insertImage(
    String id,
    String filePath, {
    String? analysisData,
  }) async {
    final db = await AppDatabase.db;
    await db.insert("images", {
      "id": id,
      "filePath": filePath,
      "createdAt": DateTime.now().toString(),
      "analysis_data": analysisData,
    });
  }

  Future<void> updateImageAnalysis(String id, String analysisData) async {
    final db = await AppDatabase.db;
    await db.update(
      "images",
      {"analysis_data": analysisData},
      where: "id = ?",
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> getAllImages() async {
    final db = await AppDatabase.db;
    return await db.query("images");
  }

  Future<void> deleteImage(String id) async {
    final db = await AppDatabase.db;
    // Delete from images table
    await db.delete("images", where: "id = ?", whereArgs: [id]);
    // Also delete any connections to boards
    await db.delete("board_images", where: "image_id = ?", whereArgs: [id]);
  }
  
  Future<String?> getImagePath(String id) async {
    final db = await AppDatabase.db;
    final res = await db.query("images", columns: ["filePath"], where: "id = ?", whereArgs: [id]);
    if (res.isNotEmpty) return res.first["filePath"] as String;
    return null;
  }
}
