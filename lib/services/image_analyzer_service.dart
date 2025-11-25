import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:convert';

class ImageAnalyzerService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.adobe/image_analyzer',
  );

  static Future<Map<String, dynamic>?> analyzeImage(String imagePath) async {
    try {
      final String? result = await _channel.invokeMethod('analyzeImage', {
        'imagePath': imagePath,
      });

      if (result != null) {
        final Map<String, dynamic> jsonResult = json.decode(result);
        return jsonResult;
      }
      return null;
    } on PlatformException catch (e) {
      debugPrint("Error analyzing image: ${e.message}");
      return {'success': false, 'error': e.message ?? 'Unknown error occurred'};
    } catch (e) {
      debugPrint("Unexpected error: $e");
      return {'success': false, 'error': e.toString()};
    }
  }
}

