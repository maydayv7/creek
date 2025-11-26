class BoardCategory {
  final int id;
  final String name;
  final String createdAt;

  BoardCategory({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  factory BoardCategory.fromMap(Map<String, dynamic> map) {
    return BoardCategory(
      id: map['id'],
      name: map['name'],
      createdAt: map['createdAt'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt,
    };
  }
}