// lib/services/image_service.dart

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../data/repos/image_repo.dart';
import '../data/repos/board_image_repo.dart';

class ImageService {
  final _imgRepo = ImageRepository();
  final _boardImgRepo = BoardImageRepository();

  Future<String> saveImage(File file) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory("${dir.path}/images");

    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }

    final id = const Uuid().v4();
    // Handle cases where file might not have an extension
    String ext = 'jpg';
    if (file.path.contains('.')) {
      ext = file.path.split('.').last;
    }

    final newPath = "${folder.path}/$id.$ext";
    final savedFile = await file.copy(newPath);

    await _imgRepo.insertImage(id, savedFile.path);

    return id;
  }

  // 1. DELETE IMAGE (Completely removes file and DB entries)
  Future<void> deleteImagePermanently(String imageId) async {
    // A. Get path to delete physical file
    final path = await _imgRepo.getImagePath(imageId);
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
    // B. Delete from DB (Repo handles cascade to board_images)
    await _imgRepo.deleteImage(imageId);
  }

  // 2. COPY TO BOARD (Keep in old board, add to new board)
  Future<void> copyImageToBoard(String imageId, int targetBoardId) async {
    // Just add a new entry in the mapping table
    await _boardImgRepo.saveToBoard(targetBoardId, imageId);
  }

  // 3. MOVE TO BOARD (Remove from old board, add to new board)
  Future<void> moveImage(String imageId, int currentBoardId, int targetBoardId) async {
    // A. Add to new
    await _boardImgRepo.saveToBoard(targetBoardId, imageId);
    // B. Remove from old
    await _boardImgRepo.removeImageFromBoard(currentBoardId, imageId);
  }
  
  // 4. REMOVE FROM BOARD (But keep file in "All Images")
  Future<void> removeImageFromSpecificBoard(String imageId, int boardId) async {
    await _boardImgRepo.removeImageFromBoard(boardId, imageId);
  }
}