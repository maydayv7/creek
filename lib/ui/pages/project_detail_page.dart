import 'dart:io';
import 'package:flutter/material.dart';
import '../../data/models/project_model.dart';
import '../../data/repos/project_repo.dart';
import '../../services/project_service.dart';
import 'project_board_page.dart';
import 'stylesheet_page.dart';

class ProjectDetailPage extends StatefulWidget {
  final int projectId;

  const ProjectDetailPage({super.key, required this.projectId});

  @override
  State<ProjectDetailPage> createState() => _ProjectDetailPageState();
}

class _ProjectDetailPageState extends State<ProjectDetailPage> {
  final _projectRepo = ProjectRepo();
  final _projectService = ProjectService();

  ProjectModel? _project;
  List<ProjectModel> _events = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final project = await _projectRepo.getProjectById(widget.projectId);

      // If project not found, handle exit
      if (project == null) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Project not found')));
        }
        return;
      }

      // Fetch sub-events
      final events = await _projectRepo.getEvents(widget.projectId);

      if (mounted) {
        setState(() {
          _project = project;
          _events = events;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading project data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _createEventDialog() async {
    if (_project?.id == null) return;

    final nameController = TextEditingController();
    final descriptionController = TextEditingController();

    if (!mounted) return;

    await showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text(
              "Create New Event",
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
                    hintText: "Event Name",
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
                child: const Text("Cancel"),
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
                        parentId: _project!.id,
                      );
                      if (context.mounted) {
                        Navigator.pop(context);
                        _loadData(); // Refresh to show new event
                      }
                    } catch (e) {
                      debugPrint("Error creating event: $e");
                    }
                  }
                },
                child: const Text("Create"),
              ),
            ],
          ),
    );
  }

  void _navigateToBoard(int projectId) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProjectBoardPage(projectId: projectId)),
    ).then((_) => _loadData());
  }

  void _navigateToStylesheet(int projectId) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StylesheetPage(projectId: projectId)),
    ).then((_) => _loadData());
  }

  void _showPlaceholder(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature coming soon!'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(title: const Text("Loading...")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_project == null) return const Scaffold(body: SizedBox());

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(_project!.title),
        backgroundColor: theme.appBarTheme.backgroundColor,
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Main Project Details & Actions
              _buildSectionHeader("Project Overview", theme),
              const SizedBox(height: 8),
              if (_project!.description != null &&
                  _project!.description!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _project!.description!,
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                      fontFamily: 'GeneralSans',
                    ),
                  ),
                ),

              // Actions for Main Project
              _buildActionRow(_project!.id!, theme, isDark),

              const SizedBox(height: 32),

              // 2. Events Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildSectionHeader("Events", theme),
                  IconButton(
                    onPressed: _createEventDialog,
                    icon: Icon(
                      Icons.add_circle,
                      color: theme.colorScheme.primary,
                    ),
                    tooltip: "Add Event",
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 3. Events List
              if (_events.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[850] : Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.event_note, size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 8),
                      Text(
                        "No events created yet",
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _events.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final event = _events[index];
                    return _buildEventCard(event, theme, isDark);
                  },
                ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // --- Widgets ---

  Widget _buildSectionHeader(String title, ThemeData theme) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        fontFamily: 'GeneralSans',
        color: theme.colorScheme.onSurface,
      ),
    );
  }

  Widget _buildEventCard(ProjectModel event, ThemeData theme, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  event.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'GeneralSans',
                  ),
                ),
              ),
            ],
          ),
          if (event.description != null && event.description!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              event.description!,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 16),
          // Actions for this specific Event
          _buildActionRow(event.id!, theme, isDark, isSmall: true),
        ],
      ),
    );
  }

  /// Reusable row of actions (Moodboard, Stylesheet, Files)
  Widget _buildActionRow(
    int targetId,
    ThemeData theme,
    bool isDark, {
    bool isSmall = false,
  }) {
    return Row(
      children: [
        Expanded(
          child: _buildActionButton(
            label: "Moodboard",
            icon: Icons.dashboard_outlined,
            color: Colors.purple, // Distinct color for main action
            theme: theme,
            isDark: isDark,
            isSmall: isSmall,
            onTap: () => _navigateToBoard(targetId),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildActionButton(
            label: "Stylesheet",
            icon: Icons.palette_outlined,
            color: Colors.blue,
            theme: theme,
            isDark: isDark,
            isSmall: isSmall,
            onTap: () => _navigateToStylesheet(targetId),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildActionButton(
            label: "Files",
            icon: Icons.folder_open_outlined,
            color: Colors.orange,
            theme: theme,
            isDark: isDark,
            isSmall: isSmall,
            onTap: () => _showPlaceholder("Files"),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required ThemeData theme,
    required bool isDark,
    required VoidCallback onTap,
    bool isSmall = false,
  }) {
    return Material(
      color: isDark ? Colors.grey[800] : Colors.grey[100],
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: isSmall ? 10 : 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: isSmall ? 20 : 24, color: color),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: isSmall ? 11 : 13,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface,
                  fontFamily: 'GeneralSans',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
