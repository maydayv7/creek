import 'package:flutter/material.dart';
import 'package:creekui/ui/styles/variables.dart';
import 'package:creekui/data/models/image_model.dart';
import 'package:creekui/data/repos/image_repo.dart';
import 'package:creekui/ui/widgets/moodboard_image_card.dart';
import 'package:creekui/ui/widgets/empty_state.dart';
import 'image_details_page.dart';

class ProjectBoardPageAlternate extends StatefulWidget {
  final int projectId;
  const ProjectBoardPageAlternate({super.key, required this.projectId});

  @override
  State<ProjectBoardPageAlternate> createState() =>
      ProjectBoardPageAlternateState();
}

class ProjectBoardPageAlternateState extends State<ProjectBoardPageAlternate> {
  final _imageRepo = ImageRepo();
  List<ImageModel> _allImages = [];
  List<ImageModel> _filteredImages = [];
  List<String> _allTags = [];
  final Set<String> _selectedTags = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant ProjectBoardPageAlternate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) _loadData();
  }

  void refreshData() => _loadData();

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final images = await _imageRepo.getImages(widget.projectId);
    final Set<String> tags = {};
    for (var img in images) {
      tags.addAll(img.tags);
    }

    if (mounted) {
      setState(() {
        _allImages = images;
        _filteredImages = images;
        _allTags = tags.toList()..sort();
        _isLoading = false;
      });
      if (_selectedTags.isNotEmpty) _applyFilter();
    }
  }

  void _applyFilter() {
    setState(() {
      _filteredImages =
          _selectedTags.isEmpty
              ? _allImages
              : _allImages
                  .where(
                    (img) =>
                        img.tags.toSet().intersection(_selectedTags).isNotEmpty,
                  )
                  .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final leftColumn = <Widget>[];
    final rightColumn = <Widget>[];

    for (int i = 0; i < _filteredImages.length; i++) {
      final item = MoodboardImageCard(
        image: _filteredImages[i],
        height: (i % 3 == 0) ? 240 : 180,
        showTags: true,
        onTap:
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder:
                    (_) => ImageDetailsPage(
                      imagePath: _filteredImages[i].filePath,
                      imageId: _filteredImages[i].id,
                      projectId: widget.projectId,
                    ),
              ),
            ),
        onDeleted: refreshData,
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

    return Column(
      children: [
        // Context Info Row (Image Count + Active Filters)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: [
              const Spacer(),
              if (_selectedTags.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Variables.textPrimary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "${_selectedTags.length} Active",
                    style: Variables.captionStyle.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Masonry Grid
        Expanded(
          child:
              _filteredImages.isEmpty
                  ? const EmptyState(
                    icon: Icons.image_not_supported_outlined,
                    title: "No images found",
                    subtitle: "Try removing filters or adding new images",
                  )
                  : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: Column(children: leftColumn)),
                        const SizedBox(width: 12),
                        Expanded(child: Column(children: rightColumn)),
                      ],
                    ),
                  ),
        ),
      ],
    );
  }
}
