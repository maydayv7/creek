import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/image_service.dart';

class ImagePickerPage extends StatelessWidget {
  ImagePickerPage({super.key});
  final picker = ImagePicker();
  final service = ImageService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Pick Image")),
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            final picked = await picker.pickImage(source: ImageSource.gallery);

            if (picked != null) {
              await service.saveImage(File(picked.path));
            }
            
            if (!context.mounted) return;
            Navigator.pop(context);
          },
          child: Text("Pick From Gallery"),
        ),
      ),
    );
  }
}
