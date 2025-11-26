// lib/ui/pages/all_image_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:adobe/data/repos/image_repo.dart';
import 'package:adobe/services/image_service.dart';
import 'package:adobe/services/theme_service.dart';

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
            Text("Long press an image for options", style: TextStyle(fontSize: 12)),
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
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _imagesFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final images = snapshot.data!;
          if (images.isEmpty) return const Center(child: Text("No images saved yet."));

          return GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8,
            ),
            itemCount: images.length,
            itemBuilder: (context, index) {
              final img = images[index];
              final file = File(img['filePath']);

              return GestureDetector(
                onLongPress: () => _confirmDeleteForever(img['id']),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(file, fit: BoxFit.cover, errorBuilder: (_,__,___) => const Icon(Icons.broken_image)),
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