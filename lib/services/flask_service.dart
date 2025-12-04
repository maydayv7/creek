import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:creekui/data/repos/project_repo.dart';
import 'package:creekui/data/repos/image_repo.dart';
import 'package:creekui/data/repos/note_repo.dart';
import 'package:creekui/data/repos/file_repo.dart';
import 'package:creekui/services/python_service.dart';

class FlaskService {
  // ===========================================================================
  // CONFIGURATION
  // ===========================================================================

  static String get _urlGenerate => dotenv.env['URL_GENERATE'] ?? '';
  static String get _urlInpainting => dotenv.env['URL_INPAINTING'] ?? '';
  static String get _urlInpaintingApi => dotenv.env['URL_INPAINTING_API'] ?? '';
  static String get _urlSketchApi => dotenv.env['URL_SKETCH_API'] ?? '';
  static String get _urlAsset => dotenv.env['URL_ASSET'] ?? '';
  static String get _urlDescribe => dotenv.env['URL_DESCRIBE'] ?? '';

  static const Map<String, String> _headers = {
    'Content-Type': 'application/json',
  };

  // --- OPTIMIZATION: Instantiate Repos once ---
  final _imageRepo = ImageRepo();
  final _noteRepo = NoteRepo();
  final _projectRepo = ProjectRepo();
  final _fileRepo = FileRepo();
  final _pythonService = PythonService();

  // ===========================================================================
  // 1. PIPELINES (Complex workflows)
  // ===========================================================================

  /// [Sketch-to-Image Pipeline]
  Future<String?> sketchToImage({
    required int projectId,
    required String sketchPath,
    required String userPrompt,
    String? imageDescription,
  }) async {
    debugPrint("🔗 [Pipeline] Starting Sketch-to-Image...");

    // 1. Analyze Sketch (Use cached description if available)
    final String? sketchDescription = imageDescription ?? await describeImage(
      imagePath: sketchPath,
      prompt: '<MORE_DETAILED_CAPTION>',
    );

    if (sketchDescription == null) {
      debugPrint("❌ [Pipeline] Failed: Could not analyze sketch.");
      return null;
    }

    // 2. Fetch Stylesheet & Construct Prompt
    final project = await _projectRepo.getProjectById(projectId);
    final String stylesheetJson = project?.globalStylesheet ?? "{}";

    // --- DEBUG LOGS ---
    debugPrint("🐛 [DEBUG] 1. User Prompt: $userPrompt");
    debugPrint("🐛 [DEBUG] 2. Image Caption: $sketchDescription");
    await _logToFile("debug_stylesheet.json", stylesheetJson);

    debugPrint("🔗 [Pipeline] Generating magic prompt from stylesheet...");

    final String? magicPrompt = await _pythonService.generateMagicPrompt(
      stylesheetJson: stylesheetJson,
      caption: sketchDescription,
      userPrompt: userPrompt,
    );

    if (magicPrompt != null) {
        await _logToFile("debug_magic_prompt.txt", magicPrompt);
        debugPrint("🐛 [DEBUG] 4. Magic Prompt: $magicPrompt");
    } else {
        debugPrint("🐛 [DEBUG] 4. Magic Prompt: null");
    }

    final String globalPrompt = magicPrompt ?? "$userPrompt. The image features: $sketchDescription";

    debugPrint("🔗 [Pipeline] Generating base image...");

    final String? generatedImagePath = await generateAndSaveImage(globalPrompt);

    if (generatedImagePath == null) {
      debugPrint("❌ [Pipeline] Failed: Image generation returned null.");
      return null;
    }

    return generatedImagePath;
  }

  // ===========================================================================
  // 2. GENERATION SERVICES (Returns File Path)
  // ===========================================================================

  /// [Text-to-Image]
  Future<String?> generateAndSaveImage(String prompt) async {
    return _performImageOperation(
      fullUrl: _urlGenerate,
      logPrefix: '🎨 Text-to-Image',
      body: {'prompt': prompt},
      filenamePrefix: 'gen',
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
      fullUrl: _urlInpainting,
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

  /// [Inpainting-API]
  Future<String?> inpaintApiImage({
    required String imagePath,
    required String maskPath,
    required String prompt,
  }) async {
    final String? base64Image = await _encodeFile(imagePath);
    final String? base64Mask = await _encodeFile(maskPath);

    if (base64Image == null || base64Mask == null) return null;

    return _performImageOperation(
      fullUrl: _urlInpaintingApi,
      logPrefix: '🖌️ Inpainting',
      body: {
        'prompt': prompt,
        'negative_prompt': 'blurry, bad quality, low res, ugly',
        'image': base64Image,
        'mask_image': base64Mask,
      },
      filenamePrefix: 'inpaint_api$prompt',
    );
  }

  /// [Sketch-to-Image-API]
  Future<String?> sketchToImageAPI({
    required int projectId,
    required String sketchPath,
    required String userPrompt,
    required int option,
    String? imageDescription,
  }) async {
    debugPrint("🔗 [Pipeline] Starting Sketch-to-Image-API...");

    // 1. Analyze Sketch (Use cached description if available)
    final String? sketchDescription = imageDescription ?? await describeImage(
      imagePath: sketchPath,
      prompt: '<MORE_DETAILED_CAPTION>',
    );

    if (sketchDescription == null) {
      debugPrint("❌ [Pipeline] Failed: Could not analyze sketch.");
      return null;
    }

    // 2. Fetch Stylesheet & Construct Prompt
    final project = await _projectRepo.getProjectById(projectId);
    final String stylesheetJson = project?.globalStylesheet ?? "{}";

    // --- DEBUG LOGS ---
    debugPrint("🐛 [DEBUG] 1. User Prompt: $userPrompt");
    debugPrint("🐛 [DEBUG] 2. Image Caption: $sketchDescription");
    await _logToFile("debug_stylesheet.json", stylesheetJson);

    debugPrint("🔗 [Pipeline] Generating magic prompt from stylesheet...");

    final String? magicPrompt = await _pythonService.generateMagicPrompt(
      stylesheetJson: stylesheetJson,
      caption: sketchDescription,
      userPrompt: userPrompt,
    );

    debugPrint("🐛 [DEBUG] 4. Magic Prompt: ${magicPrompt != null ? '(See debug_magic_prompt.txt)' : 'null'}");
    if(magicPrompt != null) await _logToFile("debug_magic_prompt.txt", magicPrompt);

    final String globalPrompt = magicPrompt ?? "$userPrompt. The image features: $sketchDescription";

    debugPrint("🔗 [Pipeline] Generating base image...");

    final String? generatedImagePath = await _performImageOperation(
      fullUrl: _urlSketchApi,
      logPrefix: '🖌️ Inpainting',
      body: {
        'prompt': globalPrompt,
        'option': option,
      },
      filenamePrefix: 'sketch-to-image-api_$globalPrompt',
    );

    if (generatedImagePath == null) {
      debugPrint("❌ [Pipeline] Failed: Image generation returned null.");
      return null;
    }

    return generatedImagePath;
  }

  /// [Background Removal]
  Future<String?> generateAsset({required String imagePath}) async {
    // 1. Prepare and Upload
    final String? base64Image = await _encodeFile(imagePath);
    if (base64Image == null) return null;

    final String? generatedAssetPath = await _performImageOperation(
      fullUrl: _urlAsset,
      logPrefix: '✂️ Asset Gen',
      body: {'image': base64Image},
      filenamePrefix: 'asset',
    );

    // 2. Resolve Project ID and Save
    if (generatedAssetPath != null) {
      int? projectId;

      // --- CHECK 1: Is this a Main Image? ---
      final imageModel = await _imageRepo.getByFilePath(imagePath);
      if (imageModel != null) {
        projectId = imageModel.projectId;
      }

      // --- CHECK 2: Is this a Note Crop? ---
      if (projectId == null) {
        // You need a method in NoteRepo to find a note by its crop path
        final noteModel = await _noteRepo.getByCropPath(imagePath);

        if (noteModel != null) {
          // Traverse up: Note -> Parent Image -> Project
          final parentImage = await _imageRepo.getById(noteModel.imageId);
          if (parentImage != null) {
            projectId = parentImage.projectId;
            debugPrint("🔗 Linked Asset to Project via Note: ${noteModel.id}");
          }
        }
      }

      // --- CHECK 3: Is this a generic File? ---
      if (projectId == null) {
        final fileModel = await _fileRepo.getByFilePath(imagePath);
        if (fileModel != null) {
          projectId = fileModel.projectId;
        }
      }

      // 3. Update the Project
      if (projectId != null) {
        final project = await _projectRepo.getProjectById(projectId);
        if (project != null) {
          project.assetsPath.add(generatedAssetPath);
          await _projectRepo.updateAssets(projectId, project.assetsPath);
          debugPrint("✅ Asset path saved to Project DB: $generatedAssetPath");
        }
      } else {
        debugPrint("⚠️ Asset generated but could not link to a Project ID.");
      }
    }

    return generatedAssetPath;
  }

  // ===========================================================================
  // 3. ANALYSIS SERVICES
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
      fullUrl: _urlDescribe,
      body: {'image': base64Image, 'prompt': prompt},
    );

    if (response != null && response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['output'] != null) {
        debugPrint("✅ [Describe] Success: ${data['output']}");
        return data['output'];
      }
    }

    debugPrint("❌ [Describe] Failed.");
    return null;
  }

  // ===========================================================================
  // PRIVATE HELPERS
  // ===========================================================================

  // LOG TO FILE HELPER
  // Use following command to see logs:
  // adb -d shell "run-as com.creek.ui cat /data/user/0/com.creek.ui/app_flutter/debug_magic_prompt.txt"
  Future<void> _logToFile(String filename, String content) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsString(content);
      debugPrint("📄 [LOG] Saved full content to: ${file.path}");
    } catch (e) {
      debugPrint("❌ Failed to log to file: $e");
    }
  }

  Future<String?> _performImageOperation({
    required String fullUrl,
    required String logPrefix,
    required Map<String, dynamic> body,
    required String filenamePrefix,
  }) async {
    debugPrint("$logPrefix Sending request to $fullUrl...");

    final response = await _postRequest(fullUrl: fullUrl, body: body);

    if (response != null && response.statusCode == 200) {
      return _saveImageFromResponse(response, filenamePrefix);
    }

    debugPrint(
      "❌ $logPrefix Failed: ${response?.statusCode ?? 'No Connection'}",
    );
    return null;
  }

  Future<http.Response?> _postRequest({
    required String fullUrl,
    required Map<String, dynamic> body,
  }) async {
    try {
      if (fullUrl.isEmpty) {
        debugPrint("❌ Config Error: URL is missing in .env");
        return null;
      }
      return await http.post(
        Uri.parse(fullUrl),
        headers: _headers,
        body: jsonEncode(body),
      );
    } catch (e) {
      debugPrint("❌ Network Error ($fullUrl): $e");
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

  Future<String?> _saveImageFromResponse(
    http.Response response,
    String prefix,
  ) async {
    try {
      final data = jsonDecode(response.body);
      if (data['image'] == null) return null;

      final Uint8List imageBytes = base64Decode(data['image']);

      final directory = await getApplicationDocumentsDirectory();
      final imagesDirPath = p.join(directory.path, 'generated_images');
      final imagesDir = Directory(imagesDirPath);

      if (!await imagesDir.exists()) await imagesDir.create(recursive: true);

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final safePrefix = prefix
          .replaceAll(RegExp(r'[^\w\s]'), '')
          .trim()
          .replaceAll(' ', '_');
      final shortPrefix =
          safePrefix.length > 20 ? safePrefix.substring(0, 20) : safePrefix;

      final String filePath = p.join(
        imagesDir.path,
        '${shortPrefix}_$timestamp.png',
      );

      await File(filePath).writeAsBytes(imageBytes);
      debugPrint("✅ Image saved: $filePath");
      return filePath;
    } catch (e) {
      debugPrint("❌ Error saving image: $e");
      return null;
    }
  }
}
