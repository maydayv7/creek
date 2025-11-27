import 'dart:io';
import 'package:flutter/material.dart';
import '../../data/models/project_model.dart';
import '../../data/repos/project_repo.dart';
import '../../data/repos/image_repo.dart';
import '../../services/project_service.dart';
import 'image_analysis_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _projectRepo = ProjectRepo();
  final _imageRepo = ImageRepo();
  final _projectService = ProjectService();

  List<ProjectModel> _recentProjects = [];
  List<ProjectModel> _allProjects = [];
  Map<int, List<String>> _projectPreviews =
      {}; // projectId -> list of image paths
  bool _isLoading = true;
  final String _userName =
      "User"; // Default name, can be loaded from preferences later

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Load recent projects (limit to 10 for horizontal scroll)
      final recent = await _projectRepo.getRecentProjects(10);

      // Load all projects
      final all = await _projectRepo.getAllProjects();

      // Load preview images for each project
      final Map<int, List<String>> previews = {};
      for (final project in all) {
        if (project.id != null) {
          final images = await _imageRepo.getImages(project.id!);
          previews[project.id!] =
              images.take(4).map((img) => img.filePath).toList();
        }
      }

      if (mounted) {
        setState(() {
          _recentProjects = recent;
          _allProjects = all;
          _projectPreviews = previews;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading home data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createProjectDialog() async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();

    if (!mounted) return;

    await showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text(
              "Create New Project",
              style: TextStyle(
                fontFamily: 'GeneralSans',
                fontWeight: FontWeight.w600,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    hintText: "Project Name",
                    labelText: "Name",
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                  style: const TextStyle(fontFamily: 'GeneralSans'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    hintText: "Description (optional)",
                    labelText: "Description",
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  style: const TextStyle(fontFamily: 'GeneralSans'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  "Cancel",
                  style: TextStyle(fontFamily: 'GeneralSans'),
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (nameController.text.trim().isNotEmpty) {
                    try {
                      await _projectService.createProject(
                        nameController.text.trim(),
                        description:
                            descriptionController.text.trim().isEmpty
                                ? null
                                : descriptionController.text.trim(),
                      );
                      if (context.mounted) {
                        Navigator.pop(context);
                        _loadData();
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error creating project: $e')),
                        );
                      }
                    }
                  }
                },
                child: const Text(
                  "Create",
                  style: TextStyle(fontFamily: 'GeneralSans'),
                ),
              ),
            ],
          ),
    );
  }

  void _openProject(ProjectModel project) {
    // Update last accessed time
    if (project.id != null) {
      _projectService.openProject(project.id!);
    }

    // Navigate to project page (placeholder for now)
    // TODO: Create project detail page
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Opening ${project.title}...')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SafeArea(
                child: RefreshIndicator(
                  onRefresh: _loadData,
                  child: CustomScrollView(
                    slivers: [
                      // Header Section
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                          child: Row(
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Hi, $_userName",
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'GeneralSans',
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              // Image Analysis Button
                              IconButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const ImageAnalysisPage(),
                                    ),
                                  );
                                },
                                icon: Icon(
                                  Icons.analytics_outlined,
                                  color: theme.colorScheme.onSurface,
                                ),
                                tooltip: 'Image Analysis',
                              ),
                              const SizedBox(width: 8),
                              // Profile Picture Placeholder
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.person,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Recent Section
                      if (_recentProjects.isNotEmpty) ...[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                            child: Text(
                              "Recent",
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'GeneralSans',
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: 140,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              itemCount: _recentProjects.length,
                              itemBuilder: (context, index) {
                                final project = _recentProjects[index];
                                return _buildRecentCard(project, theme, isDark);
                              },
                            ),
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 24)),
                      ],

                      // Your Project Section
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                          child: Row(
                            children: [
                              Text(
                                "Your Project",
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'GeneralSans',
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Projects Grid
                      if (_allProjects.isEmpty)
                        SliverFillRemaining(
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.folder_outlined,
                                  size: 64,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.3),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  "No projects yet",
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.6),
                                    fontFamily: 'GeneralSans',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "Tap the + button to create your first project",
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.5),
                                    fontFamily: 'GeneralSans',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          sliver: SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 16,
                                  mainAxisSpacing: 16,
                                  childAspectRatio: 0.85,
                                ),
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final project = _allProjects[index];
                              return _buildProjectCard(project, theme, isDark);
                            }, childCount: _allProjects.length),
                          ),
                        ),

                      // Bottom padding
                      const SliverToBoxAdapter(child: SizedBox(height: 100)),
                    ],
                  ),
                ),
              ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createProjectDialog,
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildRecentCard(ProjectModel project, ThemeData theme, bool isDark) {
    final previewImages =
        project.id != null ? (_projectPreviews[project.id!] ?? []) : [];

    return GestureDetector(
      onTap: () => _openProject(project),
      child: Container(
        width: 200,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[800] : Colors.grey[100],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Preview Image
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                child:
                    previewImages.isEmpty
                        ? Container(
                          color: isDark ? Colors.grey[700] : Colors.grey[200],
                          child: Center(
                            child: Icon(
                              Icons.image_outlined,
                              size: 40,
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.3,
                              ),
                            ),
                          ),
                        )
                        : Image.file(
                          File(previewImages.first),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder:
                              (context, error, stackTrace) => Container(
                                color:
                                    isDark
                                        ? Colors.grey[700]
                                        : Colors.grey[200],
                                child: Icon(
                                  Icons.broken_image,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.3),
                                ),
                              ),
                        ),
              ),
            ),
            // Project Title
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                project.title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'GeneralSans',
                  color: theme.colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectCard(ProjectModel project, ThemeData theme, bool isDark) {
    final previewImages =
        project.id != null ? (_projectPreviews[project.id!] ?? []) : [];

    return GestureDetector(
      onTap: () => _openProject(project),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[800] : Colors.grey[100],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Preview Image(s)
            Expanded(
              flex: 3,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                child:
                    previewImages.isEmpty
                        ? Container(
                          color: isDark ? Colors.grey[700] : Colors.grey[200],
                          child: Center(
                            child: Icon(
                              Icons.folder_outlined,
                              size: 48,
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.3,
                              ),
                            ),
                          ),
                        )
                        : previewImages.length == 1
                        ? Image.file(
                          File(previewImages.first),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder:
                              (context, error, stackTrace) => Container(
                                color:
                                    isDark
                                        ? Colors.grey[700]
                                        : Colors.grey[200],
                                child: Icon(
                                  Icons.broken_image,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.3),
                                ),
                              ),
                        )
                        : GridView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 2,
                                crossAxisSpacing: 2,
                              ),
                          itemCount: previewImages.length.clamp(0, 4),
                          itemBuilder: (context, index) {
                            return Image.file(
                              File(previewImages[index]),
                              fit: BoxFit.cover,
                              errorBuilder:
                                  (context, error, stackTrace) => Container(
                                    color:
                                        isDark
                                            ? Colors.grey[700]
                                            : Colors.grey[200],
                                  ),
                            );
                          },
                        ),
              ),
            ),
            // Project Title
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                project.title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'GeneralSans',
                  color: theme.colorScheme.onSurface,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
