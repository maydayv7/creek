import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:creekui/ui/styles/variables.dart';
import 'package:creekui/ui/widgets/top_bar.dart';
import 'package:creekui/ui/widgets/bottom_bar.dart';
import 'package:creekui/ui/widgets/moodboard_image_card.dart';
import 'package:creekui/ui/widgets/empty_state.dart';
import 'package:creekui/data/models/image_model.dart';
import 'package:creekui/data/repos/image_repo.dart';
import 'package:creekui/data/repos/project_repo.dart';
import 'package:creekui/data/repos/note_repo.dart';
import 'image_save_page.dart';
import 'image_details_page.dart';

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

    await Future.wait(
      allImages.map((img) async {
        bool matches = false;
        if (widget.tag == 'Uncategorized') {
          if (img.tags.isEmpty) {
            final notes = await _noteRepo.getNotesForImage(img.id);
            if (!notes.any((n) => n.category.isNotEmpty)) matches = true;
          }
        } else {
          if (img.tags.contains(widget.tag))
            matches = true;
          else {
            final notes = await _noteRepo.getNotesForImage(img.id);
            if (notes.any((n) => n.category == widget.tag)) matches = true;
          }
        }
        if (matches) filtered.add(img);
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
    final leftColumn = <Widget>[];
    final rightColumn = <Widget>[];

    for (int i = 0; i < _images.length; i++) {
      final item = MoodboardImageCard(
        image: _images[i],
        height: (i % 3 == 0) ? 240 : 180,
        onTap:
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder:
                    (_) => ImageDetailsPage(
                      imagePath: _images[i].filePath,
                      imageId: _images[i].id,
                      projectId: widget.projectId,
                    ),
              ),
            ).then((_) => _loadData()),
        onDeleted: _loadData,
      );

      if (i % 2 == 0) {
        leftColumn.add(
          Padding(padding: const EdgeInsets.only(bottom: 12), child: item),
        );
      } else {
        rightColumn.add(
          Padding(padding: const EdgeInsets.only(bottom: 12), child: item),
        );
      }
    }

    return Scaffold(
      backgroundColor: Variables.surfaceBackground,
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
              ? EmptyState(
                icon: Icons.image_not_supported_outlined,
                title: "No images found",
                subtitle: "No images found for '${widget.tag}'",
              )
              : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Column(children: leftColumn)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(children: rightColumn)),
                  ],
                ),
              ),
    );
  }
}
