import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'style_analyzer_service.dart'; // Ensure this import points to your ONNX service

class ImageAnalyzerService {
  // Channel for Python/Chaquopy (OpenCV)
  static const MethodChannel _channel = MethodChannel(
    'com.example.adobe/image_analyzer',
  );

  static Future<Map<String, dynamic>?> analyzeImage(String imagePath) async {
    try {
      // 1. Run BOTH analyzers in parallel (Faster performance)
      final results = await Future.wait([
        // Task A: Python OpenCV (Composition, Colors, Geometry)
        _channel.invokeMethod('analyzeImage', {'imagePath': imagePath}),
        
        // Task B: Flutter ONNX (AI Style Detection)
        StyleAnalyzerService.analyzeImage(imagePath),
      ]);

      // 2. Extract Results
      final String? pyResultJson = results[0] as String?;
      final Map<String, dynamic>? aiResultMap = results[1] as Map<String, dynamic>?;

      // 3. Parse Python Result (This is the Base)
      Map<String, dynamic> finalResult = {};
      
      if (pyResultJson != null) {
        try {
          finalResult = json.decode(pyResultJson);
        } catch (e) {
          debugPrint("Error decoding Python JSON: $e");
          // Continue even if python fails, so we can try to show AI results
          finalResult = {'success': true, 'error_partial': 'Python analysis failed'}; 
        }
      } else {
        finalResult = {'success': true};
      }

      // 4. Merge AI Style Result into the Base JSON
      if (aiResultMap != null && aiResultMap['success'] == true) {
        // We inject the style data as new keys in the existing JSON
        finalResult['style_label'] = aiResultMap['label']; // e.g., "Cyberpunk"
        finalResult['style_scores'] = aiResultMap['scores']; // Map of style probabilities
        
        // Optional: You can also merge the top5 lists if you want one unified list
        // For now, we keep them distinct so your UI logic remains simple
      }

      debugPrint("Platform analyzing image finalResult[\"style_label\"]: ${finalResult["style_label"]}, finalResult[\"style_scores\"]: ${finalResult["style_scores"]}");

      return finalResult;

    } on PlatformException catch (e) {
      debugPrint("Platform Error analyzing image: ${e.message}");
      return {'success': false, 'error': e.message ?? 'Unknown error'};
    } catch (e) {
      debugPrint("Unexpected error: $e");
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>?> analyzeColorStyle(
    String imagePath,
  ) async {
    try {
      // Logic for the new Color Analyzer
      final result = await _channel.invokeMethod('analyzeColorStyle', {
        'imagePath': imagePath,
      });
      return _parseResult(result);
    } catch (e) {
      debugPrint("Color Service Error: $e");
      return {'success': false, 'error': e.toString()};
    }
  }

  static Map<String, dynamic>? _parseResult(dynamic result) {
    if (result == null) return null;

    // 1. Check if Kotlin sent us the "raw_json" wrapper (The fix we made)
    if (result is Map && result.containsKey('raw_json')) {
      try {
        String jsonString = result['raw_json'];
        return jsonDecode(jsonString) as Map<String, dynamic>;
      } catch (e) {
        debugPrint("JSON Parse Error: $e");
        return {'success': false, 'error': "Failed to parse JSON from Python"};
      }
    }

    // 2. Fallback: If it's already a map (Old logic)
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    return null;
  }
}
