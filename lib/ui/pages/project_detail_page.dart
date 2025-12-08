import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:creekui/data/models/project_model.dart';
import 'package:creekui/data/models/image_model.dart';
import 'package:creekui/data/repos/project_repo.dart';
import 'package:creekui/data/repos/image_repo.dart';
import 'package:creekui/services/project_service.dart';
import 'package:creekui/ui/styles/variables.dart';
import 'package:creekui/ui/widgets/empty_state.dart';
import 'package:creekui/ui/widgets/section_header.dart';
import 'package:creekui/ui/widgets/app_bar.dart';
import 'package:creekui/ui/widgets/dialog.dart';
import 'package:creekui/ui/widgets/text_field.dart';
import 'package:creekui/ui/pages/settings_page.dart';
import 'package:creekui/ui/pages/home_page.dart';
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createEventDialog() async {
    if (_project?.id == null) return;

    final nameController = TextEditingController();
    final descriptionController = TextEditingController();

    if (!mounted) return;

    await ShowDialog.show(
      context,
      title: "Event Details",
      primaryButtonText: "Add Event",
      content: Column(
        children: [
          CommonTextField(
            hintText: "Add Name*",
            controller: nameController,
            autoFocus: true,
          ),
          const SizedBox(height: 16),
          CommonTextField(
            hintText: "Add Description",
            controller: descriptionController,
            maxLines: 3,
          ),
        ],
      ),
      onPrimaryPressed: () async {
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
              _loadData();
            }
          } catch (e) {
            debugPrint("Error creating event: $e");
          }
        }
      },
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Variables.surfaceBackground,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_project == null) return const Scaffold(body: SizedBox());

    return Scaffold(
      backgroundColor: Variables.surfaceBackground,
      appBar: CustomAppBar(
        title: _project!.title,
        showBack: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back,
            size: 20,
            color: Variables.textPrimary,
          ),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const HomePage()),
              );
            }
          },
        ),
        actions: [
          IconButton(
            icon: SvgPicture.asset(
              'assets/icons/settings-line.svg',
              width: 24,
              height: 24,
              colorFilter: const ColorFilter.mode(
                Variables.textPrimary,
                BlendMode.srcIn,
              ),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              _buildActionCardsRow(_project!.id!),
              const SizedBox(height: 16),
              SectionHeader(
                title: 'Events',
                trailing: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _createEventDialog,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: SvgPicture.asset(
                        'assets/icons/add-line.svg',
                        width: 24,
                        height: 24,
                        colorFilter: const ColorFilter.mode(
                          Variables.textPrimary,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_events.isEmpty)
                const EmptyState(
                  icon: Icons.event_note,
                  title: "No events created yet",
                  subtitle: "Create an event to start organizing",
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _events.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final event = _events[index];
                    return Center(child: _buildEventCard(event));
                  },
                ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // Widgets
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
          border: Border.all(color: Variables.borderSubtle, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Blob image container
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
                        errorBuilder:
                            (context, error, stackTrace) =>
                                Container(color: const Color(0xFF27272A)),
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
                    style: Variables.bodyStyle.copyWith(
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
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

  Widget _buildEventCard(ProjectModel event) {
    final eventImages = _eventImages[event.id] ?? [];
    return GestureDetector(
      onTap: () {
        if (event.id != null) _navigateToBoard(event.id!);
      },
      child: Container(
        width: 328,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Variables.borderSubtle, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 3 images side by side (or fewer if not available)
            Container(
              height: 115,
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  for (int i = 0; i < 3; i++) ...[
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child:
                            i < eventImages.length
                                ? Image.file(
                                  File(eventImages[i].filePath),
                                  fit: BoxFit.cover,
                                  errorBuilder:
                                      (_, __, ___) =>
                                          Container(color: Colors.grey[300]),
                                )
                                : Container(color: Colors.grey[200]),
                      ),
                    ),
                    if (i < 2) const SizedBox(width: 4),
                  ],
                ],
              ),
            ),
            // Event title
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                event.title,
                style: Variables.bodyStyle.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
