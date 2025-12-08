import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:creekui/services/file_service.dart';
import 'package:creekui/services/project_service.dart';
import 'package:creekui/data/models/file_model.dart';
import 'package:creekui/data/models/project_model.dart';
import 'package:creekui/ui/styles/variables.dart';
import 'package:creekui/ui/widgets/search_bar.dart';
import 'package:creekui/ui/widgets/file_card.dart';
import 'package:creekui/ui/widgets/section_header.dart';
import 'package:creekui/ui/widgets/empty_state.dart';
import 'package:creekui/ui/widgets/app_bar.dart';
import 'create_file_page.dart';
import 'canvas_page.dart';

class ShareToFilePage extends StatefulWidget {
  final File sharedImage;
  const ShareToFilePage({super.key, required this.sharedImage});

  @override
  State<ShareToFilePage> createState() => _ShareToFilePageState();
}

class _ShareToFilePageState extends State<ShareToFilePage> {
  final FileService _fileService = FileService();
  final ProjectService _projectService = ProjectService();
  final TextEditingController _searchController = TextEditingController();

  List<FileModel> _allFiles = [];
  List<FileModel> _filteredFiles = [];
  List<FileModel> _recentFiles = [];

  // file.id -> { 'preview': path, 'dimensions': str }
  Map<String, Map<String, String>> _fileMetadata = {};

  // Avoid repeated fetches
  final Map<int, ProjectModel> _projectCache = {};

  bool _isLoading = true;
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _fetchFiles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchFiles() async {
    setState(() => _isLoading = true);
    try {
      final List<FileModel> files = await _fileService.getAllFiles();
      final List<FileModel> recent = await _fileService.getRecentFiles(
        limit: 10,
      );

      // Sort by lastUpdated descending
      files.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
      recent.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));

      _allFiles = files;
      _filteredFiles = List.from(files);
      _recentFiles = recent.take(3).toList();

      await _loadFileMetadata(files);
      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error fetching files in ShareToFilePage: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadFileMetadata(List<FileModel> files) async {
    final Map<String, Map<String, String>> meta = {};
    for (final fmodel in files) {
      try {
        final f = File(fmodel.filePath);
        if (!await f.exists()) continue;

        if (fmodel.filePath.toLowerCase().endsWith('.json')) {
          // File JSON
          try {
            final content = await f.readAsString();
            final data = jsonDecode(content);
            String preview = '';
            String dims = 'Unknown';

            if (data is Map) {
              if (data['preview_path'] != null &&
                  data['preview_path'].toString().isNotEmpty) {
                preview = data['preview_path'].toString();
                // If preview is relative, try to resolve relative to JSON file
                if (!File(preview).existsSync()) {
                  final parentDir = f.parent.path;
                  final candidate = File('$parentDir/$preview');
                  if (candidate.existsSync()) preview = candidate.path;
                }
              }
              if (data['width'] != null && data['height'] != null) {
                final w = (data['width'] as num).toInt();
                final h = (data['height'] as num).toInt();
                dims = '$w x $h px';
              }
            }
            meta[fmodel.id] = {'preview': preview, 'dimensions': dims};
          } catch (e) {
            debugPrint('Error parsing canvas json for ${fmodel.id}: $e');
          }
        } else {
          // Regular image file - assign path and try
          String dims = 'Unknown';
          try {
            final bytes = await f.readAsBytes();
            final image = img.decodeImage(bytes);
            if (image != null) dims = '${image.width} x ${image.height} px';
          } catch (_) {
            // ignore
          }
          meta[fmodel.id] = {'preview': fmodel.filePath, 'dimensions': dims};
        }
      } catch (e) {
        debugPrint('Error while loading metadata for ${fmodel.id}: $e');
      }
    }
    _fileMetadata = meta;
  }

  void _filterFiles(String query) {
    setState(() {
      _searchQuery = query;
      if (query.trim().isEmpty) {
        _filteredFiles = List.from(_allFiles);
      } else {
        final q = query.toLowerCase();
        _filteredFiles =
            _allFiles.where((file) {
              final nameMatch = file.name.toLowerCase().contains(q);
              final breadcrumb = _getProjectBreadcrumbSync(file).toLowerCase();
              final projectMatch = breadcrumb.contains(q);
              return nameMatch || projectMatch;
            }).toList();
      }
    });
  }

  // Synchronous breadcrumb using cached project; returns empty if not cached
  String _getProjectBreadcrumbSync(FileModel file) {
    final proj = _projectCache[file.projectId];
    if (proj == null) return '';
    if (proj.parentId != null) {
      final parent = _projectCache[proj.parentId!];
      if (parent != null) return '${parent.title} / ${proj.title}';
    }
    return proj.title;
  }

  // Async breadcrumb loader that fetches projects into cache as needed
  Future<String> _getProjectEventLabel(FileModel file) async {
    if (!_projectCache.containsKey(file.projectId)) {
      try {
        final p = await _projectService.getProjectById(file.projectId);
        if (p != null) _projectCache[file.projectId] = p;
      } catch (e) {
        debugPrint('Project load failed for ${file.projectId}: $e');
      }
    }
    final project = _projectCache[file.projectId];
    if (project == null) return "Unknown";

    if (project.parentId == null) {
      return project.title;
    }

    final parentId = project.parentId!;
    if (!_projectCache.containsKey(parentId)) {
      try {
        final parent = await _projectService.getProjectById(parentId);
        if (parent != null) _projectCache[parentId] = parent;
      } catch (e) {
        debugPrint('Parent project load failed for $parentId: $e');
      }
    }

    final parentProject = _projectCache[parentId];
    if (parentProject == null) return project.title;
    return "${parentProject.title} / ${project.title}";
  }

  void _onAddPressed() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateFilePage(file: widget.sharedImage),
      ),
    );
  }

  void _onFileSelected(FileModel file) async {
    try {
      final f = File(file.filePath);
      if (!await f.exists()) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("File not found")));
        return;
      }

      double width = 1080;
      double height = 1080;

      if (file.filePath.toLowerCase().endsWith('.json')) {
        final content = await f.readAsString();
        final data = jsonDecode(content);

        if (data is Map) {
          if (data['width'] != null && data['height'] != null) {
            width = (data['width'] as num).toDouble();
            height = (data['height'] as num).toDouble();
          }
        }
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => CanvasPage(
                projectId: file.projectId,
                width: width,
                height: height,
                existingFile: file,
                injectedMedia: widget.sharedImage,
              ),
        ),
      );
    } catch (e) {
      debugPrint("Error opening file: $e");
    }
  }

  String _formatDate(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  // Fallback to original filePath if preview path empty/missing
  String _resolvePreviewPath(FileModel file) {
    final meta = _fileMetadata[file.id];
    if (meta == null) return file.filePath;
    final preview = meta['preview'] ?? '';
    if (preview.isNotEmpty && File(preview).existsSync()) return preview;

    if (file.filePath.toLowerCase().endsWith('.json')) {
      final f = File(file.filePath);
      final base = f.uri.pathSegments.last;
      final nameWithoutExt = base.split('.').first;
      final parent = f.parent;
      final candidates = [
        '${parent.path}/$nameWithoutExt.png',
        '${parent.path}/$nameWithoutExt.jpg',
        '${parent.path}/preview_$nameWithoutExt.png',
      ];
      for (final c in candidates) {
        if (File(c).existsSync()) return c;
      }
    }
    if (File(file.filePath).existsSync()) return file.filePath;
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Variables.surfaceBackground,
      appBar: CustomAppBar(
        title: 'Files',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Variables.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Variables.textPrimary, size: 28),
            onPressed: _onAddPressed,
            tooltip: "Create New File",
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(
                child: CircularProgressIndicator(color: Variables.textPrimary),
              )
              : _allFiles.isEmpty
              ? _buildEmptyState()
              : Column(
                children: [
                  // Search bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: CommonSearchBar(
                      controller: _searchController,
                      onChanged: _filterFiles,
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_filteredFiles.isEmpty && _searchQuery.isNotEmpty)
                            const Padding(
                              padding: EdgeInsets.all(32.0),
                              child: EmptyState(
                                icon: Icons.search_off,
                                title: "No results found",
                                subtitle: "Try adjusting your search",
                              ),
                            ),

                          // Recent Files
                          if (_recentFiles.isNotEmpty &&
                              _searchQuery.isEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: SectionHeader(title: "Recent Files"),
                            ),
                            const SizedBox(height: 12),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Column(
                                children:
                                    _recentFiles
                                        .map((file) => _buildFileCard(file))
                                        .toList(),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],

                          // All files header
                          if (_filteredFiles.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: SectionHeader(
                                title:
                                    _searchQuery.isEmpty
                                        ? "All Files"
                                        : "Search Results",
                              ),
                            ),
                            const SizedBox(height: 12),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _filteredFiles.length,
                                itemBuilder:
                                    (context, index) =>
                                        _buildFileCard(_filteredFiles[index]),
                              ),
                            ),
                          ],
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.folder_open, size: 80, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            "No files yet",
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _onAddPressed,
            child: const Text("Create your first file"),
          ),
        ],
      ),
    );
  }

  Widget _buildFileCard(FileModel file) {
    final preview = _resolvePreviewPath(file);
    final meta = _fileMetadata[file.id] ?? {};
    final dimensions = meta['dimensions'] ?? 'Unknown';

    return FutureBuilder<String>(
      future: _getProjectEventLabel(file),
      builder: (context, snapshot) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: FileCard(
            file: file,
            breadcrumb: snapshot.data ?? "",
            dimensions: dimensions,
            previewPath: preview,
            timeAgo: _formatDate(file.lastUpdated),
            onTap: () => _onFileSelected(file),
            onMenuAction: null,
          ),
        );
      },
    );
  }
}
