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
    // Resolve valid image path
    final bool hasPreview =
        previewPath.isNotEmpty && File(previewPath).existsSync();
    final ImageProvider? imageProvider =
        hasPreview ? FileImage(File(previewPath)) : null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE4E4E7)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                bottomLeft: Radius.circular(16),
              ),
              child: SizedBox(
                width: 120,
                height: 120,
                child:
                    hasPreview
                        ? Image(
                          image: imageProvider!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildPlaceholder(),
                        )
                        : _buildPlaceholder(),
              ),
            ),

            const SizedBox(width: 12),

            // Info Column
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (breadcrumb.isNotEmpty)
                      Text(
                        breadcrumb,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF71717B),
                          fontFamily: 'GeneralSans',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 4),
                    Text(
                      file.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'GeneralSans',
                        color: Color(0xFF27272A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      dimensions,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF71717B),
                        fontFamily: 'GeneralSans',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      timeAgo,
                      style: TextStyle(
                        fontSize: 12,
                        color: const Color(0xFF71717B).withValues(alpha: 0.8),
                        fontFamily: 'GeneralSans',
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Menu
            if (onMenuAction != null)
              PopupMenuButton<String>(
                onSelected: onMenuAction,
                itemBuilder:
                    (_) => const [
                      PopupMenuItem(value: "open", child: Text("Open")),
                      PopupMenuItem(value: "rename", child: Text("Rename")),
                      PopupMenuItem(value: "delete", child: Text("Delete")),
                    ],
                icon: const Icon(
                  Icons.more_vert,
                  size: 20,
                  color: Color(0xFF71717B),
                ),
              )
            else
              const SizedBox(width: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey[300],
      child: const Center(
        child: Icon(Icons.image, size: 32, color: Colors.white),
      ),
    );
  }
}
