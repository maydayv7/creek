// lib/ui/pages/board_detail_page.dart

import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

// Repos & Models
import 'package:adobe/data/models/board_model.dart';
import 'package:adobe/data/models/image_model.dart';
import 'package:adobe/data/repos/board_image_repo.dart';
import 'package:adobe/data/repos/image_repo.dart';
import 'package:adobe/data/repos/board_repo.dart';

// Services
import 'package:adobe/services/layout_analyzer_service.dart';
import 'package:adobe/services/image_service.dart';
import 'package:adobe/services/theme_service.dart';

class BoardDetailPage extends StatefulWidget {
  final Board board;

  const BoardDetailPage({super.key, required this.board});

  @override
  State<BoardDetailPage> createState() => _BoardDetailPageState();
}

class _BoardDetailPageState extends State<BoardDetailPage> {
  final _boardImageRepo = BoardImageRepository();
  final _imageRepo = ImageRepository();
  final _boardRepo = BoardRepository(); // To list boards for moving
  final _imageService = ImageService(); // Service for logic
  
  final _imagePicker = ImagePicker();
  final _uuid = const Uuid();
  
  late Future<List<ImageModel>> _imagesFuture;

  @override
  void initState() {
    super.initState();
    _imagesFuture = _fetchImages();
  }

  Future<List<ImageModel>> _fetchImages() async {
    final rawData = await _boardImageRepo.getImagesOfBoard(widget.board.id);
    return rawData.map((e) => ImageModel.fromMap(e)).toList();
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );
      if (image == null) return;

      // Copy to images directory
      final dir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${dir.path}/images');
      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }

      final extension = image.path.split('.').last;
      final imageId = _uuid.v4();
      final targetPath = '${imagesDir.path}/$imageId.$extension';

      await File(image.path).copy(targetPath);
      await _imageRepo.insertImage(imageId, targetPath);
      await _boardImageRepo.saveToBoard(widget.board.id, imageId);

      // Trigger analysis
      _analyzeImage(imageId, targetPath);

      if (mounted) {
        setState(() {
          _imagesFuture = _fetchImages();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error picking image: $e')));
      }
    }
  }

  Future<void> _analyzeImage(String imageId, String imagePath) async {
    try {
      final result = await LayoutAnalyzerService.analyzeImage(imagePath);
      if (result != null && result['success'] == true) {
        await _imageRepo.updateImageAnalysis(imageId, json.encode(result));
        if (mounted) {
          setState(() {
            _imagesFuture = _fetchImages();
          });
        }
      }
    } catch (e) {
      debugPrint('Error analyzing image: $e');
    }
  }

  // --- DIALOGS ---

  void _showImageOptionsDialog(ImageModel img) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.remove_circle_outline, color: Colors.orange),
              title: const Text("Remove from this Board"),
              subtitle: const Text("Image stays in 'All Images'"),
              onTap: () async {
                await _imageService.removeImageFromSpecificBoard(img.id, widget.board.id);
                if (context.mounted) Navigator.pop(context);
                setState(() { _imagesFuture = _fetchImages(); });
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text("Delete Completely"),
              subtitle: const Text("Remove from device & all boards"),
              onTap: () {
                 Navigator.pop(context);
                 _confirmDeleteForever(img.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outline, color: Colors.blue),
              title: const Text("Move / Copy to Board"),
              onTap: () {
                Navigator.pop(context);
                _showMoveCopyDialog(img);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteForever(String imageId) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Delete Permanently?"),
        content: const Text("This cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await _imageService.deleteImagePermanently(imageId);
              if (c.mounted) Navigator.pop(c);
              setState(() { _imagesFuture = _fetchImages(); });
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  void _showMoveCopyDialog(ImageModel img) async {
    final boards = await _boardRepo.getBoards(); // Raw maps
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Select Board"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: boards.length,
            itemBuilder: (context, index) {
              final b = boards[index];
              if (b['id'] == widget.board.id) return const SizedBox.shrink(); // Skip current

              return ListTile(
                title: Text(b['name']),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      child: const Text("Copy"),
                      onPressed: () async {
                         await _imageService.copyImageToBoard(img.id, b['id']);
                         if (c.mounted) Navigator.pop(c);
                         if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Copied!")));
                      },
                    ),
                    TextButton(
                      child: const Text("Move"),
                      onPressed: () async {
                         await _imageService.moveImage(img.id, widget.board.id, b['id']);
                         if (c.mounted) Navigator.pop(c);
                         setState(() { _imagesFuture = _fetchImages(); });
                         if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Moved!")));
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _showAnalysisDialog(ImageModel image) {
    if (image.analysisData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Analysis not available for this image')),
      );
      return;
    }

    try {
      final analysis = json.decode(image.analysisData!);
      if (analysis['success'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Analysis failed for this image')),
        );
        return;
      }

      final scores = analysis['scores'] as Map<String, dynamic>;
      final top5 = analysis['top5'] as List;

      showDialog(
        context: context,
        builder:
            (context) => Dialog(
              child: Container(
                padding: const EdgeInsets.all(16),
                constraints: const BoxConstraints(
                  maxWidth: 400,
                  maxHeight: 600,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Image Analysis',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Top 5 Features:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: top5.length,
                        itemBuilder: (context, index) {
                          final item = top5[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(item['name']),
                                Text(
                                  '${(item['score'] * 100).toStringAsFixed(1)}%',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'All Scores:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: scores.length,
                        itemBuilder: (context, index) {
                          final entry = scores.entries.elementAt(index);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(entry.key),
                                Text(
                                  '${(entry.value * 100).toStringAsFixed(1)}%',
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
            ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error displaying analysis: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(widget.board.name, style: TextStyle(fontWeight: FontWeight.bold)),
            const Text("Long press an image for options", style: TextStyle(fontSize: 12)),
          ],
        ),
        centerTitle: true,
        leading: IconButton(
          // THEME TOGGLE BUTTON
          icon: Icon(themeService.mode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode),
          onPressed: () {
            themeService.toggleTheme();
          },
          tooltip: 'Toggle Theme',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_library),
            onPressed: _pickImageFromGallery,
            tooltip: 'Add from Gallery',
          ),
        ],
      ),
      body: FutureBuilder<List<ImageModel>>(
        future: _imagesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text("No images saved to this board yet."),
            );
          }

          final images = snapshot.data!;

          return GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 0.8,
            ),
            itemCount: images.length,
            itemBuilder: (context, index) {
              final img = images[index];
              final file = File(img.filePath);

              return GestureDetector(
                onTap: () => _showAnalysisDialog(img),
                onLongPress: () => _showImageOptionsDialog(img), // ADDED THIS
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: file.existsSync()
                          ? Image.file(
                              file,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  color: Colors.grey[300],
                                  alignment: Alignment.center,
                                  child: const Icon(Icons.broken_image, color: Colors.grey),
                                );
                              },
                            )
                          : Container(
                              color: Colors.grey[300],
                              child: const Icon(Icons.error, color: Colors.red),
                            ),
                    ),
                    if (img.analysisData != null)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.8),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.analytics, color: Colors.white, size: 16),
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}