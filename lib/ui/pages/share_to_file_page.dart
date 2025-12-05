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
import 'package:creekui/ui/widgets/empty_state.dart';
import 'package:creekui/ui/widgets/section_header.dart';
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
      debugPrint('Error fetching files: $e');
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
              if (data['preview_path'] != null) {
                preview = data['preview_path'].toString();
                // If preview is relative, try to resolve relative to JSON file
                if (!File(preview).existsSync()) {
                  final parentDir = f.parent.path;
                  final candidate = File('$parentDir/$preview');
                  if (candidate.existsSync()) preview = candidate.path;
                }
              }
              if (data['width'] != null && data['height'] != null) {
                dims = '${data['width']} x ${data['height']} px';
              }
            }
            meta[fmodel.id] = {'preview': preview, 'dimensions': dims};
          } catch (_) {}
        } else {
          // Regular image file - assign path and try
          String dims = 'Unknown';
          try {
            final bytes = await f.readAsBytes();
            final image = img.decodeImage(bytes);
            if (image != null) dims = '${image.width} x ${image.height} px';
          } catch (_) {}
          meta[fmodel.id] = {'preview': fmodel.filePath, 'dimensions': dims};
        }
      } catch (_) {}
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
              return nameMatch || breadcrumb.contains(q);
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
      } catch (_) {}
    }
    final project = _projectCache[file.projectId];
    if (project == null) return "Unknown";
    if (project.parentId == null) return project.title;

    if (!_projectCache.containsKey(project.parentId!)) {
      try {
        final parent = await _projectService.getProjectById(project.parentId!);
        if (parent != null) _projectCache[project.parentId!] = parent;
      } catch (_) {}
    }
    final parent = _projectCache[project.parentId];
    return parent == null
        ? project.title
        : "${parent.title} / ${project.title}";
  }

  void _onFileSelected(FileModel file) async {
    try {
      final f = File(file.filePath);
      if (!await f.exists()) return;

      double width = 1080, height = 1080;
      if (file.filePath.toLowerCase().endsWith('.json')) {
        final content = await f.readAsString();
        final data = jsonDecode(content);
        if (data is Map && data['width'] != null) {
          width = (data['width'] as num).toDouble();
          height = (data['height'] as num).toDouble();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Variables.background,
      appBar: AppBar(
        backgroundColor: Variables.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Files',
          style: Variables.headerStyle.copyWith(fontSize: 20),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.black, size: 28),
            onPressed:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CreateFilePage(file: widget.sharedImage),
                  ),
                ),
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _allFiles.isEmpty
              ? const EmptyState(
                icon: Icons.folder_open,
                title: "No files yet",
                subtitle: "Tap + to create your first file",
              )
              : Column(
                children: [
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
                          if (_recentFiles.isNotEmpty &&
                              _searchQuery.isEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: SectionHeader(title: "Recent Files"),
                            ),
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
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: SectionHeader(
                              title:
                                  _searchQuery.isEmpty
                                      ? "All Files"
                                      : "Search Results",
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _filteredFiles.length,
                              itemBuilder:
                                  (context, index) =>
                                      _buildFileItem(_filteredFiles[index]),
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

  Widget _buildFileCard(FileModel file) {
    return FutureBuilder<String>(
      future: _getProjectEventLabel(file),
      builder: (context, snapshot) {
        final meta = _fileMetadata[file.id] ?? {};
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: FileCard(
            file: file,
            breadcrumb: snapshot.data ?? "",
            dimensions: meta['dimensions'] ?? "Unknown",
            previewPath: meta['preview'] ?? "",
            timeAgo: _formatDate(file.lastUpdated),
            onTap: () => _onFileSelected(file),
            onMenuAction: null,
          ),
        );
      },
    );
  }

  Widget _buildFileItem(FileModel file) => _buildFileCard(file);
}
