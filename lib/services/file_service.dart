import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../data/repos/file_repo.dart';
import '../data/models/file_model.dart';

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

  Future<List<FileModel>> getFiles(int projectId) async {
    return await _repo.getFiles(projectId);
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
}
