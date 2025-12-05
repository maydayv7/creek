import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:creekui/data/models/project_model.dart';
import 'package:creekui/data/models/file_model.dart';
import 'package:creekui/data/repos/project_repo.dart';
import 'package:creekui/data/repos/image_repo.dart';
import 'package:creekui/data/repos/file_repo.dart';
import 'package:creekui/services/project_service.dart';
import 'package:creekui/ui/styles/variables.dart';
import 'package:creekui/ui/widgets/search_bar.dart';
import 'package:creekui/ui/widgets/file_card.dart';
import 'package:creekui/ui/widgets/project_card.dart';
import 'package:creekui/ui/widgets/empty_state.dart';
import 'package:creekui/ui/widgets/section_header.dart';
import 'project_detail_page.dart';
import 'define_brand_page.dart';
import 'canvas_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _projectRepo = ProjectRepo();
  final _imageRepo = ImageRepo();
  final _fileRepo = FileRepo();
  final _projectService = ProjectService();

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  List<ProjectModel> _allProjects = [];
  List<FileModel> _recentFiles = [];
  Map<int, ProjectModel> _projectMap = {};
  final Map<int, List<String>> _projectPreviews = {};
  Map<String, Map<String, String>> _fileMetadata = {};
  bool _isLoading = true;
  final String _userName = "Alex"; // TODO

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
    try {
      final allProjects = await _projectRepo.getAllProjects();
      final Map<int, ProjectModel> projectMap = {};
      for (final project in allProjects) {
        if (project.id != null) {
          projectMap[project.id!] = project;
          final images = await _imageRepo.getImages(project.id!);
          _projectPreviews[project.id!] =
              images.take(1).map((img) => img.filePath).toList();
        }
      }

      final recentFiles = await _fileRepo.getRecentFiles(limit: 10);
      final Map<String, Map<String, String>> fileMetadata = {};

      for (final file in recentFiles) {
        try {
          final f = File(file.filePath);
          if (await f.exists()) {
            if (file.filePath.toLowerCase().endsWith('.json')) {
              try {
                final content = await f.readAsString();
                final data = jsonDecode(content);
                String dims = 'Unknown';
                String? previewPath;

                if (data is Map) {
                  if (data['width'] != null && data['height'] != null) {
                    dims =
                        '${(data['width'] as num).toInt()} x ${(data['height'] as num).toInt()} px';
                  }
                  if (data['preview_path'] != null) {
                    previewPath = data['preview_path'];
                  }
                }

                fileMetadata[file.id] = {
                  'dimensions': dims,
                  'preview': previewPath ?? '',
                };
              } catch (e) {
                debugPrint('Error parsing JSON for ${file.id}: $e');
              }
            } else {
              final dimensions = await _getImageDimensions(file.filePath);
              fileMetadata[file.id] = {
                'dimensions': dimensions,
                'preview': file.filePath,
              };
            }
          }
        } catch (e) {
          debugPrint('Error loading metadata for ${file.id}: $e');
        }
      }

      if (mounted) {
        setState(() {
          _allProjects = allProjects;
          _recentFiles = recentFiles;
          _projectMap = projectMap;
          _fileMetadata = fileMetadata;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading home data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<String> _getImageDimensions(String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final image = img.decodeImage(bytes);
      if (image != null) {
        return '${image.width} x ${image.height} px';
      }
    } catch (e) {
      debugPrint('Error getting dimensions: $e');
    }
    return 'Unknown';
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return 'Edited ${difference.inDays} ${difference.inDays == 1 ? 'day' : 'days'} ago';
    } else if (difference.inHours > 0) {
      return 'Edited ${difference.inHours} ${difference.inHours == 1 ? 'hour' : 'hours'} ago';
    } else if (difference.inMinutes > 0) {
      return 'Edited ${difference.inMinutes} ${difference.inMinutes == 1 ? 'minute' : 'minutes'} ago';
    } else {
      return 'Edited just now';
    }
  }

  String _getProjectBreadcrumb(FileModel file) {
    final project = _projectMap[file.projectId];
    if (project == null) return '';

    // If the project has a parent, it's an event. Show Parent / Event
    if (project.parentId != null) {
      final parentProject = _projectMap[project.parentId!];
      if (parentProject != null) {
        return '${parentProject.title} / ${project.title}';
      }
    }
    // Otherwise just the project name
    return project.title;
  }

  Future<void> _createNewProject() async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => const DefineBrandPage(
              projectName: "",
              projectDescription: null,
            ),
      ),
    ).then((result) {
      _loadData();
    });
  }

  void _openProject(ProjectModel project) {
    if (project.id != null) {
      _projectService.openProject(project.id!);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProjectDetailPage(projectId: project.id!),
        ),
      ).then((_) => _loadData());
    }
  }

  // Rename Project Logic
  Future<void> _renameProject(ProjectModel project) async {
    final controller = TextEditingController(text: project.title);
    final theme = Theme.of(context);

    final didRename = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: theme.cardColor,
            title: Text(
              'Rename Project',
              style: Variables.headerStyle.copyWith(fontSize: 18),
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              style: Variables.bodyStyle,
              decoration: InputDecoration(
                hintText: 'Enter new name',
                hintStyle: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(
                    color: theme.colorScheme.primary.withValues(alpha: 0.5),
                  ),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: theme.colorScheme.primary),
                ),
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            actions: [
              TextButton(
                child: Text(
                  'Cancel',
                  style: Variables.bodyStyle.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx, false),
              ),
              TextButton(
                child: Text(
                  'Save',
                  style: Variables.bodyStyle.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                onPressed: () {
                  if (controller.text.trim().isNotEmpty) {
                    Navigator.pop(ctx, true);
                  }
                },
              ),
            ],
          ),
    );

    if (didRename == true && project.id != null) {
      setState(() => _isLoading = true);
      try {
        await _projectService.updateProjectDetails(
          project.id!,
          title: controller.text.trim(),
        );
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Project renamed')));
        }
        _loadData();
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error renaming: $e')));
        }
      }
    }
  }

  // Delete Project Logic
  Future<void> _deleteProject(ProjectModel project) async {
    final theme = Theme.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: theme.cardColor,
            title: Text(
              'Delete Project',
              style: Variables.headerStyle.copyWith(fontSize: 18),
            ),
            content: Text(
              'Are you sure you want to delete "${project.title}"? This cannot be undone.',
              style: Variables.bodyStyle.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
            actions: [
              TextButton(
                child: Text(
                  'Cancel',
                  style: Variables.bodyStyle.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx, false),
              ),
              TextButton(
                child: Text(
                  'Delete',
                  style: Variables.bodyStyle.copyWith(color: Colors.red),
                ),
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
    );

    if (confirm == true && project.id != null) {
      setState(() => _isLoading = true);
      try {
        await _projectService.deleteProject(project.id!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Project deleted successfully')),
          );
        }
        _loadData();
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error deleting project: $e')));
        }
      }
    }
  }

  Future<void> _openFile(FileModel file) async {
    double width = 1080;
    double height = 1920;

    try {
      final f = File(file.filePath);
      if (await f.exists()) {
        if (file.filePath.toLowerCase().endsWith('.json')) {
          final content = await f.readAsString();
          final data = jsonDecode(content);
          if (data is Map) {
            width = (data['width'] as num?)?.toDouble() ?? width;
            height = (data['height'] as num?)?.toDouble() ?? height;
          }
        } else {
          final bytes = await f.readAsBytes();
          final image = img.decodeImage(bytes);
          if (image != null) {
            width = image.width.toDouble();
            height = image.height.toDouble();
          }
        }
      }
    } catch (e) {
      debugPrint("Error detecting dimensions for open: $e");
    }

    if (mounted) {
      _projectService.openProject(file.projectId);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => CanvasPage(
                projectId: file.projectId,
                width: width,
                height: height,
                existingFile: file,
              ),
        ),
      ).then((_) => _loadData());
    }
  }

  void _navigateToSeeAll(String title, bool isProjects) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => _SeeAllPage(
              title: title,
              isProjects: isProjects,
              projectRepo: _projectRepo,
              fileRepo: _fileRepo,
              imageRepo: _imageRepo,
              onProjectTap: _openProject,
              onFileTap: _openFile,
              onProjectDelete: _deleteProject,
              onProjectRename: _renameProject,
            ),
      ),
    ).then((_) => _loadData());
  }

  void _showComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Coming Soon'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bool isSearching = _searchQuery.isNotEmpty;
    final List<FileModel> filteredFiles =
        isSearching
            ? _recentFiles
                .where(
                  (f) =>
                      f.name.toLowerCase().contains(
                        _searchQuery.toLowerCase(),
                      ) ||
                      _getProjectBreadcrumb(
                        f,
                      ).toLowerCase().contains(_searchQuery.toLowerCase()),
                )
                .toList()
            : _recentFiles;
    final List<ProjectModel> filteredProjects =
        isSearching
            ? _allProjects
                .where(
                  (p) => p.title.toLowerCase().contains(
                    _searchQuery.toLowerCase(),
                  ),
                )
                .toList()
            : _allProjects;

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
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                          child: Row(
                            children: [
                              Text(
                                "Hello, $_userName!",
                                style: Variables.headerStyle.copyWith(
                                  fontSize: 24,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: theme.scaffoldBackgroundColor,
                                    width: 1.25,
                                  ),
                                ),
                                child: Icon(
                                  Icons.person,
                                  size: 16,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Search Bar
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: CommonSearchBar(
                            controller: _searchController,
                            onChanged: (value) {
                              setState(() {
                                _searchQuery = value.trim();
                              });
                            },
                          ),
                        ),
                      ),

                      const SliverToBoxAdapter(child: SizedBox(height: 12)),

                      if (isSearching)
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverList(
                            delegate: SliverChildListDelegate([
                              if (filteredFiles.isEmpty &&
                                  filteredProjects.isEmpty)
                                const EmptyState(
                                  icon: Icons.search_off,
                                  title: "No results found",
                                  subtitle: "Try searching for something else",
                                ),

                              if (filteredProjects.isNotEmpty) ...[
                                Text(
                                  "Projects & Events",
                                  style: Variables.bodyStyle.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.7),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ...filteredProjects.map(
                                  (p) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: SizedBox(
                                      height: 180,
                                      child: ProjectCard(
                                        project: p,
                                        previewImages:
                                            _projectPreviews[p.id] ?? [],
                                        onTap: () => _openProject(p),
                                        onRename: () => _renameProject(p),
                                        onDelete: () => _deleteProject(p),
                                        isHorizontal: false,
                                        showGrid: false,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                              if (filteredFiles.isNotEmpty) ...[
                                Text(
                                  "Files",
                                  style: Variables.bodyStyle.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.7),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ...filteredFiles.map((f) {
                                  final meta = _fileMetadata[f.id] ?? {};
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: FileCard(
                                      file: f,
                                      breadcrumb: _getProjectBreadcrumb(f),
                                      dimensions:
                                          meta['dimensions'] ?? 'Unknown',
                                      previewPath: meta['preview'] ?? '',
                                      timeAgo: _formatTimeAgo(f.lastUpdated),
                                      onTap: () => _openFile(f),
                                      onMenuAction: null,
                                    ),
                                  );
                                }),
                              ],
                            ]),
                          ),
                        )
                      else
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_recentFiles.isNotEmpty) ...[
                                  SectionHeader(
                                    title: 'Recent Files',
                                    onTap:
                                        () => _navigateToSeeAll(
                                          'Recent Files',
                                          false,
                                        ),
                                  ),
                                  const SizedBox(height: 12),
                                  ...(_recentFiles.take(2).map((file) {
                                    final meta = _fileMetadata[file.id] ?? {};
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: FileCard(
                                        file: file,
                                        breadcrumb: _getProjectBreadcrumb(file),
                                        dimensions:
                                            meta['dimensions'] ?? 'Unknown',
                                        previewPath: meta['preview'] ?? '',
                                        timeAgo: _formatTimeAgo(
                                          file.lastUpdated,
                                        ),
                                        onTap: () => _openFile(file),
                                        onMenuAction: null,
                                      ),
                                    );
                                  }).toList()),
                                  const SizedBox(height: 12),
                                ],
                                SectionHeader(
                                  title: 'Projects',
                                  onTap:
                                      () => _navigateToSeeAll(
                                        'All Projects',
                                        true,
                                      ),
                                ),
                                const SizedBox(height: 12),

                                // Show "Create Project" if empty, else list
                                _allProjects.isEmpty
                                    ? _buildCreateProjectCard(theme, isDark)
                                    : SizedBox(
                                      height: 140,
                                      child: ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: _allProjects.length,
                                        itemBuilder: (context, index) {
                                          final project = _allProjects[index];
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              right: 12,
                                            ),
                                            child: ProjectCard(
                                              project: project,
                                              previewImages:
                                                  _projectPreviews[project
                                                      .id] ??
                                                  [],
                                              onTap:
                                                  () => _openProject(project),
                                              onRename:
                                                  () => _renameProject(project),
                                              onDelete:
                                                  () => _deleteProject(project),
                                              showGrid: false,
                                              isHorizontal: true,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                const SizedBox(height: 24),
                                SectionHeader(
                                  title: 'Explore templates',
                                  onTap: () {},
                                ),
                                const SizedBox(height: 12),
                                _buildTemplatesSection(theme, isDark),
                                const SizedBox(height: 24),
                              ],
                            ),
                          ),
                        ),
                      const SliverToBoxAdapter(child: SizedBox(height: 100)),
                    ],
                  ),
                ),
              ),
      floatingActionButton:
          _allProjects.isEmpty
              ? null
              : FloatingActionButton(
                onPressed: _createNewProject,
                backgroundColor: isDark ? Colors.grey[900] : Colors.grey[900],
                foregroundColor: Colors.white,
                child: const Icon(Icons.add, size: 24),
              ),
    );
  }

  Widget _buildCreateProjectCard(ThemeData theme, bool isDark) {
    return GestureDetector(
      onTap: _createNewProject,
      child: Container(
        height: 130,
        width: 130,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(Variables.radiusMedium),
          border: Border.all(
            color: isDark ? Variables.borderDark : Variables.borderSubtle,
            width: 1,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_circle_outline,
              size: 32,
              color: theme.colorScheme.primary.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 8),
            Text(
              "Create Project",
              style: Variables.bodyStyle.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplatesSection(ThemeData theme, bool isDark) {
    final templates = [
      {
        'title': 'Diwali Lights',
        'subtitle': 'Instagram Post',
        'image': 'assets/templates/diwali.png',
      },
      {
        'title': 'Business Opening',
        'subtitle': 'Flyer',
        'image': 'assets/templates/business.png',
      },
      {
        'title': 'Birthday Party',
        'subtitle': 'Invitation',
        'image': 'assets/templates/party.png',
      },
    ];

    return SizedBox(
      height: 140,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: templates.length,
        itemBuilder: (context, index) {
          final template = templates[index];
          return GestureDetector(
            onTap: _showComingSoon,
            child: Container(
              width: 100,
              margin: const EdgeInsets.only(right: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[800] : Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        template['image']!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: Icon(
                              Icons.image_outlined,
                              size: 32,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.3,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    template['title']!,
                    style: Variables.bodyStyle.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    template['subtitle']!,
                    style: Variables.captionStyle.copyWith(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SeeAllPage extends StatefulWidget {
  final String title;
  final bool isProjects;
  final ProjectRepo projectRepo;
  final FileRepo fileRepo;
  final ImageRepo imageRepo;
  final Function(ProjectModel) onProjectTap;
  final Function(FileModel) onFileTap;
  final Function(ProjectModel) onProjectRename;
  final Function(ProjectModel) onProjectDelete;

  const _SeeAllPage({
    required this.title,
    required this.isProjects,
    required this.projectRepo,
    required this.fileRepo,
    required this.imageRepo,
    required this.onProjectTap,
    required this.onFileTap,
    required this.onProjectRename,
    required this.onProjectDelete,
  });

  @override
  State<_SeeAllPage> createState() => _SeeAllPageState();
}

class _SeeAllPageState extends State<_SeeAllPage> {
  bool _isLoading = true;
  List<dynamic> _items = [];
  Map<int, ProjectModel> _projectMap = {};
  Map<int, List<String>> _projectPreviews = {};
  Map<String, Map<String, String>> _fileMetadata = {};

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      if (widget.isProjects) {
        final projects = await widget.projectRepo.getAllProjects();
        // Fetch Child Event Images for Grid Preview
        for (final p in projects) {
          if (p.id != null) {
            final events = await widget.projectRepo.getEvents(p.id!);
            List<String> eventImages = [];
            // Get 1 image from up to 4 distinct events
            for (final event in events.take(4)) {
              if (event.id != null) {
                final imgs = await widget.imageRepo.getImages(event.id!);
                if (imgs.isNotEmpty) {
                  eventImages.add(imgs.first.filePath);
                }
              }
            }
            _projectPreviews[p.id!] = eventImages;
          }
        }
        _items = projects;
      } else {
        final files = await widget.fileRepo.getRecentFiles(limit: 50);
        final allProjects = await widget.projectRepo.getAllProjects();
        _projectMap = {for (var p in allProjects) p.id!: p};

        for (final file in files) {
          try {
            final f = File(file.filePath);
            if (await f.exists()) {
              if (file.filePath.toLowerCase().endsWith('.json')) {
                try {
                  final content = await f.readAsString();
                  final data = jsonDecode(content);
                  String dims = 'Unknown';
                  String? previewPath;
                  if (data is Map) {
                    if (data['width'] != null && data['height'] != null) {
                      dims =
                          '${(data['width'] as num).toInt()} x ${(data['height'] as num).toInt()} px';
                    }
                    if (data['preview_path'] != null) {
                      previewPath = data['preview_path'];
                    }
                  }
                  _fileMetadata[file.id] = {
                    'dimensions': dims,
                    'preview': previewPath ?? '',
                  };
                } catch (_) {}
              } else {
                final bytes = await f.readAsBytes();
                final image = img.decodeImage(bytes);
                if (image != null) {
                  _fileMetadata[file.id] = {
                    'dimensions': '${image.width} x ${image.height} px',
                    'preview': file.filePath,
                  };
                }
              }
            }
          } catch (_) {}
        }
        _items = files;
      }
    } catch (e) {
      debugPrint("Error loading see all data: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getBreadcrumb(FileModel file) {
    final project = _projectMap[file.projectId];
    if (project == null) return '';
    if (project.parentId != null) {
      final parent = _projectMap[project.parentId!];
      if (parent != null) return '${parent.title} / ${project.title}';
    }
    return project.title;
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 0) return 'Edited ${diff.inDays} days ago';
    return 'Edited recently';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title,
          style: Variables.headerStyle.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            color: theme.colorScheme.onSurface,
          ),
        ),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.colorScheme.onSurface),
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                padding: const EdgeInsets.all(16.0),
                child:
                    widget.isProjects
                        ? GridView.builder(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                childAspectRatio: 0.8,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                          itemCount: _items.length,
                          itemBuilder: (context, index) {
                            final project = _items[index] as ProjectModel;
                            return ProjectCard(
                              project: project,
                              previewImages: _projectPreviews[project.id] ?? [],
                              onTap: () => widget.onProjectTap(project),
                              // Chain callbacks, reload data on completion
                              onRename: () async {
                                await widget.onProjectRename(project);
                                _fetchData();
                              },
                              onDelete: () async {
                                await widget.onProjectDelete(project);
                                _fetchData();
                              },
                              isHorizontal: false,
                              showGrid: true,
                            );
                          },
                        )
                        : ListView.builder(
                          itemCount: _items.length,
                          itemBuilder: (context, index) {
                            final file = _items[index] as FileModel;
                            final meta = _fileMetadata[file.id] ?? {};
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: FileCard(
                                file: file,
                                breadcrumb: _getBreadcrumb(file),
                                dimensions: meta['dimensions'] ?? 'Unknown',
                                previewPath: meta['preview'] ?? '',
                                timeAgo: _timeAgo(file.lastUpdated),
                                onTap: () => widget.onFileTap(file),
                                onMenuAction: null,
                              ),
                            );
                          },
                        ),
              ),
    );
  }
}
