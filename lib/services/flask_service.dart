import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class FlaskService {
  // ===========================================================================
  // CONFIGURATION
  // ===========================================================================
  
  static const String _serverUrl = 'https://locustlike-trieciously-rudolph.ngrok-free.dev';
  static const Map<String, String> _headers = {'Content-Type': 'application/json'};

  // ===========================================================================
  // 1. PIPELINES (Complex workflows)
  // ===========================================================================

  /// [Sketch-to-Image Pipeline]
  /// 1. Analyzes the sketch to get a text description.
  /// 2. Combines User Prompt + Sketch Description + Style Prompt.
  /// 3. Generates a new image based on this global prompt.
  Future<String?> sketchToImage({
    required String sketchPath,
    required String userPrompt,
    required String stylePrompt,
  }) async {
    debugPrint("🔗 [Pipeline] Starting Sketch-to-Image...");

    // Step 1: Get the description of the sketch
    // We use a specific prompt to ensure we get structural details
    final String? sketchDescription = await describeImage(
      imagePath: sketchPath, 
      prompt: '<MORE_DETAILED_CAPTION>'
    );

    if (sketchDescription == null) {
      debugPrint("❌ [Pipeline] Failed: Could not analyze sketch.");
      return null;
    }

    // Step 2: Construct the Global Prompt
    // Strategy: Style + User Intent + Content context
    final String globalPrompt = 
        "$stylePrompt. $userPrompt. The image features: $sketchDescription";

    debugPrint("🔗 [Pipeline] Generated Global Prompt: \n$globalPrompt");

    // Step 3: Generate the final image
    return generateAndSaveImage(globalPrompt);
  }

  // ===========================================================================
  // 2. GENERATION SERVICES (Returns File Path)
  // ===========================================================================

  /// [Text-to-Image]
  Future<String?> generateAndSaveImage(String prompt) async {
    return _performImageOperation(
      endpoint: '/generate',
      logPrefix: '🎨 Text-to-Image',
      body: {'prompt': prompt},
      filenamePrefix: prompt,
    );
  }

  /// [Inpainting]
  Future<String?> inpaintImage({
    required String imagePath,
    required String maskPath,
    required String prompt,
  }) async {
    final String? base64Image = await _encodeFile(imagePath);
    final String? base64Mask = await _encodeFile(maskPath);

    if (base64Image == null || base64Mask == null) return null;

    return _performImageOperation(
      endpoint: '/inpainting',
      logPrefix: '🖌️ Inpainting',
      body: {
        'prompt': prompt,
        'negative_prompt': 'blurry, bad quality, low res, ugly',
        'image': base64Image,
        'mask_image': base64Mask,
      },
      filenamePrefix: 'inpaint_$prompt',
    );
  }

  /// [Background Removal]
  Future<String?> generateAsset({required String imagePath}) async {
    final String? base64Image = await _encodeFile(imagePath);
    if (base64Image == null) return null;

    return _performImageOperation(
      endpoint: '/remove-background',
      logPrefix: '✂️ Asset Gen',
      body: {'image': base64Image},
      filenamePrefix: 'asset',
    );
  }

  // ===========================================================================
  // 3. ANALYSIS SERVICES (Returns String)
  // ===========================================================================

  /// [Image Captioning]
  Future<String?> describeImage({
    required String imagePath,
    String prompt = '<MORE_DETAILED_CAPTION>',
  }) async {
    debugPrint("👁️ [Describe] Preparing request...");
    
    final String? base64Image = await _encodeFile(imagePath);
    if (base64Image == null) return null;

    final response = await _postRequest(
      endpoint: '/describe',
      body: {
        'image': base64Image,
        'prompt': prompt,
      },
    );

    if (response != null && response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['caption'] != null) {
        debugPrint("✅ [Describe] Success: ${data['caption']}");
        return data['caption'];
      }
    }

    debugPrint("❌ [Describe] Failed.");
    return null;
  }

  // ===========================================================================
  // PRIVATE HELPERS
  // ===========================================================================

  Future<String?> _performImageOperation({
    required String endpoint,
    required String logPrefix,
    required Map<String, dynamic> body,
    required String filenamePrefix,
  }) async {
    debugPrint("$logPrefix Sending request to $endpoint...");

    final response = await _postRequest(endpoint: endpoint, body: body);

    if (response != null && response.statusCode == 200) {
      return _saveImageFromResponse(response, filenamePrefix);
    }
    
    debugPrint("❌ $logPrefix Failed: ${response?.statusCode ?? 'No Connection'}");
    return null;
  }

  Future<http.Response?> _postRequest({
    required String endpoint,
    required Map<String, dynamic> body,
  }) async {
    try {
      return await http.post(
        Uri.parse("$_serverUrl$endpoint"),
        headers: _headers,
        body: jsonEncode(body),
      );
    } catch (e) {
      debugPrint("❌ Network Error ($endpoint): $e");
      return null;
    }
  }

  Future<String?> _encodeFile(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      debugPrint("❌ File not found: $path");
      return null;
    }
    return base64Encode(await file.readAsBytes());
  }

  Future<String?> _saveImageFromResponse(http.Response response, String prefix) async {
    try {
      final data = jsonDecode(response.body);
      if (data['image'] == null) return null;

      final Uint8List imageBytes = base64Decode(data['image']);
      
      final directory = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${directory.path}/generated_images');
      if (!await imagesDir.exists()) await imagesDir.create(recursive: true);

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final safePrefix = prefix.replaceAll(RegExp(r'[^\w\s]'), '').trim().replaceAll(' ', '_');
      final shortPrefix = safePrefix.length > 20 ? safePrefix.substring(0, 20) : safePrefix;
      final String filePath = '${imagesDir.path}/${shortPrefix}_$timestamp.png';

      await File(filePath).writeAsBytes(imageBytes);
      debugPrint("✅ Image saved: $filePath");
      return filePath;
    } catch (e) {
      debugPrint("❌ Error saving image: $e");
      return null;
    }
  }
}
