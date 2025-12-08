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
import 'package:creekui/ui/widgets/dialog.dart';
import 'package:creekui/ui/widgets/text_field.dart';
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

  // Load data
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

  // File Metadata
  Future<void> _loadMetadata(List<FileModel> list) async {
    for (final file in list) {
      final meta = await _fileService.getFileMetadata(file.filePath);
      _fileMetadata[file.id] = {
        "preview": meta.previewPath ?? "",
        "dimensions": meta.dimensions,
      };
    }
  }

  Future<void> _onSelectEvent(ProjectModel event) async {
    setState(() => _selectedEvent = event);
    _eventFiles = await _fileService.getFiles(event.id!);
    await _loadMetadata(_eventFiles);
    setState(() {});
  }

  void _openFile(FileModel file) async {
    // Default values
    double width = 1080;
    double height = 1920;
    final meta = await _fileService.getFileMetadata(file.filePath);
    if (meta.width > 0 && meta.height > 0) {
      width = meta.width;
      height = meta.height;
    }

    if (mounted) {
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
      );
    }
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

    await ShowDialog.show(
      context,
      title: "Rename File",
      primaryButtonText: "Save",
      content: CommonTextField(
        hintText: "New file name",
        controller: controller,
        autoFocus: true,
      ),
      onPrimaryPressed: () async {
        final newName = controller.text.trim();
        if (newName.isNotEmpty) {
          await _fileService.renameFile(file.id, newName);
          await _loadEverything();
          if (mounted) Navigator.pop(context);
        }
      },
    );
  }

  Future<void> _deleteFile(FileModel file) async {
    await ShowDialog.show(
      context,
      title: "Delete File?",
      description: "This will permanently remove ${file.name}.",
      primaryButtonText: "Delete",
      isDestructive: true,
      onPrimaryPressed: () async {
        try {
          await _fileService.deleteFile(file.id!);
          final disk = File(file.filePath);
          if (await disk.exists()) await disk.delete();

          setState(() {
            _allFiles.removeWhere((f) => f.id == file.id);
            _eventFiles.removeWhere((f) => f.id == file.id);
          });

          if (mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text("File deleted")));
          }
        } catch (e) {
          debugPrint("Delete error: $e");
        }
      },
    );
  }

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

  // Breadcrumb
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

  // UI Builder
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Variables.surfaceSubtle,
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
            color: Variables.textPrimary,
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
                        backgroundColor: Variables.background,
                      ),
                      const SizedBox(height: 24),
                      // All Files
                      Text(
                        "All Files",
                        style: Variables.bodyStyle.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
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
                      // Files for Events
                      Text(
                        "Files for Events",
                        style: Variables.bodyStyle.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
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

  // Dropdown
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

  // Filter
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
