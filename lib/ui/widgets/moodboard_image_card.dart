import 'dart:io';
import 'package:flutter/material.dart';
import 'package:creekui/data/models/image_model.dart';
import 'package:creekui/ui/styles/variables.dart';
import 'package:creekui/ui/widgets/image_context_menu.dart';

class MoodboardImageCard extends StatelessWidget {
  final ImageModel image;
  final VoidCallback onTap;
  final VoidCallback onDeleted;
  final bool showTags;
  final double? height;

  const MoodboardImageCard({
    super.key,
    required this.image,
    required this.onTap,
    required this.onDeleted,
    this.showTags = false,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return ImageContextMenu(
      image: image,
      onImageDeleted: onDeleted,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Variables.radiusMedium),
            color: Variables.surfaceSubtle,
            border: Border.all(color: Variables.borderSubtle),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                File(image.filePath),
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder:
                    (_, __, ___) => const Center(
                      child: Icon(
                        Icons.broken_image,
                        color: Variables.textDisabled,
                      ),
                    ),
              ),
              if (showTags && image.tags.isNotEmpty)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withOpacity(0.8),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children:
                          image.tags.take(3).map((tag) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                tag.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontFamily: 'GeneralSans',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }).toList(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
