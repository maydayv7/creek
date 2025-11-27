import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/clip_image_processor.dart';

class EraEmbeddingsService {
  static OrtSession? _session;
  static List<List<double>>? _centroids;
  static List<String>? _classes;

  static Future<void> initialize() async {
    if (_session != null) return;

    try {
      debugPrint("Initializing Embeddings (Dino/CLIP)...");

      final rawAsset = await rootBundle.load('assets/clip_image_encoder.onnx');
      final dir = await getTemporaryDirectory();
      final modelFile = File('${dir.path}/clip_model.onnx');

      if (!await modelFile.exists()) {
        await modelFile.writeAsBytes(rawAsset.buffer.asUint8List());
      }

      // Initialize runtime
      final ort = OnnxRuntime();
      _session = await ort.createSession(modelFile.path);

      final jsonString = await rootBundle.loadString(
        'assets/era_centroids.json',
      );
      final jsonData = json.decode(jsonString);

      _classes = List<String>.from(jsonData['classes']);
      _centroids =
          (jsonData['centroids'] as List)
              .map((e) => List<double>.from(e))
              .toList();
    } catch (e) {
      debugPrint("Embeddings Init Error: $e");
    }
  }

  static Future<Map<String, dynamic>?> analyze(String imagePath) async {
    if (_session == null) await initialize();

    OrtValue? inputOrt;
    OrtValue? outputOrt;

    try {
      final float32Input = await ClipImageProcessor.preprocess(imagePath);
      //debugPrint("[EMOTION] Preprocess length: ${float32Input?.length}");
      if (float32Input == null) return null;

      // Create Tensor
      // Note: ensure ClipImageProcessor returns a flat List<double>
      inputOrt = await OrtValue.fromList(float32Input, [1, 3, 224, 224]);

      // Run Inference
      // 'image' is the input name for CLIP. Check your model if it differs (e.g. 'input')
      final outputs = await _session!.run({"image": inputOrt});
      //debugPrint("[EMOTION] Output keys: ${outputs.keys}");

      // Get Output
      outputOrt =
          outputs['output']; // or outputs['image_features'] depending on model
      // If outputOrt is null, try iterating outputs.values.first
      final resultOrt = outputOrt ?? outputs.values.first;

      if (resultOrt == null) throw Exception("No output from model");

      // Flatten Output
      final List<dynamic> rawList = await resultOrt.asList();
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

      flatten(rawList);

      // debugPrint("[EMOTION] Embedding length: ${imgFeat.length}");
      // debugPrint("[EMOTION] Centroid length: ${_centroids?[0].length}");

      // Normalize & Compare
      final normFeat = _l2Normalize(imgFeat);
      List<Map<String, dynamic>> scores = [];

      for (int i = 0; i < _classes!.length; i++) {
        double score = _dotProduct(normFeat, _centroids![i]);
        scores.add({"name": _classes![i], "score": score * 100.0});
      }

      scores.sort(
        (a, b) => (b['score'] as double).compareTo(a['score'] as double),
      );

      return {
        "success": true,
        "label": scores.first['name'],
        "top5": scores.take(5).toList(),
      };
    } catch (e) {
      debugPrint("Embeddings Analysis Error: $e");
      return null;
    } finally {
      inputOrt?.dispose();
      outputOrt?.dispose();
    }
  }

  static List<double> _l2Normalize(List<double> vec) {
    double sum = vec.fold(0, (p, c) => p + c * c);
    double norm = sqrt(sum);
    if (norm == 0) return vec;
    return vec.map((v) => v / norm).toList();
  }

  static double _dotProduct(List<double> a, List<double> b) {
    double sum = 0;
    // Ensure lengths match to avoid range errors
    int len = min(a.length, b.length);
    for (int i = 0; i < len; i++) {
      sum += a[i] * b[i];
    }
    return sum;
  }
}
