import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models/file_model.dart';
import '../../data/models/project_model.dart';
import '../../services/file_service.dart';
import '../../data/repos/project_repo.dart';
import '../widgets/bottom_bar.dart';
import 'create_file_page.dart';
import 'canvas_board_page.dart';

import 'package:image/image.dart' as img;

class ProjectFilePage extends StatefulWidget {
  final int projectId;

  const ProjectFilePage({super.key, required this.projectId});

  @override
  State<ProjectFilePage> createState() => _ProjectFilePageState();
}

class _ProjectFilePageState extends State<ProjectFilePage> {
  final _fileService = FileService();
  final _projectRepo = ProjectRepo();

  List<FileModel> _allFiles = [];
  List<ProjectModel> _events = [];
  List<FileModel> _eventFiles = [];

  Map<String, Map<String, String>> _fileMetadata = {};

  ProjectModel? _selectedEvent;
  bool _isLoading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadEverything();
  }

  // ---------------------------------------
  // LOAD EVERYTHING
  // ---------------------------------------
  Future<void> _loadEverything() async {
    setState(() => _isLoading = true);
    try {
      _events = await _projectRepo.getEvents(widget.projectId);

      _allFiles = await _fileService.getFilesForProjectAndEvents(
        widget.projectId,
      );

      await _loadMetadata(_allFiles);

      if (_events.isNotEmpty) {
        _selectedEvent = _events.first;
        _eventFiles = await _fileService.getFiles(_selectedEvent!.id!);
        await _loadMetadata(_eventFiles);
      }
    } catch (e) {
      debugPrint("Error loading project page: $e");
    }

    if (mounted) setState(() => _isLoading = false);
  }

  // ---------------------------------------
  // LOAD METADATA (Like HomePage)
  // ---------------------------------------
  Future<void> _loadMetadata(List<FileModel> list) async {
    for (final file in list) {
      try {
        final f = File(file.filePath);
        if (!await f.exists()) continue;

        if (file.filePath.toLowerCase().endsWith(".json")) {
          final content = await f.readAsString();
          final data = jsonDecode(content);

          String dims = "Unknown";
          String preview = "";

          if (data is Map) {
            if (data["width"] != null && data["height"] != null) {
              dims = "${data["width"]} x ${data["height"]} px";
            }
            if (data["preview_path"] != null) {
              preview = data["preview_path"];
            }
          }

          // Fix relative preview path
          if (preview.isNotEmpty && !File(preview).existsSync()) {
            final base = f.parent.path;
            final candidate = "$base/$preview";
            if (File(candidate).existsSync()) preview = candidate;
          }

          _fileMetadata[file.id] = {"preview": preview, "dimensions": dims};
        } else {
          final bytes = await f.readAsBytes();
          final decoded = img.decodeImage(bytes);

          String dims = "Unknown";
          if (decoded != null) {
            dims = "${decoded.width} x ${decoded.height} px";
          }

          _fileMetadata[file.id] = {
            "preview": file.filePath,
            "dimensions": dims,
          };
        }
      } catch (_) {}
    }
  }

  // ---------------------------------------
  // SELECT EVENT
  // ---------------------------------------
  Future<void> _onSelectEvent(ProjectModel event) async {
    setState(() => _selectedEvent = event);
    _eventFiles = await _fileService.getFiles(event.id!);
    await _loadMetadata(_eventFiles);
    setState(() {});
  }

  // ---------------------------------------
  // OPEN FILE
  // ---------------------------------------
  void _openFile(FileModel file) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => CanvasBoardPage(
              projectId: file.projectId,
              width: 1080,
              height: 1920,
              existingFile: file,
            ),
      ),
    );
  }

  void _handleFileMenuAction(FileModel file, String action) {
    switch (action) {
      case "open":
        _openFile(file);
        break;

      case "rename":
        _renameFile(file);
        break;

      case "delete":
        _deleteFile(file);
        break;
    }
  }

  Future<void> _renameFile(FileModel file) async {
    final controller = TextEditingController(text: file.name);

    final newName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Rename File"),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: "New file name",
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              child: const Text("Cancel"),
              onPressed: () => Navigator.pop(context),
            ),
            FilledButton(
              child: const Text("Save"),
              onPressed: () => Navigator.pop(context, controller.text.trim()),
            ),
          ],
        );
      },
    );

    if (newName == null || newName.isEmpty) return;

    // ✔ Update DB
    await _fileService.renameFile(file.id, newName);

    // ✔ Reload UI
    await _loadEverything();
  }

  
  Future<void> _deleteFile(FileModel file) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text("Delete File?"),
            content: Text("This will permanently remove ${file.name}."),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancel"),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Delete"),
              ),
            ],
          ),
    );

    if (confirm != true) return;

    try {
      await _fileService.deleteFile(file.id!);

      final disk = File(file.filePath);
      if (await disk.exists()) await disk.delete();

      setState(() {
        _allFiles.removeWhere((f) => f.id == file.id);
        _eventFiles.removeWhere((f) => f.id == file.id);
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("File deleted")));
    } catch (e) {
      debugPrint("Delete error: $e");
    }
  }


  // ---------------------------------------
  // CREATE FILE
  // ---------------------------------------
  void _navigateToCreateFile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateFilePage(projectId: widget.projectId),
      ),
    ).then((_) => _loadEverything());
  }

  // ---------------------------------------
  // FILE CARD (Same UI but thumbnail updated)
  // ---------------------------------------
  Widget _fileCard(FileModel file) {
    final date = DateFormat.yMMMd().format(file.lastUpdated);
    final meta = _fileMetadata[file.id] ?? {};
    final preview = meta["preview"] ?? "";
    final realPreview =
        preview.isNotEmpty && File(preview).existsSync()
            ? preview
            : file.filePath;

    return GestureDetector(
      onTap: () => _openFile(file),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE4E4E7)),
        ),
        child: Row(
          children: [
            // ---------------------------------------
            // ✔ NEW THUMBNAIL SIZE (HomePage style)
            // ---------------------------------------
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey[300],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(realPreview),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.image),
                ),
              ),
            ),

            const SizedBox(width: 12),

            // ---------------------------------------
            // TEXT INFO (unchanged UI)
            // ---------------------------------------
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _breadcrumbFor(file),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                      fontFamily: 'GeneralSans',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: 2),

                  Text(
                    file.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'GeneralSans',
                    ),
                  ),

                  const SizedBox(height: 2),

                  Text(
                    "Edited $date",
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontFamily: 'GeneralSans',
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),
            PopupMenuButton<String>(
              onSelected: (value) => _handleFileMenuAction(file, value),
              itemBuilder:
                  (context) => [
                    const PopupMenuItem(value: "open", child: Text("Open")),
                    const PopupMenuItem(value: "rename", child: Text("Rename")),
                    const PopupMenuItem(value: "delete", child: Text("Delete")),
                  ],
              icon: const Icon(Icons.more_vert, size: 20),
            ),

          ],
        ),
      ),
    );
  }

  // ---------------------------------------
  // BREADCRUMB
  // ---------------------------------------
  String _breadcrumbFor(FileModel file) {
    final event = _events.firstWhere(
      (e) => e.id == file.projectId,
      orElse:
          () => ProjectModel(
            id: widget.projectId,
            title: "",
            lastAccessedAt: DateTime.now(),
            createdAt: DateTime.now(),
          ),
    );

    if (event.parentId == null) return "";

    final parent = _events.firstWhere(
      (e) => e.id == event.parentId,
      orElse:
          () => ProjectModel(
            id: widget.projectId,
            title: "",
            lastAccessedAt: DateTime.now(),
            createdAt: DateTime.now(),
          ),
    );

    return "${parent.title} / ${event.title}";
  }

  // ---------------------------------------
  // UI
  // ---------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F7F8),
        elevation: 0,
        title: const Text(
          "Project Files",
          style: TextStyle(
            fontFamily: 'GeneralSans',
            fontWeight: FontWeight.w500,
            color: Color(0xFF27272A),
          ),
        ),
      ),

      bottomNavigationBar: BottomBar(
        currentTab: BottomBarItem.files,
        projectId: widget.projectId,
      ),

      floatingActionButton: GestureDetector(
        onTap: _navigateToCreateFile,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF27272A),
            borderRadius: BorderRadius.circular(50),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text(
                "Create File",
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              SizedBox(width: 8),
              Icon(Icons.add, color: Colors.white),
            ],
          ),
        ),
      ),

      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                onRefresh: _loadEverything,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),

                      _buildSearchBar(),

                      const SizedBox(height: 24),

                      // -------------------------
                      // ALL FILES
                      // -------------------------
                      const Text(
                        "All Files",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'GeneralSans',
                          color: Color(0xFF27272A),
                        ),
                      ),

                      const SizedBox(height: 12),

                      if (_filteredAllFiles().isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              "No files found",
                              style: TextStyle(color: Colors.grey[500]),
                            ),
                          ),
                        )
                      else
                        Column(
                          children:
                              _filteredAllFiles()
                                  .map((f) => _fileCard(f))
                                  .toList(),
                        ),

                      const SizedBox(height: 32),

                      // -------------------------
                      // FILES FOR EVENTS
                      // -------------------------
                      const Text(
                        "Files for Events",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'GeneralSans',
                          color: Color(0xFF27272A),
                        ),
                      ),

                      const SizedBox(height: 12),

                      if (_events.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            "No events yet",
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // -----------------------
                            // DROPDOWN ONLY
                            // -----------------------
                            _buildEventDropdown(),

                            const SizedBox(height: 16),

                            _eventFiles.isEmpty
                                ? Text(
                                  "No files in this event yet",
                                  style: TextStyle(color: Colors.grey[500]),
                                )
                                : Column(
                                  children:
                                      _eventFiles
                                          .map((f) => _fileCard(f))
                                          .toList(),
                                ),
                          ],
                        ),

                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
    );
  }

  // ---------------------------------------
  // SEARCH
  // ---------------------------------------
  Widget _buildSearchBar() {
    return TextField(
      onChanged: (v) => setState(() => _search = v.trim()),
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.grey[200],
        hintText: "Search your files",
        prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  // ---------------------------------------
  // DROPDOWN (ONLY — add event removed)
  // ---------------------------------------
  Widget _buildEventDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButton<ProjectModel>(
        value: _selectedEvent,
        items:
            _events
                .map(
                  (e) => DropdownMenuItem(
                    value: e,
                    child: Text(
                      e.title,
                      style: const TextStyle(
                        fontFamily: 'GeneralSans',
                        fontSize: 14,
                      ),
                    ),
                  ),
                )
                .toList(),
        onChanged: (e) {
          if (e != null) _onSelectEvent(e);
        },
        underline: const SizedBox(),
        isExpanded: true,
      ),
    );
  }
  
  // ---------------------------------------
  // FILTER
  // ---------------------------------------
  List<FileModel> _filteredAllFiles() {
    if (_search.isEmpty) return _allFiles;
    return _allFiles
        .where(
          (f) =>
              f.name.toLowerCase().contains(_search.toLowerCase()) ||
              _breadcrumbFor(f).toLowerCase().contains(_search.toLowerCase()),
        )
        .toList();
  }
}
