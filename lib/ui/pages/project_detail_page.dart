import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../data/models/project_model.dart';
import '../../data/models/image_model.dart';
import '../../data/repos/project_repo.dart';
import '../../data/repos/image_repo.dart';
import '../../services/project_service.dart';
import 'project_board_page.dart';
import 'stylesheet_page.dart';
import 'project_file_page.dart';

class ProjectDetailPage extends StatefulWidget {
  final int projectId;

  const ProjectDetailPage({super.key, required this.projectId});

  @override
  State<ProjectDetailPage> createState() => _ProjectDetailPageState();
}

class _ProjectDetailPageState extends State<ProjectDetailPage> {
  final _projectRepo = ProjectRepo();
  final _projectService = ProjectService();
  final _imageRepo = ImageRepo();

  ProjectModel? _project;
  List<ProjectModel> _events = [];
  Map<int, List<ImageModel>> _eventImages = {}; // eventId -> recent images
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

      // Fetch recent images for each event (up to 3 most recent)
      final Map<int, List<ImageModel>> eventImagesMap = {};
      for (final event in events) {
        if (event.id != null) {
          final images = await _imageRepo.getImages(event.id!);
          // Get the 3 most recent images (already ordered by created_at DESC)
          eventImagesMap[event.id!] = images.take(3).toList();
        }
      }

      if (mounted) {
        setState(() {
          _project = project;
          _events = events;
          _eventImages = eventImagesMap;
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

  void _navigateToFiles(int projectId) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProjectFilePage(projectId: projectId)),
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
        backgroundColor: const Color(0xFFFAFAFA),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_project == null) return const Scaffold(body: SizedBox());

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: Text(
          _project!.title,
          style: const TextStyle(
            fontFamily: 'GeneralSans',
            fontSize: 20,
            fontWeight: FontWeight.w500,
            color: Color(0xFF27272A),
          ),
        ),
        backgroundColor: const Color(0xFFFAFAFA),
        elevation: 0,
        actions: [
          IconButton(
            icon: SvgPicture.asset(
              'assets/icons/settings-line.svg',
              width: 24,
              height: 24,
            ),
            onPressed: () {},
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(left: 16, right: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              
              // Action Cards Row
              _buildActionCardsRow(_project!.id!),

              const SizedBox(height: 16),

              // Events Header
              _buildEventsHeader(),

              const SizedBox(height: 16),

              // Events List
              if (_events.isEmpty)
                Center(
                  child: Container(
                    width: 328,
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.grey[300]!,
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
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _events.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final event = _events[index];
                    return Center(
                      child: _buildEventCard(event),
                    );
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

  Widget _buildActionCardsRow(int projectId) {
    return Row(
      children: [
        Expanded(
          child: _buildActionCard(
            blobImage: 'assets/moodboard_blob.png',
            iconPath: 'assets/icons/moodboard_icon.svg',
            label: 'Moodboard',
            onTap: () => _navigateToBoard(projectId),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildActionCard(
            blobImage: 'assets/stylesheet_blob.png',
            iconPath: 'assets/icons/stylesheet_icon.svg',
            label: 'Stylesheet',
            onTap: () => _navigateToStylesheet(projectId),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildActionCard(
            blobImage: 'assets/files_blob.png',
            iconPath: 'assets/icons/files_icon.svg',
            label: 'Files',
            onTap: () => _navigateToFiles(projectId),
          ),
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required String blobImage,
    required String iconPath,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFE4E4E7),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Blob image container with dark background
            Container(
              height: 115,
              decoration: const BoxDecoration(
                color: Color(0xFF27272A),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Stack(
                children: [
                  // Blob image
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                      child: Image.asset(
                        blobImage,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: const Color(0xFF27272A),
                          );
                        },
                      ),
                    ),
                  ),
                  // Gradient overlay
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.white.withOpacity(0.6),
                            const Color(0xFF111EB6).withOpacity(0.82),
                          ],
                        ),
                        backgroundBlendMode: BlendMode.hue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Icon and label section
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon in circular background
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0E7FF),
                      borderRadius: BorderRadius.circular(46),
                    ),
                    child: SvgPicture.asset(
                      iconPath,
                      width: 16,
                      height: 16,
                      colorFilter: const ColorFilter.mode(
                        Color(0xFF7C86FF),
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Label
                  Text(
                    label,
                    style: const TextStyle(
                      fontFamily: 'GeneralSans',
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF27272A),
                      letterSpacing: 0.4,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventsHeader() {
    return Container(
      padding: const EdgeInsets.only(bottom: 8, top: 16),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Color(0xFFE4E4E7),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            'Events',
            style: TextStyle(
              fontFamily: 'GeneralSans',
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Color(0xFF27272A),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _createEventDialog,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(8),
                child: SvgPicture.asset(
                  'assets/icons/add-line.svg',
                  width: 24,
                  height: 24,
                  colorFilter: const ColorFilter.mode(
                    Color(0xFF27272A),
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventCard(ProjectModel event) {
    final eventImages = _eventImages[event.id] ?? [];
    
    return Container(
      width: 328,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFE4E4E7),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Three images side by side (or fewer if not available)
          Container(
            height: 115,
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                // Show up to 3 images
                for (int i = 0; i < 3; i++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: i < 2 ? 4 : 0,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: i < eventImages.length
                            ? Image.file(
                                File(eventImages[i].filePath),
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    color: Colors.grey[300],
                                  );
                                },
                              )
                            : Container(
                                color: Colors.grey[200],
                              ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Event title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Text(
              event.title,
              style: const TextStyle(
                fontFamily: 'GeneralSans',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF27272A),
                letterSpacing: 0.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
