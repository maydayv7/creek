class NoteModel {
  final int? id;
  final String imageId;
  final String content;
  final String category;
  final DateTime createdAt;
  final double normX;
  final double normY;
  final double normWidth;
  final double normHeight;

  NoteModel({
    this.id,
    required this.imageId,
    required this.content,
    required this.category,
    required this.createdAt,
    this.normX = 0.5,
    this.normY = 0.5,
    this.normWidth = 0.0,
    this.normHeight = 0.0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'image_id': imageId,
      'content': content,
      'category': category,
      'created_at': createdAt.toIso8601String(),
      'norm_x': normX,
      'norm_y': normY,
      'norm_width': normWidth,
      'norm_height': normHeight,
    };
  }

  factory NoteModel.fromMap(Map<String, dynamic> map) {
    return NoteModel(
      id: map['id'],
      imageId: map['image_id'],
      content: map['content'],
      category: map['category'],
      createdAt: DateTime.parse(map['created_at']),
      normX: map['norm_x'] ?? 0.5,
      normY: map['norm_y'] ?? 0.5,
      normWidth: map['norm_width'] ?? 0.0,
      normHeight: map['norm_height'] ?? 0.0,
    );
  }
}
