import '../database.dart';
import '../models/note_model.dart';

class NoteRepo {
  Future<int> addNote(NoteModel note) async {
    final db = await AppDatabase.db;
    return await db.insert('notes', note.toMap());
  }

  Future<List<NoteModel>> getNotesForImage(dynamic imageId) async {
    final db = await AppDatabase.db;
    final res = await db.query(
      'notes',
      where: 'image_id = ?',
      whereArgs: [imageId],
      orderBy: 'created_at DESC',
    );

    return res.map((e) => NoteModel.fromMap(e)).toList();
  }

  Future<List<NoteModel>> getPendingNotes() async {
    final db = await AppDatabase.db;
    final res = await db.query(
      'notes',
      where: 'status = ?',
      whereArgs: ['pending'],
    );
    return res.map((e) => NoteModel.fromMap(e)).toList();
  }

  Future<List<NoteModel>> getNotesByProjectId(int projectId) async {
    final db = await AppDatabase.db;
    final res = await db.rawQuery(
      '''
      SELECT notes.* FROM notes
      INNER JOIN images ON notes.image_id = images.id
      WHERE images.project_id = ?
    ''',
      [projectId],
    );
    return res.map((e) => NoteModel.fromMap(e)).toList();
  }

  Future<void> updateNote(
    int id, {
    String? content,
    String? category,
    double? normX,
    double? normY,
    double? normWidth,
    double? normHeight,
    String? analysisData,
    String? status,
    String? cropFilePath,
  }) async {
    final db = await AppDatabase.db;
    final Map<String, dynamic> updates = {};

    if (content != null) updates['content'] = content;
    if (category != null) updates['category'] = category;

    if (normX != null) updates['norm_x'] = normX;
    if (normY != null) updates['norm_y'] = normY;
    if (normWidth != null) updates['norm_width'] = normWidth;
    if (normHeight != null) updates['norm_height'] = normHeight;

    if (analysisData != null) updates['analysis_data'] = analysisData;
    if (cropFilePath != null) updates['crop_file_path'] = cropFilePath;
    if (status != null) updates['status'] = status;

    if (updates.isNotEmpty) {
      await db.update('notes', updates, where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<void> deleteNote(int id) async {
    final db = await AppDatabase.db;
    await db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }
}
