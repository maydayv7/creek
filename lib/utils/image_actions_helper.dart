import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../data/models/image_model.dart';
import '../services/image_service.dart';
import '../ui/pages/share_to_file_page.dart';
import '../ui/styles/variables.dart';

class ImageActionsHelper {
  static Future<void> shareImage(BuildContext context, String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await Share.shareXFiles([XFile(filePath)]);
    }
  }

  static void sendToFiles(BuildContext context, String filePath) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShareToFilePage(sharedImage: File(filePath)),
      ),
    );
  }

  static Future<void> renameImage(
    BuildContext context,
    ImageModel image,
    VoidCallback onSuccess,
  ) async {
    final TextEditingController nameController = TextEditingController(
      text: image.name,
    );
    await showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              "Rename Image",
              style: TextStyle(
                fontFamily: 'GeneralSans',
                fontWeight: FontWeight.w600,
              ),
            ),
            content: TextField(
              controller: nameController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: "Enter new name",
                filled: true,
                fillColor: Variables.surfaceSubtle,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  "Cancel",
                  style: TextStyle(
                    color: Variables.textSecondary,
                    fontFamily: 'GeneralSans',
                  ),
                ),
              ),
              TextButton(
                onPressed: () async {
                  if (nameController.text.isNotEmpty) {
                    await ImageService().renameImage(
                      image.id,
                      nameController.text.trim(),
                    );
                    onSuccess();
                    if (ctx.mounted) Navigator.pop(ctx);
                  }
                },
                child: const Text(
                  "Save",
                  style: TextStyle(
                    color: Variables.textPrimary,
                    fontFamily: 'GeneralSans',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
    );
  }

  static Future<void> deleteImage(
    BuildContext context,
    ImageModel image,
    VoidCallback onSuccess,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              "Delete Image?",
              style: TextStyle(
                fontFamily: 'GeneralSans',
                fontWeight: FontWeight.w600,
              ),
            ),
            content: const Text(
              "This action cannot be undone.",
              style: TextStyle(
                fontFamily: 'GeneralSans',
                color: Variables.textSecondary,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  "Cancel",
                  style: TextStyle(
                    color: Variables.textSecondary,
                    fontFamily: 'GeneralSans',
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  "Delete",
                  style: TextStyle(
                    color: Colors.red,
                    fontFamily: 'GeneralSans',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
    );

    if (confirm == true) {
      await ImageService().deleteImage(image.id);
      onSuccess();
    }
  }
}
