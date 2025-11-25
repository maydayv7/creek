// lib/data/models/image_model.dart

import 'dart:convert';

class ImageModel {
  final String id;
  final String filePath;
  final String? analysisData;

  ImageModel({required this.id, required this.filePath, this.analysisData});

  factory ImageModel.fromMap(Map<String, dynamic> m) {
    return ImageModel(
      id: m['id'],
      filePath: m['filePath'],
      analysisData: m['analysis_data'],
    );
  }

  Map<String, dynamic>? get analysis {
    if (analysisData == null) return null;
    try {
      // analysisData is a JSON string, so we need to decode it
      if (analysisData is String) {
        return json.decode(analysisData as String) as Map<String, dynamic>;
      }
      // If it's already a Map, convert it
      return Map<String, dynamic>.from(analysisData as Map);
    } catch (e) {
      return null;
    }
  }
}
