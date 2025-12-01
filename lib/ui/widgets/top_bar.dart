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
      color: Variables.background,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                // 1. Back Button
                if (widget.onBack != null) ...[
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Variables.textPrimary,
                    ),
                    onPressed: widget.onBack,
                  ),
                  const SizedBox(width: 8),
                ],

                // 2. Title & Selector
                Expanded(
                  child:
                      widget.titleOverride != null
                          ? Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: Text(
                                widget.titleOverride!,
                                style: const TextStyle(
                                  fontFamily: 'GeneralSans',
                                  fontSize: 20,
                                  fontWeight: FontWeight.w500,
                                  color: Variables.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            )
                          : (!_isLoading &&
                                  _currentProject != null &&
                                  _rootProject != null)
                              ? Row(
                                  children: [
                                    if (widget.onBack == null)
                                      const SizedBox(width: 12),
                                    Flexible(
                                      child: Text(
                                        _rootProject!.title,
                                        style: const TextStyle(
                                          fontFamily: 'GeneralSans',
                                          fontSize: 20,
                                          fontWeight: FontWeight.w500,
                                          color: Variables.textPrimary,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                )
                              : const SizedBox(),
                ),
                if (!_isLoading &&
                    _currentProject != null &&
                    _rootProject != null)
                  PopupMenuButton<ProjectModel>(
                    padding: EdgeInsets.zero,
                    onSelected:
                        (project) => widget.onProjectChanged?.call(project),
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    offset: const Offset(0, 38),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Variables.surfaceSubtle,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _currentProject!.id == _rootProject!.id
                                ? "Main"
                                : _currentProject!.title,
                            style: Variables.bodyStyle.copyWith(
                              fontFamily: 'GeneralSans',
                              fontSize: 15 * textScaler.scale(1.1),
                              fontWeight: FontWeight.w500,
                              color: Variables.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 18,
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
                            isRoot ? "Main Project" : project.title,
                            style: Variables.bodyStyle.copyWith(
                              fontFamily: 'GeneralSans',
                              fontWeight:
                                  isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                              color:
                                  isSelected
                                      ? Variables.textPrimary
                                      : Variables.textSecondary,
                            ),
                          ),
                        );
                      }).toList();
                    },
                  ),
                const SizedBox(width: 4),

                // 3. Settings Icon
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
                  onPressed: widget.onSettingsPressed,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
