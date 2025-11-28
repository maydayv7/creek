import 'dart:io';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

// Models & Repos
import '../../data/models/project_model.dart';
import '../../data/repos/project_repo.dart';
import '../../data/repos/image_repo.dart';

// Services
import '../../services/project_service.dart';

// Pages
import 'image_save_page.dart';

// --- VIEW MODELS ---

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
  // Holds ViewModels so we have cover paths for events too
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

// --- WIDGET ---

class ShareToMoodboardPage extends StatefulWidget {
  final List<File> imageFiles;

  const ShareToMoodboardPage({super.key, required this.imageFiles});

  @override
  State<ShareToMoodboardPage> createState() => _ShareToMoodboardPageState();
}

class _ShareToMoodboardPageState extends State<ShareToMoodboardPage> {
  final ProjectRepo _projectRepo = ProjectRepo();
  final ImageRepo _imageRepo = ImageRepo();
  final ProjectService _projectService = ProjectService();

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

  /// Helper to fetch the latest image for a project to use as cover
  Future<String?> _getProjectCover(int projectId) async {
    try {
      final images = await _imageRepo.getImages(projectId);
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

    // 1. Fetch Raw Data
    final recentItems = await _projectRepo.getRecentProjectsAndEvents();
    final allProjects = await _projectRepo.getAllProjects();

    // 2. Build Recent View Models
    final List<ProjectItemViewModel> recents = [];
    for (var item in recentItems.take(3)) {
      String? parentTitle;
      if (item.parentId != null) {
        final parent = await _projectRepo.getProjectById(item.parentId!);
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

    // 3. Build Grouped Projects
    final List<ProjectGroup> groups = [];
    for (final p in allProjects) {
      // Fetch Events
      final rawEvents = await _projectRepo.getEvents(p.id!);

      // Convert Events to ViewModels (to get their covers)
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
    final controller = TextEditingController();
    final String? title = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text("New Project"),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(hintText: "Project Title"),
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: const Text("Create"),
              ),
            ],
          ),
    );

    if (title != null && title.isNotEmpty) {
      final newId = await _projectService.createProject(title);
      await _loadData();
      _navigateToSavePage(newId, title);
    }
  }

  void _navigateToSavePage(int projectId, String projectName) {
    _projectService.openProject(projectId);
    ReceiveSharingIntent.instance.reset();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => ImageSavePage(
              imagePaths: widget.imageFiles.map((f) => f.path).toList(),
              projectId: projectId,
              projectName: projectName,
              isFromShare: true,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "MoodBoards",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.black, size: 28),
            onPressed: _createNewProject,
            tooltip: "Create New Project",
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                children: [
                  // Search Bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: TextField(
                      controller: _searchController,
                      onChanged: _filterProjects,
                      decoration: InputDecoration(
                        hintText: "Search",
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Colors.grey,
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                        suffixIcon:
                            _searchQuery.isNotEmpty
                                ? IconButton(
                                  icon: const Icon(
                                    Icons.clear,
                                    color: Colors.grey,
                                  ),
                                  onPressed: () {
                                    _searchController.clear();
                                    _filterProjects("");
                                  },
                                )
                                : null,
                      ),
                    ),
                  ),

                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // --- RECENT SECTION ---
                          if (_searchQuery.isEmpty &&
                              _recentViewModels.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Text(
                                "Recent Projects/Events",
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Column(
                                children:
                                    _recentViewModels
                                        .map((vm) => _buildRecentItem(vm))
                                        .toList(),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],

                          // --- ALL PROJECTS SECTION ---
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Text(
                              _searchQuery.isEmpty
                                  ? "All Projects/Events"
                                  : "Search Results",
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _filteredGroupedProjects.length,
                              itemBuilder:
                                  (context, index) => _buildProjectGroup(
                                    _filteredGroupedProjects[index],
                                  ),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
    );
  }

  // --- WIDGETS ---

  Widget _buildRecentItem(ProjectItemViewModel vm) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _navigateToSavePage(vm.id, vm.title),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Cover Image
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
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
                        ? Icon(Icons.image, color: Colors.grey[400], size: 30)
                        : null,
              ),
              const SizedBox(width: 16),
              // Text Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (vm.isEvent && vm.parentTitle != null)
                      Text(
                        vm.parentTitle!,
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text(
                      vm.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
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

  // UPDATED: Main tap saves to Project, Arrow toggles Events
  Widget _buildProjectGroup(ProjectGroup g) {
    final project = g.project;
    final hasEvents = g.events.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12), // Separate cards
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200), // FULL BORDER
      ),
      child: Column(
        children: [
          // PARENT PROJECT TILE
          ListTile(
            // ACTION 1: Tap main area -> Save to Project
            onTap: () => _navigateToSavePage(project.id!, project.title),

            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: Container(
              width: 50,
              height: 50,
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
              project.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),

            // ACTION 2: Tap Dropdown -> Toggle List
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

          // CHILDREN (EVENTS) with GREY BACKGROUND
          if (hasEvents)
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Container(
                width: double.infinity, // Stretch to full width
                color: Colors.grey[50], // LIGHT GREY BACKGROUND
                child: Column(
                  children:
                      g.events.map((e) {
                        return ListTile(
                          onTap: () => _navigateToSavePage(e.id, e.title),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 6,
                          ),
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
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
                                      color: Colors.grey,
                                    )
                                    : null,
                          ),
                          title: Text(
                            e.title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
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
