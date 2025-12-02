import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'canvas_board_page.dart';
import 'define_brand_page.dart';

// Services
import '../../services/project_service.dart';
import '../../services/image_service.dart';

// Models
import '../../data/models/project_model.dart';

class CreateFilePage extends StatefulWidget {
  final File? file;
  final int? projectId; // ⭐ MAKE NULLABLE

  const CreateFilePage({super.key, this.file, this.projectId});

  @override
  State<CreateFilePage> createState() => _CreateFilePageState();
}

class _CreateFilePageState extends State<CreateFilePage> {
  final TextEditingController _searchController = TextEditingController();

  // Project Selection
  int? _selectedProjectId;
  String _selectedProjectTitle = "Select Project";

  // Presets
  final List<CanvasPreset> _allPresets = [
    CanvasPreset(
      name: 'Custom',
      width: 0,
      height: 0,
      displaySize: 'Custom Size',
    ),
    CanvasPreset(
      name: 'Poster',
      width: 2304,
      height: 3456,
      displaySize: '24 x 36 in',
    ),
    CanvasPreset(
      name: 'Instagram Post',
      width: 1080,
      height: 1080,
      displaySize: '1080 x 1080 px',
      svgPath: 'assets/icons/instagram_poster.svg',
    ),
    CanvasPreset(
      name: 'Invitation',
      width: 480,
      height: 672,
      displaySize: '5 x 7 in',
      svgPath: 'assets/icons/invitation.svg',
    ),
    CanvasPreset(
      name: 'Flyer - A5',
      width: 560,
      height: 794,
      displaySize: '148 x 210 mm',
    ),
    CanvasPreset(
      name: 'Business Card',
      width: 336,
      height: 192,
      displaySize: '3.5 x 2 in',
      svgPath: 'assets/icons/group.svg',
    ),
    CanvasPreset(
      name: 'Photo Collage',
      width: 1800,
      height: 1800,
      displaySize: '1800 x 1800 px',
    ),
    CanvasPreset(
      name: 'Menu',
      width: 794,
      height: 1123,
      displaySize: '210 x 297 mm',
    ),
    CanvasPreset(
      name: 'Menu Book',
      width: 794,
      height: 1123,
      displaySize: '210 x 297 mm',
    ),
  ];

  List<CanvasPreset> _filteredPresets = [];

  @override
  void initState() {
    super.initState();
    _filteredPresets = _allPresets;

    // ⭐ If an existing projectId was passed, lock to that project
    _selectedProjectId = widget.projectId;
    if (_selectedProjectId != null) {
      _selectedProjectTitle = "Current Project";
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _runFilter(String keyword) {
    if (keyword.isEmpty) {
      setState(() => _filteredPresets = _allPresets);
      return;
    }

    setState(() {
      _filteredPresets =
          _allPresets
              .where(
                (p) => p.name.toLowerCase().contains(keyword.toLowerCase()),
              )
              .toList();
    });
  }

  // ⭐ Select project (only for ShareToFilePage flow)
  void _openProjectSelection() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (_, controller) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: ProjectSelectionModal(
                scrollController: controller,
                onProjectSelected: (id, title) {
                  setState(() {
                    _selectedProjectId = id;
                    _selectedProjectTitle = title;
                  });
                  Navigator.pop(context);
                },
              ),
            );
          },
        );
      },
    );
  }

  // ⭐ Go to canvas with selected project
  void _navigateToEditor(int width, int height) {
    if (_selectedProjectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a destination project")),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => CanvasBoardPage(
              projectId: _selectedProjectId!, // ⭐ use selected project
              width: width.toDouble(),
              height: height.toDouble(),
              initialImage: widget.file,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F5F7),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Create Files',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),

        // ⭐ Show project chooser ONLY when projectId was NOT passed
        actions: [
          if (widget.projectId == null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: TextButton.icon(
                onPressed: _openProjectSelection,
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                icon: Icon(
                  _selectedProjectId == null
                      ? Icons.create_new_folder_outlined
                      : Icons.folder_open,
                  size: 18,
                  color: Colors.black,
                ),
                label: Text(
                  _selectedProjectTitle,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
        ],
      ),

      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _runFilter,
                decoration: InputDecoration(
                  hintText: 'Search sizes',
                  prefixIcon: Icon(
                    Icons.search,
                    color: Colors.grey[400],
                    size: 20,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  suffixIcon:
                      _searchController.text.isNotEmpty
                          ? IconButton(
                            icon: const Icon(
                              Icons.clear,
                              color: Colors.grey,
                              size: 20,
                            ),
                            onPressed: () {
                              _searchController.clear();
                              _runFilter('');
                            },
                          )
                          : null,
                ),
              ),
            ),
          ),

          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Canvas Sizes',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          // Grid
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.75,
              ),
              itemCount: _filteredPresets.length,
              itemBuilder: (_, i) => _buildPresetCard(_filteredPresets[i]),
            ),
          ),
        ],
      ),
    );
  }

  // Card widget
  Widget _buildPresetCard(CanvasPreset preset) {
    final bool isCustom = preset.name == 'Custom';

    return InkWell(
      onTap: () {
        _navigateToEditor(
          isCustom ? 1000 : preset.width,
          isCustom ? 1000 : preset.height,
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E7FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child:
                      isCustom
                          ? const Icon(Icons.add, color: Colors.blue, size: 30)
                          : Padding(
                            padding: const EdgeInsets.all(12),
                            child: AspectRatio(
                              aspectRatio: preset.width / preset.height,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(4),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child:
                                    preset.svgPath != null
                                        ? SvgPicture.asset(
                                          preset.svgPath!,
                                          fit: BoxFit.contain,
                                        )
                                        : null,
                              ),
                            ),
                          ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              preset.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 11,
                color: Colors.black,
              ),
            ),
            Text(
              preset.displaySize,
              style: const TextStyle(color: Colors.grey, fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }
}

class CanvasPreset {
  final String name;
  final int width;
  final int height;
  final String displaySize;
  final String? svgPath;

  CanvasPreset({
    required this.name,
    required this.width,
    required this.height,
    required this.displaySize,
    this.svgPath,
  });
}

// --------------------------------------------------------------------------
// --- PROJECT SELECTION MODAL ----------------------------------------------
// --------------------------------------------------------------------------

class ProjectItemViewModel {
  final ProjectModel item;
  final String? parentTitle;
  final String? coverPath;

  ProjectItemViewModel({required this.item, this.parentTitle, this.coverPath});

  String get title => item.title;
  bool get isEvent => item.isEvent;
  int get id => item.id!;
}

class ProjectGroup {
  final ProjectModel project;
  final List<ProjectItemViewModel> events;
  final String? coverPath;
  bool isExpanded;

  ProjectGroup({
    required this.project,
    this.events = const [],
    this.coverPath,
    this.isExpanded = false,
  });
}

class ProjectSelectionModal extends StatefulWidget {
  final Function(int id, String title) onProjectSelected;
  final ScrollController scrollController;

  const ProjectSelectionModal({
    super.key,
    required this.onProjectSelected,
    required this.scrollController,
  });

  @override
  State<ProjectSelectionModal> createState() => _ProjectSelectionModalState();
}

class _ProjectSelectionModalState extends State<ProjectSelectionModal> {
  final ProjectService _projectService = ProjectService();
  final ImageService _imageService = ImageService();

  List<ProjectItemViewModel> _recentViewModels = [];
  List<ProjectGroup> _groupedProjects = [];
  List<ProjectGroup> _filteredGroupedProjects = [];

  bool _isLoading = true;
  String _searchQuery = "";

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<String?> _getProjectCover(int projectId) async {
    try {
      final images = await _imageService.getImages(projectId);
      if (images.isNotEmpty) {
        return images.first.filePath;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final recent = await _projectService.getRecentProjectsAndEvents();
    final allProjects = await _projectService.getAllProjects();

    // Build Recent
    final List<ProjectItemViewModel> recents = [];
    for (var item in recent.take(3)) {
      String? parentTitle;
      if (item.parentId != null) {
        final parent = await _projectService.getProjectById(item.parentId!);
        parentTitle = parent?.title;
      }
      final cover = await _getProjectCover(item.id!);
      recents.add(
        ProjectItemViewModel(
          item: item,
          parentTitle: parentTitle,
          coverPath: cover,
        ),
      );
    }
    _recentViewModels = recents;

    // Build groups
    final List<ProjectGroup> groups = [];
    for (final p in allProjects) {
      final eventsRaw = await _projectService.getEvents(p.id!);
      final List<ProjectItemViewModel> events = [];
      for (final e in eventsRaw) {
        final cover = await _getProjectCover(e.id!);
        events.add(ProjectItemViewModel(item: e, coverPath: cover));
      }
      final cover = await _getProjectCover(p.id!);
      groups.add(ProjectGroup(project: p, events: events, coverPath: cover));
    }

    _groupedProjects = groups;
    _filteredGroupedProjects = groups;

    if (mounted) setState(() => _isLoading = false);
  }

  void _filterProjects(String query) {
    setState(() {
      _searchQuery = query;

      if (query.isEmpty) {
        _filteredGroupedProjects = _groupedProjects;
        return;
      }

      final q = query.toLowerCase();
      final List<ProjectGroup> filtered = [];

      for (final g in _groupedProjects) {
        final projectMatch = g.project.title.toLowerCase().contains(q);
        final matchingEvents =
            g.events.where((e) => e.title.toLowerCase().contains(q)).toList();

        if (projectMatch) {
          filtered.add(
            ProjectGroup(
              project: g.project,
              events: g.events,
              isExpanded: true,
              coverPath: g.coverPath,
            ),
          );
        } else if (matchingEvents.isNotEmpty) {
          filtered.add(
            ProjectGroup(
              project: g.project,
              events: matchingEvents,
              isExpanded: true,
              coverPath: g.coverPath,
            ),
          );
        }
      }

      _filteredGroupedProjects = filtered;
    });
  }

  Future<void> _createNewProject() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DefineBrandPage(projectName: "")),
    );

    if (result != null && result is Map) {
      widget.onProjectSelected(result["id"], result["title"]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        // Header row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Select Destination",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: _createNewProject,
              ),
            ],
          ),
        ),

        // Search bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _searchController,
            onChanged: _filterProjects,
            decoration: InputDecoration(
              hintText: "Search Projects",
              prefixIcon: const Icon(Icons.search, size: 20),
              filled: true,
              fillColor: const Color(0xFFE4E4E7),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),

        Divider(color: Colors.grey[300]),

        Expanded(
          child:
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                    controller: widget.scrollController,
                    children: [
                      if (_searchQuery.isEmpty && _recentViewModels.isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.only(left: 16, bottom: 8),
                          child: Text(
                            "Recent Projects/Events",
                            style: TextStyle(fontSize: 14),
                          ),
                        ),
                      if (_searchQuery.isEmpty)
                        ..._recentViewModels.map(_buildRecentItem),

                      const Padding(
                        padding: EdgeInsets.only(left: 16, top: 8, bottom: 8),
                        child: Text(
                          "All Projects/Events",
                          style: TextStyle(fontSize: 14),
                        ),
                      ),

                      ..._filteredGroupedProjects.map(_buildProjectGroup),
                    ],
                  ),
        ),
      ],
    );
  }

  Widget _buildRecentItem(ProjectItemViewModel vm) {
    return InkWell(
      onTap: () => widget.onProjectSelected(vm.id, vm.title),
      child: ListTile(
        leading: _thumbnail(vm.coverPath),
        title: Text(vm.title),
        subtitle: vm.parentTitle != null ? Text(vm.parentTitle!) : null,
      ),
    );
  }

  Widget _thumbnail(String? path) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
        image:
            path != null
                ? DecorationImage(
                  image: FileImage(File(path)),
                  fit: BoxFit.cover,
                )
                : null,
      ),
      child: path == null ? Icon(Icons.image, color: Colors.grey[400]) : null,
    );
  }

  Widget _buildProjectGroup(ProjectGroup g) {
    final hasEvents = g.events.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          ListTile(
            onTap: () {
              if (hasEvents) {
                setState(() => g.isExpanded = !g.isExpanded);
              } else {
                widget.onProjectSelected(g.project.id!, g.project.title);
              }
            },
            leading: _thumbnail(g.coverPath),
            title: Text(g.project.title),
            trailing:
                hasEvents
                    ? Icon(
                      g.isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                    )
                    : null,
          ),

          if (hasEvents && g.isExpanded)
            Container(
              color: Colors.grey[100],
              child: Column(
                children:
                    g.events.map((e) {
                      return ListTile(
                        onTap: () => widget.onProjectSelected(e.id, e.title),
                        leading: _thumbnail(e.coverPath),
                        title: Text(e.title),
                      );
                    }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
