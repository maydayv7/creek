class Board {
  final int id;
  final String name;
  final String createdAt;
  final int? categoryId; // Added categoryId

  Board({
    required this.id,
    required this.name,
    required this.createdAt,
    this.categoryId, // Added categoryId to constructor
  });

  factory Board.fromMap(Map<String, dynamic> map) {
    return Board(
      id: map['id'],
      name: map['name'],
      createdAt: map['createdAt'],
      categoryId: map['category_id'], // Map category_id from DB
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt,
      'category_id': categoryId, // Include category_id in map
    };
  }
}