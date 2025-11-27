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
import 'package:adobe/data/repos/board_repo.dart';
import 'package:adobe/services/image_service.dart';
import 'package:adobe/services/theme_service.dart';
import 'package:adobe/services/image_analyzer_service.dart'; // Master Service
import '../widgets/analysis_dialog.dart'; // Dialog Widget

class BoardDetailPage extends StatefulWidget {
  final Board board;
  const BoardDetailPage({super.key, required this.board});

  @override
  State<BoardDetailPage> createState() => _BoardDetailPageState();
}

class _BoardDetailPageState extends State<BoardDetailPage> {
  final _boardImageRepo = BoardImageRepository();
  final _imageRepo = ImageRepository();
  final _boardRepo = BoardRepository(); 
  final _imageService = ImageService(); 
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
      final XFile? image = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (image == null) return;

      final dir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${dir.path}/images');
      if (!await imagesDir.exists()) await imagesDir.create(recursive: true);

      final extension = image.path.split('.').last;
      final imageId = _uuid.v4();
      final targetPath = '${imagesDir.path}/$imageId.$extension';

      await File(image.path).copy(targetPath);
      await _imageRepo.insertImage(imageId, targetPath);
      await _boardImageRepo.saveToBoard(widget.board.id, imageId);

      // Trigger analysis
      _analyzeImage(imageId, targetPath);

      if (mounted) setState(() { _imagesFuture = _fetchImages(); });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _analyzeImage(String imageId, String imagePath) async {
    try {
      // Changed to use Master Runner
      final result = await ImageAnalyzerService.analyzeFullSuite(imagePath);
      if (result['success'] == true) {
        await _imageRepo.updateImageAnalysis(imageId, json.encode(result));
        if (mounted) setState(() { _imagesFuture = _fetchImages(); });
      }
    } catch (e) {
      debugPrint('Analysis Error: $e');
    }
  }

  void _showAnalysisDialog(ImageModel image) {
    showDialog(
      context: context,
      builder: (context) => AnalysisDialog(image: image),
    );
  }

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
              onTap: () async {
                await _imageService.removeImageFromSpecificBoard(img.id, widget.board.id);
                if (context.mounted) Navigator.pop(context);
                setState(() { _imagesFuture = _fetchImages(); });
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text("Delete Completely"),
              onTap: () { Navigator.pop(context); _confirmDeleteForever(img.id); },
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.board.name),
        leading: IconButton(
          icon: Icon(themeService.mode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode),
          onPressed: () { themeService.toggleTheme(); },
        ),
        actions: [
          IconButton(icon: const Icon(Icons.photo_library), onPressed: _pickImageFromGallery),
        ],
      ),
      body: FutureBuilder<List<ImageModel>>(
        future: _imagesFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final images = snapshot.data!;
          if (images.isEmpty) return const Center(child: Text("No images."));

          return GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 0.8,
            ),
            itemCount: images.length,
            itemBuilder: (context, index) {
              final img = images[index];
              final file = File(img.filePath);

              return GestureDetector(
                onTap: () => _showAnalysisDialog(img),
                onLongPress: () => _showImageOptionsDialog(img),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(file, fit: BoxFit.cover, errorBuilder: (_,__,___) => const Icon(Icons.error)),
                    ),
                    if (img.analysisData != null)
                      Positioned(top: 8, right: 8, child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        child: const Icon(Icons.analytics, color: Colors.white, size: 16),
                      )),
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
