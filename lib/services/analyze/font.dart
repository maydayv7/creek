import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:image/image.dart' as img;

class FontIdentifierService {
  OrtSession? _session;
  Map<String, List<double>>? _fontDb;
  final _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  static const int IMG_SIZE = 64;

  Future<void> initialize({required String modelPath, required String jsonPath}) async {
    if (_session != null) return;

    try {
      debugPrint("Initializing Font Service...");
      OrtEnv.instance.init();

      // 1. Load ONNX
      final sessionOptions = OrtSessionOptions();
      _session = OrtSession.fromFile(File(modelPath), sessionOptions);
      sessionOptions.release();

      // 2. Load JSON DB
      final jsonStr = await File(jsonPath).readAsString();
      final Map<String, dynamic> rawDb = json.decode(jsonStr);
      _fontDb = {};
      rawDb.forEach((key, value) {
        _fontDb![key] = List<double>.from(value);
      });
    } catch (e) {
      debugPrint("Font Service Init Error: $e");
    }
  }

  Future<Map<String, dynamic>> analyze(String imagePath, {
    String? modelPath, 
    String? jsonPath
  }) async {
    if (modelPath == null || jsonPath == null) return {'success': false, 'scores': {}, 'error': 'Paths missing'};
    await initialize(modelPath: modelPath, jsonPath: jsonPath);
    if (_session == null || _fontDb == null) return {'success': false, 'scores': {}, 'error': 'Init failed'};

    try {
      // 1. OCR Detection (Native Platform Call)
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognizedText = await _textRecognizer.processImage(inputImage);
      
      if (recognizedText.blocks.isEmpty) {
        return {'success': true, 'scores': {'No Text Detected': 1.0}, 'error': null};
      }

      // 2. Load Image for Processing
      final bytes = await File(imagePath).readAsBytes();
      final fullImage = img.decodeImage(bytes);
      if (fullImage == null) return {'success': false, 'scores': {}, 'error': 'Image decode failed'};

      // Store counts to find dominant font
      Map<String, double> fontCounts = {};
      int totalBlocks = 0;

      // 3. Iterate Text Blocks
      for (TextBlock block in recognizedText.blocks) {
        for (TextLine line in block.lines) {
          
          // Crop
          final rect = line.boundingBox;
          
          // Safety check for bounds
          int x = max(0, rect.left.toInt());
          int y = max(0, rect.top.toInt());
          int w = min(rect.width.toInt(), fullImage.width - x);
          int h = min(rect.height.toInt(), fullImage.height - y);

          if (w <= 0 || h <= 0) continue;

          final crop = img.copyCrop(fullImage, x: x, y: y, width: w, height: h);

          // Preprocess & Inference
          final floatInput = _preprocessImage(crop);
          final embedding = _runInference(floatInput);
          final match = _findBestFont(embedding);

          // Aggregate Scores
          final fontName = match.key;
          final conf = match.value;
          
          if (fontCounts.containsKey(fontName)) {
            fontCounts[fontName] = fontCounts[fontName]! + conf;
          } else {
            fontCounts[fontName] = conf;
          }
          totalBlocks++;
        }
      }

      // Normalize scores
      fontCounts.updateAll((key, value) => (value / totalBlocks) * 100);

      // Sort
      var sorted = fontCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      Map<String, dynamic> finalScores = {};
      for(var entry in sorted) {
        finalScores[entry.key] = entry.value;
      }

      return {
        'success': true,
        'scores': finalScores,
        'error': null,
      };

    } catch (e) {
      debugPrint("Font Analysis Failed: $e");
      return {'success': false, 'scores': {}, 'error': e.toString()};
    }
  }

  /// Convert crop to 64x64 Grayscale Thresholded Float32List
  Float32List _preprocessImage(img.Image crop) {
    // Resize to 64x64
    final resized = img.copyResize(crop, width: IMG_SIZE, height: IMG_SIZE);
    final pixels = Float32List(IMG_SIZE * IMG_SIZE);
    
    // 1. Calculate Mean Brightness (Adaptive Threshold)
    double totalLum = 0;
    for (final pixel in resized) {
      totalLum += pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114; 
    }
    double mean = totalLum / (IMG_SIZE * IMG_SIZE);

    // 2. Binarize (Inverted: Text=1.0, BG=0.0)
    int idx = 0;
    for (int y = 0; y < IMG_SIZE; y++) {
      for (int x = 0; x < IMG_SIZE; x++) {
        final p = resized.getPixel(x, y);
        final lum = p.r * 0.299 + p.g * 0.587 + p.b * 0.114;
        // If pixel is darker than mean, it's text (1.0)
        pixels[idx++] = (lum < mean) ? 1.0 : 0.0;
      }
    }
    return pixels;
  }

  List<double> _runInference(Float32List imageFloats) {
    OrtValueTensor? imgTensor;
    OrtValueTensor? charTensor;
    OrtRunOptions? runOptions;
    List<OrtValue?>? outputs;

    try {
      // Input 1: Image [1, 64, 64, 1]
      imgTensor = OrtValueTensor.createTensorWithDataList(
        imageFloats, [1, 64, 64, 1]
      );

      // Input 2: Dummy Char [1, 26, 1] (Required by FANNet architecture)
      final dummyFloats = Float32List(26 * 1); 
      charTensor = OrtValueTensor.createTensorWithDataList(
        dummyFloats, [1, 26, 1]
      );

      runOptions = OrtRunOptions();
      
      // Run
      outputs = _session!.run(runOptions, {
        'image_input': imgTensor,
        'char_input': charTensor
      });

      // Output Flattening
      final rawOutput = outputs[0]?.value; 
      final List<double> flatOutput = [];
      
      void flatten(dynamic d) {
        if (d is num) flatOutput.add(d.toDouble());
        else if (d is List) for(var i in d) flatten(i);
      }
      flatten(rawOutput);
      
      return flatOutput;

    } finally {
      imgTensor?.release();
      charTensor?.release();
      runOptions?.release();
      outputs?.forEach((e) => e?.release());
    }
  }

  MapEntry<String, double> _findBestFont(List<double> embedding) {
    String bestFont = "Unknown";
    double minDist = double.infinity;

    _fontDb!.forEach((fontName, fontFeat) {
      double sum = 0;
      for (int i = 0; i < min(embedding.length, fontFeat.length); i++) {
        double diff = embedding[i] - fontFeat[i];
        sum += diff * diff;
      }
      double dist = sqrt(sum);
      
      if (dist < minDist) {
        minDist = dist;
        bestFont = fontName;
      }
    });

    return MapEntry(bestFont, 1 / (1 + minDist));
  }

  void dispose() {
    _session?.release();
    _textRecognizer.close();
  }
}
