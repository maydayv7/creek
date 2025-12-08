import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:creekui/data/models/image_model.dart';
import 'package:creekui/services/image_service.dart';
import 'package:creekui/ui/pages/share_to_file_page.dart';
import 'package:creekui/ui/widgets/dialog.dart';
import 'package:creekui/ui/widgets/text_field.dart';

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

    await ShowDialog.show(
      context,
      title: "Rename Image",
      primaryButtonText: "Save",
      content: CommonTextField(
        hintText: "Enter new name",
        controller: nameController,
        autoFocus: true,
      ),
      onPrimaryPressed: () async {
        if (nameController.text.isNotEmpty) {
          await ImageService().renameImage(
            image.id,
            nameController.text.trim(),
          );
          onSuccess();
          if (context.mounted) Navigator.pop(context);
        }
      },
    );
  }

  static Future<void> deleteImage(
    BuildContext context,
    ImageModel image,
    VoidCallback onSuccess,
  ) async {
    await ShowDialog.show(
      context,
      title: "Delete Image?",
      description: "This action cannot be undone.",
      primaryButtonText: "Delete",
      isDestructive: true,
      onPrimaryPressed: () async {
        await ImageService().deleteImage(image.id);
        onSuccess();
        if (context.mounted) Navigator.pop(context);
      },
    );
  }
}
