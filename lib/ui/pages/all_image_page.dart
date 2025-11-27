import 'dart:io';
import 'package:flutter/material.dart';
import 'package:adobe/data/repos/image_repo.dart';
import 'package:adobe/services/image_service.dart';
import 'package:adobe/services/theme_service.dart';
import 'package:adobe/data/models/image_model.dart'; // Import Model
import '../widgets/analysis_dialog.dart'; // Import Dialog

class AllImagesPage extends StatefulWidget {
  const AllImagesPage({super.key});

  @override
  State<AllImagesPage> createState() => _AllImagesPageState();
}

class _AllImagesPageState extends State<AllImagesPage> {
  final _imageRepo = ImageRepository();
  final _imageService = ImageService();
  late Future<List<Map<String, dynamic>>> _imagesFuture;

  @override
  void initState() {
    super.initState();
    _refreshImages();
  }

  void _refreshImages() {
    setState(() {
      _imagesFuture = _imageRepo.getAllImages();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("All Images", style: TextStyle(fontWeight: FontWeight.bold)),
            Text("Tap for analysis • Long press for options", style: TextStyle(fontSize: 12)),
          ],
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(themeService.mode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode),
          onPressed: () { themeService.toggleTheme(); },
        ),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _imagesFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final imagesData = snapshot.data!;
          if (imagesData.isEmpty) return const Center(child: Text("No images saved yet."));

          return GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8,
            ),
            itemCount: imagesData.length,
            itemBuilder: (context, index) {
              // Convert raw Map to ImageModel for the dialog
              final imgModel = ImageModel.fromMap(imagesData[index]);
              final file = File(imgModel.filePath);

              return GestureDetector(
                // ADDED: Tap to view analysis
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (c) => AnalysisDialog(image: imgModel),
                  );
                },
                onLongPress: () => _confirmDeleteForever(imgModel.id),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(file, fit: BoxFit.cover, errorBuilder: (_,__,___) => const Icon(Icons.broken_image)),
                    ),
                    // ADDED: Icon indicator if analysis exists
                    if (imgModel.analysisData != null)
                      Positioned(
                        top: 8, right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.analytics, size: 14, color: Colors.white),
                        ),
                      )
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _confirmDeleteForever(String imageId) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Delete Permanently?"),
        content: const Text("This will remove the image from your device and ALL boards."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await _imageService.deleteImagePermanently(imageId);
              if (c.mounted) Navigator.pop(c);
              _refreshImages();
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }
}
