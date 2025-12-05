import 'dart:io';
import 'package:flutter/material.dart';
import 'package:creekui/data/models/project_model.dart';
import 'package:creekui/ui/styles/variables.dart';

class ProjectCard extends StatelessWidget {
  final ProjectModel project;
  final List<String> previewImages;
  final VoidCallback onTap;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;
  final bool isHorizontal;
  final bool showGrid;

  const ProjectCard({
    super.key,
    required this.project,
    required this.previewImages,
    required this.onTap,
    this.onRename,
    this.onDelete,
    this.isHorizontal = true,
    this.showGrid = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: isHorizontal ? 130 : null,
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(Variables.radiusMedium),
          border: Border.all(
            color: isDark ? Variables.borderDark : Variables.borderSubtle,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(Variables.radiusMedium),
                ),
                child:
                    showGrid
                        ? Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: _buildGridPreview(isDark),
                        )
                        : (previewImages.isNotEmpty
                            ? Image.file(
                              File(previewImages.first),
                              fit: BoxFit.cover,
                              width: double.infinity,
                              errorBuilder:
                                  (context, error, stackTrace) =>
                                      _buildErrorPlaceholder(isDark, theme),
                            )
                            : _buildEmptyPlaceholder(isDark, theme)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      project.title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'GeneralSans',
                        color: theme.colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  if (onRename != null || onDelete != null)
                    SizedBox(
                      height: 24,
                      width: 24,
                      child: PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_vert,
                          size: 16,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        onSelected: (value) {
                          if (value == 'rename' && onRename != null) {
                            onRename!();
                          } else if (value == 'delete' && onDelete != null) {
                            onDelete!();
                          }
                        },
                        itemBuilder:
                            (context) => [
                              if (onRename != null)
                                const PopupMenuItem(
                                  value: 'rename',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit_outlined, size: 18),
                                      SizedBox(width: 12),
                                      Text(
                                        'Rename',
                                        style: TextStyle(
                                          fontFamily: 'GeneralSans',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (onDelete != null)
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.delete_outline,
                                        size: 18,
                                        color: Colors.red,
                                      ),
                                      SizedBox(width: 12),
                                      Text(
                                        'Delete',
                                        style: TextStyle(
                                          fontFamily: 'GeneralSans',
                                          color: Colors.red,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridPreview(bool isDark) {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _buildPreviewItem(
                  previewImages.isNotEmpty ? previewImages[0] : null,
                  isDark,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildPreviewItem(
                  previewImages.length > 1 ? previewImages[1] : null,
                  isDark,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _buildPreviewItem(
                  previewImages.length > 2 ? previewImages[2] : null,
                  isDark,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildPreviewItem(
                  previewImages.length > 3 ? previewImages[3] : null,
                  isDark,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewItem(String? imagePath, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Variables.surfaceDark : Variables.surfaceSubtle,
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child:
          imagePath != null
              ? Image.file(
                File(imagePath),
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorBuilder:
                    (_, __, ___) => const Icon(
                      Icons.broken_image,
                      size: 16,
                      color: Colors.grey,
                    ),
              )
              : null,
    );
  }

  Widget _buildErrorPlaceholder(bool isDark, ThemeData theme) {
    return Container(
      color: isDark ? Variables.surfaceDark : Variables.surfaceSubtle,
      child: Icon(
        Icons.broken_image,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
      ),
    );
  }

  Widget _buildEmptyPlaceholder(bool isDark, ThemeData theme) {
    return Container(
      color: isDark ? Variables.surfaceDark : Variables.surfaceSubtle,
      child: Center(
        child: Icon(
          Icons.folder_outlined,
          size: 32,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
        ),
      ),
    );
  }
}
