import 'package:flutter/material.dart';
import '../../data/models/project_model.dart'; // Adjust path as needed
import '../../data/repos/project_repo.dart'; // Adjust path as needed
import '../styles/variables.dart'; // Adjust path as needed

class TopBar extends StatefulWidget implements PreferredSizeWidget {
  final int currentProjectId;
  final VoidCallback? onBack;
  final Function(ProjectModel)? onProjectChanged;
  final VoidCallback? onSettingsPressed;
  final String? titleOverride; // New: For Tag Page title

  const TopBar({
    super.key,
    required this.currentProjectId,
    this.onBack,
    this.onProjectChanged,
    this.onSettingsPressed,
    this.titleOverride,
  });

  @override
  State<TopBar> createState() => _TopBarState();

  // FIX: Reduced from 80 to 56 (Standard Toolbar Height)
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight); 
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
      final current = await _projectRepo.getProjectById(widget.currentProjectId);
      if (current == null) return;

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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Variables.background,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight, // FIX: Use standard height
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                // 1. Back Button
                if (widget.onBack != null) ...[
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Variables.textPrimary),
                    onPressed: widget.onBack,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 12),
                ],

                // 2. Title & Selector
                Expanded(
                  child: widget.titleOverride != null
                      ? Text(
                          widget.titleOverride!,
                          style: const TextStyle(
                            fontSize: 20, // Slightly smaller for tags
                            fontWeight: FontWeight.w600,
                            color: Variables.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        )
                      : (!_isLoading && _currentProject != null && _rootProject != null)
                          ? Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    _rootProject!.title,
                                    style: const TextStyle(
                                      fontSize: 22, // Adjusted font size
                                      fontWeight: FontWeight.w600,
                                      color: Variables.textPrimary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                PopupMenuButton<ProjectModel>(
                                  padding: EdgeInsets.zero,
                                  onSelected: (project) {
                                    widget.onProjectChanged?.call(project);
                                  },
                                  color: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  offset: const Offset(0, 40),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Variables.surfaceSubtle,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          _currentProject!.id == _rootProject!.id
                                              ? "Main"
                                              : _currentProject!.title,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: Variables.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        const Icon(
                                          Icons.keyboard_arrow_down_rounded,
                                          color: Variables.textPrimary,
                                          size: 18,
                                        )
                                      ],
                                    ),
                                  ),
                                  itemBuilder: (context) {
                                    return _contextList.map((ProjectModel project) {
                                      final isRoot = project.id == _rootProject!.id;
                                      final isSelected = project.id == _currentProject!.id;
                                      return PopupMenuItem<ProjectModel>(
                                        value: project,
                                        child: Text(
                                          isRoot ? "Main Project" : project.title,
                                          style: Variables.bodyStyle.copyWith(
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                            color: isSelected ? Variables.textPrimary : Variables.textSecondary,
                                          ),
                                        ),
                                      );
                                    }).toList();
                                  },
                                ),
                              ],
                            )
                          : const SizedBox(),
                ),

                // 3. Settings Icon
                IconButton(
                  icon: const Icon(Icons.settings_outlined, color: Variables.textPrimary),
                  onPressed: widget.onSettingsPressed,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}