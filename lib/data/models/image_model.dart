import 'dart:convert';

class ImageModel {
  final String id;
  final int projectId;
  final String filePath;
  final String name;
  final List<String> tags;
  final String? analysisData;
  final DateTime createdAt;
  final String status; // NEW: 'pending', 'analyzing', 'completed', 'failed'

  ImageModel({
    required this.id,
    required this.projectId,
    required this.filePath,
    required this.name,
    this.tags = const [],
    this.analysisData,
    required this.createdAt,
    this.status = 'pending',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'project_id': projectId,
      'file_path': filePath,
      'name': name,
      'tags': jsonEncode(tags),
      'analysis_data': analysisData,
      'created_at': createdAt.toIso8601String(),
      'status': status,
    };
  }

  factory ImageModel.fromMap(Map<String, dynamic> map) {
    return ImageModel(
      id: map['id'],
      projectId: map['project_id'],
      filePath: map['file_path'],
      name: map['name'] ?? 'Untitled',
      tags:
          map['tags'] != null ? List<String>.from(jsonDecode(map['tags'])) : [],
      analysisData: map['analysis_data'],
      createdAt: DateTime.parse(map['created_at']),
      status: map['status'] ?? 'pending',
    );
  }
}
