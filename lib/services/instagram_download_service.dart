import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:adobe/data/repos/image_repo.dart';

class InstagramDownloadService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.adobe/instagram_downloader',
  );
  final _repo = ImageRepository();
  final _uuid = const Uuid();

  Future<String?> downloadInstagramImage(String url) async {
    try {
      // Get output directory
      final dir = await getApplicationDocumentsDirectory();
      final instagramDir = Directory('${dir.path}/instagram_downloads');
      if (!await instagramDir.exists()) {
        await instagramDir.create(recursive: true);
      }

      // Call Python function
      final String? result = await _channel.invokeMethod(
        'downloadInstagramImage',
        {'url': url, 'outputDir': instagramDir.path},
      );

      if (result != null) {
        final Map<String, dynamic> jsonResult = json.decode(result);

        if (jsonResult['success'] == true) {
          final downloadedPath = jsonResult['file_path'] as String;

          // Copy to images directory
          final imagesDir = Directory('${dir.path}/images');
          if (!await imagesDir.exists()) {
            await imagesDir.create(recursive: true);
          }

          final String imageId = _uuid.v4();
          final extension = downloadedPath.split('.').last;
          final String targetPath = '${imagesDir.path}/$imageId.$extension';

          // Copy file
          final sourceFile = File(downloadedPath);
          await sourceFile.copy(targetPath);

          // Save to database
          await _repo.insertImage(imageId, targetPath);

          return imageId;
        } else {
          throw Exception(jsonResult['error'] ?? 'Unknown error');
        }
      }
      return null;
    } on PlatformException catch (e) {
      throw Exception("Error downloading Instagram image: ${e.message}");
    } catch (e) {
      throw Exception("Unexpected error: $e");
    }
  }
}
