import 'dart:convert';
import '../database.dart';
import '../models/file_model.dart';

class FileRepo {
  Future<void> addFile(FileModel file) async {
    final db = await AppDatabase.db;
    await db.insert('files', file.toMap());
  }

  Future<List<FileModel>> getFiles(int projectId) async {
    final db = await AppDatabase.db;
    final res = await db.query(
      'files',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'last_updated DESC',
    );
    return res.map((e) => FileModel.fromMap(e)).toList();
  }

  Future<FileModel?> getById(String id) async {
    final db = await AppDatabase.db;
    final res = await db.query('files', where: 'id = ?', whereArgs: [id]);
    if (res.isNotEmpty) return FileModel.fromMap(res.first);
    return null;
  }

  Future<void> updateDetails(
    String id, {
    String? name,
    String? description,
    List<String>? tags,
  }) async {
    final db = await AppDatabase.db;
    final Map<String, dynamic> updates = {
      'last_updated': DateTime.now().toIso8601String(),
    };
    if (name != null) updates['name'] = name;
    if (description != null) updates['description'] = description;
    if (tags != null) updates['tags'] = jsonEncode(tags);

    await db.update('files', updates, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> touchFile(String id) async {
    final db = await AppDatabase.db;
    await db.update(
      'files',
      {'last_updated': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteFile(String id) async {
    final db = await AppDatabase.db;
    await db.delete('files', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<String>> getAllFilePathsForProjectIds(
    List<int> projectIds,
  ) async {
    if (projectIds.isEmpty) return [];
    final db = await AppDatabase.db;
    final idList = projectIds.join(',');
    final res = await db.rawQuery(
      'SELECT file_path FROM files WHERE project_id IN ($idList)',
    );
    return res.map((e) => e['file_path'] as String).toList();
  }

  Future<List<FileModel>> getRecentFiles({int limit = 10}) async {
    final db = await AppDatabase.db;
    final res = await db.query(
      'files',
      orderBy: 'last_updated DESC',
      limit: limit,
    );
    return res.map((e) => FileModel.fromMap(e)).toList();
  }
}
