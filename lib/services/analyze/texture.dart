// lib/services/texture_analyzer_service.dart

import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';
import '../../utils/image_utils.dart';

class TextureAnalyzerService {
  OrtSession? _session;
  Map<String, List<double>>? _centroids;

  static const int INPUT_SIZE = 224;
  static const int EMBED_DIM = 384; 
  static const int MAX_COUNT = 5;
  static const double RELATIVE_THRESH = 0.85;
  static const double ABSOLUTE_FLOOR = 0.15;

  Future<void> initialize({required String modelPath, required String jsonPath}) async {
    if (_session != null) return;

    try {
      debugPrint("Initializing Texture Service...");
      
      // Initialize ORT Environment (FFI)
      OrtEnv.instance.init();

      // 1. Load Model from passed PATH
      final sessionOptions = OrtSessionOptions();
      _session = OrtSession.fromFile(File(modelPath), sessionOptions);
      sessionOptions.release();

      // 2. Load JSON from passed PATH
      final jsonStr = await File(jsonPath).readAsString();
      final Map<String, dynamic> jsonMap = json.decode(jsonStr);
      _centroids = {};
      jsonMap.forEach((k, v) => _centroids![k] = List<double>.from(v));

    } catch (e) {
      debugPrint("Texture Service Init Error: $e");
    }
  }

  // Changed return type to Map to match other services
  Future<Map<String, dynamic>> analyze(String path, {
    String? modelPath, 
    String? jsonPath
  }) async {
    // Safety check
    if (modelPath == null || jsonPath == null) return {'success': false, 'scores': {}, 'error': 'Paths missing'};
    await initialize(modelPath: modelPath, jsonPath: jsonPath);
    if (_session == null || _centroids == null) return {'success': false, 'scores': {}, 'error': 'Init failed'};

    OrtValueTensor? inputOrt;
    OrtRunOptions? runOptions;
    List<OrtValue?>? outputs;

    try {
      // 1. Preprocess
      final bytes = await File(path).readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return {'success': false, 'scores': {}, 'error': 'Image decode failed'};

      final resized = img.copyResize(image, width: INPUT_SIZE, height: INPUT_SIZE);

      // 2. Normalize (ImageNet stats)
      final List<double> inputFloats = List.filled(1 * 3 * INPUT_SIZE * INPUT_SIZE, 0.0);
      int pixelIndex = 0;
      for (int y = 0; y < INPUT_SIZE; y++) {
        for (int x = 0; x < INPUT_SIZE; x++) {
          final pixel = resized.getPixel(x, y);
          inputFloats[pixelIndex] = ((pixel.r / 255.0) - 0.485) / 0.229;
          inputFloats[pixelIndex + (INPUT_SIZE * INPUT_SIZE)] = ((pixel.g / 255.0) - 0.456) / 0.224;
          inputFloats[pixelIndex + (2 * INPUT_SIZE * INPUT_SIZE)] = ((pixel.b / 255.0) - 0.406) / 0.225;
          pixelIndex++;
        }
      }
      
      final float32List = Float32List.fromList(inputFloats); 

      // 3. Inference
      // Create Tensor using FFI method with Float32List
      inputOrt = OrtValueTensor.createTensorWithDataList(
          float32List, [1, 3, INPUT_SIZE, INPUT_SIZE]);

      runOptions = OrtRunOptions();
      
      // Run Inference
      // 'input' is the standard name, check your model using Netron if it fails
      outputs = _session!.run(runOptions, {"input": inputOrt});
      
      if (outputs.isEmpty) throw Exception("Output tensor missing");

      // Get Output
      // FFI returns a List<OrtValue>, usually index 0 is what we want
      final dynamic outputRaw = outputs[0]?.value; 

      // Flatten output
      final List<double> rawOutput = [];
      void flatten(dynamic data) {
        if (data is num) {
          rawOutput.add(data.toDouble());
        } else if (data is List) {
          for (var item in data) {
            flatten(item);
          }
        }
      }
      flatten(outputRaw);

      // 4. Scoring (Cosine Similarity)
      Map<String, double> rawScores = {};
      _centroids!.forEach((name, centroid) {
        double sumSim = 0.0;
        int patches = 256; 
        for (int i = 0; i < patches; i++) {
           int start = i * EMBED_DIM;
           if (start + EMBED_DIM <= rawOutput.length) {
              sumSim += cosineSim(rawOutput.sublist(start, start + EMBED_DIM), centroid);
           }
        }
        rawScores[name] = sumSim / patches;
      });

      // 5. Filter & Sort
      var sorted = rawScores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      Map<String, dynamic> finalResults = {};

      for(var entry in sorted) { //.take(3)
        finalResults[entry.key] = entry.value;
      }

      // Return Map consistent with other services
      return {
        'success': true,
        'scores': finalResults,
        'error': null,
      };

    } catch (e) {
      debugPrint("Texture Analysis Failed: $e");
      return {'success': false, 'scores': {}, 'error': e.toString()};
    } finally {
      // FFI Requires manual release of C++ resources
      inputOrt?.release();
      runOptions?.release();
      outputs?.forEach((element) => element?.release());
    }
  }
  
  void dispose() {
    _session?.release();
  }
}