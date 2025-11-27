import 'package:sqflite/sqflite.dart';
import '../database.dart';
import '../models/project_model.dart';

class ProjectRepo {
  final _db = AppDatabase();

  Future<int> createProject(ProjectModel project) async {
    final db = await AppDatabase.db;
    return await db.insert('projects', project.toMap());
  }

  Future<List<ProjectModel>> getRecentProjects(int lim) async {
    final db = await AppDatabase.db;
    final res = await db.query(
      'projects',
      where: 'parent_id IS NULL',
      orderBy: 'last_accessed_at DESC',
      limit: lim,
    );
    return res.map((e) => ProjectModel.fromMap(e)).toList();
  }

  Future<List<ProjectModel>> getEvents(int projectId) async {
    final db = await AppDatabase.db;
    final res = await db.query(
      'projects',
      where: 'parent_id = ?',
      whereArgs: [projectId],
      orderBy: 'created_at DESC',
    );
    return res.map((e) => ProjectModel.fromMap(e)).toList();
  }

  Future<ProjectModel?> getProjectById(int id) async {
    final db = await AppDatabase.db;
    final res = await db.query('projects', where: 'id = ?', whereArgs: [id]);
    if (res.isNotEmpty) return ProjectModel.fromMap(res.first);
    return null;
  }

  /// 2. Get BOTH Projects and Events, sorted by recent access (For Share Page Recents)
  Future<List<ProjectModel>> getRecentProjectsAndEvents() async {
    final db = await AppDatabase.db;
    final res = await db.query(
      'projects',
      // No 'where parent_id is null' check here, we want everything
      orderBy: 'last_accessed_at DESC',
      limit: 10,
    );
    return res.map((e) => ProjectModel.fromMap(e)).toList();
  }

  /// 3. Get ALL Projects and Events, sorted alphabetically (For Share Page Search/List)
  Future<List<ProjectModel>> getAllProjectsAndEvents() async {
    final db = await AppDatabase.db;
    final res = await db.query('projects', orderBy: 'title ASC');
    return res.map((e) => ProjectModel.fromMap(e)).toList();
  }

  Future<void> updateProject(
    int id, {
    String? title,
    String? description,
  }) async {
    final db = await AppDatabase.db;
    final Map<String, dynamic> updates = {};
    if (title != null) updates['title'] = title;
    if (description != null) updates['description'] = description;

    if (updates.isNotEmpty) {
      await db.update('projects', updates, where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<void> updateStylesheet(int id, String jsonStylesheet) async {
    final db = await AppDatabase.db;
    await db.update(
      'projects',
      {'global_stylesheet': jsonStylesheet},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> touchProject(int id) async {
    final db = await AppDatabase.db;
    await db.update(
      'projects',
      {'last_accessed_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<int>> getAllSubEventIds(int projectId) async {
    final db = await AppDatabase.db;
    final res = await db.query(
      'projects',
      columns: ['id'],
      where: 'parent_id = ?',
      whereArgs: [projectId],
    );
    return res.map((e) => e['id'] as int).toList();
  }

  Future<void> deleteProject(int id) async {
    final db = await AppDatabase.db;
    await db.delete('projects', where: 'id = ?', whereArgs: [id]);
  }
}
