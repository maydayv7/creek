import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:image/image.dart' as img;
import 'package:creekui/data/repos/file_repo.dart';
import 'package:creekui/data/models/file_model.dart';

class FileService {
  final _repo = FileRepo();

  Future<String> saveFile(
    File file,
    int projectId, {
    String? description,
    String? name,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory("${dir.path}/files");
    if (!await folder.exists()) await folder.create(recursive: true);

    final id = const Uuid().v4();
    String ext = file.path.split('.').last;
    final newPath = "${folder.path}/$id.$ext";

    await file.copy(newPath);

    final projectFile = FileModel(
      id: id,
      projectId: projectId,
      filePath: newPath,
      name: name ?? "Untitled File",
      description: description,
      lastUpdated: DateTime.now(),
      createdAt: DateTime.now(),
    );

    await _repo.addFile(projectFile);
    return id;
  }

  Future<List<FileModel>> getAllFiles() async {
    return await _repo.getAllFiles();
  }

  // Get recent files globally (limit 10 for the UI)
  Future<List<FileModel>> getRecentFiles({int limit = 10}) async {
    return await _repo.getRecentFiles(limit: limit);
  }

  @Deprecated('Use getAllFiles() or getRecentFiles() instead')
  Future<List<FileModel>> getFiles(int projectId) async {
    return await _repo.getFiles(projectId);
  }

  Future<List<FileModel>> getFilesForProjectAndEvents(int projectId) {
    return _repo.getFilesForProjectAndEvents(projectId);
  }

  Future<void> openFile(String id) async {
    await _repo.touchFile(id);
  }

  Future<void> updateFileDetails(
    String id, {
    String? name,
    String? description,
    List<String>? tags,
  }) async {
    await _repo.updateDetails(
      id,
      name: name,
      description: description,
      tags: tags,
    );
  }

  Future<void> deleteFile(String id) async {
    final fileData = await _repo.getById(id);
    if (fileData != null) {
      final file = File(fileData.filePath);
      if (await file.exists()) await file.delete();
      await _repo.deleteFile(id);
    }
  }

  Future<void> renameFile(String id, String newName) async {
    await _repo.updateDetails(id, name: newName);
  }

  // Saves canvas JSON structure to a file
  Future<String> saveCanvasFile({
    required int projectId,
    required Map<String, dynamic> canvasData,
    String? fileId,
    String? fileName,
  }) async {
    final jsonString = jsonEncode(canvasData);

    if (fileId != null) {
      // Update existing file
      final fileData = await _repo.getById(fileId);
      if (fileData != null) {
        final file = File(fileData.filePath);
        await file.writeAsString(jsonString);
        await _repo.touchFile(fileId); // Update last modified
      }
      return fileId;
    } else {
      // Create new file via temporary storage
      final directory = await getTemporaryDirectory();
      final tempFile = File(
        '${directory.path}/canvas_${DateTime.now().millisecondsSinceEpoch}.json',
      );
      await tempFile.writeAsString(jsonString);

      final newId = await saveFile(
        tempFile,
        projectId,
        name: fileName ?? "Untitled Canvas",
        description: "Editable Canvas Board",
      );

      // Cleanup temp file
      if (await tempFile.exists()) await tempFile.delete();
      return newId;
    }
  }

  // Unified metadata extraction logic
  Future<FileMetadataInfo> getFileMetadata(String filePath) async {
    try {
      final f = File(filePath);
      if (!await f.exists()) return FileMetadataInfo();

      if (filePath.toLowerCase().endsWith('.json')) {
        try {
          final content = await f.readAsString();
          final data = jsonDecode(content);

          if (data is Map) {
            final width = (data['width'] as num?)?.toDouble() ?? 0;
            final height = (data['height'] as num?)?.toDouble() ?? 0;
            final previewPath = data['preview_path'] as String?;

            return FileMetadataInfo(
              width: width,
              height: height,
              previewPath: previewPath,
            );
          }
        } catch (e) {
          // ignore: avoid_print
          print('Error parsing JSON metadata for $filePath: $e');
        }
      } else {
        // Attempt to decode image dimensions directly
        try {
          final bytes = await f.readAsBytes();
          final image = img.decodeImage(bytes);
          if (image != null) {
            return FileMetadataInfo(
              width: image.width.toDouble(),
              height: image.height.toDouble(),
              previewPath: filePath,
            );
          }
        } catch (e) {
          print('Error decoding image metadata for $filePath: $e');
        }
      }
    } catch (e) {
      print('Error accessing file metadata for $filePath: $e');
    }

    return FileMetadataInfo();
  }
}
