import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../services/file_service.dart';
import '../../services/project_service.dart';
import '../../data/models/file_model.dart';
import '../../data/models/project_model.dart';
import 'create_file_page.dart';
import 'canvas_board_page.dart';

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

  // project cache to avoid repeated fetches
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
      // Using service-style API: fetch all files and recent files
      // If your FileService has different method names, adapt them here.
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

      // Load metadata for files (previews, dimensions)
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
        if (!await f.exists()) {
          // skip if disk file missing
          continue;
        }

        if (fmodel.filePath.toLowerCase().endsWith('.json')) {
          // Canvas JSON - attempt to parse preview_path, width/height
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
          // Regular image file - assign path and try to get dims
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
    // load file.projectId
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
              (context) => CanvasBoardPage(
                projectId: file.projectId,
                width: width,
                height: height,
                existingFile: file,
                injectedMedia: widget.sharedImage, // 🔥 THIS IS THE FIX
              ),
        ),
      );
    } catch (e) {
      debugPrint("Error opening file: $e");
    }
  }



  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  // Resolve preview path; if empty or missing, fallback to original filePath
  String _resolvePreviewPath(FileModel file) {
    final meta = _fileMetadata[file.id];
    if (meta == null) return file.filePath;
    final preview = meta['preview'] ?? '';
    if (preview.isNotEmpty && File(preview).existsSync()) return preview;
    // fallback: if file is json and has no preview, return placeholder or file.path
    if (file.filePath.toLowerCase().endsWith('.json')) {
      // attempt to find PNG/JPG sibling in same folder with same base name
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
    final theme = Theme.of(context);

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
          'Files',
          style: TextStyle(
            color: Color(0xFF27272A),
            fontFamily: 'GeneralSans',
            fontSize: 20,
            fontWeight: FontWeight.w500,
            height: 1.2,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.black, size: 28),
            onPressed: _onAddPressed,
            tooltip: "Create New File",
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _allFiles.isEmpty
              ? _buildEmptyState()
              : Column(
                children: [
                  // Search bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: SizedBox(
                      height: 42,
                      child: TextField(
                        controller: _searchController,
                        onChanged: _filterFiles,
                        style: const TextStyle(
                          fontFamily: "GeneralSans",
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF71717B),
                          height: 1.4,
                        ),
                        decoration: InputDecoration(
                          hintText: "Search",
                          hintStyle: const TextStyle(
                            fontFamily: "GeneralSans",
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                            color: Color(0xFF71717B),
                          ),
                          prefixIcon: const Icon(
                            Icons.search,
                            size: 20,
                            color: Color(0xFF9F9FA9),
                          ),
                          filled: true,
                          fillColor: const Color(0xFFE4E4E7),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 16,
                          ),
                          suffixIcon:
                              _searchQuery.isNotEmpty
                                  ? IconButton(
                                    icon: const Icon(
                                      Icons.clear,
                                      size: 20,
                                      color: Color(0xFF9F9FA9),
                                    ),
                                    padding: EdgeInsets.zero,
                                    onPressed: () {
                                      _searchController.clear();
                                      _filterFiles('');
                                    },
                                  )
                                  : null,
                        ),
                      ),
                    ),
                  ),

                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Recent Files (UI like screenshot)
                          if (_recentFiles.isNotEmpty &&
                              _searchQuery.isEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 8,
                              ),
                              child: Text(
                                "Recent Files",
                                style: TextStyle(
                                  fontFamily: 'GeneralSans',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  color: Color(0xFF27272A),
                                  height: 1.43,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              child: Column(
                                children:
                                    _recentFiles
                                        .map(
                                          (file) => _buildRecentFileItem(file),
                                        )
                                        .toList(),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],

                          // All files header
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 8,
                            ),
                            child: Text(
                              _searchQuery.isEmpty
                                  ? "All Files"
                                  : "Search Results",
                              style: const TextStyle(
                                fontFamily: 'GeneralSans',
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                                color: Color(0xFF27272A),
                                height: 1.43,
                              ),
                            ),
                          ),

                          // All files list
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            "No files yet",
            style: TextStyle(color: Colors.grey[500], fontSize: 16),
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

  Widget _buildRecentFileItem(FileModel file) {
    final previewPath = _resolvePreviewPath(file);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _onFileSelected(file),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 4, 0, 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE4E4E7), width: 1),
          ),
          child: Row(
            children: [
              // thumbnail
              SizedBox(
                width: 72,
                height: 72,
                child: Center(
                  child: Container(
                    width: 66,
                    height: 66,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 6,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child:
                          previewPath.isNotEmpty &&
                                  File(previewPath).existsSync()
                              ? Image.file(
                                File(previewPath),
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, s) => _placeholderIcon(),
                              )
                              : _placeholderIcon(),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FutureBuilder<String>(
                      future: _getProjectEventLabel(file),
                      builder: (context, snapshot) {
                        final label = snapshot.data ?? "";
                        return Text(
                          label,
                          style: const TextStyle(
                            fontFamily: 'GeneralSans',
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: Color(0xFF71717B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        );
                      },
                    ),
                    const SizedBox(height: 6),
                    Text(
                      file.name,
                      style: const TextStyle(
                        fontFamily: 'GeneralSans',
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF27272A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _formatDate(file.lastUpdated),
                      style: const TextStyle(
                        fontFamily: 'GeneralSans',
                        fontSize: 12,
                        color: Color(0xFF71717B),
                      ),
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

  Widget _buildFileItem(FileModel file) {
    final previewPath = _resolvePreviewPath(file);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _onFileSelected(file),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 4, 0, 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE4E4E7), width: 1),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: Center(
                  child: Container(
                    width: 66,
                    height: 66,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 6,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child:
                          previewPath.isNotEmpty &&
                                  File(previewPath).existsSync()
                              ? Image.file(
                                File(previewPath),
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, s) => _placeholderIcon(),
                              )
                              : _placeholderIcon(),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FutureBuilder<String>(
                      future: _getProjectEventLabel(file),
                      builder: (context, snapshot) {
                        final label = snapshot.data ?? "";
                        return Text(
                          label,
                          style: const TextStyle(
                            fontFamily: 'GeneralSans',
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: Color(0xFF71717B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                    Text(
                      file.name,
                      style: const TextStyle(
                        fontFamily: 'GeneralSans',
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF27272A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(file.lastUpdated),
                      style: const TextStyle(
                        fontFamily: 'GeneralSans',
                        fontSize: 12,
                        color: Color(0xFF71717B),
                      ),
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

  Widget _placeholderIcon() {
    return Container(
      color: Colors.grey[200],
      child: Icon(Icons.image, size: 28, color: Colors.grey[400]),
    );
  }
}
