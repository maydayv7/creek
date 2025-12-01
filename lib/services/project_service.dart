import 'dart:convert';
import 'dart:io';
import 'package:flutter/rendering.dart';

import '../data/repos/project_repo.dart';
import '../data/repos/image_repo.dart';
import '../data/repos/file_repo.dart';
import '../data/models/project_model.dart';

class ProjectService {
  final _projectRepo = ProjectRepo();
  final _imageRepo = ImageRepo();
  final _fileRepo = FileRepo();

  Future<int> createProject(
    String title, {
    String? description,
    int? parentId,
  }) async {
    final project = ProjectModel(
      title: title.trim(),
      description: description,
      parentId: parentId,
      lastAccessedAt: DateTime.now(),
      createdAt: DateTime.now(),
    );
    return await _projectRepo.createProject(project);
  }

  Future<void> updateProjectDetails(
    int projectId, {
    String? title,
    String? description,
  }) async {
    if (title != null && title.trim().isEmpty) return; // Prevent empty titles
    await _projectRepo.updateProject(
      projectId,
      title: title?.trim(),
      description: description?.trim(),
    );
  }

  Future<void> openProject(int id) async {
    await _projectRepo.touchProject(id);
  }

  Future<void> saveStylesheet(
    int projectId,
    Map<String, dynamic> stylesheet,
  ) async {
    final jsonString = jsonEncode(stylesheet);
    await _projectRepo.updateStylesheet(projectId, jsonString);
  }

  Future<void> deleteProject(int projectId) async {
    List<int> allIdsToDelete = [projectId];
    final subEventIds = await _projectRepo.getAllSubEventIds(projectId);
    allIdsToDelete.addAll(subEventIds);

    List<String> pathsToDelete = [];
    pathsToDelete.addAll(
      await _imageRepo.getAllFilePathsForProjectIds(allIdsToDelete),
    );
    pathsToDelete.addAll(
      await _fileRepo.getAllFilePathsForProjectIds(allIdsToDelete),
    );

    for (var path in pathsToDelete) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (e) {
        debugPrint("Error deleting file $path: $e");
      }
    }

    await _projectRepo.deleteProject(projectId);
  }
}
