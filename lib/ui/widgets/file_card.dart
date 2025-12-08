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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 110,
        decoration: BoxDecoration(
          color: Variables.background,
          borderRadius: BorderRadius.circular(Variables.radiusMedium),
          border: Border.all(color: Variables.borderSubtle),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Preview Image
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: Variables.surfaceSubtle,
                borderRadius: BorderRadius.circular(Variables.radiusSmall),
              ),
              clipBehavior: Clip.antiAlias,
              child:
                  previewPath.isNotEmpty
                      ? Image.file(
                        File(previewPath),
                        fit: BoxFit.cover,
                        errorBuilder:
                            (context, error, stackTrace) => const Center(
                              child: Icon(
                                Icons.broken_image,
                                color: Variables.textDisabled,
                              ),
                            ),
                      )
                      : const Center(
                        child: Icon(Icons.image, color: Variables.textDisabled),
                      ),
            ),
            const SizedBox(width: 16),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (breadcrumb.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        breadcrumb,
                        style: Variables.captionStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  Text(
                    file.name,
                    style: Variables.bodyStyle.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(dimensions, style: Variables.captionStyle),
                  const SizedBox(height: 2),
                  Text(
                    timeAgo,
                    style: Variables.captionStyle.copyWith(
                      color: Variables.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            // Menu Action
            if (onMenuAction != null)
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert,
                  color: Variables.textSecondary,
                ),
                onSelected: onMenuAction,
                itemBuilder:
                    (BuildContext context) => <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(
                        value: 'open',
                        child: Row(
                          children: [
                            Icon(Icons.file_open_outlined, size: 18),
                            SizedBox(width: 12),
                            Text(
                              'Open',
                              style: TextStyle(fontFamily: 'GeneralSans'),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuItem<String>(
                        value: 'rename',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 18),
                            SizedBox(width: 12),
                            Text(
                              'Rename',
                              style: TextStyle(fontFamily: 'GeneralSans'),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuItem<String>(
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
          ],
        ),
      ),
    );
  }
}
