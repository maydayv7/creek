// lib/services/embedding_analyzer_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:adobe/utils/image_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:onnxruntime/onnxruntime.dart';
import '../utils/clip_image_processor.dart';

class EmbeddingAnalyzerService {
  OrtSession? _session;
  List<List<double>>? _centroids;
  List<String>? _classes;

  Future<void> initialize({required String modelPath, required String jsonPath}) async {
    if (_session != null) return;

    try {
      debugPrint("Initializing Embeddings (Dino/CLIP)...");
      
      // Initialize FFI Env
      OrtEnv.instance.init();

      // 1. Load Model from passed PATH (No rootBundle!)
      final sessionOptions = OrtSessionOptions();
      _session = OrtSession.fromFile(File(modelPath), sessionOptions);
      sessionOptions.release();

      final jsonString = await File(jsonPath).readAsString();
      final jsonData = json.decode(jsonString);
      
      _classes = List<String>.from(jsonData['classes']);
      _centroids = (jsonData['centroids'] as List).map((e) => List<double>.from(e)).toList();
    } catch (e) {
      debugPrint("Embeddings Init Error: $e");
    }
  }

  Future<Map<String, dynamic>?> analyze(String imagePath, {
    String? modelPath, 
    String? jsonPath
  }) async {
    // Safety check
    if (modelPath == null || jsonPath == null) return null;
    await initialize(modelPath: modelPath, jsonPath: jsonPath);
    if (_session == null || _centroids == null) return null;

    OrtValueTensor? inputOrt;
    OrtRunOptions? runOptions;
    List<OrtValue?>? outputs;

    try {
      final float32Input = await ClipImageProcessor.preprocess(imagePath);
      if (float32Input == null) return null;

      // Create Tensor
      // Note: ensure ClipImageProcessor returns a flat List<double>
      inputOrt = OrtValueTensor.createTensorWithDataList(
        float32Input, 
        [1, 3, 224, 224]
      );

      runOptions = OrtRunOptions();

      // Run Inference
      // 'image' is the input name for CLIP. 
      outputs = _session!.run(runOptions, {"image": inputOrt});
      
      if (outputs.isEmpty) throw Exception("No output from model");

      // Get Output
      // FFI returns list of outputs. Usually index 0.
      final dynamic outputRaw = outputs[0]?.value; 

      // Flatten Output
      final List<double> imgFeat = [];
      
      void flatten(dynamic data) {
        if (data is num) {
          imgFeat.add(data.toDouble());
        } else if (data is List) {
          for (var item in data) {
            flatten(item);
          }
        }
      }
      flatten(outputRaw);

      // Normalize & Compare
      final normFeat = l2Normalize(imgFeat);
      Map<String, double> scores = {};
      
      for (int i = 0; i < _classes!.length; i++) {
        double score = dotProduct(normFeat, _centroids![i]);
        scores[_classes![i]] = score * 100.0;
      }

      scores = Map.fromEntries(
        scores.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value))
      );

      return {
        "success": true,
        "predictions": scores,
        "best": {scores.keys.first: scores.values.first},
      };

    } catch (e) {
      debugPrint("Embeddings Analysis Error: $e");
      return null;
    } finally {
      inputOrt?.release();
      runOptions?.release();
      outputs?.forEach((element) => element?.release());
    }
  }

  void dispose() {
    _session?.release();
  }
}
