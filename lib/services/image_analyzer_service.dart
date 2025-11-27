// lib/services/image_analyzer_service.dart

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

// Import analysis services
import 'layout_analyzer_service.dart';
import 'color_analyzer_service.dart';
import 'texture_analyzer_service.dart';
import 'embedding_analyzer_service.dart';
import 'emotional_embeddings_service.dart';
import 'lighting_service.dart';

class ImageAnalyzerService {

  /// Prepare ALL assets (Models + JSONs) on Main Thread.
  /// Returns a map of absolute paths.
  static Future<Map<String, String>> _prepareAssets() async {
    final dir = await getApplicationDocumentsDirectory();

    Future<String> copy(String assetName, {String? filename}) async {
      final name = filename ?? assetName;
      final file = File('${dir.path}/$name');
      // Only copy if it doesn't exist or is empty
      if (!await file.exists() || await file.length() == 0) {
        final data = await rootBundle.load('assets/$assetName');
        await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      }
      return file.path;
    }

    // Copy everything needed by the services
    // Make sure your assets/ folder actually contains these files!
    final paths = await Future.wait([
      // Texture
      copy('dinov2.onnx'), 
      copy('dinov2.onnx.data'),
      copy('texture_centroids.json'),
      
      // CLIP (Embeddings/Emotion/Lighting)
      copy('clip_image_encoder.onnx'),
      copy('style_embeddings.json'),
      copy('emotion_centroids.json'),
      copy('lighting_centroids.json'),
    ]);

    return {
      'texture_model': paths[0],
      // paths[1] is .data, implicit
      'texture_json': paths[2],
      'clip_model': paths[3],
      'embedding_json': paths[4],
      'emotion_json': paths[5],
      'lighting_json': paths[6],
    };
  }

  static Future<Map<String, dynamic>> _runProfiledJob({
    required String name, 
    required String imagePath,
    required RootIsolateToken rootToken,
    required bool runInIsolate,
    // Pass config map to the task
    required Map<String, String> assetPaths,
    required Future<dynamic> Function(String, Map<String, String>) task,
  }) async {
    final stopwatch = Stopwatch()..start();
    final dev.TimelineTask timelineTask = dev.TimelineTask();
    timelineTask.start('Analyze: $name'); 

    try {
      dynamic result;

      if (runInIsolate) {
        // PARALLEL (Isolate)
        result = await Isolate.run(() async {
          BackgroundIsolateBinaryMessenger.ensureInitialized(rootToken);
          DartPluginRegistrant.ensureInitialized();
          return await task(imagePath, assetPaths);
        });
      } else {
        // CONCURRENT (Main Thread)
        result = await task(imagePath, assetPaths);
      }
      
      stopwatch.stop();
      timelineTask.finish();

      return {
        'data': result,
        'stats': {'execution_time_ms': stopwatch.elapsedMilliseconds}
      };
    } catch (e) {
      stopwatch.stop();
      timelineTask.finish();
      debugPrint("[$name] Failed: $e");
      return {'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> analyzeFullSuite(String imagePath) async {
    final totalSw = Stopwatch()..start();

    final RootIsolateToken? token = RootIsolateToken.instance;
    if (token == null) {
      throw Exception("RootIsolateToken is null.");
    }

    try {
      // 1. Prepare Assets on Main Thread (Safe)
      final assetPaths = await _prepareAssets();

      // 2. Run Analysis
      final results = await Future.wait([
        
        // --- GROUP A: MAIN THREAD (Python) ---
        _runProfiledJob(
          name: 'Layout', imagePath: imagePath, rootToken: token, runInIsolate: false, 
          assetPaths: assetPaths,
          task: (path, _) => LayoutAnalyzerService().analyze(path)
        ),
        
        _runProfiledJob(
          name: 'Color', imagePath: imagePath, rootToken: token, runInIsolate: false, 
          assetPaths: assetPaths,
          task: (path, _) => ColorAnalyzerService().analyze(path)
        ),
        
        // --- GROUP B: PARALLEL (ONNX FFI) ---
        // Notice we pass assetPaths to the tasks
        
        _runProfiledJob(
          name: 'Texture', imagePath: imagePath, rootToken: token, runInIsolate: true, 
          assetPaths: assetPaths,
          task: (path, assets) async {
             final service = TextureAnalyzerService();
             // Pass specific paths
             final res = await service.analyze(path, 
                modelPath: assets['texture_model'], 
                jsonPath: assets['texture_json']
             );
             service.dispose(); 
             return res;
          }
        ),

        _runProfiledJob(
          name: 'Embedding', imagePath: imagePath, rootToken: token, runInIsolate: true, 
          assetPaths: assetPaths,
          task: (path, assets) async {
             final service = EmbeddingAnalyzerService(); 
             final res = await service.analyze(path,
                modelPath: assets['clip_model'],
                jsonPath: assets['embedding_json']
             );
             service.dispose();
             return res;
          }
        ),

        _runProfiledJob(
          name: 'Emotional', imagePath: imagePath, rootToken: token, runInIsolate: true, 
          assetPaths: assetPaths,
          task: (path, assets) async {
             final service = EmotionalEmbeddingsService();
             final res = await service.analyze(path,
                modelPath: assets['clip_model'],
                jsonPath: assets['emotion_json']
             );
             service.dispose();
             return res;
          }
        ),

        _runProfiledJob(
          name: 'Lighting', imagePath: imagePath, rootToken: token, runInIsolate: true, 
          assetPaths: assetPaths,
          task: (path, assets) async {
             final service = LightingEmbeddingsService();
             final res = await service.analyze(path,
                modelPath: assets['clip_model'],
                jsonPath: assets['lighting_json']
             );
             service.dispose();
             return res;
          }
        ),
      ]);

      totalSw.stop();

      final finalResult = {
        'success': true,
        'total_time_ms': totalSw.elapsedMilliseconds,
        'timestamp': DateTime.now().toIso8601String(),
        'results': {
          'layout': results[0],
          'color': results[1],
          'texture': results[2],
          'embedding': results[3],
          'emotions': results[4],
          'lighting': results[5],
        }
      };

      _logSummary(finalResult);
      print("\n\n\n layout: ${results[0]} \n\n\n");
      print("color: ${results[1]} \n\n\n");
      print("texture: ${results[2]} \n\n\n");
      print("embedding: ${results[3]} \n\n\n");
      print("emotions: ${results[4]} \n\n\n");
      print("lighting: ${results[5]} \n\n\n");
      return finalResult;

    } catch (e) {
      debugPrint("Master Analysis Failed: $e");
      return {'success': false, 'error': e.toString()};
    }
  }

  static void _logSummary(Map<String, dynamic> result) {
    // ... (Keep your existing log summary code) ...
    final int total = result['total_time_ms'];
    final Map<String, dynamic> subTasks = result['results'];

    StringBuffer output = StringBuffer();
    output.writeln('\n══════════ ⚡ HYBRID PARALLEL REPORT ⚡ ══════════');
    output.writeln(' 🕒 Total Wall Time: ${total}ms');
    output.writeln('──────────────────────────────────────────────────────');
    
    subTasks.forEach((key, value) {
      if (value is Map && value.containsKey('stats')) {
        final int time = value['stats']['execution_time_ms'];
        final int barLength = (time / 50).ceil().clamp(0, 20);
        final String bar = '█' * barLength;
        
        output.writeln(' ${key.padRight(12)} : ${time.toString().padLeft(4)}ms $bar');
      } else {
        String err = value['error'] ?? "Unknown";
        if (err.length > 30) err = "${err.substring(0, 30)}...";
        output.writeln(' ${key.padRight(12)} : FAILED ❌ ($err)');
      }
    });
    output.writeln('══════════════════════════════════════════════════════\n');

    dev.log(output.toString(), name: 'ImageAnalyzer');
  }
}
