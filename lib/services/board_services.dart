// lib/services/board_services.dart

import '../data/repos/board_repo.dart';
import '../data/repos/board_image_repo.dart';
import '../data/repos/image_repo.dart';
import 'dart:io';

class BoardService {
  final _boardRepo = BoardRepository();
  final _boardImgRepo = BoardImageRepository();
  final _imgRepo = ImageRepository();

  Future<void> renameBoard(int boardId, String newName) async {
    if (newName.trim().isEmpty) return;
    await _boardRepo.updateBoardName(boardId, newName.trim());
  }

  // Option A: Just delete the board (Images stay in "All Images")
  Future<void> deleteBoardOnly(int boardId) async {
    await _boardRepo.deleteBoard(boardId);
  }

  // Option B: Delete Board AND all images inside it (Physical delete)
  Future<void> deleteBoardAndContent(int boardId) async {
    // 1. Get all images in this board
    final images = await _boardImgRepo.getImagesOfBoard(boardId);
    
    // 2. Loop through and delete them physically
    for (var img in images) {
      final String id = img['id'];
      final String path = img['filePath'];
      
      // Delete file
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
      
      // Delete from DB (images table)
      await _imgRepo.deleteImage(id);
    }

    // 3. Finally delete the board itself
    await _boardRepo.deleteBoard(boardId);
  }

  Future<void> copyAllImages(int sourceBoardId, int targetBoardId) async {
    // 1. Get all images from source
    final images = await _boardImgRepo.getImagesOfBoard(sourceBoardId);
    
    // 2. Add them to target (Repo handles duplicates usually, or simple insert)
    for (var img in images) {
      await _boardImgRepo.saveToBoard(targetBoardId, img['id']);
    }
  }

  Future<void> moveAllImages(int sourceBoardId, int targetBoardId) async {
    // 1. Copy first
    await copyAllImages(sourceBoardId, targetBoardId);
    
    // 2. Remove from source
    final images = await _boardImgRepo.getImagesOfBoard(sourceBoardId);
    for (var img in images) {
      await _boardImgRepo.removeImageFromBoard(sourceBoardId, img['id']);
    }
  }
}