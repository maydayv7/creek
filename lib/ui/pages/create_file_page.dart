import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:creekui/services/project_service.dart';
import 'package:creekui/ui/styles/variables.dart';
import 'package:creekui/ui/widgets/search_bar.dart';
import 'package:creekui/ui/widgets/project_selector.dart';
import 'package:creekui/ui/widgets/app_bar.dart';
import 'canvas_page.dart';
import 'define_brand_page.dart';

class CreateFilePage extends StatefulWidget {
  final File? file;
  final int? projectId;

  const CreateFilePage({super.key, this.file, this.projectId});

  @override
  State<CreateFilePage> createState() => _CreateFilePageState();
}

class _CreateFilePageState extends State<CreateFilePage> {
  final TextEditingController _searchController = TextEditingController();

  int? _selectedProjectId;
  String _selectedProjectTitle = "Select Project";

  final List<CanvasPreset> _allPresets = [
    CanvasPreset(
      name: 'Custom',
      width: 0,
      height: 0,
      displaySize: 'Custom Size',
    ),
    CanvasPreset(
      name: 'Poster',
      width: 2304,
      height: 3456,
      displaySize: '24 x 36 in',
    ),
    CanvasPreset(
      name: 'Instagram Post',
      width: 1080,
      height: 1080,
      displaySize: '1080 x 1080 px',
      svgPath: 'assets/icons/instagram_poster.svg',
    ),
    CanvasPreset(
      name: 'Invitation',
      width: 480,
      height: 672,
      displaySize: '5 x 7 in',
      svgPath: 'assets/icons/invitation.svg',
    ),
    CanvasPreset(
      name: 'Flyer - A5',
      width: 560,
      height: 794,
      displaySize: '148 x 210 mm',
    ),
    CanvasPreset(
      name: 'Business Card',
      width: 336,
      height: 192,
      displaySize: '3.5 x 2 in',
      svgPath: 'assets/icons/group.svg',
    ),
    CanvasPreset(
      name: 'Photo Collage',
      width: 1800,
      height: 1800,
      displaySize: '1800 x 1800 px',
    ),
    CanvasPreset(
      name: 'Menu',
      width: 794,
      height: 1123,
      displaySize: '210 x 297 mm',
    ),
    CanvasPreset(
      name: 'Menu Book',
      width: 794,
      height: 1123,
      displaySize: '210 x 297 mm',
    ),
  ];

  List<CanvasPreset> _filteredPresets = [];

  @override
  void initState() {
    super.initState();
    _filteredPresets = _allPresets;

    // If an existing projectId was passed, lock to that project
    _selectedProjectId = widget.projectId;
    if (_selectedProjectId != null) {
      _selectedProjectTitle = "Current Project";
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _runFilter(String keyword) {
    if (keyword.isEmpty) {
      setState(() => _filteredPresets = _allPresets);
      return;
    }
    setState(() {
      _filteredPresets =
          _allPresets
              .where(
                (p) => p.name.toLowerCase().contains(keyword.toLowerCase()),
              )
              .toList();
    });
  }

  // Select project
  void _openProjectSelection() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (_, controller) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: _ProjectSelectionModalContent(
                scrollController: controller,
                onProjectSelected: (id, title) {
                  setState(() {
                    _selectedProjectId = id;
                    _selectedProjectTitle = title;
                  });
                  Navigator.pop(context);
                },
              ),
            );
          },
        );
      },
    );
  }

  // Go to canvas with selected project
  void _navigateToEditor(int width, int height) {
    if (_selectedProjectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a destination project")),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => CanvasPage(
              projectId: _selectedProjectId!,
              width: width.toDouble(),
              height: height.toDouble(),
              initialImage: widget.file,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: CommonAppBar(
        title: 'Create Files',
        showBack: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (widget.projectId == null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: TextButton.icon(
                onPressed: _openProjectSelection,
                style: TextButton.styleFrom(
                  backgroundColor: isDark ? Colors.grey[800] : Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                icon: Icon(
                  _selectedProjectId == null
                      ? Icons.create_new_folder_outlined
                      : Icons.folder_open,
                  size: 18,
                  color: theme.colorScheme.onSurface,
                ),
                label: Text(
                  _selectedProjectTitle,
                  style: Variables.bodyStyle.copyWith(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: CommonSearchBar(
              controller: _searchController,
              hintText: 'Search sizes',
              onChanged: _runFilter,
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Canvas Sizes',
              style: Variables.bodyStyle.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          // Grid
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.75,
              ),
              itemCount: _filteredPresets.length,
              itemBuilder:
                  (_, i) => _buildPresetCard(_filteredPresets[i], theme),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetCard(CanvasPreset preset, ThemeData theme) {
    final bool isCustom = preset.name == 'Custom';
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap:
          () => _navigateToEditor(
            isCustom ? 1000 : preset.width,
            isCustom ? 1000 : preset.height,
          ),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Variables.borderDark : Colors.transparent,
          ),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[800] : const Color(0xFFE0E7FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child:
                      isCustom
                          ? const Icon(Icons.add, color: Colors.blue, size: 30)
                          : Padding(
                            padding: const EdgeInsets.all(12),
                            child: AspectRatio(
                              aspectRatio: preset.width / preset.height,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: theme.cardColor,
                                  borderRadius: BorderRadius.circular(4),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child:
                                    preset.svgPath != null
                                        ? SvgPicture.asset(
                                          preset.svgPath!,
                                          fit: BoxFit.contain,
                                        )
                                        : null,
                              ),
                            ),
                          ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              preset.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Variables.bodyStyle.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            Text(
              preset.displaySize,
              style: Variables.captionStyle.copyWith(
                fontSize: 9,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CanvasPreset {
  final String name;
  final int width;
  final int height;
  final String displaySize;
  final String? svgPath;

  CanvasPreset({
    required this.name,
    required this.width,
    required this.height,
    required this.displaySize,
    this.svgPath,
  });
}

// Project Selection Modal
class _ProjectSelectionModalContent extends StatefulWidget {
  final Function(int id, String title) onProjectSelected;
  final ScrollController scrollController;

  const _ProjectSelectionModalContent({
    required this.onProjectSelected,
    required this.scrollController,
  });

  @override
  State<_ProjectSelectionModalContent> createState() =>
      _ProjectSelectionModalContentState();
}

class _ProjectSelectionModalContentState
    extends State<_ProjectSelectionModalContent> {
  Key _selectorKey = UniqueKey();

  Future<void> _createNewProject() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DefineBrandPage(projectName: "")),
    );

    if (result != null && result is Map) {
      widget.onProjectSelected(result["id"], result["title"]);
    } else {
      // If project is created but not selected immediately, refreshing the list is a safe bet
      setState(() {
        _selectorKey = UniqueKey();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        // Header row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Select Destination",
                style: Variables.headerStyle.copyWith(fontSize: 18),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: _createNewProject,
                tooltip: "Create New Project",
              ),
            ],
          ),
        ),
        Divider(color: Colors.grey[300], height: 1),
        // Selector
        Expanded(
          child: ProjectSelector(
            key: _selectorKey,
            scrollController: widget.scrollController,
            searchHint: "Search Projects",
            onProjectSelected: (id, title, parentTitle) {
              final displayTitle =
                  parentTitle != null ? "$parentTitle / $title" : title;
              widget.onProjectSelected(id, displayTitle);
            },
          ),
        ),
      ],
    );
  }
}
