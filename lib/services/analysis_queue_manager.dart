import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img; 
import '../data/models/image_model.dart';
import '../data/models/note_model.dart';
import '../data/repos/image_repo.dart';
import '../data/repos/note_repo.dart';
import 'analyze/image_analyzer.dart';

class AnalysisQueueManager {
  static final AnalysisQueueManager _instance =
      AnalysisQueueManager._internal();
  factory AnalysisQueueManager() => _instance;
  AnalysisQueueManager._internal();

  bool _isProcessing = false;
  final _imageRepo = ImageRepo();
  final _noteRepo = NoteRepo();

  Future<void> processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      // 1. Fetch pending images from DB
      List<ImageModel> pendingImages = await _imageRepo.getPendingImages();
      if (pendingImages.isNotEmpty) {
        debugPrint("[Queue]: Found ${pendingImages.length} pending images");
        for (final image in pendingImages) {
          await _processSingleImage(image);
        }
      }

      // 2. Fetch pending notes from DB
      List<NoteModel> pendingNotes = await _noteRepo.getPendingNotes();
      if (pendingNotes.isNotEmpty) {
        debugPrint("[Queue]: Found ${pendingNotes.length} pending notes");

        // Group notes to avoid decoding parent image multiple times
        final Map<String, List<NoteModel>> notesByImage = {};
        for (var note in pendingNotes) {
          if (!notesByImage.containsKey(note.imageId)) {
            notesByImage[note.imageId] = [];
          }
          notesByImage[note.imageId]!.add(note);
        }

        for (final entry in notesByImage.entries) {
          await _processNoteGroup(entry.key, entry.value);
        }
      }
    } catch (e) {
      debugPrint("[Queue]: Critical Error: $e");
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _processSingleImage(ImageModel image) async {
    await _imageRepo.updateStatus(image.id, 'analyzing');
    try {
      Map<String, dynamic> result;

      // Run Analysis
      if (image.tags.isEmpty) {
        debugPrint("[Queue]: Analyzing Full Suite: ${image.name}");
        result = await ImageAnalyzerService.analyzeFullSuite(
          image.filePath,
        );
      } else {
        debugPrint(
          "[Queue]: Analyzing Selected: ${image.name} with tags: ${image.tags}",
        );
        result = await ImageAnalyzerService.analyzeSelected(
          image.filePath,
          image.tags,
        );
      }

      // Handle Result
      if (result['success'] == true && result['data'] != null) {
        final resultsMap = result['data']['results'] ?? {};
        final jsonString = jsonEncode(resultsMap);
        await _imageRepo.updateAnalysis(image.id, jsonString);
        await _imageRepo.updateStatus(image.id, 'completed');
        debugPrint("[Queue]: Completed: ${image.name}");
      } else {
        await _imageRepo.updateStatus(image.id, 'failed');
        debugPrint("[Queue]: Failed: ${result['error']}");
      }
    } catch (e) {
      debugPrint("[Queue]: Analysis Exception: $e");
      await _imageRepo.updateStatus(image.id, 'failed');
    }
  }

  Future<void> _processNoteGroup(String imageId, List<NoteModel> notes) async {
    img.Image? parentImageCache;
    try {
      // 1. Fetch Parent Info
      final parentImageModel = await _imageRepo.getById(imageId);
      if (parentImageModel == null) throw Exception("Parent image not found: $imageId");
      final parentFile = File(parentImageModel.filePath);
      if (!parentFile.existsSync()) throw Exception("Parent file missing");

      // 2. Decode once for all notes in this group
      final bytes = await parentFile.readAsBytes();
      parentImageCache = img.decodeImage(bytes);
      if (parentImageCache == null) throw Exception("Failed to decode parent image");

      final appDir = await getApplicationDocumentsDirectory();
      final cropDir = Directory('${appDir.path}/crops');
      if (!await cropDir.exists()) {
        await cropDir.create(recursive: true);
      }

      for (final note in notes) {
        await _processSingleNoteWithCache(note, parentImageCache, cropDir);
      }
    } catch (e) {
      debugPrint("[Queue]: Error processing group for image $imageId: $e");
      for (var note in notes) {
        await _noteRepo.updateNote(note.id!, status: 'failed');
      }
    }
  }

  Future<void> _processSingleNoteWithCache(
    NoteModel note, 
    img.Image parentImage, 
    Directory cropDir
  ) async {
    await _noteRepo.updateNote(note.id!, status: 'analyzing');
    try {
      // 1. Define Permanent Path
      final String cropPath = '${cropDir.path}/note_crop_${note.id}.jpg';
      final File cropFile = File(cropPath);

      // 2. Generate Crop (if it doesn't already exist)
      if (!await cropFile.exists()) {
        int x = (note.normX * parentImage.width).round();
        int y = (note.normY * parentImage.height).round();
        int w = (note.normWidth * parentImage.width).round();
        int h = (note.normHeight * parentImage.height).round();

        // Center -> Top-Left
        int left = x - (w ~/ 2);
        int top = y - (h ~/ 2);

        // Clamping logic
        if (left < 0) left = 0;
        if (top < 0) top = 0;
        if (left + w > parentImage.width) w = parentImage.width - left;
        if (top + h > parentImage.height) h = parentImage.height - top;

        if (w <= 0 || h <= 0) {
           debugPrint("[Queue]: Note ${note.id} has invalid dimensions");
           await _noteRepo.updateNote(note.id!, status: 'failed');
           return;
        }

        final croppedImg = img.copyCrop(parentImage, x: left, y: top, width: w, height: h);
        await cropFile.writeAsBytes(img.encodeJpg(croppedImg));
      }

      // 3. Analysis
      debugPrint("[Queue]: Analyzing Note ${note.id} tag: ${note.category}");
      final result = await ImageAnalyzerService.analyzeSelected(
        cropPath,
        [note.category],
      );

      // 4. Update DB
      if (result['success'] == true && result['data'] != null) {
        final resultsMap = result['data']['results'] ?? {};
        final jsonString = jsonEncode(resultsMap);
        await _noteRepo.updateNote(
          note.id!, 
          analysisData: jsonString, 
          status: 'completed',
          cropFilePath: cropPath,
        );
      } else {
        await _noteRepo.updateNote(note.id!, status: 'failed');
      }
    } catch (e) {
      debugPrint("[Queue]: Note processing error: $e");
      await _noteRepo.updateNote(note.id!, status: 'failed');
    }
  }
}
