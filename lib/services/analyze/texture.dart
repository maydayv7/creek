import 'dart:io';
import 'dart:convert';
import 'package:creekui/utils/image_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

class TextureAnalyzerService {
  OrtSession? _session;
  Map<String, List<double>>? _centroids;

  // DINOv2 Small (S14) Config
  static const int INPUT_SIZE = 224;
  static const int EMBED_DIM = 384;

  // Logic params matching your Python script
  static const double RELATIVE_THRESH = 0.85;
  static const double ABSOLUTE_FLOOR = 0.05; // Updated to match Python

  Future<void> initialize({
    required String modelPath,
    required String jsonPath,
  }) async {
    if (_session != null) return;

    try {
      debugPrint("Initializing Texture Service (DINOv2 S14)...");

      OrtEnv.instance.init();

      // 1. Load Model
      final sessionOptions = OrtSessionOptions();
      _session = OrtSession.fromFile(File(modelPath), sessionOptions);
      sessionOptions.release();

      // 2. Load Centroids
      final jsonStr = await File(jsonPath).readAsString();
      final Map<String, dynamic> jsonMap = json.decode(jsonStr);
      _centroids = {};
      jsonMap.forEach((k, v) => _centroids![k] = List<double>.from(v));
    } catch (e) {
      debugPrint("Texture Service Init Error: $e");
    }
  }

  Future<Map<String, dynamic>> analyze(
    String path, {
    String? modelPath,
    String? jsonPath,
  }) async {
    if (modelPath == null || jsonPath == null) {
      return {'success': false, 'scores': {}, 'error': 'Paths missing'};
    }
    await initialize(modelPath: modelPath, jsonPath: jsonPath);
    if (_session == null || _centroids == null) {
      return {'success': false, 'scores': {}, 'error': 'Init failed'};
    }

    OrtValueTensor? inputOrt;
    OrtRunOptions? runOptions;
    List<OrtValue?>? outputs;

    try {
      // 1. Preprocess (Standard ImageNet Normalization)
      final bytes = await File(path).readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) {
        return {'success': false, 'scores': {}, 'error': 'Decode failed'};
      }

      final resized = img.copyResize(
        image,
        width: INPUT_SIZE,
        height: INPUT_SIZE,
      );
      final List<double> inputFloats = List.filled(
        1 * 3 * INPUT_SIZE * INPUT_SIZE,
        0.0,
      );

      // ImageNet Stats
      const mean = [0.485, 0.456, 0.406];
      const std = [0.229, 0.224, 0.225];

      int pixelIndex = 0;
      for (int y = 0; y < INPUT_SIZE; y++) {
        for (int x = 0; x < INPUT_SIZE; x++) {
          final pixel = resized.getPixel(x, y);
          // R
          inputFloats[pixelIndex] = ((pixel.r / 255.0) - mean[0]) / std[0];
          // G
          inputFloats[pixelIndex + (INPUT_SIZE * INPUT_SIZE)] =
              ((pixel.g / 255.0) - mean[1]) / std[1];
          // B
          inputFloats[pixelIndex + (2 * INPUT_SIZE * INPUT_SIZE)] =
              ((pixel.b / 255.0) - mean[2]) / std[2];
          pixelIndex++;
        }
      }

      final float32List = Float32List.fromList(inputFloats);

      // 2. Inference
      inputOrt = OrtValueTensor.createTensorWithDataList(float32List, [
        1,
        3,
        INPUT_SIZE,
        INPUT_SIZE,
      ]);
      runOptions = OrtRunOptions();

      // Run Inference
      // Note: 'input' is standard for tf2onnx/torch.onnx exports
      outputs = _session!.run(runOptions, {"input": inputOrt});

      if (outputs.isEmpty) throw Exception("No output");

      // 3. Extract Feature Vector
      // The Python export script baked "Mean Pooling" into the model.
      // So we get a single vector [1, 384] directly. No need to loop patches!
      final rawOutput = outputs[0]?.value as List;
      final List<double> embedding = [];
      void flatten(dynamic data) {
        if (data is num) {
          embedding.add(data.toDouble());
        } else if (data is List) {
          for (var item in data) {
            flatten(item);
          }
        }
      }

      flatten(rawOutput);

      // 4. Normalize Embedding (L2 Norm)
      // DINOv2 cosine similarity requires normalized vectors.
      final normalizedEmbedding = l2Normalize(embedding);

      // 5. Scoring (Dot Product = Cosine Similarity)
      Map<String, double> rawScores = {};
      _centroids!.forEach((name, centroid) {
        double dot = dotProduct(normalizedEmbedding, centroid);
        rawScores[name] = dot;
      });

      // 6. Filter & Sort
      var sorted =
          rawScores.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
      Map<String, dynamic> finalResults = {};

      if (sorted.isNotEmpty) {
        double topScore = sorted.first.value;
        for (var entry in sorted) {
          if (entry.value < ABSOLUTE_FLOOR) continue;
          if (entry.value < (topScore * RELATIVE_THRESH)) break;

          finalResults[entry.key] = entry.value;
        }
      }

      return {'success': true, 'scores': finalResults, 'error': null};
    } catch (e) {
      debugPrint("Texture Analysis Failed: $e");
      return {'success': false, 'scores': {}, 'error': e.toString()};
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
