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
  final File? file; // Made optional for blank canvas creation
  final int? projectId; // Optional: If null, user can select a project

  const CreateFilePage({super.key, this.file, this.projectId});

  @override
  State<CreateFilePage> createState() => _CreateFilePageState();
}

class _CreateFilePageState extends State<CreateFilePage> {
  final TextEditingController _searchController = TextEditingController();

  // Project Selection State
  int? _selectedProjectId;
  String _selectedProjectTitle = "Select Project";

  // Master list of presets
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
      svgPath: 'assets/icons/Group.svg',
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

    // Initialize from passed project ID
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

  void _runFilter(String enteredKeyword) {
    List<CanvasPreset> results = [];
    if (enteredKeyword.isEmpty) {
      results = _allPresets;
    } else {
      results =
          _allPresets
              .where(
                (preset) => preset.name.toLowerCase().contains(
                  enteredKeyword.toLowerCase(),
                ),
              )
              .toList();
    }
    setState(() {
      _filteredPresets = results;
    });
  }

  void _openProjectSelection() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder:
                (_, controller) => Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
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
            color: Colors.black,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        actions: [
          // ONLY show selection button if projectId was NOT passed in
          if (widget.projectId == null)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: TextButton.icon(
                onPressed: _openProjectSelection,
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
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
                    color: Colors.black,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search Bar
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
                  hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
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

          // Label
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

          // Tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildTab('All', isSelected: true),
                  const SizedBox(width: 12),
                  _buildTab('Saved', isSelected: false),
                  const SizedBox(width: 12),
                  _buildTab('Photo', isSelected: false),
                  const SizedBox(width: 12),
                  _buildTab('Print', isSelected: false),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

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
              itemBuilder: (context, index) {
                return _buildPresetCard(_filteredPresets[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(String label, {required bool isSelected}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.black : Colors.grey,
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildPresetCard(CanvasPreset preset) {
    final bool isCustom = preset.name == 'Custom';

    return InkWell(
      onTap: () {
        if (isCustom) {
          _navigateToEditor(1000, 1000);
        } else {
          _navigateToEditor(preset.width, preset.height);
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E7FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child:
                      isCustom
                          ? const Icon(Icons.add, size: 30, color: Colors.blue)
                          : Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: AspectRatio(
                              aspectRatio:
                                  (preset.width > 0 && preset.height > 0)
                                      ? preset.width / preset.height
                                      : 1.0,
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
                                child: Center(
                                  child:
                                      preset.svgPath != null
                                          ? Padding(
                                            padding: const EdgeInsets.all(4.0),
                                            child: SvgPicture.asset(
                                              preset.svgPath!,
                                              fit: BoxFit.contain,
                                            ),
                                          )
                                          : null,
                                ),
                              ),
                            ),
                          ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                const SizedBox(height: 2),
                Text(
                  preset.displaySize,
                  style: const TextStyle(color: Colors.grey, fontSize: 9),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToEditor(int width, int height) {
    // FORCE Selection: If no project is selected, open the modal and return.
    if (_selectedProjectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a destination project")),
      );
      _openProjectSelection();
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => CanvasBoardPage(
              // Use the selected project ID
              projectId: _selectedProjectId.toString(),
              width: width.toDouble(),
              height: height.toDouble(),
              initialImage: widget.file,
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
// --- PROJECT SELECTION MODAL ---
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
    } catch (e) {
      debugPrint("Error fetching cover for project $projectId: $e");
    }
    return null;
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final recentItems = await _projectService.getRecentProjectsAndEvents();
    final allProjects = await _projectService.getAllProjects();

    // Build Recent View Models
    final List<ProjectItemViewModel> recents = [];
    for (var item in recentItems.take(3)) {
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

    // Build Grouped Projects
    final List<ProjectGroup> groups = [];
    for (final p in allProjects) {
      final rawEvents = await _projectService.getEvents(p.id!);
      final List<ProjectItemViewModel> eventVMs = [];
      for (final e in rawEvents) {
        final eCover = await _getProjectCover(e.id!);
        eventVMs.add(ProjectItemViewModel(item: e, coverPath: eCover));
      }
      final pCover = await _getProjectCover(p.id!);
      groups.add(ProjectGroup(project: p, events: eventVMs, coverPath: pCover));
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
      } else {
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
      }
    });
  }

  Future<void> _createNewProject() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => const DefineBrandPage(
              projectName:
                  "", // Can pass empty string if you want user to type it
            ),
      ),
    );

    // Check if a project was created and returned
    if (result != null && result is Map) {
      final newId = result['id'];
      final title = result['title'];
      if (newId != null && title != null) {
        widget.onProjectSelected(newId, title);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header handle
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        // Header Row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Select Destination",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'GeneralSans',
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: _createNewProject,
                tooltip: "Create New Project",
              ),
            ],
          ),
        ),

        // Search Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SizedBox(
            height: 42,
            child: TextField(
              controller: _searchController,
              onChanged: _filterProjects,
              decoration: InputDecoration(
                hintText: "Search Projects",
                prefixIcon: const Icon(
                  Icons.search,
                  size: 20,
                  color: Color(0xFF9F9FA9),
                ),
                filled: true,
                fillColor: const Color(0xFFE4E4E7),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 0,
                  horizontal: 16,
                ),
              ),
            ),
          ),
        ),

        Divider(color: Colors.grey[200]),

        // Content
        Expanded(
          child:
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                    controller: widget.scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    children: [
                      if (_searchQuery.isEmpty &&
                          _recentViewModels.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8, top: 8),
                          child: Text(
                            "Recent Projects/Events",
                            style: TextStyle(
                              fontSize: 14,
                              fontFamily: 'GeneralSans',
                              color: Color(0xFF27272A),
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                        ..._recentViewModels.map((vm) => _buildRecentItem(vm)),
                        const SizedBox(height: 16),
                      ],

                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _searchQuery.isEmpty
                              ? "All Projects/Events"
                              : "Search Results",
                          style: const TextStyle(
                            fontSize: 14,
                            fontFamily: 'GeneralSans',
                            color: Color(0xFF27272A),
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      ..._filteredGroupedProjects.map(
                        (g) => _buildProjectGroup(g),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
        ),
      ],
    );
  }

  Widget _buildRecentItem(ProjectItemViewModel vm) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => widget.onProjectSelected(vm.id, vm.title),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 4, 0, 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE4E4E7), width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(8),
                  image:
                      vm.coverPath != null
                          ? DecorationImage(
                            image: FileImage(File(vm.coverPath!)),
                            fit: BoxFit.cover,
                          )
                          : null,
                ),
                child:
                    vm.coverPath == null
                        ? Icon(Icons.image, color: Colors.grey[400], size: 28)
                        : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (vm.isEvent && vm.parentTitle != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          vm.parentTitle!,
                          style: const TextStyle(
                            fontFamily: 'GeneralSans',
                            fontSize: 12,
                            color: Color(0xFF27272A),
                            fontWeight: FontWeight.w400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    Text(
                      vm.title,
                      style: const TextStyle(
                        fontFamily: 'GeneralSans',
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF27272A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProjectGroup(ProjectGroup g) {
    final hasEvents = g.events.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: Column(
        children: [
          ListTile(
            onTap:
                () =>
                    hasEvents
                        ? setState(() => g.isExpanded = !g.isExpanded)
                        : widget.onProjectSelected(
                          g.project.id!,
                          g.project.title,
                        ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            visualDensity: VisualDensity.compact,
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                image:
                    g.coverPath != null
                        ? DecorationImage(
                          image: FileImage(File(g.coverPath!)),
                          fit: BoxFit.cover,
                        )
                        : null,
              ),
              child:
                  g.coverPath == null
                      ? Icon(Icons.folder, color: Colors.grey[500])
                      : null,
            ),
            title: Text(
              g.project.title,
              style: const TextStyle(
                fontFamily: 'GeneralSans',
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Color(0xFF27272A),
              ),
            ),
            trailing:
                hasEvents
                    ? IconButton(
                      icon: Icon(
                        g.isExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: Colors.grey[600],
                      ),
                      onPressed: () {
                        setState(() => g.isExpanded = !g.isExpanded);
                      },
                    )
                    : null,
          ),
          if (hasEvents && g.isExpanded)
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Container(
                width: double.infinity,
                color: const Color(0xFFF9FAFB),
                child: Column(
                  children:
                      g.events.map((e) {
                        return ListTile(
                          onTap: () => widget.onProjectSelected(e.id, e.title),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 2,
                          ),
                          visualDensity: VisualDensity.compact,
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.shade200),
                              image:
                                  e.coverPath != null
                                      ? DecorationImage(
                                        image: FileImage(File(e.coverPath!)),
                                        fit: BoxFit.cover,
                                      )
                                      : null,
                            ),
                            child:
                                e.coverPath == null
                                    ? const Icon(
                                      Icons.event,
                                      size: 20,
                                      color: Colors.grey,
                                    )
                                    : null,
                          ),
                          title: Text(
                            e.title,
                            style: const TextStyle(
                              fontFamily: 'GeneralSans',
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF27272A),
                            ),
                          ),
                        );
                      }).toList(),
                ),
              ),
              crossFadeState:
                  g.isExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
        ],
      ),
    );
  }
}
