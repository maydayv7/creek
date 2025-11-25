// lib/ui/pages/board_detail_page.dart

import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:adobe/data/models/board_model.dart';
import 'package:adobe/data/models/image_model.dart';
import 'package:adobe/data/repos/board_image_repo.dart';
import 'package:adobe/data/repos/image_repo.dart';
import 'package:adobe/services/image_analyzer_service.dart';

class BoardDetailPage extends StatefulWidget {
  final Board board;

  const BoardDetailPage({super.key, required this.board});

  @override
  State<BoardDetailPage> createState() => _BoardDetailPageState();
}

class _BoardDetailPageState extends State<BoardDetailPage> {
  final _boardImageRepo = BoardImageRepository();
  final _imageRepo = ImageRepository();
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
      final result = await ImageAnalyzerService.analyzeImage(imagePath);
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
        title: Text(widget.board.name),
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
              childAspectRatio: 0.8, // Taller for images
            ),
            itemCount: images.length,
            itemBuilder: (context, index) {
              final img = images[index];
              final file = File(img.filePath);

              return GestureDetector(
                onTap: () => _showAnalysisDialog(img),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child:
                          file.existsSync()
                              ? Image.file(
                                file,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    color: Colors.grey[300],
                                    alignment: Alignment.center,
                                    child: const Icon(
                                      Icons.broken_image,
                                      color: Colors.grey,
                                    ),
                                  );
                                },
                              )
                              : Container(
                                color: Colors.grey[300],
                                child: const Icon(
                                  Icons.error,
                                  color: Colors.red,
                                ),
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
                          child: const Icon(
                            Icons.analytics,
                            color: Colors.white,
                            size: 16,
                          ),
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
