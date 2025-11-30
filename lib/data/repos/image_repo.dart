import 'dart:convert';
import '../database.dart';
import '../models/image_model.dart';

class ImageRepo {
  Future<void> addImage(ImageModel image) async {
    final db = await AppDatabase.db;
    await db.insert('images', image.toMap());
  }

  Future<List<ImageModel>> getImages(int projectId) async {
    final db = await AppDatabase.db;
    final res = await db.query(
      'images',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'created_at DESC',
    );
    return res.map((e) => ImageModel.fromMap(e)).toList();
  }

  Future<ImageModel?> getById(String id) async {
    final db = await AppDatabase.db;
    final res = await db.query('images', where: 'id = ?', whereArgs: [id]);
    if (res.isNotEmpty) return ImageModel.fromMap(res.first);
    return null;
  }

  Future<ImageModel?> getByFilePath(String path) async {
    final db = await AppDatabase.db;
    final res = await db.query(
      'images',
      where: 'file_path = ?',
      whereArgs: [path],
      limit: 1,
    );
    if (res.isNotEmpty) return ImageModel.fromMap(res.first);
    return null;
  }

  Future<void> updateProject(String id, int projectId) async {
    final db = await AppDatabase.db;
    await db.update(
      'images',
      {'project_id': projectId},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<ImageModel>> getPendingImages() async {
    final db = await AppDatabase.db;
    final res = await db.query(
      'images',
      where: 'status = ? OR status = ?',
      whereArgs: ['pending', 'analyzing'],
    );
    return res.map((e) => ImageModel.fromMap(e)).toList();
  }

  Future<void> updateStatus(String id, String status) async {
    final db = await AppDatabase.db;
    await db.update(
      'images',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<String>> getTagsForImage(dynamic id) async {
    final db = await AppDatabase.db;
    final res = await db.query(
      'images',
      columns: ['tags'],
      where: 'id = ?',
      whereArgs: [id],
    );

    if (res.isNotEmpty && res.first['tags'] != null) {
      try {
        // Decode the JSON string stored in the DB back to a List<String>
        final tagsJson = res.first['tags'] as String;
        if (tagsJson.isEmpty) return [];

        final List<dynamic> decoded = jsonDecode(tagsJson);
        return decoded.map((e) => e.toString()).toList();
      } catch (e) {
        print("Error decoding tags: $e");
        return [];
      }
    }
    return [];
  }

  Future<void> updateAnalysis(String id, String analysisData) async {
    final db = await AppDatabase.db;
    await db.update(
      'images',
      {'analysis_data': analysisData},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateTags(String id, List<String> tags) async {
    final db = await AppDatabase.db;
    await db.update(
      'images',
      {'tags': jsonEncode(tags)},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteImage(String id) async {
    final db = await AppDatabase.db;
    await db.delete('images', where: 'id = ?', whereArgs: [id]);
  }

  // Helper for Project Deletion Service
  Future<List<String>> getAllFilePathsForProjectIds(
    List<int> projectIds,
  ) async {
    if (projectIds.isEmpty) return [];
    final db = await AppDatabase.db;
    final idList = projectIds.join(',');
    final res = await db.rawQuery(
      'SELECT file_path FROM images WHERE project_id IN ($idList)',
    );
    return res.map((e) => e['file_path'] as String).toList();
  }
}
