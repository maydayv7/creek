import 'package:flutter/foundation.dart';
import 'python_service.dart';

class LayoutAnalyzerService {
  final PythonService _pythonService = PythonService();

  Future<Map<String, dynamic>?> analyze(String imagePath) async {
    try {
      debugPrint("Starting Layout Analysis...");
      return await _pythonService.analyzeLayout(imagePath);
    } catch (e) {
      debugPrint("Layout Analysis Exception: $e");
      return {'success': false, 'error': e.toString()};
    }
  }
}
