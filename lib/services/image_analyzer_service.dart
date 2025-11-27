import 'dart:convert';
import 'package:flutter/foundation.dart';

// Import the segregated services
import 'layout_analyzer_service.dart';
import 'color_analyzer_service.dart';
import 'texture_analyzer_service.dart';
import 'embedding_analyzer_service.dart';
import 'emotional_embeddings_service.dart'; 
import 'lighting_service.dart';

class ImageAnalyzerService {
  /// Runs all 4 analysis tools in parallel and returns a combined JSON Map.
  static Future<Map<String, dynamic>> analyzeFullSuite(String imagePath) async {
    // 1. Instantiate services
    final layoutService = LayoutAnalyzerService();
    final colorService = ColorAnalyzerService();
    final textureService = TextureAnalyzerService();
    // EmbeddingService is static

    try {
      // 2. Run in parallel for performance
      final results = await Future.wait([
        layoutService.analyze(imagePath),           // Index 0: Layout
        colorService.analyze(imagePath),            // Index 1: Color
        textureService.analyze(imagePath),          // Index 2: Texture
        EmbeddingAnalyzerService.analyze(imagePath) // Index 3: Embeddings
      ]);

      // 3. Construct Unified Result
      final Map<String, dynamic> combinedResult = {
        'success': true,
        'timestamp': DateTime.now().toIso8601String(),
        'layout': results[0],
        'color': results[1],
        'texture': results[2],   // This is a List
        'embedding': results[3],
      };

      return combinedResult;

    } catch (e) {
      debugPrint("Master Analysis Failed: $e");
      return {
        'success': false,
        'error': e.toString(),
      };
    } finally {
      // 4. Cleanup heavy resources
      textureService.dispose();
    }
  }
}
