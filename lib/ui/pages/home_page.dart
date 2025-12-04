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
  final String _userName = "Alex";

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
          builder: (_) => CanvasPage(
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
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: 'GeneralSans',
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
                          child: TextField(
                            controller: _searchController,
                            onChanged: (value) {
                              setState(() {
                                _searchQuery = value.trim();
                              });
                            },
                            decoration: InputDecoration(
                              hintText: 'Search',
                              hintStyle: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.5,
                                ),
                                fontFamily: 'GeneralSans',
                              ),
                              prefixIcon: Icon(
                                Icons.search,
                                size: 18,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                              prefixIconConstraints: const BoxConstraints(
                                minWidth: 50,
                                minHeight: 18,
                              ),
                              filled: true,
                              fillColor:
                                  isDark ? Colors.grey[800] : Colors.grey[200],
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'GeneralSans',
                              color: theme.colorScheme.onSurface,
                            ),
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
                                Padding(
                                  padding: const EdgeInsets.only(top: 40),
                                  child: Center(
                                    child: Text(
                                      "No results found",
                                      style: TextStyle(
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: 0.5),
                                        fontFamily: 'GeneralSans',
                                      ),
                                    ),
                                  ),
                                ),
                              if (filteredProjects.isNotEmpty) ...[
                                Text(
                                  "Projects & Events",
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'GeneralSans',
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
                                      child: _ProjectCard(
                                        project: p,
                                        theme: theme,
                                        isDark: isDark,
                                        previewImages:
                                            _projectPreviews[p.id] ?? [],
                                        onTap: () => _openProject(p),
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
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'GeneralSans',
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.7),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ...filteredFiles.map(
                                  (f) {
                                    final meta = _fileMetadata[f.id] ?? {};
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: _FileCard(
                                        file: f,
                                        theme: theme,
                                        isDark: isDark,
                                        breadcrumb: _getProjectBreadcrumb(f),
                                        dimensions: meta['dimensions'] ?? 'Unknown',
                                        previewPath: meta['preview'] ?? '',
                                        timeAgo: _formatTimeAgo(f.lastUpdated),
                                        onTap: () => _openFile(f),
                                      ),
                                    );
                                  },
                                ),
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
                                  _buildSectionHeader(
                                    'Recent Files',
                                    theme,
                                    onTap:
                                        () => _navigateToSeeAll(
                                          'Recent Files',
                                          false,
                                        ),
                                  ),
                                  const SizedBox(height: 12),
                                  ...(_recentFiles
                                      .take(2)
                                      .map(
                                        (file) {
                                          final meta = _fileMetadata[file.id] ?? {};
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 12,
                                            ),
                                            child: _FileCard(
                                              file: file,
                                              theme: theme,
                                              isDark: isDark,
                                              breadcrumb: _getProjectBreadcrumb(
                                                file,
                                              ),
                                              dimensions: meta['dimensions'] ?? 'Unknown',
                                              previewPath: meta['preview'] ?? '',
                                              timeAgo: _formatTimeAgo(
                                                file.lastUpdated,
                                              ),
                                              onTap: () => _openFile(file),
                                            ),
                                          );
                                        },
                                      )
                                      .toList()),
                                  const SizedBox(height: 24),
                                ],
                                _buildSectionHeader(
                                  'Projects',
                                  theme,
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
                                        height: 140, // Reduced height
                                        child: ListView.builder(
                                          scrollDirection: Axis.horizontal,
                                          itemCount: _allProjects.length,
                                          itemBuilder: (context, index) {
                                            final project = _allProjects[index];
                                            return Padding(
                                              padding: const EdgeInsets.only(
                                                right: 12,
                                              ),
                                              child: _ProjectCard(
                                                project: project,
                                                theme: theme,
                                                isDark: isDark,
                                                previewImages:
                                                    _projectPreviews[project.id] ??
                                                    [],
                                                onTap: () => _openProject(project),
                                                showGrid: false,
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                const SizedBox(height: 24),
                                _buildSectionHeader(
                                  'Explore templates',
                                  theme,
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
      floatingActionButton: _allProjects.isEmpty
          ? null
          : FloatingActionButton(
              onPressed: _createNewProject,
              backgroundColor: isDark ? Colors.grey[900] : Colors.grey[900],
              foregroundColor: Colors.white,
              child: const Icon(Icons.add, size: 24),
            ),
    );
  }

  Widget _buildSectionHeader(
    String title,
    ThemeData theme, {
    VoidCallback? onTap,
  }) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            fontFamily: 'GeneralSans',
            color: theme.colorScheme.onSurface,
          ),
        ),
        const Spacer(),
        if (onTap != null)
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Icon(
                  Icons.chevron_right,
                  size: 24,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
      ],
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
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
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
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                fontFamily: 'GeneralSans',
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
      height: 140, // Reduced
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: templates.length,
        itemBuilder: (context, index) {
          final template = templates[index];
          return GestureDetector(
            onTap: _showComingSoon,
            child: Container(
              width: 100, // Reduced
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
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'GeneralSans',
                      color: theme.colorScheme.onSurface,
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    template['subtitle']!,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'GeneralSans',
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

// -----------------------------------------------------------------------------
// REUSABLE WIDGETS & PAGES
// -----------------------------------------------------------------------------

class _FileCard extends StatelessWidget {
  final FileModel file;
  final ThemeData theme;
  final bool isDark;
  final String breadcrumb;
  final String dimensions;
  final String previewPath;
  final String timeAgo;
  final VoidCallback onTap;

  const _FileCard({
    required this.file,
    required this.theme,
    required this.isDark,
    required this.breadcrumb,
    required this.dimensions,
    required this.previewPath,
    required this.timeAgo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center, 
          children: [
            SizedBox(
              width: 88,
              height: 88,
              child: Center(
                child: Container(
                  width: 80, 
                  height: 80,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[800] : Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: previewPath.isNotEmpty
                        ? Image.file(
                            File(previewPath),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                              color: isDark ? Colors.grey[800] : Colors.grey[200],
                              child: Icon(
                                Icons.broken_image,
                                size: 20,
                                color:
                                    theme.colorScheme.onSurface.withValues(
                                      alpha: 0.3,
                                    ),
                              ),
                            ),
                          )
                        : Container(
                            color: isDark ? Colors.grey[800] : Colors.grey[200],
                            child: Icon(
                              Icons.image,
                              size: 24,
                              color:
                                  theme.colorScheme.onSurface.withValues(
                                    alpha: 0.3,
                                  ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min, // Keep height minimal for centering
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Project Breadcrumb
                              if (breadcrumb.isNotEmpty)
                                Text(
                                  breadcrumb,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    fontFamily: 'Inter',
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              const SizedBox(height: 4),
                              // File Name
                              Text(
                                file.name,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'GeneralSans',
                                  color: theme.colorScheme.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.more_vert,
                          size: 20,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      dimensions,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'GeneralSans',
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      timeAgo,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'GeneralSans',
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.4,
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
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final ProjectModel project;
  final ThemeData theme;
  final bool isDark;
  final List<String> previewImages;
  final VoidCallback onTap;
  final bool isHorizontal;
  final bool showGrid;

  const _ProjectCard({
    required this.project,
    required this.theme,
    required this.isDark,
    required this.previewImages,
    required this.onTap,
    this.isHorizontal = true,
    this.showGrid = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: isHorizontal ? 130 : null,
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: showGrid
                    ? Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: _buildGridPreview(),
                    )
                    : (previewImages.isNotEmpty
                        ? Image.file(
                            File(previewImages.first),
                            fit: BoxFit.cover,
                            width: double.infinity,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                              color: isDark ? Colors.grey[800] : Colors.grey[200],
                              child: Icon(
                                Icons.broken_image,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                            ),
                          )
                        : Container(
                            color: isDark ? Colors.grey[800] : Colors.grey[200],
                            child: Center(
                              child: Icon(
                                Icons.folder_outlined,
                                size: 32,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                            ),
                          )),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      project.title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'GeneralSans',
                        color: theme.colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.more_vert,
                    size: 16,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Grid Preview Logic
  Widget _buildGridPreview() {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _buildPreviewItem(
                  previewImages.isNotEmpty ? previewImages[0] : null,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildPreviewItem(
                  previewImages.length > 1 ? previewImages[1] : null,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _buildPreviewItem(
                  previewImages.length > 2 ? previewImages[2] : null,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildPreviewItem(
                  previewImages.length > 3 ? previewImages[3] : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewItem(String? imagePath) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.grey[200],
        borderRadius: BorderRadius.circular(6), // Rounded grid items
      ),
      clipBehavior: Clip.antiAlias,
      child: imagePath != null
          ? Image.file(
              File(imagePath),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (context, error, stackTrace) =>
                  const Icon(Icons.broken_image, size: 16, color: Colors.grey),
            )
          : null, // Empty placeholder
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

  const _SeeAllPage({
    required this.title,
    required this.isProjects,
    required this.projectRepo,
    required this.fileRepo,
    required this.imageRepo,
    required this.onProjectTap,
    required this.onFileTap,
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
          style: TextStyle(
            fontFamily: 'GeneralSans',
            color: theme.colorScheme.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.colorScheme.onSurface),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: widget.isProjects
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
                        return _ProjectCard(
                          project: project,
                          theme: theme,
                          isDark: isDark,
                          previewImages: _projectPreviews[project.id] ?? [],
                          onTap: () => widget.onProjectTap(project),
                          isHorizontal: false,
                          showGrid: true, // Show Grid for Projects here
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
                          child: _FileCard(
                            file: file,
                            theme: theme,
                            isDark: isDark,
                            breadcrumb: _getBreadcrumb(file),
                            dimensions: meta['dimensions'] ?? 'Unknown',
                            previewPath: meta['preview'] ?? '',
                            timeAgo: _timeAgo(file.lastUpdated),
                            onTap: () => widget.onFileTap(file),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
