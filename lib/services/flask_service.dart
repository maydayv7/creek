import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class FlaskService {
  // Existing base URL config
  static const String _serverUrl = 'https://locustlike-trieciously-rudolph.ngrok-free.dev/generate';

  /// Generates a new image from text (Text-to-Image)
  Future<String?> generateAndSaveImage(String prompt) async {
    // ... (Your existing code here) ...
    // For brevity, I am not repeating the existing function, 
    // but I will use the same saving logic below.
    try {
      debugPrint("🎨 Sending prompt to server: '$prompt'...");

      final response = await http.post(
        Uri.parse(_serverUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'prompt': prompt}),
      );

      return _handleResponse(response, prompt);
    } catch (e) {
      debugPrint("❌ Error generating image: $e");
      return null;
    }
  }

  // ---------------------------------------------------------
  // NEW SERVICE: INPAINTING
  // ---------------------------------------------------------

  /// Takes file paths for the original image and the mask, plus a prompt.
  /// Returns the path of the saved result.
  Future<String?> inpaintImage({
    required String imagePath,
    required String maskPath,
    required String prompt,
  }) async {
    try {
      // 1. Derive the Inpainting URL from the base URL
      // Replaces '/generate' with '/inpainting'
      final String inpaintingUrl = _serverUrl.replaceFirst('/generate', '/inpainting');
      
      debugPrint("🖌️ Preparing inpainting request...");
      debugPrint("   Image: $imagePath");
      debugPrint("   Mask:  $maskPath");

      // 2. Verify files exist
      final File originalFile = File(imagePath);
      final File maskFile = File(maskPath);

      if (!originalFile.existsSync() || !maskFile.existsSync()) {
        debugPrint("❌ Error: Image or Mask file does not exist.");
        return null;
      }

      // 3. Convert Images to Base64 Strings
      // .readAsBytes() returns Uint8List, which base64Encode accepts
      final String base64Image = base64Encode(await originalFile.readAsBytes());
      final String base64Mask = base64Encode(await maskFile.readAsBytes());

      // 4. Construct Payload
      final Map<String, dynamic> requestBody = {
        "prompt": prompt,
        "negative_prompt": "blurry, bad quality, low res, ugly", // Good default
        "image": base64Image,
        "mask_image": base64Mask,
      };

      // 5. Send Request
      debugPrint("🚀 Sending to: $inpaintingUrl");
      final response = await http.post(
        Uri.parse(inpaintingUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      // 6. Reuse response handling logic
      return _handleResponse(response, "inpaint_${prompt}");

    } catch (e) {
      debugPrint("❌ Error during inpainting: $e");
      return null;
    }
  }

  // ---------------------------------------------------------
  // HELPER: Handles parsing and saving (Used by both functions)
  // ---------------------------------------------------------
  Future<String?> _handleResponse(http.Response response, String promptPrefix) async {
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      if (data['image'] != null) {
        final String base64String = data['image'];
        final Uint8List imageBytes = base64Decode(base64String);

        // Get Directory
        final directory = await getApplicationDocumentsDirectory();
        final imagesDir = Directory('${directory.path}/generated_images');
        if (!await imagesDir.exists()) {
          await imagesDir.create(recursive: true);
        }

        // Generate Filename
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        // Clean the prompt for filename
        final safePrompt = promptPrefix
            .replaceAll(RegExp(r'[^\w\s]'), '')
            .trim()
            .replaceAll(' ', '_');
        
        final shortPrompt = safePrompt.length > 20 ? safePrompt.substring(0, 20) : safePrompt;
        final String filePath = '${imagesDir.path}/${shortPrompt}_$timestamp.png';
        
        // Save
        final File file = File(filePath);
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
  }
}