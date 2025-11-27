import 'package:flutter/foundation.dart';
import 'python_service.dart';

class ColorAnalyzerService {
  final PythonService _pythonService = PythonService();

  Future<Map<String, dynamic>?> analyze(String imagePath) async {
    try {
      debugPrint("Starting Color Style Analysis...");
      return await _pythonService.analyzeColorStyle(imagePath);
    } catch (e) {
      debugPrint("Color Analysis Exception: $e");
      return {'success': false, 'error': e.toString()};
    }
  }
}
