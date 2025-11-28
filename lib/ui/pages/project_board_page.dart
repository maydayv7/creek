import 'dart:io';
import 'package:flutter/material.dart';
import '../../data/models/project_model.dart';
import '../../data/models/image_model.dart';
import '../../data/repos/project_repo.dart';
import '../../data/repos/image_repo.dart';
import 'project_tag_page.dart';
import 'image_details_page.dart';

class ProjectBoardPage extends StatefulWidget {
  final int projectId;

  const ProjectBoardPage({super.key, required this.projectId});

  @override
  State<ProjectBoardPage> createState() => _ProjectBoardPageState();
}

class _ProjectBoardPageState extends State<ProjectBoardPage> {
  final _projectRepo = ProjectRepo();
  final _imageRepo = ImageRepo();

  ProjectModel? _mainProject;
  List<ProjectModel> _events = [];
  ProjectModel? _selectedProject;

  Map<String, List<ImageModel>> _categorizedImages = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final events = await _projectRepo.getEvents(widget.projectId);

    _mainProject = ProjectModel(
      id: widget.projectId,
      title: "Main Project",
      lastAccessedAt: DateTime.now(),
      createdAt: DateTime.now(),
    );

    _events = events;
    _selectedProject = _mainProject;

    await _loadImagesForSelected();
  }

  Future<void> _loadImagesForSelected() async {
    if (_selectedProject?.id == null) return;

    setState(() => _isLoading = true);

    final images = await _imageRepo.getImages(_selectedProject!.id!);
    _categorizeImages(images);

    setState(() => _isLoading = false);
  }

  void _categorizeImages(List<ImageModel> images) {
    _categorizedImages.clear();

    for (var img in images) {
      if (img.tags.isEmpty) {
        if (!_categorizedImages.containsKey('Uncategorized')) {
          _categorizedImages['Uncategorized'] = [];
        }
        _categorizedImages['Uncategorized']!.add(img);
      } else {
        for (var tag in img.tags) {
          if (!_categorizedImages.containsKey(tag)) {
            _categorizedImages[tag] = [];
          }
          _categorizedImages[tag]!.add(img);
        }
      }
    }
  }

  void _onProjectChanged(ProjectModel? newValue) {
    if (newValue != null && newValue != _selectedProject) {
      setState(() {
        _selectedProject = newValue;
      });
      _loadImagesForSelected();
    }
  }

  // Navigate to image details and refresh on return
  Future<void> _navigateToImageDetails(ImageModel image) async {
    final result = await Navigator.push(
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

    // Refresh the board when returning from image details
    // The result can be anything or null - we always refresh
    await _loadImagesForSelected();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final buttonColor =
        isDark ? Colors.white.withOpacity(0.1) : Colors.grey[100];

    final List<DropdownMenuItem<ProjectModel>> dropdownItems = [];
    if (_mainProject != null) {
      dropdownItems.add(
        DropdownMenuItem(
          value: _mainProject,
          child: Text(
            _mainProject!.title,
            style: const TextStyle(fontFamily: 'GeneralSans'),
          ),
        ),
      );
    }
    for (var event in _events) {
      dropdownItems.add(
        DropdownMenuItem(
          value: event,
          child: Text(
            event.title,
            style: const TextStyle(fontFamily: 'GeneralSans'),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        centerTitle: false,
        title: Text(
          _mainProject?.title ?? "Project",
          style: TextStyle(
            fontFamily: 'GeneralSans',
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.settings_outlined, color: theme.iconTheme.color),
            onPressed: () {},
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Controls Row
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: buttonColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<ProjectModel>(
                        value: _selectedProject,
                        isExpanded: true,
                        items: dropdownItems,
                        onChanged: _onProjectChanged,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontFamily: 'GeneralSans',
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                        icon: Icon(
                          Icons.keyboard_arrow_down,
                          size: 18,
                          color: theme.iconTheme.color,
                        ),
                        dropdownColor: theme.cardColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _buildControlIcon(
                  theme,
                  buttonColor,
                  Icons.palette_outlined,
                  "Stylesheet",
                  () {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text("Stylesheet")));
                  },
                ),
                const SizedBox(width: 8),
                _buildControlIcon(
                  theme,
                  buttonColor,
                  Icons.tune_outlined,
                  "Filter",
                  () {},
                ),
              ],
            ),
          ),

          // Main Content
          Expanded(
            child:
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _categorizedImages.isEmpty
                    ? Center(
                      child: Text(
                        "No images found",
                        style: TextStyle(
                          fontFamily: 'GeneralSans',
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    )
                    : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      itemCount: _categorizedImages.keys.length,
                      itemBuilder: (context, index) {
                        final category = _categorizedImages.keys.elementAt(
                          index,
                        );
                        final images = _categorizedImages[category]!;

                        return GestureDetector(
                          onTap: () {
                            if (_selectedProject?.id != null) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (_) => ProjectTagPage(
                                        projectId: _selectedProject!.id!,
                                        tag: category,
                                      ),
                                ),
                              ).then((_) => _loadImagesForSelected());
                            }
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              color:
                                  isDark
                                      ? const Color(0xFF1E1E1E)
                                      : Colors.white,
                              border: Border.all(
                                color: Colors.grey.withOpacity(0.3),
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Category Header
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    12,
                                    16,
                                    8,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        category.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.0,
                                          fontFamily: 'GeneralSans',
                                          color: theme.colorScheme.onSurface,
                                        ),
                                      ),
                                      Icon(
                                        Icons.arrow_forward,
                                        size: 16,
                                        color: theme.colorScheme.onSurface
                                            .withOpacity(0.4),
                                      ),
                                    ],
                                  ),
                                ),

                                // Image List
                                SizedBox(
                                  height: 140,
                                  child: ListView.separated(
                                    clipBehavior: Clip.none,
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      16,
                                    ),
                                    scrollDirection: Axis.horizontal,
                                    itemCount: images.length,
                                    separatorBuilder:
                                        (_, __) => const SizedBox(width: 8),
                                    itemBuilder: (context, imgIndex) {
                                      final image = images[imgIndex];
                                      return _buildImageCard(
                                        image,
                                        theme,
                                        isDark,
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlIcon(
    ThemeData theme,
    Color? bgColor,
    IconData icon,
    String tooltip,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: theme.iconTheme.color),
      ),
    );
  }

  Widget _buildImageCard(ImageModel image, ThemeData theme, bool isDark) {
    return GestureDetector(
      onTap: () => _navigateToImageDetails(image),
      child: Container(
        width: 120,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isDark ? Colors.black26 : Colors.grey[200],
          border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: 'image_${image.id}',
              child: Image.file(
                File(image.filePath),
                fit: BoxFit.cover,
                errorBuilder:
                    (_, __, ___) => Container(
                      color: Colors.grey[300],
                      child: const Icon(Icons.broken_image, color: Colors.grey),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
