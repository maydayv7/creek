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
}
