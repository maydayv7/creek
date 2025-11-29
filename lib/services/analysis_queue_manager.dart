import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../data/models/image_model.dart';
import '../data/repos/image_repo.dart';
import 'analyze/image_analyzer.dart';

class AnalysisQueueManager {
  static final AnalysisQueueManager _instance = AnalysisQueueManager._internal();
  factory AnalysisQueueManager() => _instance;
  AnalysisQueueManager._internal();

  bool _isProcessing = false;
  final _repo = ImageRepo();
  Future<void> processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      // 1. Fetch pending work from DB
      List<ImageModel> pending = await _repo.getPendingImages();

      if (pending.isEmpty) {
        _isProcessing = false;
        return;
      }

      debugPrint("[Queue]: Found ${pending.length} pending images");
      for (final image in pending) {
        await _repo.updateStatus(image.id, 'analyzing');
        try {
          Map<String, dynamic> result;

          // 2. Run Analysis
          if (image.tags.isEmpty) {
             debugPrint("[Queue]: Analyzing Full Suite: ${image.name}");
             result = await ImageAnalyzerService.analyzeFullSuite(image.filePath);
          } else {
             debugPrint("[Queue]: Analyzing Selected: ${image.name} with tags: ${image.tags}");
             result = await ImageAnalyzerService.analyzeSelected(image.filePath, image.tags);
          }

          // 3. Handle Result
          if (result['success'] == true && result['data'] != null) {
             final resultsMap = result['data']['results'] ?? {};
             final jsonString = jsonEncode(resultsMap);
             await _repo.updateAnalysis(image.id, jsonString);
             await _repo.updateStatus(image.id, 'completed');
             debugPrint("[Queue]: Completed: ${image.name}");
          } else {
             await _repo.updateStatus(image.id, 'failed');
             debugPrint("[Queue]: Failed: ${result['error']}");
          }

        } catch (e) {
          debugPrint("[Queue]: Analysis Exception: $e");
          await _repo.updateStatus(image.id, 'failed');
        }
      }
    } catch (e) {
      debugPrint("[Queue]: Critical Error: $e");
    } finally {
      _isProcessing = false;
    }
  }
}
