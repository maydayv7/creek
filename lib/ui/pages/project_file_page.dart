import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:creekui/data/models/file_model.dart';
import 'package:creekui/data/models/project_model.dart';
import 'package:creekui/services/file_service.dart';
import 'package:creekui/data/repos/project_repo.dart';
import 'package:creekui/ui/widgets/top_bar.dart';
import 'package:creekui/ui/widgets/bottom_bar.dart';
import 'package:creekui/ui/styles/variables.dart';
import 'package:creekui/ui/widgets/search_bar.dart';
import 'package:creekui/ui/widgets/file_card.dart';
import 'package:creekui/ui/widgets/empty_state.dart';
import 'create_file_page.dart';
import 'canvas_page.dart';

class ProjectFilePage extends StatefulWidget {
  final int projectId;

  const ProjectFilePage({super.key, required this.projectId});

  @override
  State<ProjectFilePage> createState() => _ProjectFilePageState();
}

class _ProjectFilePageState extends State<ProjectFilePage> {
  final _fileService = FileService();
  final _projectRepo = ProjectRepo();
  final TextEditingController _searchController = TextEditingController();

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
  // LOAD METADATA
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
            (_) => CanvasPage(
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
          title: Text(
            "Rename File",
            style: Variables.headerStyle.copyWith(fontSize: 18),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: Variables.bodyStyle,
            decoration: const InputDecoration(
              labelText: "New file name",
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              child: Text("Cancel", style: Variables.bodyStyle),
              onPressed: () => Navigator.pop(context),
            ),
            FilledButton(
              child: Text("Save", style: Variables.buttonTextStyle),
              onPressed: () => Navigator.pop(context, controller.text.trim()),
            ),
          ],
        );
      },
    );

    if (newName == null || newName.isEmpty) return;
    await _fileService.renameFile(file.id, newName);
    await _loadEverything();
  }

  Future<void> _deleteFile(FileModel file) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: Text(
              "Delete File?",
              style: Variables.headerStyle.copyWith(fontSize: 18),
            ),
            content: Text(
              "This will permanently remove ${file.name}.",
              style: Variables.bodyStyle,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text("Cancel", style: Variables.bodyStyle),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text("Delete", style: Variables.buttonTextStyle),
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

  String _formatRelative(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays > 0) {
      return "${diff.inDays} day${diff.inDays > 1 ? 's' : ''} ago";
    }
    if (diff.inHours > 0) {
      return "${diff.inHours} hour${diff.inHours > 1 ? 's' : ''} ago";
    }
    if (diff.inMinutes > 0) {
      return "${diff.inMinutes} min ago";
    }
    return "just now";
  }

  Widget _buildFileCard(FileModel file) {
    final meta = _fileMetadata[file.id] ?? {};
    final preview = meta["preview"] ?? "";
    final dimensions = meta["dimensions"] ?? "Unknown";

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FileCard(
        file: file,
        breadcrumb: _breadcrumbFor(file),
        dimensions: dimensions,
        previewPath: preview,
        timeAgo: "Last edited • ${_formatRelative(file.lastUpdated)}",
        onTap: () => _openFile(file),
        onMenuAction: (value) => _handleFileMenuAction(file, value),
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
      appBar: TopBar(
        currentProjectId: widget.projectId,
        onBack: () => Navigator.pop(context),
        titleOverride: "Project Files",
        onProjectChanged: (project) {
          // When user switches project from dropdown, refresh page with new ID
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ProjectFilePage(projectId: project.id!),
            ),
          );
        },
        hideSecondRow: true,
        onSettingsPressed: () {},
        onLayoutToggle: () {},
        isAlternateView: false,
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

                      // Search Bar
                      CommonSearchBar(
                        controller: _searchController,
                        hintText: "Search your files",
                        onChanged: (v) => setState(() => _search = v.trim()),
                      ),

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
                        EmptyState(
                          icon: Icons.folder_outlined,
                          title:
                              _search.isEmpty
                                  ? "No files yet"
                                  : "No files found",
                          subtitle:
                              _search.isEmpty
                                  ? "Create your first file to get started"
                                  : "Try a different search term",
                        )
                      else
                        Column(
                          children:
                              _filteredAllFiles()
                                  .map((f) => _buildFileCard(f))
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
                        const EmptyState(
                          icon: Icons.event_outlined,
                          title: "No events yet",
                          subtitle: "Create an event to organize your files",
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // -----------------------
                            // DROPDOWN
                            // -----------------------
                            _buildEventDropdown(),

                            const SizedBox(height: 16),

                            _eventFiles.isEmpty
                                ? const EmptyState(
                                  icon: Icons.insert_drive_file_outlined,
                                  title: "No files in this event yet",
                                  subtitle:
                                      "Create a file to add it to this event",
                                )
                                : Column(
                                  children:
                                      _eventFiles
                                          .map((f) => _buildFileCard(f))
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
  // DROPDOWN
  // ---------------------------------------
  Widget _buildEventDropdown() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFE4E4E7),
        borderRadius: BorderRadius.circular(Variables.radiusSmall),
      ),
      child: DropdownButton<ProjectModel>(
        value: _selectedEvent,
        isExpanded: false,
        underline: const SizedBox(),
        icon: const Icon(
          Icons.keyboard_arrow_down_rounded,
          size: 18,
          color: Color(0xFF27272A),
        ),
        style: const TextStyle(
          fontFamily: "GeneralSans",
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Color(0xFF27272A),
        ),
        dropdownColor: Colors.white,
        borderRadius: BorderRadius.circular(8),
        items:
            _events
                .map(
                  (e) => DropdownMenuItem(
                    value: e,
                    child: Text(
                      e.title,
                      style: const TextStyle(
                        fontFamily: "GeneralSans",
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF27272A),
                      ),
                    ),
                  ),
                )
                .toList(),
        onChanged: (value) {
          if (value != null) _onSelectEvent(value);
        },
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
