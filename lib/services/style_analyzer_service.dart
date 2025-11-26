// lib/services/style_analyzer_service.dart

import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/clip_image_processor.dart';

class StyleAnalyzerService {
  static OrtSession? _session;
  static List<List<double>>? _centroids;
  static List<String>? _classes;

  static Future<void> initialize() async {
    if (_session != null) return;

    debugPrint("Initializing AI...");
    
    // 1. Setup ONNX Environment
    OrtEnv.instance.init();
    
    // 2. Load Model from Assets
    final sessionOptions = OrtSessionOptions();
    final rawAsset = await rootBundle.load('assets/clip_image_encoder.onnx');
    final bytes = rawAsset.buffer.asUint8List();
    
    // Store temp file to load into ONNX
    final dir = await getTemporaryDirectory();
    final modelFile = File('${dir.path}/clip_model.onnx');
    await modelFile.writeAsBytes(bytes);
    
    _session = OrtSession.fromFile(modelFile, sessionOptions);

    // 3. Load Embeddings JSON
    final jsonString = await rootBundle.loadString('assets/style_embeddings.json');
    final jsonData = json.decode(jsonString);
    
    _classes = List<String>.from(jsonData['classes']);
    _centroids = (jsonData['centroids'] as List).map((e) => List<double>.from(e)).toList();
    
    debugPrint("✅ AI Ready: Loaded ${_classes!.length} styles.");
  }

  static Future<Map<String, dynamic>?> analyzeImage(String imagePath) async {
    if (_session == null) await initialize();

    try {
      // 1. Preprocess Image
      final float32Input = await ClipImageProcessor.preprocess(imagePath);
      if (float32Input == null) return null;

      // 2. Create Tensor [1, 3, 224, 224]
      final inputTensor = OrtValueTensor.createTensorWithDataList(
        float32Input, 
        [1, 3, 224, 224]
      );

      // 3. Run Inference
      final inputs = {'image': inputTensor}; // Check input name in Netron.app if 'image' fails (might be 'input')
      final runOptions = OrtRunOptions();
      final outputs = _session!.run(runOptions, inputs);
      
      // 4. Get Embedding [1, 512]
      // ONNX Runtime usually returns a List<List<double>> for 2D output
      final rawOutput = outputs[0]?.value as List; 
      // Flatten if necessary, or access [0]
      List<double> imgFeat = (rawOutput[0] as List).map((e) => e as double).toList();

      // Cleanup
      inputTensor.release();
      runOptions.release();
      for (var element in outputs) {
        element?.release();
      }

      // 5. Math: Normalize & Dot Product
      imgFeat = _l2Normalize(imgFeat);
      
      List<Map<String, dynamic>> scores = [];
      for (int i = 0; i < _classes!.length; i++) {
        double score = _dotProduct(imgFeat, _centroids![i]);
        scores.add({
          "name": _classes![i],
          "score": score * 100.0 // Scale for display
        });
      }

      // 6. Sort & Return
      scores.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));

      return {
        "success": true,
        "label": scores.first['name'],
        "top5": scores.take(5).toList(),
        "scores": { for (var e in scores) e['name'] : e['score'] }
      };

    } catch (e) {
      debugPrint("Analysis Error: $e");
      return null;
    }
  }

  // --- MATH HELPERS ---
  
  static List<double> _l2Normalize(List<double> vec) {
    double sum = 0;
    for (var v in vec) {
      sum += v * v;
    }
    double norm = sqrt(sum);
    return vec.map((v) => v / norm).toList();
  }

  static double _dotProduct(List<double> a, List<double> b) {
    double sum = 0;
    for (int i = 0; i < a.length; i++) {
      sum += a[i] * b[i];
    }
    return sum;
  }
}