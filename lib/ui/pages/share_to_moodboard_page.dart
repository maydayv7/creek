import 'dart:io';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:creekui/data/models/project_model.dart';
import 'package:creekui/data/repos/project_repo.dart';
import 'package:creekui/data/repos/image_repo.dart';
import 'package:creekui/services/project_service.dart';
import 'package:creekui/ui/styles/variables.dart';
import 'package:creekui/ui/widgets/search_bar.dart';
import 'package:creekui/ui/widgets/section_header.dart';
import 'image_save_page.dart';

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

  Future<String?> _getProjectCover(int projectId) async {
    try {
      final images = await _imageRepo.getImages(projectId);
      if (images.isNotEmpty) return images.first.filePath;
    } catch (_) {}
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
      final rawEvents = await _projectRepo.getEvents(p.id!);
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

  void _navigateToSavePage(
    int projectId,
    String projectName, {
    String? parentProjectName,
  }) {
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
              parentProjectName: parentProjectName,
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
        title: Text(
          "MoodBoards",
          style: Variables.headerStyle.copyWith(fontSize: 20),
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: CommonSearchBar(
                      controller: _searchController,
                      onChanged: _filterProjects,
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_searchQuery.isEmpty &&
                              _recentViewModels.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 8,
                              ),
                              child: SectionHeader(
                                title: "Recent Projects/Events",
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
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
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 8,
                            ),
                            child: SectionHeader(
                              title:
                                  _searchQuery.isEmpty
                                      ? "All Projects/Events"
                                      : "Search Results",
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
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
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
    );
  }

  // Wrappers for consistent UI
  Widget _buildRecentItem(ProjectItemViewModel vm) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap:
            () => _navigateToSavePage(
              vm.id,
              vm.title,
              parentProjectName: vm.parentTitle,
            ),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 4, 0, 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Variables.borderSubtle, width: 1),
          ),
          child: Row(
            children: [
              // Cover Image
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Variables.surfaceSubtle,
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
                      Text(
                        vm.parentTitle!,
                        style: Variables.captionStyle.copyWith(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text(
                      vm.title,
                      style: Variables.bodyStyle.copyWith(
                        fontWeight: FontWeight.w500,
                        fontSize: 16,
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
    final project = g.project;
    final hasEvents = g.events.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Variables.borderSubtle),
      ),
      child: Column(
        children: [
          // Parent Project
          ListTile(
            onTap:
                () =>
                    hasEvents
                        ? setState(() => g.isExpanded = !g.isExpanded)
                        : _navigateToSavePage(project.id!, project.title),
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
              project.title,
              style: Variables.bodyStyle.copyWith(
                fontWeight: FontWeight.w500,
                fontSize: 16,
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
                      onPressed:
                          () => setState(() => g.isExpanded = !g.isExpanded),
                    )
                    : null,
          ),

          // Children (Events)
          if (hasEvents)
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Container(
                width: double.infinity,
                color: Variables.surfaceSubtle,
                child: Column(
                  children:
                      g.events.map((e) {
                        return ListTile(
                          onTap: () => _navigateToSavePage(e.id, e.title),
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
                            style: Variables.bodyStyle.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
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
