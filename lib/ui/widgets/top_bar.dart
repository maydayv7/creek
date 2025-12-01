import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:adobe/data/models/project_model.dart';
import 'package:adobe/data/repos/project_repo.dart';
import '../styles/variables.dart';

class TopBar extends StatefulWidget implements PreferredSizeWidget {
  final int currentProjectId;
  final VoidCallback? onBack;
  final Function(ProjectModel)? onProjectChanged;
  final VoidCallback? onSettingsPressed;
  final String? titleOverride;
  final VoidCallback? onLayoutPressed;
  final VoidCallback? onFilterPressed;
  final VoidCallback? onAIPressed;
  final bool? isAlternateView; // For toggle state
  final VoidCallback? onLayoutToggle; // For toggle callback

  const TopBar({
    super.key,
    required this.currentProjectId,
    this.onBack,
    this.onProjectChanged,
    this.onSettingsPressed,
    this.titleOverride,
    this.onLayoutPressed,
    this.onFilterPressed,
    this.onAIPressed,
    this.isAlternateView,
    this.onLayoutToggle,
  });

  @override
  State<TopBar> createState() => _TopBarState();

  @override
  Size get preferredSize => const Size.fromHeight(88.0); // Height for two rows
}

class _TopBarState extends State<TopBar> {
  final ProjectRepo _projectRepo = ProjectRepo();

  bool _isLoading = true;
  ProjectModel? _currentProject;
  ProjectModel? _rootProject;
  List<ProjectModel> _contextList = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant TopBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentProjectId != widget.currentProjectId) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    try {
      final current = await _projectRepo.getProjectById(
        widget.currentProjectId,
      );
      if (current == null) {
        setState(() => _isLoading = false);
        return;
      }

      ProjectModel? root;
      List<ProjectModel> events = [];

      if (current.parentId == null) {
        root = current;
        events = await _projectRepo.getEvents(current.id!);
      } else {
        root = await _projectRepo.getProjectById(current.parentId!);
        if (root != null) {
          events = await _projectRepo.getEvents(root.id!);
        }
      }
      root ??= current;
      final List<ProjectModel> fullList = [root, ...events];
      if (mounted) {
        setState(() {
          _currentProject = current;
          _rootProject = root;
          _contextList = fullList;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("TopBar Error: $e");
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.of(context).textScaler;
    return Container(
      color: Colors.white, // White background
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // First Row: Title and Settings
            Container(
              height: 48.0, // py-[12px] = 24px + 24px content
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  // Back Button
                  if (widget.onBack != null) ...[
                    GestureDetector(
                      onTap: widget.onBack,
                      child: Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.arrow_back,
                          size: 20,
                          color: Variables.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // Title
                  Expanded(
                    child: widget.titleOverride != null
                        ? Text(
                            widget.titleOverride!,
                            style: const TextStyle(
                              fontFamily: 'GeneralSans',
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
                              height: 24 / 20, // line-height: 24px
                              color: Variables.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          )
                        : (!_isLoading &&
                                _currentProject != null &&
                                _rootProject != null)
                            ? Text(
                                _rootProject!.title,
                                style: const TextStyle(
                                  fontFamily: 'GeneralSans',
                                  fontSize: 20,
                                  fontWeight: FontWeight.w500,
                                  height: 24 / 20,
                                  color: Variables.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              )
                            : const SizedBox(),
                  ),
                  // Settings Icon
                  GestureDetector(
                    onTap: widget.onSettingsPressed,
                    child: SvgPicture.asset(
                      'assets/icons/settings-line.svg',
                      width: 24,
                      height: 24,
                      colorFilter: const ColorFilter.mode(
                        Variables.textPrimary,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Second Row: Global Dropdown and Action Buttons
            Container(
              height: 40.0, // py-[8px] = 16px + 24px content
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  // Left group: Global Dropdown and Layout Button
                  Row(
                    children: [
                      // Global Dropdown
                      if (!_isLoading &&
                          _currentProject != null &&
                          _rootProject != null)
                        PopupMenuButton<ProjectModel>(
                          padding: EdgeInsets.zero,
                          onSelected: (project) =>
                              widget.onProjectChanged?.call(project),
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          offset: const Offset(0, 42),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Variables.borderSubtle, // #e4e4e7
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _currentProject!.id == _rootProject!.id
                                      ? "Global"
                                      : _currentProject!.title,
                                  style: const TextStyle(
                                    fontFamily: 'GeneralSans',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    height: 24 / 16,
                                    color: Variables.textPrimary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 20,
                                  color: Variables.textPrimary,
                                ),
                              ],
                            ),
                          ),
                          itemBuilder: (context) {
                            return _contextList.map((project) {
                              final isSelected = project.id == _currentProject!.id;
                              final isRoot = project.id == _rootProject!.id;
                              return PopupMenuItem<ProjectModel>(
                                value: project,
                                child: Text(
                                  isRoot ? "Global" : project.title,
                                  style: Variables.bodyStyle.copyWith(
                                    fontFamily: 'GeneralSans',
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? Variables.textPrimary
                                        : Variables.textSecondary,
                                  ),
                                ),
                              );
                            }).toList();
                          },
                        ),
                      const SizedBox(width: 8),
                      // Layout Icon Button (Toggle between All Images/Categorized)
                      GestureDetector(
                        onTap: widget.onLayoutToggle ?? widget.onLayoutPressed,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Variables.borderSubtle,
                            borderRadius: BorderRadius.circular(1000),
                          ),
                          child: Icon(
                            widget.isAlternateView == true
                                ? Icons.dashboard
                                : Icons.view_agenda_outlined,
                            size: 20,
                            color: Variables.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Right group: Filter and AI/Sparkle Buttons
                  Row(
                    children: [
                      // Filter Icon Button
                      GestureDetector(
                        onTap: widget.onFilterPressed,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Variables.borderSubtle,
                            borderRadius: BorderRadius.circular(1000),
                          ),
                          child: const Icon(
                            Icons.tune,
                            size: 20,
                            color: Variables.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // AI/Sparkle Icon Button
                      GestureDetector(
                        onTap: widget.onAIPressed,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Variables.borderSubtle,
                            borderRadius: BorderRadius.circular(1000),
                          ),
                          child: const Icon(
                            Icons.auto_awesome,
                            size: 20,
                            color: Variables.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
