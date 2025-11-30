import 'dart:io';
import 'package:flutter/material.dart';
import 'package:adobe/data/models/project_model.dart';
import 'package:adobe/data/models/file_model.dart';
import 'package:adobe/data/repos/project_repo.dart';
import 'package:adobe/data/repos/image_repo.dart';
import 'package:adobe/data/repos/file_repo.dart';
import 'package:adobe/services/project_service.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'project_detail_page.dart';
import 'image_analysis_page.dart';
import 'define_brand_page.dart';

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

  List<ProjectModel> _allProjects = [];
  List<FileModel> _recentFiles = [];
  Map<int, ProjectModel> _projectMap = {};
  Map<int, List<String>> _projectPreviews = {};
  Map<String, String> _fileDimensions = {};
  bool _isLoading = true;
  final String _userName = "Alex"; // Can be loaded from preferences later

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Load all projects and create a map for quick lookup
      final allProjects = await _projectRepo.getAllProjects();
      final Map<int, ProjectModel> projectMap = {};
      for (final project in allProjects) {
        if (project.id != null) {
          projectMap[project.id!] = project;
          // Load preview images for each project
          final images = await _imageRepo.getImages(project.id!);
          _projectPreviews[project.id!] =
              images.take(4).map((img) => img.filePath).toList();
        }
      }

      // Load recent files
      final recentFiles = await _fileRepo.getRecentFiles(limit: 10);

      // Load dimensions for files
      final Map<String, String> fileDimensions = {};
      for (final file in recentFiles) {
        try {
          final dimensions = await _getImageDimensions(file.filePath);
          fileDimensions[file.id] = dimensions;
        } catch (e) {
          debugPrint('Error loading dimensions for ${file.id}: $e');
        }
      }

      if (mounted) {
        setState(() {
          _allProjects = allProjects;
          _recentFiles = recentFiles;
          _projectMap = projectMap;
          _fileDimensions = fileDimensions;
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
    
    // Check if project is an event (has parentId)
    if (project.isEvent) {
      final parentProject = _projectMap[project.parentId!];
      if (parentProject != null) {
        return '${parentProject.title} / ${project.title}';
      }
    }
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
    // Update last accessed time
    if (project.id != null) {
      _projectService.openProject(project.id!);

      // Navigate to project detail page
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProjectDetailPage(projectId: project.id!),
        ),
      ).then((_) => _loadData());
    }
  }

  void _openFile(FileModel file) {
    // Navigate to file detail or project detail
    final project = _projectMap[file.projectId];
    if (project != null) {
      _openProject(project);
    }
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
                              // Profile Picture
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
                          child: Container(
                            decoration: BoxDecoration(
                              color: isDark ? Colors.grey[800] : Colors.grey[200],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: TextField(
                              decoration: InputDecoration(
                                hintText: 'Search',
                                hintStyle: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                                  fontFamily: 'GeneralSans',
                                ),
                                prefixIcon: Icon(
                                  Icons.search,
                                  size: 18,
                                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                                ),
                                border: InputBorder.none,
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
                      ),

                      const SliverToBoxAdapter(child: SizedBox(height: 12)),

                      // Content Sections
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Recent Files Section
                              if (_recentFiles.isNotEmpty) ...[
                                _buildSectionHeader(
                                  'Recent Files',
                                  theme,
                                  onTap: () {
                                    // Navigate to recent files page
                                  },
                                ),
                                const SizedBox(height: 12),
                                ...(_recentFiles.take(2).map((file) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _buildRecentFileCard(file, theme, isDark),
                                )).toList()),
                                const SizedBox(height: 24),
                              ],

                              // Projects Section
                              _buildSectionHeader(
                                'Projects',
                                theme,
                                onTap: () {
                                  // Navigate to all projects
                                },
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 100,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _allProjects.length,
                                  itemBuilder: (context, index) {
                                    final project = _allProjects[index];
                                    return _buildProjectCard(project, theme, isDark);
                                  },
                                ),
                              ),
                              const SizedBox(height: 24),

                              // Explore Templates Section
                              _buildSectionHeader(
                                'Explore templates',
                                theme,
                                onTap: () {
                                  // Navigate to templates
                                },
                              ),
                              const SizedBox(height: 12),
                              _buildTemplatesSection(theme, isDark),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                      ),

                      // Bottom padding
                      const SliverToBoxAdapter(child: SizedBox(height: 100)),
                    ],
                  ),
                ),
              ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createNewProject,
        backgroundColor: isDark ? Colors.grey[900] : Colors.grey[900],
        foregroundColor: Colors.white,
        child: const Icon(Icons.add, size: 24),
      ),
    );
  }

  Widget _buildSectionHeader(String title, ThemeData theme, {VoidCallback? onTap}) {
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
          GestureDetector(
            onTap: onTap,
            child: Icon(
              Icons.chevron_right,
              size: 24,
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
      ],
    );
  }

  Widget _buildRecentFileCard(FileModel file, ThemeData theme, bool isDark) {
    final breadcrumb = _getProjectBreadcrumb(file);
    final dimensions = _fileDimensions[file.id] ?? 'Unknown';
    final timeAgo = _formatTimeAgo(file.lastUpdated);

    return GestureDetector(
      onTap: () => _openFile(file),
      child: Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            Container(
              width: 104,
              height: 106,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[800] : Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(file.filePath),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: isDark ? Colors.grey[800] : Colors.grey[200],
                    child: Icon(
                      Icons.broken_image,
                      size: 24,
                      color: theme.colorScheme.onSurface.withOpacity(0.3),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // File Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (breadcrumb.isNotEmpty)
                                Text(
                                  breadcrumb,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    fontFamily: 'Inter',
                                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              const SizedBox(height: 4),
                              Text(
                                file.name,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: 'GeneralSans',
                                  color: theme.colorScheme.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(
                          Icons.more_vert,
                          size: 16,
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      dimensions,
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: 'GeneralSans',
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      timeAgo,
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: 'GeneralSans',
                        color: theme.colorScheme.onSurface.withOpacity(0.4),
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

  Widget _buildProjectCard(ProjectModel project, ThemeData theme, bool isDark) {
    final previewImages =
        project.id != null ? (_projectPreviews[project.id!] ?? []) : [];

    return GestureDetector(
      onTap: () => _openProject(project),
      child: Container(
        width: 156,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(8),
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
                  top: Radius.circular(8),
                ),
                child:
                    previewImages.isEmpty
                        ? Container(
                          color: isDark ? Colors.grey[800] : Colors.grey[200],
                          child: Center(
                            child: Icon(
                              Icons.folder_outlined,
                              size: 32,
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
                                        ? Colors.grey[800]
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
            // Project Title and Actions
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      project.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'GeneralSans',
                        color: theme.colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.more_vert,
                    size: 16,
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplatesSection(ThemeData theme, bool isDark) {
    // Static templates for now - can be made dynamic later
    final templates = [
      {'title': 'Diwali Lights', 'subtitle': 'Instagram Post'},
      {'title': 'Business Opening', 'subtitle': 'Flyer'},
      {'title': 'Birthday Party', 'subtitle': 'Invitation'},
    ];

    return SizedBox(
      height: 160,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: templates.length,
        itemBuilder: (context, index) {
          final template = templates[index];
          return Container(
            width: 104,
            margin: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 104,
                  height: 106,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[800] : Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.image_outlined,
                      size: 32,
                      color: theme.colorScheme.onSurface.withOpacity(0.3),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  template['title']!,
                  style: TextStyle(
                    fontSize: 14,
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
                    fontSize: 12,
                    fontFamily: 'GeneralSans',
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}