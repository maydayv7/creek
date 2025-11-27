import 'dart:io';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

// Models & Repos
import '../../data/models/project_model.dart';
import '../../data/repos/project_repo.dart';

// Services
import '../../services/project_service.dart';
import '../../services/image_service.dart'; // <--- CHANGED: Import ImageService

// Helper model for UI rendering
class ProjectItemViewModel {
  final ProjectModel item;
  final String? parentTitle;

  ProjectItemViewModel({required this.item, this.parentTitle});

  String get title => item.title;
  bool get isEvent => item.isEvent;
  int get id => item.id!;
}

class ShareToMoodboardPage extends StatefulWidget {
  final File imageFile;

  const ShareToMoodboardPage({super.key, required this.imageFile});

  @override
  State<ShareToMoodboardPage> createState() => _ShareToMoodboardPageState();
}

class _ShareToMoodboardPageState extends State<ShareToMoodboardPage> {
  final ProjectRepo _projectRepo = ProjectRepo();
  final ProjectService _projectService = ProjectService();

  // FIXED: Use ImageService (which handles Moodboard Images)
  final ImageService _imageService = ImageService();

  List<ProjectItemViewModel> _recentViewModels = [];
  List<ProjectItemViewModel> _allViewModels = [];
  List<ProjectItemViewModel> _filteredViewModels = [];

  bool _isLoading = true;
  bool _isSaving = false;
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

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // Fetch raw data
    final recentItems = await _projectRepo.getRecentProjectsAndEvents();
    final allItems = await _projectRepo.getAllProjectsAndEvents();

    // Build view models with parent titles
    _recentViewModels = await _buildViewModels(recentItems.take(3).toList());
    _allViewModels = await _buildViewModels(allItems);
    _filteredViewModels = _allViewModels;

    setState(() => _isLoading = false);
  }

  Future<List<ProjectItemViewModel>> _buildViewModels(
    List<ProjectModel> items,
  ) async {
    final List<ProjectItemViewModel> viewModels = [];
    for (var item in items) {
      String? parentTitle;
      if (item.parentId != null) {
        final parent = await _projectRepo.getProjectById(item.parentId!);
        parentTitle = parent?.title;
      }
      viewModels.add(
        ProjectItemViewModel(item: item, parentTitle: parentTitle),
      );
    }
    return viewModels;
  }

  void _filterProjects(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredViewModels = _allViewModels;
      } else {
        _filteredViewModels =
            _allViewModels.where((vm) {
              final titleMatches = vm.title.toLowerCase().contains(
                query.toLowerCase(),
              );
              final parentMatches =
                  vm.parentTitle?.toLowerCase().contains(query.toLowerCase()) ??
                  false;
              return titleMatches || parentMatches;
            }).toList();
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
      // Create the project and save the image to it immediately
      final newId = await _projectService.createProject(title);
      await _saveAndExit(newId);
    }
  }

  Future<void> _saveAndExit(int projectId) async {
    setState(() => _isSaving = true);

    try {
      // 1. Save Image to Moodboard (Using ImageService)
      await _imageService.saveImage(widget.imageFile, projectId);

      // 2. Update "Recently Used" status
      await _projectService.openProject(projectId);

      // 3. Reset Share Intent
      ReceiveSharingIntent.instance.reset();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Saved to Moodboard!"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.popUntil(
          context,
          (route) => route.isFirst,
        ); // Go back to home
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error saving: $e"),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isSaving = false);
      }
    }
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
          _isLoading || _isSaving
              ? const Center(child: CircularProgressIndicator())
              : Column(
                children: [
                  // --- Search Bar ---
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
                          // --- Recent Projects/Events Section ---
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
                            SizedBox(
                              height: 90,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                itemCount: _recentViewModels.length,
                                separatorBuilder:
                                    (_, __) => const SizedBox(width: 12),
                                itemBuilder: (context, index) {
                                  return _buildRecentItem(
                                    _recentViewModels[index],
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],

                          // --- All Projects/Events Section ---
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
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _filteredViewModels.length,
                            itemBuilder: (context, index) {
                              return _buildAllItem(_filteredViewModels[index]);
                            },
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

  // --- Widget for Recent Items (Horizontal List) ---
  Widget _buildRecentItem(ProjectItemViewModel vm) {
    return InkWell(
      onTap: () => _saveAndExit(vm.id),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 220,
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
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.image, color: Colors.grey[400], size: 30),
            ),
            const SizedBox(width: 12),
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
    );
  }

  // --- Widget for All Items (Vertical List) ---
  Widget _buildAllItem(ProjectItemViewModel vm) {
    return ListTile(
      onTap: () => _saveAndExit(vm.id),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          vm.isEvent ? Icons.event : Icons.folder,
          color: Colors.grey[500],
        ),
      ),
      title:
          vm.isEvent && vm.parentTitle != null
              ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vm.parentTitle!,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                  Text(
                    vm.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )
              : Text(
                vm.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
    );
  }
}
