import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:creekui/data/repos/image_repo.dart';
import 'package:creekui/data/models/image_model.dart';
import 'analysis_queue_manager.dart';

class ImageService {
  final ImageRepo _repo = ImageRepo();
  final Uuid _uuid = const Uuid();

  // Checks if image is a draft (from ShareHandler) and updates it, or saves new
  Future<String> saveOrUpdateImage(
    File file,
    int projectId, {
    List<String> tags = const [],
  }) async {
    final existing = await _repo.getByFilePath(file.path);
    if (existing != null) {
      debugPrint(
        "ImageService: Updating existing draft ${existing.id} -> Project $projectId",
      );
      await _repo.updateProject(existing.id, projectId);
      await updateTags(existing.id, tags);
      return existing.id;
    } else {
      debugPrint("ImageService: Saving new image");
      return await saveImage(file, projectId, tags: tags);
    }
  }

  // --- PUBLIC METHODS ---

  // Saves a single image and returns its ID
  Future<String> saveImage(
    File file,
    int projectId, {
    List<String> tags = const [],
    String? status,
  }) async {
    // 1. Prepare Directory
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory("${dir.path}/images");
    if (!await folder.exists()) await folder.create(recursive: true);

    // 2. Generate ID and Path
    final String id = _uuid.v4();
    String ext = "jpg"; // Default
    try {
      if (file.path.contains('.')) {
        ext = file.path.split('.').last;
      }
    } catch (_) {}

    final String newPath = "${folder.path}/$id.$ext";
    await file.copy(newPath);

    // 3. Create & Save Model
    final image = ImageModel(
      id: id,
      projectId: projectId,
      filePath: newPath,
      name: file.path.split('/').last,
      createdAt: DateTime.now(),
      tags: tags,
      status: status ?? 'pending',
    );
    await _repo.addImage(image);

    // 4. Trigger Analysis Queue
    AnalysisQueueManager().processQueue();

    return id;
  }

  // Bulk save method
  Future<List<String>> saveImages(
    List<File> files,
    int projectId, {
    List<String> tags = const [],
  }) async {
    List<String> ids = [];
    for (var file in files) {
      String id = await saveImage(file, projectId, tags: tags);
      ids.add(id);
    }
    return ids;
  }

  // Updates tags and triggers relevant analysis
  Future<void> updateTags(String imageId, List<String> newTags) async {
    // 1. Update Tags in Database
    await _repo.updateTags(imageId, newTags);

    // 2. Mark as pending and trigger queue
    await _repo.updateStatus(imageId, 'pending');
    AnalysisQueueManager().processQueue();
  }

  Future<void> renameImage(String id, String newName) async {
    await _repo.updateName(id, newName);
  }

  Future<void> updateAnalysis(String id, Map<String, dynamic> analysis) async {
    final jsonString = jsonEncode(analysis);
    await _repo.updateAnalysis(id, jsonString);
  }

  Future<ImageModel?> getImage(String id) async {
    return await _repo.getById(id);
  }

  Future<List<String>> getTags(String imageId) async {
    return await _repo.getTagsForImage(imageId);
  }

  Future<void> deleteImage(String id) async {
    final img = await _repo.getById(id);
    if (img != null) {
      final file = File(img.filePath);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (e) {
          debugPrint("Error deleting file: $e");
        }
      }
      await _repo.deleteImage(id);
    }
  }

  Future<List<ImageModel>> getImages(int projectId) async {
    return await _repo.getImages(projectId);
  }
}
