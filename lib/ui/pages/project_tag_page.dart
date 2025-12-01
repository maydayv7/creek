import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:adobe/ui/styles/variables.dart';
import 'package:adobe/ui/widgets/top_bar.dart';
import 'package:adobe/ui/widgets/bottom_bar.dart';
import '../../data/models/image_model.dart';
import '../../data/repos/image_repo.dart';
import '../../data/repos/project_repo.dart';
import '../../data/repos/note_repo.dart';
import 'image_save_page.dart';
import 'image_details_page.dart';
import '../widgets/image_context_menu.dart';

class ProjectTagPage extends StatefulWidget {
  final int projectId;
  final String tag;

  const ProjectTagPage({super.key, required this.projectId, required this.tag});

  @override
  State<ProjectTagPage> createState() => _ProjectTagPageState();
}

class _ProjectTagPageState extends State<ProjectTagPage> {
  final _imageRepo = ImageRepo();
  final _projectRepo = ProjectRepo();
  final _noteRepo = NoteRepo();
  final ImagePicker _picker = ImagePicker();

  List<ImageModel> _images = [];
  String _projectName = "Project";
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final project = await _projectRepo.getProjectById(widget.projectId);
    if (project != null) _projectName = project.title;

    final allImages = await _imageRepo.getImages(widget.projectId);
    final List<ImageModel> filtered = [];

    // Process logic in parallel for speed
    await Future.wait(
      allImages.map((img) async {
        bool matches = false;

        if (widget.tag == 'Uncategorized') {
          if (img.tags.isEmpty) {
            final notes = await _noteRepo.getNotesForImage(img.id);
            final hasCategorizedNote = notes.any((n) => n.category.isNotEmpty);
            if (!hasCategorizedNote) matches = true;
          }
        } else {
          if (img.tags.contains(widget.tag)) {
            matches = true;
          } else {
            final notes = await _noteRepo.getNotesForImage(img.id);
            if (notes.any((n) => n.category == widget.tag)) {
              matches = true;
            }
          }
        }

        if (matches) {
          filtered.add(img);
        }
      }),
    );

    if (mounted) {
      setState(() {
        _images = filtered;
        _isLoading = false;
      });
    }
  }

  Future<void> _pickAndRedirect() async {
    try {
      final List<XFile> pickedFiles = await _picker.pickMultiImage();
      if (pickedFiles.isNotEmpty) {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) => ImageSavePage(
                  imagePaths: pickedFiles.map((e) => e.path).toList(),
                  projectId: widget.projectId,
                  projectName: _projectName,
                  isFromShare: false,
                ),
          ),
        ).then((_) => _loadData());
      }
    } catch (e) {
      debugPrint("Error picking images: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. Prepare Columns for Masonry Layout
    final leftColumn = <Widget>[];
    final rightColumn = <Widget>[];

    for (int i = 0; i < _images.length; i++) {
      final item = _buildStaggeredImageItem(_images[i], index: i);
      if (i % 2 == 0) {
        leftColumn.add(item);
      } else {
        rightColumn.add(item);
      }
    }

    return Scaffold(
      backgroundColor: Variables.background,

      appBar: TopBar(
        currentProjectId: widget.projectId,
        titleOverride: widget.tag.toUpperCase(),
        onBack: () => Navigator.pop(context),
        hideSecondRow: true,
      ),

      bottomNavigationBar: BottomBar(
        currentTab: BottomBarItem.moodboard,
        projectId: widget.projectId,
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: _pickAndRedirect,
        backgroundColor: Variables.textPrimary,
        foregroundColor: Variables.background,
        child: const Icon(Icons.add_photo_alternate_outlined),
      ),

      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _images.isEmpty
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.image_not_supported_outlined,
                      size: 64,
                      color: Variables.textDisabled,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "No images found for '${widget.tag}'",
                      style: Variables.bodyStyle.copyWith(
                        color: Variables.textSecondary,
                      ),
                    ),
                  ],
                ),
              )
              : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        children:
                            leftColumn
                                .map(
                                  (e) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: e,
                                  ),
                                )
                                .toList(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        children:
                            rightColumn
                                .map(
                                  (e) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: e,
                                  ),
                                )
                                .toList(),
                      ),
                    ),
                  ],
                ),
              ),
    );
  }

  Widget _buildStaggeredImageItem(ImageModel image, {required int index}) {
    return ImageContextMenu(
      image: image,
      onImageDeleted: () => _loadData(),
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (_) => ImageDetailsPage(
                    imagePath: image.filePath,
                    imageId: image.id,
                    projectId: widget.projectId,
                  ),
            ),
          ).then((_) => _loadData());
        },
        child: Container(
          // Simulate staggered heights similar to Alternate Page
          height: (index % 3 == 0) ? 240 : 180,
          decoration: BoxDecoration(
            color: Variables.surfaceSubtle,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Variables.borderSubtle),
          ),
          // Explicitly clip content to border radius
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  File(image.filePath),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  errorBuilder:
                      (_, __, ___) => Container(
                        color: Variables.surfaceSubtle,
                        child: const Center(
                          child: Icon(
                            Icons.broken_image,
                            color: Variables.textDisabled,
                          ),
                        ),
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
