import 'dart:io';
import 'package:flutter/material.dart';
import 'package:creekui/data/models/project_model.dart';
import 'package:creekui/data/repos/project_repo.dart';
import 'package:creekui/data/repos/image_repo.dart';
import 'package:creekui/ui/styles/variables.dart';
import 'package:creekui/ui/widgets/search_bar.dart';
import 'package:creekui/ui/widgets/section_header.dart';
import 'package:creekui/ui/widgets/empty_state.dart';

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

class ProjectSelector extends StatefulWidget {
  final Function(int id, String title, String? parentTitle) onProjectSelected;
  final String searchHint;
  final ScrollController? scrollController;

  const ProjectSelector({
    super.key,
    required this.onProjectSelected,
    this.searchHint = "Search",
    this.scrollController,
  });

  @override
  State<ProjectSelector> createState() => _ProjectSelectorState();
}

class _ProjectSelectorState extends State<ProjectSelector> {
  final ProjectRepo _projectRepo = ProjectRepo();
  final ImageRepo _imageRepo = ImageRepo();

  final TextEditingController _searchController = TextEditingController();

  List<ProjectItemViewModel> _recentViewModels = [];
  List<ProjectGroup> _groupedProjects = [];
  List<ProjectGroup> _filteredGroupedProjects = [];

  bool _isLoading = true;
  String _searchQuery = "";

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
      if (images.isNotEmpty) {
        return images.first.filePath;
      }
    } catch (e) {
      debugPrint("Error fetching cover for project $projectId: $e");
    }
    return null;
  }

  Future<void> _loadData() async {
    if (!mounted) return;
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

    if (mounted) {
      setState(() {
        _recentViewModels = recents;
        _groupedProjects = groups;
        _filterProjects(_searchQuery); // Re-apply filter if any
        _isLoading = false;
      });
    }
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Search Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: CommonSearchBar(
            controller: _searchController,
            onChanged: _filterProjects,
            hintText: widget.searchHint,
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            controller: widget.scrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Empty State
                if (_filteredGroupedProjects.isEmpty && _searchQuery.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32.0),
                    child: EmptyState(
                      icon: Icons.search_off,
                      title: "No results found",
                      subtitle: "Try adjusting your search",
                    ),
                  ),

                // Recents Section
                if (_searchQuery.isEmpty && _recentViewModels.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SectionHeader(title: "Recent Projects/Events"),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children:
                          _recentViewModels
                              .map((vm) => _buildRecentItem(vm))
                              .toList(),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // All Projects Section
                if (_filteredGroupedProjects.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SectionHeader(
                      title:
                          _searchQuery.isEmpty
                              ? "All Projects/Events"
                              : "Search Results",
                    ),
                  ),
                  const SizedBox(height: 12),
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
                ],
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentItem(ProjectItemViewModel vm) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => widget.onProjectSelected(vm.id, vm.title, vm.parentTitle),
        borderRadius: BorderRadius.circular(Variables.radiusMedium),
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 4, 0, 4),
          decoration: BoxDecoration(
            color: Variables.background,
            borderRadius: BorderRadius.circular(Variables.radiusMedium),
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
                  borderRadius: BorderRadius.circular(Variables.radiusSmall),
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
                        ? const Icon(
                          Icons.image,
                          color: Variables.textDisabled,
                          size: 28,
                        )
                        : null,
              ),
              const SizedBox(width: 12),
              // Text Content
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
                          style: Variables.captionStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    Text(
                      vm.title,
                      style: Variables.bodyStyle.copyWith(
                        fontWeight: FontWeight.w600,
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
        color: Variables.background,
        borderRadius: BorderRadius.circular(Variables.radiusMedium),
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
                        : widget.onProjectSelected(
                          project.id!,
                          project.title,
                          null,
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
                color: Variables.surfaceSubtle,
                borderRadius: BorderRadius.circular(Variables.radiusMedium),
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
                      ? const Icon(Icons.folder, color: Variables.textDisabled)
                      : null,
            ),
            title: Text(
              project.title,
              style: Variables.bodyStyle.copyWith(
                fontWeight: FontWeight.w600,
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
                        color: Variables.textSecondary,
                      ),
                      onPressed: () {
                        setState(() => g.isExpanded = !g.isExpanded);
                      },
                    )
                    : null,
          ),

          // Children (Events)
          if (hasEvents)
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Container(
                width: double.infinity,
                color: Variables.surfaceSubtle.withOpacity(0.5),
                child: Column(
                  children:
                      g.events.map((e) {
                        return ListTile(
                          onTap:
                              () => widget.onProjectSelected(
                                e.id,
                                e.title,
                                project.title,
                              ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 2,
                          ),
                          visualDensity: VisualDensity.compact,
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Variables.background,
                              borderRadius: BorderRadius.circular(
                                Variables.radiusSmall,
                              ),
                              border: Border.all(color: Variables.borderSubtle),
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
                                      color: Variables.textDisabled,
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
