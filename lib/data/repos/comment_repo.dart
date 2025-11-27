import 'package:adobe/data/database.dart';
import 'package:adobe/data/models/comment_model.dart';

class CommentRepository {
  // Add a new comment to the database
  Future<int> addComment(Comment comment) async {
    final db = await AppDatabase.db;
    return await db.insert('comments', comment.toMap());
  }

  // Retrieve all comments for a specific image
  Future<List<Comment>> getCommentsForImage(String imageId) async {
    final db = await AppDatabase.db;
    final result = await db.query(
      'comments',
      where: 'image_id = ?',
      whereArgs: [imageId],
      orderBy: 'createdAt DESC', // Most recent comments first
    );

    return result.map((e) => Comment.fromMap(e)).toList();
  }

  // Optional: Delete a comment
  Future<int> deleteComment(int id) async {
    final db = await AppDatabase.db;
    return await db.delete(
      'comments',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}