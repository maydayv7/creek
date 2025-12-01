import 'dart:convert';

class ProjectModel {
  final int? id;
  final String title;
  final String? description;
  final int? parentId; // null -> Project, int - Event
  final String? globalStylesheet; // Stored as JSON string
  final DateTime lastAccessedAt;
  final DateTime createdAt;
  final List<String> assetsPath;

  ProjectModel({
    this.id,
    required this.title,
    this.description,
    this.parentId,
    this.globalStylesheet,
    required this.lastAccessedAt,
    required this.createdAt,
    this.assetsPath = const [],
  });

  bool get isEvent => parentId != null;

  // Helper to get stylesheet as a JSON Object (Map)
  Map<String, dynamic> get styleSheetMap {
    if (globalStylesheet == null || globalStylesheet!.isEmpty) return {};
    try {
      return jsonDecode(globalStylesheet!) as Map<String, dynamic>;
    } catch (e) {
      return {};
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'parent_id': parentId,
      'global_stylesheet': globalStylesheet,
      'last_accessed_at': lastAccessedAt.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'assets_path': jsonEncode(assetsPath),
    };
  }

  factory ProjectModel.fromMap(Map<String, dynamic> map) {
    return ProjectModel(
      id: map['id'],
      title: map['title'],
      description: map['description'],
      parentId: map['parent_id'],
      globalStylesheet: map['global_stylesheet'],
      lastAccessedAt: DateTime.parse(map['last_accessed_at']),
      createdAt: DateTime.parse(map['created_at']),
      assetsPath:
        map['assets_path'] != null ? List<String>.from(jsonDecode(map['assets_path'])) : [],
    );
  }
}
