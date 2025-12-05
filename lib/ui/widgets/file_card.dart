import 'dart:io';
import 'package:flutter/material.dart';
import 'package:creekui/data/models/file_model.dart';
import 'package:creekui/ui/styles/variables.dart';

class FileCard extends StatelessWidget {
  final FileModel file;
  final String breadcrumb;
  final String dimensions;
  final String previewPath;
  final String timeAgo;
  final VoidCallback onTap;

  // Optional actions for the context menu.
  // If null, the menu icon is hidden or disabled.
  final Function(String)? onMenuAction;

  const FileCard({
    super.key,
    required this.file,
    required this.breadcrumb,
    required this.dimensions,
    required this.previewPath,
    required this.timeAgo,
    required this.onTap,
    this.onMenuAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Resolve valid image path
    final bool hasPreview =
        previewPath.isNotEmpty && File(previewPath).existsSync();
    final ImageProvider? imageProvider =
        hasPreview ? FileImage(File(previewPath)) : null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(Variables.radiusSmall),
          // Optional: Add subtle border if needed to match FilePage style
          border: Border.all(
            color: isDark ? Variables.borderDark : Colors.transparent,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Thumbnail
            SizedBox(
              width: 88,
              height: 88,
              child: Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color:
                        isDark
                            ? Variables.surfaceDark
                            : Variables.surfaceSubtle,
                    borderRadius: BorderRadius.circular(Variables.radiusSmall),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Variables.radiusSmall),
                    child:
                        hasPreview
                            ? Image(
                              image: imageProvider!,
                              fit: BoxFit.cover,
                              errorBuilder:
                                  (_, __, ___) => _buildPlaceholder(theme),
                            )
                            : _buildPlaceholder(theme),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Info Column
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (breadcrumb.isNotEmpty)
                                Text(
                                  breadcrumb,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    fontFamily: 'GeneralSans',
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              const SizedBox(height: 4),
                              Text(
                                file.name,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'GeneralSans',
                                  color: theme.colorScheme.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Menu
                        if (onMenuAction != null)
                          PopupMenuButton<String>(
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              Icons.more_vert,
                              size: 20,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                            onSelected: onMenuAction,
                            itemBuilder:
                                (_) => const [
                                  PopupMenuItem(
                                    value: "open",
                                    child: Text("Open"),
                                  ),
                                  PopupMenuItem(
                                    value: "rename",
                                    child: Text("Rename"),
                                  ),
                                  PopupMenuItem(
                                    value: "delete",
                                    child: Text("Delete"),
                                  ),
                                ],
                          )
                        else
                          Icon(
                            Icons.more_vert,
                            size: 20,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      dimensions,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'GeneralSans',
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      timeAgo,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'GeneralSans',
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(ThemeData theme) {
    return Center(
      child: Icon(
        Icons.image,
        size: 24,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
      ),
    );
  }
}
