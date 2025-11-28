import 'dart:io';
import 'package:flutter/material.dart';
import '../../data/models/image_model.dart';
import '../../data/repos/image_repo.dart';

class ProjectTagPage extends StatefulWidget {
  final int projectId;
  final String tag;

  const ProjectTagPage({
    super.key,
    required this.projectId,
    required this.tag,
  });

  @override
  State<ProjectTagPage> createState() => _ProjectTagPageState();
}

class _ProjectTagPageState extends State<ProjectTagPage> {
  final _imageRepo = ImageRepo();
  List<ImageModel> _images = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  Future<void> _loadImages() async {
    final allImages = await _imageRepo.getImages(widget.projectId);

    final filtered = allImages.where((img) {
      if (widget.tag == 'Uncategorized') {
        return img.tags.isEmpty;
      }
      return img.tags.contains(widget.tag);
    }).toList();

    if (mounted) {
      setState(() {
        _images = filtered;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          widget.tag.toUpperCase(),
          style: const TextStyle(
            fontFamily: 'GeneralSans',
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
          ),
        ),
        centerTitle: false, // Changed to false for left alignment
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _images.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.image_not_supported_outlined,
                          size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        "No images found for '${widget.tag}'",
                        style: TextStyle(
                          fontFamily: 'GeneralSans',
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: _images.length,
                  itemBuilder: (context, index) {
                    final image = _images[index];
                    return GestureDetector(
                      onTap: () {
                        // Navigate to detail view
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E1E1E) : Colors.grey[200],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark ? Colors.white10 : Colors.transparent,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(
                              File(image.filePath),
                              fit: BoxFit.cover,
                              width: double.infinity,
                              errorBuilder: (_, __, ___) => Container(
                                color: Colors.grey[300],
                                child: const Center(
                                  child: Icon(Icons.broken_image, color: Colors.grey),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}