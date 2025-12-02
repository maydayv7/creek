import 'dart:convert';
import 'dart:io';
import 'package:adobe/data/repos/file_repo.dart';
import 'package:adobe/data/repos/image_repo.dart';
import 'package:adobe/data/repos/note_repo.dart';
import 'package:adobe/data/repos/project_repo.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

    // 1. Analyze Sketch
    final String? sketchDescription = await describeImage(
      imagePath: sketchPath,
      prompt: '<MORE_DETAILED_CAPTION>',
    );

    if (sketchDescription == null) {
      debugPrint("❌ [Pipeline] Failed: Could not analyze sketch.");
      return null;
    }

    // 2. Construct Prompt & Generate
    final String globalPrompt =
        "$stylePrompt. $userPrompt. The image features: $sketchDescription";

    debugPrint("🔗 [Pipeline] Generating base image...");

    final String? generatedImagePath = await generateAndSaveImage(globalPrompt);

    if (generatedImagePath == null) {
      debugPrint("❌ [Pipeline] Failed: Image generation returned null.");
      return null;
    }

    // 3. Remove Background (Pipeline Extension)
    debugPrint("🔗 [Pipeline] Removing background from generated result...");

    // This returns the path to the no-background version
    return generateAsset(imagePath: generatedImagePath);
  }

  // ===========================================================================
  // 1.5. STYLE PROMPT GENERATION (From Stylesheet - New Feature)
  // ===========================================================================

  /// Generates a style prompt from a stylesheet JSON following the notebook logic.
  /// Returns a formatted style instruction string or a default fallback.
  String generateStylePromptFromStylesheet(String? stylesheetJson) {
    if (stylesheetJson == null || stylesheetJson.isEmpty) {
      return "high quality, realistic";
    }

    try {
      // Parse the JSON
      Map<String, dynamic> sheet = jsonDecode(stylesheetJson);

      // Normalize: extract from "results" if present
      Map<String, dynamic> results =
          sheet.containsKey('results') ? sheet['results'] as Map<String, dynamic> : sheet;

      // Normalize the sheet structure
      Map<String, Map<String, dynamic>> normalized = _normalizeStylesheet(results);

      // Extract style phrases
      List<String> stylePhrases = _pickStylePhrases(normalized);

      // Extract top colors
      List<String> topColors = _extractTopColors(results);

      // Build style instruction
      String styleInstruction = "";
      if (stylePhrases.isNotEmpty) {
        styleInstruction =
            "User prefers these style cues (use as inspiration): ${stylePhrases.join('; ')}";
      }
      if (topColors.isNotEmpty) {
        String colorStr = topColors.join(", ");
        if (styleInstruction.isNotEmpty) {
          styleInstruction += "; color palette: $colorStr";
        } else {
          styleInstruction = "color palette: $colorStr";
        }
      }

      // Get tone hint from primary style
      String primaryStyle = "";
      if (normalized.containsKey('Style')) {
        dynamic primary = normalized['Style']!['Primary'];
        primaryStyle =
            primary is String ? primary : (primary is List && primary.isNotEmpty ? primary[0] : "");
      }
      String toneHint = _styleToTone(primaryStyle);

      // Combine everything
      List<String> parts = [];
      if (styleInstruction.isNotEmpty) {
        parts.add(styleInstruction);
      }
      parts.add("Tone: $toneHint");

      return parts.join(". ");
    } catch (e) {
      debugPrint("❌ Error generating style prompt: $e");
      return "high quality, realistic";
    }
  }

  /// Normalizes the stylesheet structure into a consistent format
  Map<String, Map<String, dynamic>> _normalizeStylesheet(Map<String, dynamic> results) {
    Map<String, Map<String, dynamic>> normalized = {};

    // Categories to extract
    List<String> categories = [
      "Style",
      "Background/Texture",
      "Lighting",
      "Composition",
      "Era/Cultural Reference",
      "Material Look",
      "Typography",
    ];

    // Also check for variations
    Map<String, List<String>> categoryAliases = {
      "Style": ["style", "Style"],
      "Background/Texture": [
        "Background/Texture",
        "background/texture",
        "Texture",
        "texture",
        "Background",
        "background"
      ],
      "Lighting": ["Lighting", "lighting"],
      "Composition": ["Composition", "composition", "Compositions", "compositions"],
      "Era/Cultural Reference": ["Era/Cultural Reference", "era / reference", "Era", "era"],
      "Material Look": ["Material Look", "material look", "Material look"],
      "Typography": ["Typography", "typography", "Fonts", "fonts"],
    };

    for (String category in categories) {
      List<String> labels = [];
      List<String> aliases = categoryAliases[category] ?? [category];

      // Find the category in results
      dynamic categoryData;
      for (String alias in aliases) {
        if (results.containsKey(alias)) {
          categoryData = results[alias];
          break;
        }
      }

      if (categoryData == null) continue;

      // Extract labels from the category data
      List<dynamic> items = [];
      if (categoryData is List) {
        items = categoryData;
      } else if (categoryData is Map && categoryData.containsKey('scores')) {
        items = categoryData['scores'] is List ? categoryData['scores'] : [];
      }

      // Sort by score if available
      try {
        items.sort((a, b) {
          double scoreA = 0.0, scoreB = 0.0;
          if (a is Map) scoreA = (a['score'] ?? 0.0).toDouble();
          if (b is Map) scoreB = (b['score'] ?? 0.0).toDouble();
          return scoreB.compareTo(scoreA);
        });
      } catch (_) {}

      // Extract labels
      for (var item in items) {
        String? label;
        if (item is Map) {
          label = item['label']?.toString();
        } else if (item is String) {
          label = item;
        }
        if (label != null && label.isNotEmpty) {
          labels.add(label.trim());
        }
      }

      if (labels.isNotEmpty) {
        normalized[category] = {
          'Primary': labels.first,
          'Secondary': labels.length > 1 ? labels.sublist(1) : [],
        };
      }
    }

    return normalized;
  }

  /// Picks style phrases from normalized stylesheet (following notebook logic)
  List<String> _pickStylePhrases(Map<String, Map<String, dynamic>> normalized,
      {int maxSecondaries = 3}) {
    Map<String, String> keyMap = {
      "Style": "style",
      "Background/Texture": "background/texture",
      "Lighting": "lighting",
      "Composition": "composition",
      "Era/Cultural Reference": "era / reference",
      "Material Look": "material look",
      "Typography": "typography",
    };

    List<String> phrases = [];

    for (String category in normalized.keys) {
      Map<String, dynamic>? entry = normalized[category];
      if (entry == null) continue;

      dynamic primaryValue = entry['Primary'];
      List<String> primary =
          primaryValue is String ? [primaryValue] : (primaryValue is List ? List<String>.from(primaryValue) : []);
      List<String> secondary = entry['Secondary'] ?? [];

      List<String> chosen = [];
      if (primary.isNotEmpty) {
        chosen.addAll(primary);
      }
      for (String s in secondary) {
        if (chosen.length < (1 + maxSecondaries)) {
          chosen.add(s);
        }
      }

      if (chosen.isNotEmpty) {
        String key = keyMap[category] ?? category.toLowerCase();
        phrases.add("$key: ${chosen.join(', ')}");
      }
    }

    return phrases;
  }

  /// Extracts top colors from stylesheet
  List<String> _extractTopColors(Map<String, dynamic> results, {int maxColors = 5}) {
    dynamic palette = results['Color Palette'] ??
        results['Colour Palette'] ??
        results['colors'] ??
        results['Colors'];

    if (palette == null) return [];

    List<dynamic> paletteList = [];
    if (palette is List) {
      paletteList = palette;
    } else if (palette is Map && palette.containsKey('scores')) {
      paletteList = palette['scores'] is List ? palette['scores'] : [];
    }

    // Sort by score
    try {
      paletteList.sort((a, b) {
        double scoreA = 0.0, scoreB = 0.0;
        if (a is Map) scoreA = (a['score'] ?? 0.0).toDouble();
        if (b is Map) scoreB = (b['score'] ?? 0.0).toDouble();
        return scoreB.compareTo(scoreA);
      });
    } catch (_) {}

    List<String> colors = [];
    for (var item in paletteList) {
      String? label;
      if (item is Map) {
        label = item['label']?.toString();
      } else if (item is String) {
        label = item;
      }
      if (label != null && label.isNotEmpty) {
        colors.add(label.trim());
        if (colors.length >= maxColors) break;
      }
    }

    return colors;
  }

  /// Determines tone hint from primary style
  String _styleToTone(String primary) {
    String s = primary.toLowerCase();
    if (s.contains("retro") ||
        s.contains("collage") ||
        s.contains("poster") ||
        s.contains("pop-art") ||
        s.contains("surreal")) {
      return "illustrative, textured, poster-like";
    }
    if (s.contains("photoreal") || s.contains("realistic") || s.contains("film")) {
      return "photorealistic, high-detail";
    }
    return "high detail, sharp focus";
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
    required String sketchPath,
    required String userPrompt,
    required String stylePrompt,
    required int option,
  }) async {
    debugPrint("🔗 [Pipeline] Starting Sketch-to-Image-API...");

    // 1. Analyze Sketch
    final String? sketchDescription = await describeImage(
      imagePath: sketchPath,
      prompt: '<MORE_DETAILED_CAPTION>',
    );

    if (sketchDescription == null) {
      debugPrint("❌ [Pipeline] Failed: Could not analyze sketch.");
      return null;
    }

    // 2. Construct Prompt & Generate
    final String globalPrompt =
        " $userPrompt.$stylePrompt. The image features: $sketchDescription";

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

    // 3. Remove Background (Pipeline Extension)
    debugPrint("🔗 [Pipeline] Removing background from generated result...");

    // This returns the path to the no-background version
    return generateAsset(imagePath: generatedImagePath);



    

  }



  /// [Background Removal]
  Future<String?> generateAsset({required String imagePath}) async {
    // 1. Prepare and Upload
    final String? base64Image = await _encodeFile(imagePath);
    if (base64Image == null) return null;

    final String? generatedAssetPath = await _performImageOperation(
      endpoint: '/asset',
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
  // 3. ANALYSIS SERVICES (Returns String)
  // ===========================================================================

  /// [Image Captioning]
  Future<String?> describeImage({
    required String imagePath,
    String prompt = '<MORE_DETAILED_CAPTION>',
  }) async {
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

  Future<String?> _performImageOperation({
    String? endpoint,
    String? fullUrl,
    required String logPrefix,
    required Map<String, dynamic> body,
    required String filenamePrefix,
  }) async {
    String url;
    if (fullUrl != null) {
      url = fullUrl;
    } else if (endpoint != null) {
      // Map endpoints to their corresponding URL getters
      switch (endpoint) {
        case '/generate':
          url = _urlGenerate;
          break;
        case '/inpainting':
          url = _urlInpainting;
          break;
        case '/asset':
          url = _urlAsset;
          break;
        case '/describe':
          url = _urlDescribe;
          break;
        default:
          url = '';
      }
    } else {
      return null;
    }

    if (url.isEmpty) {
      return null;
    }

    final response = await _postRequest(fullUrl: url, body: body);

    if (response != null && response.statusCode == 200) {
      return _saveImageFromResponse(response, filenamePrefix);
    }

    return null;
  }

  Future<http.Response?> _postRequest({
    required String fullUrl,
    required Map<String, dynamic> body,
  }) async {
    try {
      if (fullUrl.isEmpty) {
        return null;
      }
      return await http.post(
        Uri.parse(fullUrl),
        headers: _headers,
        body: jsonEncode(body),
      );
    } catch (e) {
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
      // Use join for safe path construction
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

      // Use join here too
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