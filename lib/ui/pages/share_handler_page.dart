import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:adobe/services/download_service.dart';
import 'package:adobe/services/instagram_download_service.dart';
import 'package:adobe/data/repos/board_repo.dart';
import 'package:adobe/data/repos/board_image_repo.dart';
import 'package:adobe/data/repos/image_repo.dart';
import 'package:adobe/services/image_analyzer_service.dart'; // Master Runner

class ShareHandlerPage extends StatefulWidget {
  final String sharedText; 

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
    _boards = await _boardRepo.getBoards();
    final sharedPath = widget.sharedText.trim();

    if (File(sharedPath).existsSync()) {
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
        if (mounted) setState(() { _hasError = true; _errorMessage = "$e"; _isDownloading = false; });
      }
    } else {
      // URL Handling
      final urlRegExp = RegExp(r'(https?://\S+)');
      final match = urlRegExp.firstMatch(sharedPath);

      if (match != null) {
        final url = match.group(0)!;
        try {
          if (url.contains('instagram.com')) {
            final ids = await _instagramService.downloadInstagramImage(url);
            if (mounted) setState(() {
               _downloadedImageIds = ids ?? [];
               _isDownloading = false;
               if (_downloadedImageIds.isEmpty) { _hasError = true; _errorMessage = "Insta download failed"; }
            });
          } else {
            final id = await _downloadService.downloadAndSaveImage(url);
            if (mounted) setState(() {
               if (id != null) _downloadedImageIds = [id];
               _isDownloading = false;
               if (id == null) { _hasError = true; _errorMessage = "Download failed"; }
            });
          }
        } catch (e) {
          if (mounted) setState(() { _hasError = true; _errorMessage = "$e"; _isDownloading = false; });
        }
      } else {
        if (mounted) setState(() { _hasError = true; _errorMessage = "Invalid URL"; _isDownloading = false; });
      }
    }
  }

  Future<String?> _handleDirectImage(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return null;

    final dir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory('${dir.path}/images');
    if (!await imagesDir.exists()) await imagesDir.create(recursive: true);

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
      final imageData = images.firstWhere((img) => img['id'] == id, orElse: () => <String, dynamic>{});
      if (imageData.isNotEmpty && imageData['filePath'] != null) {
        // Trigger Background Analysis
        _analyzeImageInBackground(id, imageData['filePath'] as String);
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Saved ${_downloadedImageIds.length} image(s)! Analysis running.")),
    );
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  Future<void> _analyzeImageInBackground(String imageId, String imagePath) async {
    try {
      // Changed to use Master Runner
      final result = await ImageAnalyzerService.analyzeFullSuite(imagePath);
      if (result['success'] == true) {
        await _imageRepo.updateImageAnalysis(imageId, json.encode(result));
      }
    } catch (e) {
      debugPrint('Background Analysis Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Save to Board")),
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
            Text(_errorMessage ?? "Error"),
            ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text("Back"))
          ],
        ),
      );
    }
    if (_isDownloading) return const Center(child: CircularProgressIndicator());

    return ListView.builder(
      itemCount: _boards.length + 2, 
      itemBuilder: (context, index) {
        if (index == 0) return const Padding(padding: EdgeInsets.all(16), child: Text("Select a Board"));
        if (index == 1) return ListTile(
          leading: const Icon(Icons.add_box, color: Colors.red),
          title: const Text("Create New Board"),
          onTap: _showCreateBoardDialog,
        );
        
        final board = _boards[index - 2];
        return ListTile(
          leading: const Icon(Icons.dashboard),
          title: Text(board['name']),
          onTap: () => _saveToBoard(board['id']),
        );
      },
    );
  }

  void _showCreateBoardDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("New Board"),
        content: TextField(controller: controller, decoration: const InputDecoration(hintText: "Name")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                final newId = await _boardRepo.createBoard(controller.text);
                if (!c.mounted) return;
                Navigator.pop(c);
                _saveToBoard(newId);
              }
            },
            child: const Text("Create"),
          ),
        ],
      ),
    );
  }
}
