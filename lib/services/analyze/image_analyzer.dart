import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

// Import analysis services
import 'color.dart';
import 'texture.dart';
import 'embedding.dart';
import 'layout.dart';
import 'font.dart';

class ImageAnalyzerService {
  /// Prepare ALL assets (Models + JSONs) on Main Thread.
  /// Returns a map of absolute paths.
  static Future<Map<String, String>> _prepareAssets() async {
    final dir = await getApplicationDocumentsDirectory();

    Future<String> copy(String assetName, {String? filename}) async {
      final name = filename ?? assetName;
      final file = File('${dir.path}/$name');
      if (!await file.exists() || await file.length() == 0) {
        final data = await rootBundle.load('assets/$assetName');
        await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      }
      return file.path;
    }

    // Copy everything needed by the services
    final paths = await Future.wait([
      // DINO
      copy('dinov2.onnx'),
      copy('dinov2.onnx.data'),
      copy('texture_centroids.json'),

      // CLIP
      copy('clip_image_encoder.onnx'),
      copy('style_embeddings.json'),
      copy('emotion_centroids.json'),
      copy('lighting_centroids.json'),
      copy('era_centroids.json'),
      copy('fannet.onnx'),
      copy('font_database.json'),
    ]);

    return {
      'texture_model': paths[0],
      // paths[1] is .data, implicit
      'texture_json': paths[2],
      'clip_model': paths[3],
      'embedding_json': paths[4],
      'emotion_json': paths[5],
      'lighting_json': paths[6],
      'era_json': paths[7],
      'fannet_model': paths[8],
      'font_json': paths[9],
    };
  }

  static Future<Map<String, dynamic>> _runProfiledJob({
    required String name,
    required String imagePath,
    required RootIsolateToken rootToken,
    required bool runInIsolate,
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
      result['execution_time'] = stopwatch.elapsedMilliseconds;
      return result;
    } catch (e) {
      stopwatch.stop();
      timelineTask.finish();
      debugPrint("[$name] Failed: $e");

      return {
        'success': false,
        'scores': {},
        'error': e.toString(),
        'execution_time': stopwatch.elapsedMilliseconds,
      };
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
        // --- GROUP A: PARALLEL ---
        _runProfiledJob(
          name: 'Layout',
          imagePath: imagePath,
          rootToken: token,
          runInIsolate: true,
          assetPaths: assetPaths,
          task: (path, _) => LayoutAnalyzerService().analyze(path),
        ),

        _runProfiledJob(
          name: 'Color',
          imagePath: imagePath,
          rootToken: token,
          runInIsolate: true,
          assetPaths: assetPaths,
          task: (path, _) => ColorAnalyzerService().analyze(path),
        ),

        _runProfiledJob(
          name: 'Texture',
          imagePath: imagePath,
          rootToken: token,
          runInIsolate: true,
          assetPaths: assetPaths,
          task: (path, assets) async {
            final service = TextureAnalyzerService();
            // Pass specific paths
            final res = await service.analyze(
              path,
              modelPath: assets['texture_model'],
              jsonPath: assets['texture_json'],
            );
            service.dispose();
            return res;
          },
        ),

        _runProfiledJob(
          name: 'Embedding',
          imagePath: imagePath,
          rootToken: token,
          runInIsolate: true,
          assetPaths: assetPaths,
          task: (path, assets) async {
            final service = EmbeddingAnalyzerService();
            final res = await service.analyze(
              path,
              modelPath: assets['clip_model'],
              jsonPath: assets['embedding_json'],
            );
            service.dispose();
            return res;
          },
        ),

        _runProfiledJob(
          name: 'Emotional',
          imagePath: imagePath,
          rootToken: token,
          runInIsolate: true,
          assetPaths: assetPaths,
          task: (path, assets) async {
            final service = EmbeddingAnalyzerService();
            final res = await service.analyze(
              path,
              modelPath: assets['clip_model'],
              jsonPath: assets['emotion_json'],
            );
            service.dispose();
            return res;
          },
        ),

        _runProfiledJob(
          name: 'Lighting',
          imagePath: imagePath,
          rootToken: token,
          runInIsolate: true,
          assetPaths: assetPaths,
          task: (path, assets) async {
            final service = EmbeddingAnalyzerService();
            final res = await service.analyze(
              path,
              modelPath: assets['clip_model'],
              jsonPath: assets['lighting_json'],
            );
            service.dispose();
            return res;
          },
        ),

        _runProfiledJob(
          name: 'Era',
          imagePath: imagePath,
          rootToken: token,
          runInIsolate: true,
          assetPaths: assetPaths,
          task: (path, assets) async {
            final service = EmbeddingAnalyzerService();
            final res = await service.analyze(
              path,
              modelPath: assets['clip_model'],
              jsonPath: assets['era_json'],
            );
            service.dispose();
            return res;
          },
        ),

        // --- GROUP B: MAIN THREAD ---
        _runProfiledJob(
          name: 'Font',
          imagePath: imagePath,
          rootToken: token,
          runInIsolate: false,
          assetPaths: assetPaths,
          task: (path, assets) async {
            final service = FontIdentifierService();
            final res = await service.analyze(
              path,
              modelPath: assets['fannet_model'],
              jsonPath: assets['font_json'],
            );
            service.dispose();
            return res;
          },
        ),
      ]);

      totalSw.stop();

      // This is only for testing
      final logResult = {
        'success': true,
        'total_time': totalSw.elapsedMilliseconds,
        'filename': p.basename(imagePath),
        'results': {
          'Layout': results[0]['execution_time'],
          'Color': results[1]['execution_time'],
          'Texture': results[2]['execution_time'],
          'Style': results[3]['execution_time'],
          'Emotions': results[4]['execution_time'],
          'Lighting': results[5]['execution_time'],
          'Era': results[6]['execution_time'],
          'Font': results[7]['execution_time'],
        },
      };
      _logSummary(logResult);

      final finalResult = {
        'success': true,
        'data': {
          'filename': p.basename(imagePath),
          'results': {
            'Style': {"scores": results[3]['scores']},
            'Texture': {"scores": results[2]['scores']},
            'Lighting': {"scores": results[5]['scores']},
            'Colour Palette': {"scores": results[1]['scores']},
            'Emotions': {"scores": results[4]['scores']},
            'Era': {"scores": results[6]['scores']},
            'Layout': {"scores": results[0]['scores']},
            'Font': {"scores": results[7]['scores']},
          },
        },
        'error': null,
      };
      debugPrint(finalResult.toString());
      return finalResult;
    } catch (e) {
      debugPrint("Master Analysis Failed: $e");
      return {
        'success': false,
        'data': {
          'filename': '',
          'results': {
            'Style': {"scores": {}},
            'Texture': {"scores": {}},
            'Lighting': {"scores": {}},
            'Colour Palette': {"scores": {}},
            'Emotions': {"scores": {}},
            'Era': {"scores": {}},
            'Font': {"scores": {}},
          },
        },
        'error': e.toString(),
      };
    }
  }

  static void _logSummary(Map<String, dynamic> result) {
    final int total = result['total_time'];
    final Map<String, dynamic> subTasks = result['results'];
    StringBuffer output = StringBuffer();

    output.writeln('\n══════════ ⚡ HYBRID PARALLEL REPORT ⚡ ══════════');
    output.writeln(' 🕒 Total Wall Time: ${total}ms');
    output.writeln('──────────────────────────────────────────────────────');

    subTasks.forEach((key, value) {
      final int barLength = (value / 50).ceil().clamp(0, 20);
      final String bar = '█' * barLength;
      output.writeln(
        ' ${key.padRight(12)} : ${value.toString().padLeft(4)}ms $bar',
      );
    });

    output.writeln('══════════════════════════════════════════════════════\n');
    dev.log(output.toString(), name: 'ImageAnalyzer');
  }
}
