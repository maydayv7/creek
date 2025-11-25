// lib/ui/pages/share_handler_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:adobe/services/download_service.dart';
import 'package:adobe/services/instagram_download_service.dart';
import 'package:adobe/data/repos/board_repo.dart';
import 'package:adobe/data/repos/board_image_repo.dart';
import 'package:adobe/data/repos/image_repo.dart';
import 'package:adobe/services/image_analyzer_service.dart';
import 'dart:convert';

class ShareHandlerPage extends StatefulWidget {
  final String sharedText; // The URL passed from Android

  const ShareHandlerPage({super.key, required this.sharedText});

  @override
  State<ShareHandlerPage> createState() => _ShareHandlerPageState();
}

class _ShareHandlerPageState extends State<ShareHandlerPage> {
  final _downloadService = DownloadService();
  final _instagramService = InstagramDownloadService();
  final _boardRepo = BoardRepository();
  final _boardImageRepo = BoardImageRepository();
  final _imageRepo = ImageRepository();
  final _uuid = const Uuid();

  List<String> _downloadedImageIds = []; 
  bool _isDownloading = true;
  bool _hasError = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _boards = [];

  @override
  void initState() {
    super.initState();
    _startProcess();
  }

  void _startProcess() async {
    // 1. Start loading boards immediately
    _boards = await _boardRepo.getBoards();

    // 2. Check if it's a file path (direct image share) or URL
    final sharedPath = widget.sharedText.trim();

    if (File(sharedPath).existsSync()) {
      // Direct image file - copy it to our images directory
      try {
        final id = await _handleDirectImage(sharedPath);
        if (mounted) {
          setState(() {
            if (id != null) _downloadedImageIds = [id];
            _isDownloading = false;
            if (id == null) {
              _hasError = true;
              _errorMessage = "Failed to save image";
            }
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _hasError = true;
            _errorMessage = "Error: $e";
            _isDownloading = false;
          });
        }
      }
    } else {
      // It's a URL - check if it's Instagram
      final urlRegExp = RegExp(r'(https?://\S+)');
      final match = urlRegExp.firstMatch(sharedPath);

      if (match != null) {
        final url = match.group(0)!;

        // Check if it's an Instagram URL
        if (url.contains('instagram.com')) {
          try {
            final ids = await _instagramService.downloadInstagramImage(url);
            if (mounted) {
              setState(() {
                if (ids != null) _downloadedImageIds = ids;
                _isDownloading = false;
                if (ids == null || ids.isEmpty) {
                  _hasError = true;
                  _errorMessage = "Failed to download from Instagram";
                }
              });
            }
          } catch (e) {
            if (mounted) {
              setState(() {
                _hasError = true;
                _errorMessage = "Error: $e";
                _isDownloading = false;
              });
            }
          }
        } else {
          // Regular URL - use existing download service
          final id = await _downloadService.downloadAndSaveImage(url);
          if (mounted) {
            setState(() {
              if (id != null) _downloadedImageIds = [id]; // Wrap single ID in list
              _isDownloading = false;
              if (id == null) {
                _hasError = true;
                _errorMessage = "Failed to download image";
              }
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _hasError = true;
            _errorMessage = "Invalid URL or file path";
            _isDownloading = false;
          });
        }
      }
    }
  }

  Future<String?> _handleDirectImage(String filePath) async {
    // Import needed packages
    final file = File(filePath);
    if (!await file.exists()) return null;

    // Copy to images directory
    final dir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory('${dir.path}/images');
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    final extension = filePath.split('.').last;
    final imageId = _uuid.v4();
    final targetPath = '${imagesDir.path}/$imageId.$extension';

    await file.copy(targetPath);
    await _imageRepo.insertImage(imageId, targetPath);

    return imageId;
  }

  Future<void> _saveToBoard(int boardId) async {
    if (_downloadedImageIds.isEmpty) return;

    for (final id in _downloadedImageIds) {
      await _boardImageRepo.saveToBoard(boardId, id);
    }

    final images = await _imageRepo.getAllImages();
    
    for (final id in _downloadedImageIds) {
      final imageData = images.firstWhere(
        (img) => img['id'] == id,
        orElse: () => <String, dynamic>{},
      );

      if (imageData.isNotEmpty && imageData['filePath'] != null) {
        _analyzeImageInBackground(
          id,
          imageData['filePath'] as String,
        );
      }
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Saved ${_downloadedImageIds.length} image(s) to board! Analysis running."),
      ),
    );

    // Close the app or go back to main screen
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  Future<void> _analyzeImageInBackground(
    String imageId,
    String imagePath,
  ) async {
    try {
      final result = await ImageAnalyzerService.analyzeImage(imagePath);
      if (result != null && result['success'] == true) {
        await _imageRepo.updateImageAnalysis(imageId, json.encode(result));
      }
    } catch (e) {
      debugPrint('Error analyzing image in background: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Save to Board")),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? "Could not process image",
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Go Back"),
            ),
          ],
        ),
      );
    }

    // While downloading, show loader but ALSO show boards (disabled or overlay)
    // Or just show loader as per your request
    if (_isDownloading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Downloading image(s)..."),
          ],
        ),
      );
    }

    // Once downloaded, allow selection
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Text(
                "Select a board",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              if (_downloadedImageIds.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    "(${_downloadedImageIds.length} images found)",
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _boards.length + 1, // +1 for "Create Board"
            itemBuilder: (context, index) {
              // "Create New Board" Option
              if (index == 0) {
                return ListTile(
                  leading: Icon(Icons.add_box, color: Colors.red),
                  title: Text("Create New Board"),
                  onTap: () {
                    // Call your create board dialog logic here
                    _showCreateBoardDialog();
                  },
                );
              }

              final board = _boards[index - 1];
              return ListTile(
                leading: Icon(Icons.dashboard),
                title: Text(board['name']),
                onTap: () => _saveToBoard(board['id']),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showCreateBoardDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder:
          (c) => AlertDialog(
            title: Text("New Board"),
            content: TextField(
              controller: controller,
              decoration: InputDecoration(hintText: "Name"),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (controller.text.isNotEmpty) {
                    // Create board
                    final newId = await _boardRepo.createBoard(controller.text);
                    if (!c.mounted) return;
                    Navigator.pop(c); // Close dialog
                    // Save image to new board
                    _saveToBoard(newId);
                  }
                },
                child: Text("Create"),
              ),
            ],
          ),
    );
  }
}
