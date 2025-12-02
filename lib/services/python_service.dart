import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PythonService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.adobe/methods',
  );

  // 1. Layout Analysis (OpenCV)
  Future<Map<String, dynamic>> analyzeLayout(String imagePath) async {
    try {
      final String? result = await _channel.invokeMethod('analyzeLayout', {
        'imagePath': imagePath,
      });
      if (result == null) return {'success': false, 'error': 'Null response'};
      return json.decode(result);
    } catch (e) {
      debugPrint("Layout Analysis Error: $e");
      return {'success': false, 'error': e.toString()};
    }
  }

  // 2. Color Style Analysis (Scikit-Learn)
  Future<Map<String, dynamic>> analyzeColorStyle(String imagePath) async {
    try {
      final String? result = await _channel.invokeMethod('analyzeColorStyle', {
        'imagePath': imagePath,
      });
      if (result == null) return {'success': false, 'error': 'Null response'};
      return json.decode(result);
    } catch (e) {
      debugPrint("Color Analysis Error: $e");
      return {'success': false, 'error': e.toString()};
    }
  }

  // 3. Instagram Downloader
  Future<Map<String, dynamic>?> downloadInstagramImage(
    String url,
    String outputDir,
  ) async {
    try {
      final String? result = await _channel.invokeMethod(
        'downloadInstagramImage',
        {'url': url, 'outputDir': outputDir},
      );
      return result != null ? json.decode(result) : null;
    } catch (e) {
      debugPrint("Instagram Download Error: $e");
      return null;
    }
  }

  // 4. Stylesheet Generation
  Future<Map<String, dynamic>?> generateStylesheet(
    List<String> jsonList,
  ) async {
    try {
      final String? result = await _channel.invokeMethod('generateStylesheet', {
        'jsonList': jsonList,
      });
      return result != null ? json.decode(result) : null;
    } catch (e) {
      debugPrint("Stylesheet Generation Error: $e");
      return null;
    }
  }

  // 5. Magic Prompt Generation
  Future<String?> generateMagicPrompt({
    required String stylesheetJson,
    required String caption,
    required String userPrompt,
  }) async {
    try {
      final String? result = await _channel.invokeMethod('generateMagicPrompt', {
        'stylesheetJson': stylesheetJson,
        'caption': caption,
        'userPrompt': userPrompt,
      });
      return result;
    } catch (e) {
      debugPrint("Magic Prompt Generation Error: $e");
      return null;
    }
  }
}
