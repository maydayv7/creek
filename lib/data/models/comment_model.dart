enum CommentType {
  illustrations,
  layout,
  motif,
  typography,
  colour,
  font,
  vibe,
  other
}

class Comment {
  final int? id; // Database ID
  final String imageId; // Foreign key to the Image
  final String content; // The text content
  final CommentType type; // The category of comment
  final String createdAt; // Timestamp

  Comment({
    this.id,
    required this.imageId,
    required this.content,
    required this.type,
    required this.createdAt,
  });

  // Convert from Map (Database) to Model
  factory Comment.fromMap(Map<String, dynamic> map) {
    return Comment(
      id: map['id'] as int?,
      imageId: map['image_id'] as String,
      content: map['content'] as String,
      type: _parseType(map['comment_type'] as String),
      createdAt: map['createdAt'] as String,
    );
  }

  // Convert from Model to Map (Database)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'image_id': imageId,
      'content': content,
      'comment_type': type.name, // Stores as string e.g., "illustrations"
      'createdAt': createdAt,
    };
  }

  // Helper to parse string to Enum safely
  static CommentType _parseType(String typeString) {
    return CommentType.values.firstWhere(
      (e) => e.name == typeString,
      orElse: () => CommentType.other,
    );
  }
}