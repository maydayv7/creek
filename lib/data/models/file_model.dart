import 'dart:convert';

class FileMetadataInfo {
  final double width;
  final double height;
  final String? previewPath;

  FileMetadataInfo({this.width = 0, this.height = 0, this.previewPath});

  String get dimensions => '${width.toInt()} x ${height.toInt()} px';
}

class FileModel {
  final String id;
  final int projectId;
  final String filePath;
  final String name;
  final String? description;
  final List<String> tags;
  final DateTime lastUpdated;
  final DateTime createdAt;

  FileModel({
    required this.id,
    required this.projectId,
    required this.filePath,
    required this.name,
    this.description,
    this.tags = const [],
    required this.lastUpdated,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'project_id': projectId,
      'file_path': filePath,
      'name': name,
      'description': description,
      'tags': jsonEncode(tags),
      'last_updated': lastUpdated.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory FileModel.fromMap(Map<String, dynamic> map) {
    return FileModel(
      id: map['id'],
      projectId: map['project_id'],
      filePath: map['file_path'],
      name: map['name'] ?? 'Untitled',
      description: map['description'],
      tags:
          map['tags'] != null ? List<String>.from(jsonDecode(map['tags'])) : [],
      lastUpdated:
          map['last_updated'] != null
              ? DateTime.parse(map['last_updated'])
              : DateTime.parse(map['created_at']),
      createdAt: DateTime.parse(map['created_at']),
    );
  }
}
