import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:adobe/data/repos/image_repo.dart';
import 'python_service.dart';

class InstagramDownloadService {
  final _pythonService = PythonService();
  final _repo = ImageRepository();
  final _uuid = const Uuid();

  Future<List<String>?> downloadInstagramImage(String url) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      
      // Create directories
      final instagramDir = Directory('${dir.path}/instagram_downloads');
      if (!await instagramDir.exists()) await instagramDir.create(recursive: true);

      final imagesDir = Directory('${dir.path}/images');
      if (!await imagesDir.exists()) await imagesDir.create(recursive: true);

      // Call Python Service
      final jsonResult = await _pythonService.downloadInstagramImage(url, instagramDir.path);

      if (jsonResult != null && jsonResult['success'] == true) {
        final List<dynamic> paths = jsonResult['file_paths'];
        final List<String> savedImageIds = [];

        // Save downloaded files to app storage and DB
        for (var path in paths) {
          final String sourcePath = path as String;
          final File sourceFile = File(sourcePath);

          if (await sourceFile.exists()) {
            final String imageId = _uuid.v4();
            final extension = sourcePath.split('.').last;
            final String targetPath = '${imagesDir.path}/$imageId.$extension';

            await sourceFile.copy(targetPath);
            await _repo.insertImage(imageId, targetPath);
            savedImageIds.add(imageId);
          }
        }
        return savedImageIds.isNotEmpty ? savedImageIds : null;
      }
      return null;
    } catch (e) {
      throw Exception("Download failed: $e");
    }
  }
}
