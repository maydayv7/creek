import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:path_provider/path_provider.dart';

class TextureAnalyzerService {
  OrtSession? _session;
  Map<String, List<double>>? _centroids;

  static const int INPUT_SIZE = 224;
  static const int EMBED_DIM = 384; 
  static const int MAX_COUNT = 5;
  static const double RELATIVE_THRESH = 0.85;
  static const double ABSOLUTE_FLOOR = 0.15;

  Future<void> _loadResources() async {
    if (_session != null) return;

    try {
      debugPrint("Initializing Texture Service...");
      final dir = await getApplicationDocumentsDirectory();
      final modelFile = File('${dir.path}/dinov2.onnx');
      final dataFile = File('${dir.path}/dinov2.onnx.data'); 

      if (!await modelFile.exists()) {
        final data = await rootBundle.load('assets/dinov2.onnx');
        await modelFile.writeAsBytes(data.buffer.asUint8List(), flush: true);
      }

      // Check for external data file
      if (!await dataFile.exists()) {
         try {
           final data = await rootBundle.load('assets/dinov2.onnx.data');
           await dataFile.writeAsBytes(data.buffer.asUint8List(), flush: true);
         } catch (_) { 
           // External data might not exist for all models
         }
      }

      _session = await OnnxRuntime().createSession(modelFile.path);

      final jsonStr = await rootBundle.loadString('assets/texture_centroids.json');
      final Map<String, dynamic> jsonMap = json.decode(jsonStr);
      _centroids = {};
      jsonMap.forEach((k, v) => _centroids![k] = List<double>.from(v));

    } catch (e) {
      debugPrint("Texture Service Init Error: $e");
    }
  }

  Future<List<Map<String, dynamic>>> analyze(String path) async {
    await _loadResources();
    if (_session == null || _centroids == null) return [];

    OrtValue? inputOrt;
    OrtValue? outputOrt;

    try {
      // 1. Preprocess
      final bytes = await File(path).readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return [];

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

      // 3. Inference
      inputOrt = await OrtValue.fromList(inputFloats, [1, 3, INPUT_SIZE, INPUT_SIZE]);
      final outputs = await _session!.run({"input": inputOrt});
      outputOrt = outputs['output'];
      
      if (outputOrt == null) throw Exception("Output tensor missing");

      // Flatten output
      final dynamic outputRaw = await outputOrt.asList();
      final List<double> rawOutput = [];
      void flatten(dynamic data) {
        if (data is num) rawOutput.add(data.toDouble());
        else if (data is List) for (var item in data) flatten(item);
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
             sumSim += _cosineSim(rawOutput.sublist(start, start + EMBED_DIM), centroid);
          }
        }
        rawScores[name] = sumSim / patches;
      });

      // 5. Filter & Sort
      var sorted = rawScores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      List<Map<String, dynamic>> finalResults = [];

      if (sorted.isNotEmpty) {
        double topScore = sorted.first.value;
        for (var entry in sorted) {
          if (finalResults.length >= MAX_COUNT) break;
          if (entry.value < ABSOLUTE_FLOOR) continue;
          if (entry.value < (topScore * RELATIVE_THRESH)) break;
          
          finalResults.add({'name': entry.key, 'score': entry.value});
        }
      }
      return finalResults;

    } catch (e) {
      debugPrint("Texture Analysis Failed: $e");
      return [];
    } finally {
      inputOrt?.dispose();
      outputOrt?.dispose();
    }
  }

  double _cosineSim(List<double> a, List<double> b) {
    double dot = 0.0, nA = 0.0, nB = 0.0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      nA += a[i] * a[i];
      nB += b[i] * b[i];
    }
    return (nA == 0 || nB == 0) ? 0.0 : dot / (sqrt(nA) * sqrt(nB));
  }
  
  void dispose() {
    _session?.close();
  }
}
