import 'dart:convert';

class ImageModel {
  final String id;
  final String filePath;
  final String? analysisData;
  final String? name; // Optional name
  final List<String>? tags; // Optional list of tags

  ImageModel({
    required this.id,
    required this.filePath,
    this.analysisData,
    this.name,
    this.tags,
  });

  factory ImageModel.fromMap(Map<String, dynamic> m) {
    // Helper to parse tags from JSON string or List
    List<String>? parseTags(dynamic tagsData) {
      if (tagsData == null) return null;
      if (tagsData is List) {
        return tagsData.map((e) => e.toString()).toList();
      }
      if (tagsData is String) {
        try {
          // If stored as JSON string ["tag1", "tag2"]
          final decoded = json.decode(tagsData);
          if (decoded is List) {
            return decoded.map((e) => e.toString()).toList();
          }
        } catch (e) {
          // Fallback: maybe comma separated?
          return tagsData.split(',').map((e) => e.trim()).toList();
        }
      }
      return null;
    }

    return ImageModel(
      id: m['id'],
      filePath: m['filePath'],
      analysisData: m['analysis_data'],
      name: m['name'],
      tags: parseTags(m['tags']),
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
  
  // You might want a toMap for saving back to DB if not already present elsewhere
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'filePath': filePath,
      'analysis_data': analysisData,
      'name': name,
      // Store tags as JSON string in SQLite usually
      'tags': tags != null ? json.encode(tags) : null,
    };
  }
}
