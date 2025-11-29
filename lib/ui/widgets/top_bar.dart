import 'package:flutter/material.dart';
import 'package:adobe/data/models/project_model.dart';
import 'package:adobe/data/repos/project_repo.dart';
import 'package:adobe/ui/styles/variables.dart';

class TopBar extends StatefulWidget implements PreferredSizeWidget {
  final int currentProjectId;
  final VoidCallback? onBack;
  final Function(ProjectModel)? onProjectChanged;
  final VoidCallback? onSettingsPressed;

  const TopBar({
    super.key,
    required this.currentProjectId,
    this.onBack,
    this.onProjectChanged,
    this.onSettingsPressed,
  });

  @override
  State<TopBar> createState() => _TopBarState();

  @override
  Size get preferredSize => const Size.fromHeight(80);
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
        // Current IS Project
        root = current;
        events = await _projectRepo.getEvents(current.id!);
      } else {
        // Current IS Event
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
        child: Container(
          height: 80,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              // 1. Back Button
              if (widget.onBack != null)
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Variables.textPrimary),
                  onPressed: widget.onBack,
                ),
              if (widget.onBack != null) const SizedBox(width: 8),

              // 2. Title & Selector
              if (!_isLoading && _currentProject != null && _rootProject != null)
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _rootProject!.title,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w600,
                            color: Variables.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      PopupMenuButton<ProjectModel>(
                        onSelected: (project) {
                          widget.onProjectChanged?.call(project);
                        },
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        offset: const Offset(0, 40),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Variables.surfaceSubtle,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _currentProject!.id == _rootProject!.id
                                    ? "Main Project"
                                    : _currentProject!.title,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: Variables.textPrimary,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Variables.textPrimary,
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
                  ),
                ),

              // 3. Settings Icon
              IconButton(
                icon: const Icon(Icons.settings_outlined, color: Variables.textPrimary),
                onPressed: widget.onSettingsPressed,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
