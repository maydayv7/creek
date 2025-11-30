import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class GenerateImageService {
  // Replace with your actual server URL.
  // Android Emulator: 'http://10.0.2.2:5000/generate'
  // iOS Simulator: 'http://127.0.0.1:5000/generate'
  // Physical Device: 'http://YOUR_PC_IP:5000/generate'
  static const String _serverUrl = 'http://10.0.2.2:5000/generate';

  /// Sends a prompt to the Flask server, decodes the Base64 image,
  /// saves it as a PNG, and returns the file path.
  Future<String?> generateAndSaveImage(String prompt) async {
    try {
      debugPrint("🎨 Sending prompt to server: '$prompt'...");

      // 1. Send POST request to Flask API
      final response = await http.post(
        Uri.parse(_serverUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'prompt': prompt}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['image'] != null) {
          final String base64String = data['image'];

          // 2. Decode Base64 string to bytes
          final Uint8List imageBytes = base64Decode(base64String);

          // 3. Get directory to save the file
          final directory = await getApplicationDocumentsDirectory();
          final imagesDir = Directory('${directory.path}/generated_images');
          if (!await imagesDir.exists()) {
            await imagesDir.create(recursive: true);
          }

          // 4. Generate unique filename
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          // Sanitize prompt for filename (remove special chars)
          final safePrompt = prompt.replaceAll(RegExp(r'[^\w\s]'), '').trim().replaceAll(' ', '_');
          // Limit filename length
          final shortPrompt = safePrompt.length > 20 ? safePrompt.substring(0, 20) : safePrompt;
          
          final String filePath = '${imagesDir.path}/${shortPrompt}_$timestamp.png';
          final File file = File(filePath);

          // 5. Save bytes to file
          await file.writeAsBytes(imageBytes);

          debugPrint("✅ Image saved successfully at: $filePath");
          return filePath;
        } else {
          debugPrint("❌ Server response missing 'image' field.");
          return null;
        }
      } else {
        debugPrint("❌ Server Error: ${response.statusCode} - ${response.body}");
        return null;
      }
    } catch (e) {
      debugPrint("❌ Error generating image: $e");
      return null;
    }
  }
}