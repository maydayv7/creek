import 'dart:io';
import 'package:flutter/material.dart';
import 'package:creekui/ui/styles/variables.dart';
import 'package:creekui/data/models/image_model.dart';
import 'package:creekui/data/repos/image_repo.dart';
import 'package:creekui/ui/widgets/image_context_menu.dart';
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

  // Called when project changes in parent
  @override
  void didUpdateWidget(covariant ProjectBoardPageAlternate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) {
      _loadData();
    }
  }

  void refreshData() {
    _loadData();
  }

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
    if (_selectedTags.isEmpty) {
      setState(() => _filteredImages = _allImages);
    } else {
      setState(() {
        _filteredImages =
            _allImages.where((img) {
              return img.tags.toSet().intersection(_selectedTags).isNotEmpty;
            }).toList();
      });
    }
  }

  void showFilterDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.6,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Filter by Tags",
                        style: Variables.headerStyle.copyWith(fontSize: 20),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (_allTags.isEmpty)
                    Text("No tags available.", style: Variables.bodyStyle),

                  Expanded(
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children:
                            _allTags.map((tag) {
                              final isSelected = _selectedTags.contains(tag);
                              return FilterChip(
                                label: Text(tag.toUpperCase()),
                                selected: isSelected,
                                onSelected: (selected) {
                                  setModalState(() {
                                    if (selected) {
                                      _selectedTags.add(tag);
                                    } else {
                                      _selectedTags.remove(tag);
                                    }
                                  });
                                  // Update main state
                                  setState(() {
                                    _applyFilter();
                                  });
                                },
                                labelStyle: Variables.captionStyle.copyWith(
                                  color:
                                      isSelected
                                          ? Colors.white
                                          : Variables.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                                backgroundColor: Variables.surfaceSubtle,
                                selectedColor: Variables.textPrimary,
                                checkmarkColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  side: BorderSide.none,
                                ),
                              );
                            }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () {
                            setState(() {
                              _selectedTags.clear();
                              _applyFilter();
                            });
                            Navigator.pop(context);
                          },
                          child: const Text(
                            "Clear All",
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Variables.textPrimary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text("Done"),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final leftColumn = <Widget>[];
    final rightColumn = <Widget>[];

    for (int i = 0; i < _filteredImages.length; i++) {
      final item = _buildImageItem(_filteredImages[i], index: i);
      if (i % 2 == 0) {
        leftColumn.add(item);
      } else {
        rightColumn.add(item);
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
                  ? Center(
                    child: Text(
                      "No images found",
                      style: Variables.bodyStyle.copyWith(
                        color: Variables.textSecondary,
                      ),
                    ),
                  )
                  : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      16,
                      0,
                      16,
                      80,
                    ), // Bottom padding for FAB
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            children:
                                leftColumn
                                    .map(
                                      (e) => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
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
                                        padding: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        child: e,
                                      ),
                                    )
                                    .toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
        ),
      ],
    );
  }

  Widget _buildImageItem(ImageModel image, {required int index}) {
    return ImageContextMenu(
      image: image,
      onImageDeleted: () => refreshData(),
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
          );
        },
        child: Container(
          height: (index % 3 == 0) ? 240 : 180,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Variables.surfaceSubtle,
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                File(image.filePath),
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder:
                    (_, __, ___) => const Center(
                      child: Icon(
                        Icons.broken_image,
                        color: Variables.textDisabled,
                      ),
                    ),
              ),
              if (image.tags.isNotEmpty)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.8),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        // Show first 2 tags
                        ...image.tags.take(2).map((tag) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                            ),
                            child: Text(
                              tag.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontFamily: 'GeneralSans',
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }),
                        // Show "+x" tag if there are more than 2 tags
                        if (image.tags.length > 2)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                            ),
                            child: Text(
                              '+${image.tags.length - 2}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontFamily: 'GeneralSans',
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
