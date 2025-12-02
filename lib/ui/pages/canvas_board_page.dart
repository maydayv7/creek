import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:undo/undo.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image/image.dart' as img;
import './canvas_toolbar/magic_draw_overlay.dart';
import './canvas_toolbar/text_tools_overlay.dart';
import '../../data/repos/project_repo.dart';
import '../../services/stylesheet_service.dart';
import 'project_file_page.dart';
import 'package:path/path.dart' as p;

import '../../services/file_service.dart';
import '../../data/models/file_model.dart';

import '../../services/flask_service.dart';

// --- MODELS WITH JSON SUPPORT ---

class DrawingPoint {
  final Offset offset;
  final Paint paint;
  const DrawingPoint({required this.offset, required this.paint});

  Map<String, dynamic> toMap() => {'dx': offset.dx, 'dy': offset.dy};

  factory DrawingPoint.fromMap(Map<String, dynamic> map) {
    return DrawingPoint(
      offset: Offset(map['dx'] ?? 0, map['dy'] ?? 0),
      paint: Paint(),
    );
  }
}

class DrawingPath {
  final List<DrawingPoint> points;
  final Color color;
  final double strokeWidth;
  final bool isEraser;

  DrawingPath({
    required this.points,
    required this.color,
    required this.strokeWidth,
    required this.isEraser,
  });

  Map<String, dynamic> toMap() {
    return {
      'points': points.map((p) => p.toMap()).toList(),
      'color': color.value,
      'strokeWidth': strokeWidth,
      'isEraser': isEraser,
    };
  }

  factory DrawingPath.fromMap(Map<String, dynamic> map) {
    return DrawingPath(
      points:
          (map['points'] as List).map((p) => DrawingPoint.fromMap(p)).toList(),
      color: Color(map['color']),
      strokeWidth: (map['strokeWidth'] as num).toDouble(),
      isEraser: map['isEraser'] ?? false,
    );
  }
}

// Helper to snapshot the entire canvas state for undo/redo
class CanvasState {
  final List<Map<String, dynamic>> elements;
  final List<DrawingPath> paths;
  CanvasState(this.elements, this.paths);
}

class CanvasBoardPage extends StatefulWidget {
  final int projectId;
  final double width;
  final double height;
  final File? initialImage;
  final FileModel? existingFile;
  final File? injectedMedia;

  const CanvasBoardPage({
    super.key,
    required this.projectId,
    required this.width,
    required this.height,
    this.initialImage,
    this.existingFile,
    this.injectedMedia,
  });

  @override
  State<CanvasBoardPage> createState() => _CanvasBoardPageState();
}

class _CanvasBoardPageState extends State<CanvasBoardPage> {
  // --- SERVICES ---
  final FileService _fileService = FileService();
  final ChangeStack _changeStack = ChangeStack();
  final ImagePicker _picker = ImagePicker();
  final ChangeStack _magicDrawChangeStack = ChangeStack();

  // --- STATE ---
  bool _hasUnsavedChanges = false;
  List<Map<String, dynamic>> elements = [];
  List<DrawingPath> _paths = []; // Keeps normal drawing strokes
  List<DrawingPath> _magicPaths = []; // Keeps temporary magic draw mask strokes

  // Snapshots for undo grouping
  CanvasState? _gestureStartSnapshot;

  // Detection Timer & AI Analysis
  Timer? _inactivityTimer;
  final GlobalKey _canvasGlobalKey = GlobalKey();
  String? _aiDescription;
  bool _isAnalyzing = false;
  bool _isDescriptionExpanded = false; // Track expansion state

  // Magic Draw / Inpainting State
  File? _tempBaseImage;
  bool _isInpainting = false;
  bool _isCapturingBase = false; // New flag to hide strokes during capture

  String? selectedId;
  late Size _canvasSize;
  List<Color> _brandColors = [];

  // --- TOOLS ---
  bool _isMagicDrawActive = false;
  bool _isTextToolsActive = false;

  bool _isMagicPanelDisabled = false;
  bool _isViewMode = false;

  // --- EDITING ---
  bool _isEditingText = false;
  final TextEditingController _textEditingController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();

  // --- DRAWING ---
  List<DrawingPoint> _currentPoints = [];
  Color _selectedColor = const Color(0xFFFF4081);
  double _strokeWidth = 10.0;
  bool _isEraser = false;
  final GlobalKey _drawingKey = GlobalKey();

  // --- VIEWPORT ---
  final TransformationController _transformationController =
      TransformationController();
  bool _hasInitializedView = false;

  @override
  void initState() {
    super.initState();
    _canvasSize = Size(widget.width, widget.height);
    _fetchBrandColors();

    if (widget.existingFile != null) {
      _loadCanvasFromFile();
    } else if (widget.initialImage != null) {
      elements.add({
        'id': 'bg_${DateTime.now().millisecondsSinceEpoch}',
        'type': 'file_image',
        'content': widget.initialImage!.path,
        'position': const Offset(0, 0),
        'size': Size(widget.width, widget.height),
        'rotation': 0.0,
      });
      _hasUnsavedChanges = true;
    }

    // Note: injectedMedia handling is done inside _loadCanvasFromFile to ensure
    // it happens after file content is loaded, avoiding race conditions.
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    _textEditingController.dispose();
    _textFocusNode.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  // Handle inactivity timer logic
  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(const Duration(seconds: 2), () {
      _analyzeCanvas();
    });
  }

  Future<bool> _confirmDiscardMagicDraw() async {
    if (_magicPaths.isEmpty) return true; // nothing drawn – no popup

    final result = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text("Discard Magic Draw?"),
            content: const Text(
              "Leaving Magic Draw will remove your sketch. Continue?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Stay"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Discard"),
              ),
            ],
          ),
    );

    return result == true;
  }

  Future<void> _analyzeCanvas() async {
    if (_isAnalyzing || _isInpainting) return; // Skip if busy
    setState(() => _isAnalyzing = true);

    try {
      debugPrint("🧠 [AI] Starting canvas analysis...");

      File? imageFile = await _captureCanvasToFile();
      if (imageFile == null) return;

      // Call the service
      final description = await FlaskService().describeImage(
        imagePath: imageFile.path,
      );

      debugPrint("🤖 [AI] Service Response: $description");

      if (description != null && mounted) {
        setState(() {
          _aiDescription = description;
          _isDescriptionExpanded =
              false; // Reset to collapsed on new description
        });
      }
    } catch (e) {
      debugPrint("❌ [AI] Analysis Failed: $e");
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  Future<File?> _captureCanvasToFile() async {
    try {
      RenderRepaintBoundary? boundary =
          _canvasGlobalKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return null;

      ui.Image image = await boundary.toImage(pixelRatio: 1.0);
      ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) return null;
      Uint8List pngBytes = byteData.buffer.asUint8List();

      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
        '${tempDir.path}/canvas_capture_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await tempFile.writeAsBytes(pngBytes);
      return tempFile;
    } catch (e) {
      debugPrint("Error capturing canvas: $e");
      return null;
    }
  }

  Future<void> _fetchBrandColors() async {
    try {
      final int? pId = widget.projectId;
      if (pId == null) return;

      final project = await ProjectRepo().getProjectById(pId);
      if (project != null && project.globalStylesheet != null) {
        final styleData = StylesheetService().parse(project.globalStylesheet);
        if (mounted && styleData.colors.isNotEmpty) {
          setState(() {
            _brandColors = styleData.colors;
          });
        }
      }
    } catch (e) {
      debugPrint("Error loading brand colors: $e");
    }
  }

  // --- UNDO/REDO ---
  // --- MAGIC DRAW UNDO/REDO (NEW) ---
  void _recordMagicChange(List<DrawingPath> oldMagicPaths) {
    final newMagicPaths = List<DrawingPath>.from(_magicPaths);
    _magicDrawChangeStack.add(
      Change(
        oldMagicPaths,
        () => setState(() => _magicPaths = List.from(newMagicPaths)), // Redo
        (val) => setState(() => _magicPaths = List.from(val)), // Undo
      ),
    );
  }

  void _recordChange(CanvasState oldState) {
    _resetInactivityTimer(); // Reset timer on undoable actions
    final newState = CanvasState(
      _deepCopyElements(elements),
      List.from(_paths),
    );

    _changeStack.add(
      Change(
        oldState,
        () {
          // REDO
          setState(() {
            elements = _deepCopyElements(newState.elements);
            _paths = List.from(newState.paths);
            _hasUnsavedChanges = true;
          });
        },
        (val) {
          // UNDO
          setState(() {
            elements = _deepCopyElements(val.elements);
            _paths = List.from(val.paths);
            _hasUnsavedChanges = true;
          });
        },
      ),
    );
    setState(() => _hasUnsavedChanges = true);
  }

  CanvasState _getCurrentState() {
    return CanvasState(_deepCopyElements(elements), List.from(_paths));
  }

  // --- ACTIONS ---

  void _toggleTextTools() {
    setState(() {
      _isTextToolsActive = !_isTextToolsActive;
      _isMagicDrawActive = false;
      if (!_isTextToolsActive) {
        _exitEditMode();
        selectedId = null;
      }
    });
  }

  void _addTextElement() {
    final oldState = _getCurrentState();
    final id = 'text_${DateTime.now().millisecondsSinceEpoch}';
    final double defaultFontSize = (_canvasSize.width / 25).clamp(24.0, 96.0);
    final initialPos = Offset(
      _canvasSize.width / 2 - 150,
      _canvasSize.height / 2 - 50,
    );

    final newElement = {
      'id': id,
      'type': 'text',
      'content': 'Double tap to edit',
      'position': initialPos,
      'size': Size(300, defaultFontSize * 2),
      'rotation': 0.0,
      'style_color': Colors.black.value,
      'style_fontSize': defaultFontSize,
    };

    setState(() {
      elements.add(newElement);
      // Bring to front
      elements.remove(newElement);
      elements.add(newElement);
      selectedId = id;
      _isTextToolsActive = true;
    });

    _recordChange(oldState);
    _enterEditMode(newElement);
  }

  void _enterEditMode(Map<String, dynamic> element) {
    setState(() {
      selectedId = element['id'];
      _isEditingText = true;
      _textEditingController.text = element['content'];
      _textEditingController.selection = TextSelection.fromPosition(
        TextPosition(offset: _textEditingController.text.length),
      );
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_textFocusNode.canRequestFocus) {
        _textFocusNode.requestFocus();
      }
    });
  }

  void _exitEditMode() {
    if (_isEditingText && selectedId != null) {
      final index = elements.indexWhere((e) => e['id'] == selectedId);
      if (index != -1) {
        if (elements[index]['content'] != _textEditingController.text) {
          final oldState = _getCurrentState();
          setState(() {
            elements[index]['content'] = _textEditingController.text;
            _isEditingText = false;
          });
          _recordChange(oldState);
        } else {
          setState(() => _isEditingText = false);
        }
      } else {
        setState(() => _isEditingText = false);
      }
      _textFocusNode.unfocus();
    }
  }

  void _updateSelectedTextProperty(String key, dynamic value) {
    if (selectedId == null) return;
    final index = elements.indexWhere((e) => e['id'] == selectedId);
    if (index == -1) return;

    final oldState = _getCurrentState();
    setState(() {
      elements[index][key] = value;
    });
    _recordChange(oldState);
  }

  void _deleteSelectedElement() {
    if (selectedId == null) return;
    final oldState = _getCurrentState();
    setState(() {
      elements.removeWhere((e) => e['id'] == selectedId);
      selectedId = null;
      _isEditingText = false;
      _isTextToolsActive = false;
    });
    _textFocusNode.unfocus();
    _recordChange(oldState);
  }

  void _handleGestureStart() {
    // Check if we need to capture a clean base image
    if (_isMagicDrawActive) {
      if (!_isInpainting && _tempBaseImage == null) {
        _ensureBaseImageCaptured();
      }
      return;
    }
    _gestureStartSnapshot = _getCurrentState();
  }

  // Captures the base image by temporarily hiding the magic strokes
  Future<void> _ensureBaseImageCaptured() async {
    if (_tempBaseImage != null) return;

    debugPrint("📸 [Magic Draw] Hiding strokes to capture clean base...");

    // 1. Hide strokes by updating state
    setState(() => _isCapturingBase = true);

    // 2. Wait for frame to render
    await Future.delayed(const Duration(milliseconds: 50));

    // 3. Capture
    try {
      _tempBaseImage = await _captureCanvasToFile();
      debugPrint("✅ [Magic Draw] Base image captured.");
    } catch (e) {
      debugPrint("❌ [Magic Draw] Failed to capture base: $e");
    } finally {
      // 4. Show strokes again
      if (mounted) setState(() => _isCapturingBase = false);
    }
  }

  void _handleElementUpdate(
    String id,
    Offset newPos,
    Size newSize,
    double newRotation,
  ) {
    _resetInactivityTimer(); // Reset timer while dragging/resizing
    final index = elements.indexWhere((e) => e['id'] == id);
    if (index == -1) return;

    setState(() {
      elements[index]['position'] = newPos;
      elements[index]['size'] = newSize;
      elements[index]['rotation'] = newRotation;
      _hasUnsavedChanges = true;
    });
  }

  void _handleGestureEnd() {
    if (_gestureStartSnapshot != null) {
      _recordChange(_gestureStartSnapshot!);
      _gestureStartSnapshot = null;
    }
  }

  Future<void> _exportProject() async {
    try {
      // 1. Show loading or feedback
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Generating image...")));

      // 2. Capture the Full Canvas using the global key
      final boundary =
          _canvasGlobalKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;

      // 3. Convert to Image (High pixel ratio for quality)
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (byteData == null) return;

      final Uint8List pngBytes = byteData.buffer.asUint8List();

      // 4. Convert PNG to JPG using 'image' package
      // We do this in a compute isolate ideally, but for simplicity here on main thread
      final img.Image? decodedImage = img.decodePng(pngBytes);

      if (decodedImage == null) {
        throw Exception("Failed to decode image");
      }

      // Encode to JPG (Quality 90)
      final Uint8List jpgBytes = img.encodeJpg(decodedImage, quality: 90);

      // 5. Save to Temporary File
      final directory = await getTemporaryDirectory();
      final String fileName =
          "export_${DateTime.now().millisecondsSinceEpoch}.jpg";
      final String filePath = '${directory.path}/$fileName';

      final File imgFile = File(filePath);
      await imgFile.writeAsBytes(jpgBytes);

      // 6. Trigger System Share/Save Dialog
      // This allows the user to "Save to Device", "Share to Instagram", etc.
      await Share.shareXFiles([
        XFile(filePath, mimeType: 'image/jpeg'),
      ], text: 'Check out my design created with Adobe Clone!');
    } catch (e) {
      debugPrint("Export Error: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Export failed: $e")));
    }
  }

  // ===========================================================================
  //  SAVE & LOAD LOGIC
  // ===========================================================================
  Future<void> _handleMagicDrawExit() async {
    // Use the helper method you already wrote: _confirmDiscardMagicDraw
    if (_magicPaths.isNotEmpty && !_isInpainting) {
      final confirm = await _confirmDiscardMagicDraw();
      if (confirm) {
        _saveAndCloseMagicDraw();
      }
      // If false, do nothing (stay)
    } else {
      _saveAndCloseMagicDraw();
    }
  }

  void _handleBackNavigation() {
    // If in magic draw mode, just close tool first
    if (_isMagicDrawActive) {
      _saveAndCloseMagicDraw();
      return;
    }

    if (!_hasUnsavedChanges && widget.existingFile != null) {
      Navigator.pop(context);
      return;
    }

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text("Save Changes?"),
            content: const Text(
              "Do you want to save your canvas before leaving?",
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context); // Leave page
                },
                child: const Text(
                  "Discard",
                  style: TextStyle(color: Colors.red),
                ),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(context); // Close dialog
                  await _saveCanvas(); // Save
                  // Note: The redirect logic is handled in _saveCanvas for new files.
                  // For existing files, we pop here.
                  if (mounted && widget.existingFile != null) {
                    Navigator.pop(context);
                  }
                },
                child: const Text("Save"),
              ),
            ],
          ),
    );
  }

  Future<String?> _showNameDialog() async {
    TextEditingController nameController = TextEditingController(
      text: "Untitled Canvas",
    );
    return showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text("Save Canvas"),
            content: TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: "Canvas Name",
                hintText: "Enter a name for your file",
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel"),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, nameController.text.trim()),
                child: const Text("Save"),
              ),
            ],
          ),
    );
  }

  // Helper to generate preview image
  Future<String?> _generatePreviewImage() async {
    try {
      final boundary =
          _canvasGlobalKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return null;

      // Capture image with lower pixel ratio for preview thumbnail
      final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (byteData == null) return null;
      final Uint8List pngBytes = byteData.buffer.asUint8List();

      final directory = await getApplicationDocumentsDirectory();
      final previewDir = Directory('${directory.path}/previews');
      if (!await previewDir.exists()) {
        await previewDir.create(recursive: true);
      }

      final String fileName =
          "preview_${DateTime.now().millisecondsSinceEpoch}.png";
      final String filePath = '${previewDir.path}/$fileName';

      final File imgFile = File(filePath);
      await imgFile.writeAsBytes(pngBytes);
      return filePath;
    } catch (e) {
      debugPrint("Error generating preview: $e");
      return null;
    }
  }

  Future<void> _saveCanvas() async {
    try {
      String fileName = "Canvas ${DateTime.now().toString().split(' ')[0]}";
      bool isNewFile = widget.existingFile == null;

      // 1. IF NEW FILE: Ask user for name
      if (isNewFile) {
        final userFileName = await _showNameDialog();
        if (userFileName == null || userFileName.isEmpty) return; // Cancelled
        fileName = userFileName;
      }

      // 2. Generate Preview
      final String? previewPath = await _generatePreviewImage();

      // 3. Serialize Elements AND Paths (Drawing) to JSON
      final jsonList = _elementsToJson(elements);
      final pathsJson = _paths.map((p) => p.toMap()).toList();

      final saveData = {
        'elements': jsonList,
        'paths': pathsJson,
        'width': _canvasSize.width, // Saving Width
        'height': _canvasSize.height, // Saving Height
        'preview_path': previewPath, // Saving Preview Path
      };
      final jsonString = jsonEncode(saveData);

      final directory = await getTemporaryDirectory();
      final tempFile = File(
        '${directory.path}/canvas_temp_${DateTime.now().millisecondsSinceEpoch}.json',
      );
      await tempFile.writeAsString(jsonString);

      if (widget.existingFile != null) {
        // Overwrite existing file
        final existingFile = File(widget.existingFile!.filePath);
        await existingFile.writeAsString(jsonString);
        await _fileService.openFile(widget.existingFile!.id);
      } else {
        // Save as new file
        await _fileService.saveFile(
          tempFile,
          widget.projectId,
          name: fileName,
          description: "Editable Canvas Board",
        );
      }

      if (await tempFile.exists()) await tempFile.delete();

      setState(() => _hasUnsavedChanges = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Canvas Saved Successfully")),
        );
        if (isNewFile) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ProjectFilePage(projectId: widget.projectId),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Save Error: $e");
    }
  }

  Future<void> _loadCanvasFromFile() async {
    try {
      final file = File(widget.existingFile!.filePath);
      if (await file.exists()) {
        final jsonString = await file.readAsString();
        final dynamic decoded = jsonDecode(jsonString);

        setState(() {
          if (decoded is Map && decoded.containsKey('elements')) {
            // New format with dimensions
            elements = _jsonToElements(decoded['elements']);
            if (decoded['paths'] != null) {
              _paths =
                  (decoded['paths'] as List)
                      .map((p) => DrawingPath.fromMap(p))
                      .toList();
            } else {
              _paths = [];
            }
            // [FIX] LOAD CANVAS DIMENSIONS & RESET VIEW INIT
            if (decoded['width'] != null && decoded['height'] != null) {
              _canvasSize = Size(
                (decoded['width'] as num).toDouble(),
                (decoded['height'] as num).toDouble(),
              );
              _hasInitializedView = false; // FORCE RE-CENTERING
            }
          } else if (decoded is List) {
            // Legacy support
            elements = _jsonToElements(decoded);
            _paths = [];
            _hasInitializedView = false;
          }
          _hasUnsavedChanges = false;
        });

        // Handle Injected Media (e.g. from Share)
        if (widget.injectedMedia != null) {
          final oldState = _getCurrentState();
          setState(() {
            final double imageWidth =
                _canvasSize.width * 0.4; // 40% of canvas width
            final double imageHeight =
                _canvasSize.height * 0.4; // 40% of canvas height
            final Offset centeredPosition = Offset(
              (_canvasSize.width - imageWidth) / 2,
              (_canvasSize.height - imageHeight) / 2,
            );
            elements.add({
              'id': 'shared_${DateTime.now().millisecondsSinceEpoch}',
              'type': 'file_image',
              'content': widget.injectedMedia!.path,
              'position': centeredPosition,
              'size': Size(imageWidth, imageHeight),
              'rotation': 0.0,
            });
          });
          _recordChange(oldState);
        }
      }
    } catch (e) {
      debugPrint("Error loading canvas: $e");
    }
  }

  List<Map<String, dynamic>> _deepCopyElements(
    List<Map<String, dynamic>> source,
  ) {
    return source.map((e) {
      final copy = Map<String, dynamic>.from(e);
      if (e['position'] is Offset) {
        copy['position'] = Offset(
          (e['position'] as Offset).dx,
          (e['position'] as Offset).dy,
        );
      }
      if (e['size'] is Size) {
        copy['size'] = Size(
          (e['size'] as Size).width,
          (e['size'] as Size).height,
        );
      }
      return copy;
    }).toList();
  }

  List<Map<String, dynamic>> _elementsToJson(
    List<Map<String, dynamic>> elements,
  ) {
    return elements.map((e) {
      final copy = Map<String, dynamic>.from(e);
      if (e['position'] is Offset) {
        copy['position'] = {
          'dx': (e['position'] as Offset).dx,
          'dy': (e['position'] as Offset).dy,
        };
      }
      if (e['size'] is Size) {
        copy['size'] = {
          'width': (e['size'] as Size).width,
          'height': (e['size'] as Size).height,
        };
      }
      return copy;
    }).toList();
  }

  List<Map<String, dynamic>> _jsonToElements(List<dynamic> jsonList) {
    return jsonList.map((item) {
      final e = Map<String, dynamic>.from(item);
      if (e['position'] is Map) {
        e['position'] = Offset(e['position']['dx'], e['position']['dy']);
      }
      if (e['size'] is Map) {
        e['size'] = Size(e['size']['width'], e['size']['height']);
      }
      e['rotation'] = (e['rotation'] as num).toDouble();
      return e;
    }).toList();
  }

  void _openLayers() => _showComingSoon('Layers');
  void _openSettings() => _showComingSoon('Settings');
  void _showComingSoon([dynamic feature]) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('Coming soon')));

  // [UPDATED] New Bottom Sheet for Assets
  void _openStylesheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.5,
            maxChildSize: 0.9,
            builder:
                (_, controller) => _AssetPickerSheet(
                  projectId: widget.projectId,
                  scrollController: controller,
                  onAddAssets: (List<String> paths) {
                    _addAssetsToCanvas(paths);
                    Navigator.pop(context);
                  },
                ),
          ),
    );
  }

  void _addAssetsToCanvas(List<String> paths) {
    if (paths.isEmpty) return;
    final oldState = _getCurrentState();
    setState(() {
      for (var path in paths) {
        final double imageWidth =
            _canvasSize.width * 0.4; // 40% of canvas width
        final double imageHeight =
            _canvasSize.height * 0.4; // 40% of canvas height
        final Offset centeredPosition = Offset(
          (_canvasSize.width - imageWidth) / 2,
          (_canvasSize.height - imageHeight) / 2,
        );
        elements.add({
          'id':
              'asset_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(1000)}',
          'type': 'file_image',
          'content': path,
          'position': centeredPosition,
          'size': Size(imageWidth, imageHeight),
          'rotation': 0.0,
        });
      }
      _hasUnsavedChanges = true;
    });
    _recordChange(oldState);
  }

  // ===========================================================================
  //  UI BUILDER
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic>? selectedEl;
    try {
      selectedEl = elements.firstWhere((e) => e['id'] == selectedId);
    } catch (_) {}

    final bool isTextSelected =
        selectedEl != null && selectedEl['type'] == 'text';
    final bool showTextOverlay = _isTextToolsActive || isTextSelected;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        _handleBackNavigation();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFE0E0E0),
        appBar: _buildAppBar(),
        body: LayoutBuilder(
          builder: (context, constraints) {
            if (!_hasInitializedView) {
              _hasInitializedView = true;
              final double scaleX =
                  (constraints.maxWidth - 40) / _canvasSize.width;
              final double scaleY =
                  (constraints.maxHeight - 40) / _canvasSize.height;
              final double initialScale = math
                  .min(scaleX, scaleY)
                  .clamp(0.01, 1.0);

              final double transX =
                  (constraints.maxWidth - (_canvasSize.width * initialScale)) /
                  2;
              final double transY =
                  (constraints.maxHeight -
                      (_canvasSize.height * initialScale)) /
                  2;

              _transformationController.value =
                  Matrix4.identity()
                    ..translate(transX, transY)
                    ..scale(initialScale);
            }

            return Stack(
              children: [
                GestureDetector(
                  onTap: () {
                    // <--- CHANGED: Allow deselecting if MagicDraw is OFF OR if Hand Mode (PanelDisabled) is ON
                    if (!_isMagicDrawActive || _isMagicPanelDisabled) {
                      _exitEditMode();
                      setState(() => selectedId = null);
                    }
                  },
                  behavior: HitTestBehavior.translucent,
                  child: InteractiveViewer(
                    transformationController: _transformationController,
                    constrained: false,
                    boundaryMargin: const EdgeInsets.all(double.infinity),
                    minScale: 0.01,
                    maxScale: 10.0,
                    // <--- CHANGED: Enable Zoom/Pan if MagicDraw is OFF OR if Hand Mode (PanelDisabled) is ON
                    scaleEnabled: !_isMagicDrawActive || _isMagicPanelDisabled,
                    panEnabled: !_isMagicDrawActive || _isMagicPanelDisabled,
                    child: RepaintBoundary(
                      key: _canvasGlobalKey,
                      child: SizedBox(
                        width: _canvasSize.width,
                        height: _canvasSize.height,
                        child: Stack(
                          children: [
                            Container(
                              width: double.infinity,
                              height: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.15),
                                    blurRadius: 40,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                            ),
                            ...elements.map((e) {
                              final bool isSelected = selectedId == e['id'];
                              return _ManipulatingBox(
                                key: ValueKey(e['id']),
                                id: e['id'],
                                position: e['position'],
                                size: e['size'],
                                rotation: e['rotation'],
                                type: e['type'],
                                content: e['content'],
                                styleData: e,
                                // <--- OPTIONAL: If you want to move elements while Hand is active, change this line too:
                                // isSelected: isSelected && (!_isMagicDrawActive || _isMagicPanelDisabled),
                                isSelected: isSelected && !_isMagicDrawActive,
                                isEditing:
                                    isSelected &&
                                    _isEditingText &&
                                    e['type'] == 'text',
                                viewScale:
                                    _transformationController.value
                                        .getMaxScaleOnAxis(),
                                onTap: () {
                                  if (!_isMagicDrawActive) {
                                    if (_isEditingText && selectedId != e['id'])
                                      _exitEditMode();
                                    setState(() {
                                      selectedId = e['id'];
                                      if (e['type'] == 'text')
                                        _isTextToolsActive = true;
                                    });
                                    setState(() {
                                      elements.remove(e);
                                      elements.add(e);
                                    });
                                  }
                                },
                                onDoubleTap: () {
                                  if (e['type'] == 'text') _enterEditMode(e);
                                },
                                onDragStart: _handleGestureStart,
                                onUpdate:
                                    (newPos, newSize, newRot) =>
                                        _handleElementUpdate(
                                          e['id'],
                                          newPos,
                                          newSize,
                                          newRot,
                                        ),
                                onDragEnd: (newPos, newSize, newRot) {
                                  _handleElementUpdate(
                                    e['id'],
                                    newPos,
                                    newSize,
                                    newRot,
                                  );
                                  _handleGestureEnd();
                                },
                                textController:
                                    isSelected ? _textEditingController : null,
                                focusNode: isSelected ? _textFocusNode : null,
                                transformationController:
                                    _transformationController,
                              );
                            }),
                            // Drawing Layer
                            IgnorePointer(
                              // <--- CHANGED: Ignore touches (disable drawing) if MagicDraw is OFF OR if Hand Mode (PanelDisabled) is ON
                              ignoring:
                                  !_isMagicDrawActive || _isMagicPanelDisabled,
                              child: RepaintBoundary(
                                key: _drawingKey,
                                child: GestureDetector(
                                  onPanStart: (_) => _handleGestureStart(),
                                  onPanUpdate: _onPanUpdate,
                                  onPanEnd: (details) {
                                    _onPanEnd(details);
                                    _handleGestureEnd();
                                  },
                                  child: CustomPaint(
                                    size: Size.infinite,
                                    painter: CanvasPainter(
                                      paths: _paths,
                                      magicPaths:
                                          _isCapturingBase ? [] : _magicPaths,
                                      currentPoints:
                                          _isCapturingBase
                                              ? []
                                              : _currentPoints,
                                      currentColor:
                                          _isEraser
                                              ? Colors.transparent
                                              : _selectedColor,
                                      currentWidth: _strokeWidth,
                                      isEraser: _isEraser,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // ... (Rest of your UI: AI Description, MagicDrawTools, etc.) ...
                // I have truncated the bottom part as it remains unchanged.
                if (_aiDescription != null && !_isMagicDrawActive)
                  Positioned(
                    top: 10,
                    left: 16,
                    right: 16,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _isDescriptionExpanded = !_isDescriptionExpanded;
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2.0),
                              child: Icon(
                                Icons.auto_awesome,
                                size: 20,
                                color: Colors.indigo.shade400,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _aiDescription!,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black87,
                                ),
                                maxLines: _isDescriptionExpanded ? null : 1,
                                overflow:
                                    _isDescriptionExpanded
                                        ? TextOverflow.visible
                                        : TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              _isDescriptionExpanded
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              size: 20,
                              color: Colors.grey[600],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                MagicDrawTools(
                  isActive: _isMagicDrawActive,
                  selectedColor: _selectedColor,
                  strokeWidth: _strokeWidth,
                  isEraser: _isEraser,
                  brandColors: _brandColors,
                  onClose: _handleMagicDrawExit,
                  onColorChanged: (c) => setState(() => _selectedColor = c),
                  onWidthChanged: (w) => setState(() => _strokeWidth = w),
                  onEraserToggle: (e) => setState(() => _isEraser = e),
                  onPromptSubmit: (prompt) => _processInpainting(prompt),
                  isProcessing: _isInpainting,
                  onMagicPanelActivityToggle:
                      (disabled) =>
                          setState(() => _isMagicPanelDisabled = disabled),
                  isMagicPanelDisabled: _isMagicPanelDisabled,
                  onViewModeToggle:
                      (enabled) => setState(() => _isViewMode = enabled),
                ),

                TextToolsOverlay(
                  isActive: showTextOverlay && !_isMagicDrawActive,
                  isTextSelected: isTextSelected,
                  currentColor: Color(
                    selectedEl?['style_color'] ?? Colors.black.value,
                  ),
                  currentFontSize:
                      (selectedEl?['style_fontSize'] ?? 24.0) as double,
                  onClose: () {
                    _exitEditMode();
                    setState(() {
                      _isTextToolsActive = false;
                      selectedId = null;
                    });
                  },
                  onAddText: _addTextElement,
                  onColorChanged:
                      (c) =>
                          _updateSelectedTextProperty('style_color', c.value),
                  onFontSizeChanged:
                      (s) => _updateSelectedTextProperty('style_fontSize', s),
                ),

                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: CanvasBottomBar(
                    activeItem:
                        _isMagicDrawActive
                            ? "Magic Draw"
                            : (_isTextToolsActive ? "Text" : null),
                    onMagicDraw: () async {
                      if (_isMagicDrawActive) {
                        final confirm = await _confirmDiscardMagicDraw();
                        if (!confirm) return;
                        setState(() {
                          _magicPaths.clear();
                          _magicDrawChangeStack.clear();
                          _tempBaseImage = null;
                          _isMagicDrawActive = false;
                        });
                        return;
                      }
                      setState(() {
                        _isMagicDrawActive = true;
                        _isTextToolsActive = false;
                        _exitEditMode();
                        _magicPaths.clear();
                        _magicDrawChangeStack.clear();
                        _tempBaseImage = null;
                      });
                    },
                    onMedia: () async {
                      if (_isMagicDrawActive) {
                        final confirm = await _confirmDiscardMagicDraw();
                        if (!confirm) return;
                        setState(() {
                          _magicPaths.clear();
                          _magicDrawChangeStack.clear();
                          _tempBaseImage = null;
                          _isMagicDrawActive = false;
                        });
                      }
                      _pickImageFromGallery();
                    },
                    onStylesheet: () async {
                      if (_isMagicDrawActive) {
                        final confirm = await _confirmDiscardMagicDraw();
                        if (!confirm) return;
                        setState(() {
                          _magicPaths.clear();
                          _magicDrawChangeStack.clear();
                          _tempBaseImage = null;
                          _isMagicDrawActive = false;
                        });
                      }
                      _openStylesheet();
                    },
                    onTools: () async {
                      if (_isMagicDrawActive) {
                        final confirm = await _confirmDiscardMagicDraw();
                        if (!confirm) return;
                        setState(() {
                          _magicPaths.clear();
                          _magicDrawChangeStack.clear();
                          _tempBaseImage = null;
                          _isMagicDrawActive = false;
                        });
                      }
                      _showComingSoon('Tools');
                    },
                    onText: () async {
                      if (_isMagicDrawActive) {
                        final confirm = await _confirmDiscardMagicDraw();
                        if (!confirm) return;
                        setState(() {
                          _magicPaths.clear();
                          _magicDrawChangeStack.clear();
                          _tempBaseImage = null;
                          _isMagicDrawActive = false;
                        });
                      }
                      _toggleTextTools();
                    },
                    onSelect: () async {
                      if (_isMagicDrawActive) {
                        final confirm = await _confirmDiscardMagicDraw();
                        if (!confirm) return;
                        setState(() {
                          _magicPaths.clear();
                          _magicDrawChangeStack.clear();
                          _tempBaseImage = null;
                          _isMagicDrawActive = false;
                        });
                      }
                      _showComingSoon('Select');
                    },
                    onPlugins: () async {
                      if (_isMagicDrawActive) {
                        final confirm = await _confirmDiscardMagicDraw();
                        if (!confirm) return;
                        setState(() {
                          _magicPaths.clear();
                          _magicDrawChangeStack.clear();
                          _tempBaseImage = null;
                          _isMagicDrawActive = false;
                        });
                      }
                      _showComingSoon('Plugins');
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
  // --- DRAWING HELPERS ---

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _currentPoints.add(
        DrawingPoint(offset: details.localPosition, paint: Paint()),
      );
    });
  }

  Future<void> _onPanEnd(DragEndDetails details) async {
    setState(() {
      if (_currentPoints.isNotEmpty) {
        if (_isMagicDrawActive) {
          // ADD TO MAGIC PATHS (Temporary mask)
          final oldMagicPaths = List<DrawingPath>.from(_magicPaths);
          _magicPaths.add(
            DrawingPath(
              points: List.from(_currentPoints),
              color: _selectedColor,
              strokeWidth: _strokeWidth,
              isEraser: _isEraser,
            ),
          );
          _recordMagicChange(oldMagicPaths);
          _currentPoints = [];
        } else {
          // NORMAL DRAWING
          _paths.add(
            DrawingPath(
              points: List.from(_currentPoints),
              color: _selectedColor,
              strokeWidth: _strokeWidth,
              isEraser: _isEraser,
            ),
          );
          _currentPoints = [];
          _hasUnsavedChanges = true;
          _resetInactivityTimer();
        }
      }
    });
  }

  Future<void> _processInpainting(String prompt) async {
    if (prompt.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Please enter a prompt!")));
      return;
    }

    setState(() => _isInpainting = true);
    _resetInactivityTimer();

    try {
      // 1. Check for Image Layers
      bool hasImageLayers = elements.any((e) => e['type'] == 'file_image');

      if (hasImageLayers) {
        // --- INPAINTING FLOW (Existing) ---
        if (_tempBaseImage == null) {
          _tempBaseImage = await _captureCanvasToFile();
        }

        if (_tempBaseImage == null) return;

        File? maskFile = await _generateMaskImageFromPaths(
          _magicPaths,
          _canvasSize,
          _tempBaseImage,
        );

        if (maskFile == null) throw Exception("Failed to generate mask");

        final String? newImageUrl = await FlaskService().inpaintImage(
          imagePath: _tempBaseImage!.path,
          maskPath: maskFile.path,
          prompt: prompt,
        );

        _addGeneratedImage(newImageUrl);
      } else {
        // --- SKETCH-TO-IMAGE FLOW (New) ---
        // Capture the entire canvas (strokes only since no images exist)
        File? sketchFile = await _captureCanvasToFile();
        if (sketchFile == null) throw Exception("Failed to capture sketch");

        final String? newImageUrl = await FlaskService().sketchToImage(
          sketchPath: sketchFile.path,
          userPrompt: prompt,
          stylePrompt: "high quality, realistic", // Default style
        );

        _addGeneratedImage(newImageUrl);
      }
    } catch (e) {
      debugPrint("Generation Error: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Generation failed.")));
    } finally {
      setState(() {
        _isInpainting = false;
        _tempBaseImage = null;
        _magicPaths.clear();
        _magicDrawChangeStack.clear(); // <--- ADD THIS
      });
    }
  }

  void _addGeneratedImage(String? newImageUrl) {
    if (newImageUrl != null) {
      debugPrint("✅ Adding generated image to canvas: $newImageUrl");
      setState(() {
        elements.add({
          'id': 'gen_${DateTime.now().millisecondsSinceEpoch}',
          'type': 'file_image',
          'content': newImageUrl,
          'position': const Offset(0, 0),
          'size': _canvasSize,
          'rotation': 0.0,
        });
        // Clear magic paths now that operation is done
        _magicPaths.clear();
      });
    }
  }

  // Updated to generate mask as: Base Image + Drawing Strokes
  Future<File?> _generateMaskImageFromPaths(
    List<DrawingPath> paths,
    Size size,
    File? baseImageFile,
  ) async {
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
        recorder,
        Rect.fromLTWH(0, 0, size.width, size.height),
      );

      // 1. Draw Base Image First (if available)
      if (baseImageFile != null) {
        final data = await baseImageFile.readAsBytes();
        final codec = await ui.instantiateImageCodec(data);
        final frameInfo = await codec.getNextFrame();
        final baseImage = frameInfo.image;

        paintImage(
          canvas: canvas,
          rect: Rect.fromLTWH(0, 0, size.width, size.height),
          image: baseImage,
          fit: BoxFit.cover, // Or contain, depending on your logic
        );
      } else {
        // Fallback to black if no base image (shouldn't happen based on logic)
        canvas.drawRect(
          Rect.fromLTWH(0, 0, size.width, size.height),
          Paint()..color = Colors.black,
        );
      }

      // 2. Draw Strokes ON TOP of the base image
      for (final path in paths) {
        final paint =
            Paint()
              ..color =
                  path
                      .color // Use the drawing color (e.g. Blue)
              ..strokeWidth = path.strokeWidth
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round
              ..style = PaintingStyle.stroke;

        if (path.points.length > 1) {
          final Path p = Path();
          p.moveTo(path.points.first.offset.dx, path.points.first.offset.dy);
          for (int i = 1; i < path.points.length; i++) {
            p.lineTo(path.points[i].offset.dx, path.points[i].offset.dy);
          }
          canvas.drawPath(p, paint);
        } else if (path.points.isNotEmpty) {
          canvas.drawPoints(ui.PointMode.points, [
            path.points.first.offset,
          ], paint);
        }
      }

      final picture = recorder.endRecording();
      final img = await picture.toImage(
        size.width.toInt(),
        size.height.toInt(),
      );
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;

      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}/mask_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(byteData.buffer.asUint8List());
      return file;
    } catch (e) {
      debugPrint("Mask Generation Error: $e");
      return null;
    }
  }

  Future<void> _saveAndCloseMagicDraw() async {
    setState(() {
      _isMagicDrawActive = false;
      _magicPaths.clear();
      _magicDrawChangeStack.clear();
      _tempBaseImage = null;
    });
  }

  PreferredSizeWidget _buildAppBar() {
    final bool canUndo =
        _isMagicDrawActive
            ? _magicDrawChangeStack.canUndo
            : _changeStack.canUndo;
    final bool canRedo =
        _isMagicDrawActive
            ? _magicDrawChangeStack.canRedo
            : _changeStack.canRedo;
    return AppBar(
      leadingWidth: 160,
      leading: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: SvgPicture.asset(
                'assets/icons/arrow-left-s-line.svg',
                width: 22,
                colorFilter: const ColorFilter.mode(
                  Colors.black,
                  BlendMode.srcIn,
                ),
              ),
              onPressed: () {
                if (_isMagicDrawActive) {
                  _handleMagicDrawExit();
                } else {
                  _handleBackNavigation();
                }
              },
            ),
            IconButton(
              icon: SvgPicture.asset(
                'assets/icons/arrow-go-back-line.svg',
                width: 22,
                colorFilter: ColorFilter.mode(
                  canUndo ? Colors.black : Colors.grey[400]!,
                  BlendMode.srcIn,
                ),
              ),
              onPressed:
                  canUndo
                      ? () => setState(
                        () =>
                            _isMagicDrawActive
                                ? _magicDrawChangeStack.undo()
                                : _changeStack.undo(),
                      )
                      : null,
            ),
            IconButton(
              icon: SvgPicture.asset(
                'assets/icons/arrow-go-forward-line.svg',
                width: 22,
                colorFilter: ColorFilter.mode(
                  canRedo ? Colors.black : Colors.grey[400]!,
                  BlendMode.srcIn,
                ),
              ),
              onPressed:
                  canRedo
                      ? () => setState(
                        () =>
                            _isMagicDrawActive
                                ? _magicDrawChangeStack.redo()
                                : _changeStack.redo(),
                      )
                      : null,
            ),
          ],
        ),
      ),
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      elevation: 0,
      actions: [
        SafeArea(
          child: Row(
            children: [
              if (selectedId != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: _deleteSelectedElement,
                  tooltip: "Delete Selected",
                ),
              IconButton(
                icon: SvgPicture.asset(
                  'assets/icons/save-3-line.svg',
                  width: 22,
                ),
                onPressed: _saveCanvas,
              ),
              IconButton(
                icon: SvgPicture.asset(
                  'assets/icons/upload-2-line.svg',
                  width: 22,
                ),
                onPressed: _exportProject,
              ),
              IconButton(
                icon: SvgPicture.asset(
                  'assets/icons/settings-line.svg',
                  width: 22,
                ),
                onPressed: _openSettings,
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickImageFromGallery() async {
    final List<XFile> images = await _picker.pickMultiImage();
    if (images.isNotEmpty) {
      final oldState = _getCurrentState();
      setState(() {
        for (int i = 0; i < images.length; i++) {
          final double imageWidth =
              _canvasSize.width * 0.4; // 40% of canvas width
          final double imageHeight =
              _canvasSize.height * 0.4; // 40% of canvas height
          final Offset centeredPosition = Offset(
            (_canvasSize.width - imageWidth) / 2,
            (_canvasSize.height - imageHeight) / 2,
          );
          elements.add({
            'id': '${DateTime.now().millisecondsSinceEpoch}_$i',
            'type': 'file_image',
            'content': images[i].path,
            'position': centeredPosition,
            'size': Size(imageWidth, imageHeight),
            'rotation': 0.0,
          });
        }
        _hasUnsavedChanges = true;
      });
      _recordChange(oldState);
    }
  }
}

// =============================================================================
//  MANIPULATING BOX WIDGET
// =============================================================================

class _ManipulatingBox extends StatefulWidget {
  final String id;
  final Offset position;
  final Size size;
  final double rotation;
  final String type;
  final String content;
  final Map<String, dynamic> styleData;
  final bool isSelected;
  final bool isEditing;
  final double viewScale;
  final TransformationController transformationController;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onDragStart;
  final Function(Offset, Size, double) onUpdate;
  final Function(Offset, Size, double) onDragEnd;
  final TextEditingController? textController;
  final FocusNode? focusNode;

  const _ManipulatingBox({
    Key? key,
    required this.id,
    required this.position,
    required this.size,
    required this.rotation,
    required this.type,
    required this.content,
    required this.styleData,
    required this.isSelected,
    required this.isEditing,
    required this.viewScale,
    required this.transformationController,
    required this.onTap,
    required this.onDoubleTap,
    required this.onDragStart,
    required this.onUpdate,
    required this.onDragEnd,
    this.textController,
    this.focusNode,
  }) : super(key: key);

  @override
  State<_ManipulatingBox> createState() => _ManipulatingBoxState();
}

class _ManipulatingBoxState extends State<_ManipulatingBox> {
  late Offset _pos;
  late Size _size;
  late double _rot;

  @override
  void initState() {
    super.initState();
    _updateInternalState();
  }

  @override
  void didUpdateWidget(_ManipulatingBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.position != oldWidget.position ||
        widget.size != oldWidget.size ||
        widget.rotation != oldWidget.rotation) {
      _updateInternalState();
    }
  }

  void _updateInternalState() {
    _pos = widget.position;
    _size = widget.size;
    _rot = widget.rotation;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: widget.transformationController,
      builder: (context, matrix, child) {
        final double zoom = matrix.getMaxScaleOnAxis();
        final double handleScale = (1 / zoom).clamp(0.2, 5.0);
        final double edgeThickness = 18 * handleScale;
        final double buttonSize = 32 * handleScale;
        final double iconSize = 14 * handleScale;

        return Positioned(
          left: _pos.dx,
          top: _pos.dy,
          child: Transform.rotate(
            angle: _rot,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  onTap: widget.onTap,
                  onDoubleTap: widget.onDoubleTap,
                  //moving element on drag works
                  onPanStart: (_) => widget.onDragStart(),
                  onPanUpdate: (details) {
                    if (widget.isSelected && !widget.isEditing) {
                      final delta = details.delta;
                      final rotated = _rotateVector(delta, _rot);
                      setState(() => _pos += rotated);
                      widget.onUpdate(_pos, _size, _rot);
                    }
                  },
                  onPanEnd: (_) => widget.onDragEnd(_pos, _size, _rot),
                  child: Container(
                    width: _size.width,
                    height: _size.height,
                    decoration:
                        widget.isSelected
                            ? BoxDecoration(
                              border: Border.all(
                                color: Color(0xFFB44CFF),
                                width: 2 * handleScale,
                              ),
                            )
                            : null,
                    child:
                        widget.type == "file_image"
                            ? Image.file(
                              File(widget.content),
                              fit: BoxFit.contain,
                            )
                            : _buildText(),
                  ),
                ),

                // ======================
                //  RESIZE EDGES (4 SIDES)
                // ======================

                // RIGHT edge
                if (widget.isSelected && !widget.isEditing)
                  Positioned(
                    right: -edgeThickness / 2,
                    top: 0,
                    bottom: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanUpdate: (d) {
                        setState(() {
                          _size = Size(_size.width + d.delta.dx, _size.height);
                        });
                        widget.onUpdate(_pos, _size, _rot);
                      },
                      onPanStart: (_) => widget.onDragStart(),
                      onPanEnd: (_) => widget.onDragEnd(_pos, _size, _rot),
                      child: Container(
                        width: edgeThickness,
                        color: Colors.transparent,
                      ),
                    ),
                  ),

                // LEFT edge
                if (widget.isSelected && !widget.isEditing)
                  Positioned(
                    left: -edgeThickness / 2,
                    top: 0,
                    bottom: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanUpdate: (d) {
                        setState(() {
                          _pos += Offset(d.delta.dx, 0);
                          _size = Size(_size.width - d.delta.dx, _size.height);
                        });
                        widget.onUpdate(_pos, _size, _rot);
                      },
                      onPanStart: (_) => widget.onDragStart(),
                      onPanEnd: (_) => widget.onDragEnd(_pos, _size, _rot),
                      child: Container(
                        width: edgeThickness,
                        color: Colors.transparent,
                      ),
                    ),
                  ),

                // TOP edge
                if (widget.isSelected && !widget.isEditing)
                  Positioned(
                    top: -edgeThickness / 2,
                    left: 0,
                    right: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanUpdate: (d) {
                        setState(() {
                          _pos += Offset(0, d.delta.dy);
                          _size = Size(_size.width, _size.height - d.delta.dy);
                        });
                        widget.onUpdate(_pos, _size, _rot);
                      },
                      onPanStart: (_) => widget.onDragStart(),
                      onPanEnd: (_) => widget.onDragEnd(_pos, _size, _rot),
                      child: Container(
                        height: edgeThickness,
                        color: Colors.transparent,
                      ),
                    ),
                  ),

                // BOTTOM edge
                if (widget.isSelected && !widget.isEditing)
                  Positioned(
                    bottom: -edgeThickness / 2,
                    left: 0,
                    right: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanUpdate: (d) {
                        setState(() {
                          _size = Size(_size.width, _size.height + d.delta.dy);
                        });
                        widget.onUpdate(_pos, _size, _rot);
                      },
                      onPanStart: (_) => widget.onDragStart(),
                      onPanEnd: (_) => widget.onDragEnd(_pos, _size, _rot),
                      child: Container(
                        height: edgeThickness,
                        color: Colors.transparent,
                      ),
                    ),
                  ),

                // ======================
                //  CORNER RESIZE HANDLES
                // ======================
                if (widget.isSelected && !widget.isEditing) ...[
                  // TOP-LEFT corner
                  Positioned(
                    top: -10 * handleScale,
                    left: -10 * handleScale,
                    child: _cornerHandle(
                      size: 20 * handleScale,
                      onDrag: (d) {
                        final local = _rotateVector(d.delta, -_rot);
                        setState(() {
                          _pos += Offset(local.dx, local.dy);
                          _size = Size(
                            (_size.width - local.dx).clamp(20, 5000),
                            (_size.height - local.dy).clamp(20, 5000),
                          );
                        });
                        widget.onUpdate(_pos, _size, _rot);
                      },
                    ),
                  ),

                  // TOP-RIGHT corner
                  Positioned(
                    top: -10 * handleScale,
                    right: -10 * handleScale,
                    child: _cornerHandle(
                      size: 20 * handleScale,
                      onDrag: (d) {
                        final local = _rotateVector(d.delta, -_rot);
                        setState(() {
                          _pos += Offset(0, local.dy);
                          _size = Size(
                            (_size.width + local.dx).clamp(20, 5000),
                            (_size.height - local.dy).clamp(20, 5000),
                          );
                        });
                        widget.onUpdate(_pos, _size, _rot);
                      },
                    ),
                  ),

                  // BOTTOM-LEFT corner
                  Positioned(
                    bottom: -10 * handleScale,
                    left: -10 * handleScale,
                    child: _cornerHandle(
                      size: 20 * handleScale,
                      onDrag: (d) {
                        final local = _rotateVector(d.delta, -_rot);
                        setState(() {
                          _pos += Offset(local.dx, 0);
                          _size = Size(
                            (_size.width - local.dx).clamp(20, 5000),
                            (_size.height + local.dy).clamp(20, 5000),
                          );
                        });
                        widget.onUpdate(_pos, _size, _rot);
                      },
                    ),
                  ),

                  // BOTTOM-RIGHT corner
                  Positioned(
                    bottom: -10 * handleScale,
                    right: -10 * handleScale,
                    child: _cornerHandle(
                      size: 20 * handleScale,
                      onDrag: (d) {
                        final local = _rotateVector(d.delta, -_rot);
                        setState(() {
                          _size = Size(
                            (_size.width + local.dx).clamp(20, 5000),
                            (_size.height + local.dy).clamp(20, 5000),
                          );
                        });
                        widget.onUpdate(_pos, _size, _rot);
                      },
                    ),
                  ),
                ],

                // move not working
                if (widget.isSelected && !widget.isEditing)
                  Positioned(
                    bottom: -buttonSize - 12,
                    left: _size.width / 2 - buttonSize - 8,
                    child: _buildCircleButton(
                      size: buttonSize,
                      icon: Icons.open_with,
                      iconSize: iconSize,
                      onDrag: (d) {
                        // FIX 1: Convert screen pixel delta (d.delta) to world/canvas units by dividing by zoom.
                        final scaledDelta = d.delta / zoom;

                        // FIX 2: Un-rotate the delta by the inverse of the element's rotation.
                        // This translates the screen drag back to the element's un-rotated position space.
                        final finalDelta = _rotateVector(scaledDelta, -_rot);

                        setState(() {
                          _pos += finalDelta;
                        });
                        widget.onUpdate(_pos, _size, _rot);
                      },
                    ),
                  ),

                //rotate not working
                if (widget.isSelected && !widget.isEditing)
                  Positioned(
                    bottom: -buttonSize - 12,
                    left: _size.width / 2 + 8,
                    child: _buildCircleButton(
                      size: buttonSize,
                      icon: Icons.rotate_right,
                      iconSize: iconSize,
                      onDrag: (d) {
                        widget.onDragStart();

                        // FIX 3: Ensures responsive rotation by increasing the multiplier.
                        setState(() {
                          _rot += d.delta.dx * 0.05; // Increased sensitivity
                        });
                        widget.onUpdate(_pos, _size, _rot);
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _cornerHandle({
    required double size, 
    required Function(DragUpdateDetails) onDrag,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => widget.onDragStart(),
      onPanUpdate: onDrag,
      onPanEnd: (_) => widget.onDragEnd(_pos, _size, _rot),
      child: Container(
        width: size, // large invisible touch area
        height: size,
        alignment: Alignment.center,
        color: Colors.transparent,
        child: Container(
          width: 6 * (1 / widget.viewScale), // <<< tiny visual square
          height: 6 * (1 / widget.viewScale), // <<< tiny visual square
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.white, width: 1),
            shape: BoxShape.rectangle,
          ),
        ),
      ),
    );
  }

  Widget _buildCircleButton({
    required double size,
    required IconData icon,
    required double iconSize,
    required Function(DragUpdateDetails) onDrag,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (details) => widget.onDragStart(),
      onPanUpdate: onDrag,
      onPanEnd: (_) => widget.onDragEnd(_pos, _size, _rot),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Center(child: Icon(icon, size: iconSize, color: Colors.black87)),
      ),
    );
  }

  Widget _buildText() {
    final style = TextStyle(
      fontSize: (widget.styleData['style_fontSize'] ?? 24.0) as double,
      color: Color(widget.styleData['style_color'] ?? Colors.black.value),
      fontFamily: 'GeneralSans',
    );

    if (widget.isEditing) {
      return Center(
        child: IntrinsicWidth(
          child: TextField(
            controller: widget.textController,
            focusNode: widget.focusNode,
            autofocus: true,
            maxLines: null,
            textAlign: TextAlign.center,
            style: style,
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (text) {
              final span = TextSpan(text: text, style: style);
              final tp = TextPainter(
                text: span,
                textDirection: TextDirection.ltr,
              );
              tp.layout(maxWidth: 10000);
              setState(() {
                _size = Size(tp.width + 40, tp.height + 40);
              });
              widget.onUpdate(_pos, _size, _rot);
            },
          ),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(widget.content, textAlign: TextAlign.center, style: style),
      ),
    );
  }

  Widget _buildHandle({
    required double touchSize,
    required double visualSize,
    required IconData icon,
    required Color color,
    required Function(Offset) onDrag,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => widget.onDragStart(),
      onPanUpdate: (details) => onDrag(details.delta),
      onPanEnd: (_) => widget.onDragEnd(_pos, _size, _rot),
      child: Container(
        width: touchSize,
        height: touchSize,
        alignment: Alignment.center,
        color: Colors.transparent,
        child: Container(
          width: visualSize,
          height: visualSize,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.26), blurRadius: 4),
            ],
          ),
          child: Icon(icon, size: visualSize * 0.6, color: Colors.white),
        ),
      ),
    );
  }

  Offset _rotateVector(Offset vector, double angle) {
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);
    return Offset(
      vector.dx * cosA - vector.dy * sinA,
      vector.dx * sinA + vector.dy * cosA,
    );
  }
}

// --- PAINTER ---
class CanvasPainter extends CustomPainter {
  final List<DrawingPath> paths;
  final List<DrawingPath> magicPaths; // ADDED: Magic paths for temporary mask
  final List<DrawingPoint> currentPoints;
  final Color currentColor;
  final double currentWidth;
  final bool isEraser;
  CanvasPainter({
    required this.paths,
    this.magicPaths = const [], // ADDED
    required this.currentPoints,
    required this.currentColor,
    required this.currentWidth,
    required this.isEraser,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());

    // Draw normal paths
    for (final path in paths) {
      _drawPath(canvas, path);
    }

    // Draw magic paths (unless hidden by empty list passed in)
    for (final path in magicPaths) {
      _drawPath(canvas, path);
    }

    // Draw current points
    if (currentPoints.isNotEmpty) {
      final paint =
          Paint()
            ..color = isEraser ? Colors.transparent : currentColor
            ..blendMode = isEraser ? BlendMode.clear : BlendMode.srcOver
            ..strokeWidth = currentWidth
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.stroke;
      final Path p = Path();
      p.moveTo(currentPoints.first.offset.dx, currentPoints.first.offset.dy);
      for (int i = 1; i < currentPoints.length; i++)
        p.lineTo(currentPoints[i].offset.dx, currentPoints[i].offset.dy);
      canvas.drawPath(p, paint);
    }
    canvas.restore();
  }

  void _drawPath(Canvas canvas, DrawingPath path) {
    final paint =
        Paint()
          ..color = path.isEraser ? Colors.transparent : path.color
          ..blendMode = path.isEraser ? BlendMode.clear : BlendMode.srcOver
          ..strokeWidth = path.strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;

    if (path.points.length > 1) {
      final Path p = Path();
      p.moveTo(path.points.first.offset.dx, path.points.first.offset.dy);
      for (int i = 1; i < path.points.length; i++)
        p.lineTo(path.points[i].offset.dx, path.points[i].offset.dy);
      canvas.drawPath(p, paint);
    } else if (path.points.isNotEmpty) {
      canvas.drawPoints(ui.PointMode.points, [path.points.first.offset], paint);
    }
  }

  @override
  bool shouldRepaint(covariant CanvasPainter oldDelegate) => true;
}

class CanvasBottomBar extends StatelessWidget {
  final String? activeItem;
  final VoidCallback onMagicDraw;
  final VoidCallback onMedia;
  final VoidCallback onStylesheet;
  final VoidCallback onTools;
  final VoidCallback onText;
  final VoidCallback onSelect;
  final VoidCallback onPlugins;
  const CanvasBottomBar({
    super.key,
    this.activeItem,
    required this.onMagicDraw,
    required this.onMedia,
    required this.onStylesheet,
    required this.onTools,
    required this.onText,
    required this.onSelect,
    required this.onPlugins,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false, // We don't need top SafeArea as it's a bottom bar
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _BottomBarItem(
                  label: "Magic Draw",
                  iconPath: "assets/icons/magic_draw.svg",
                  onTap: onMagicDraw,
                  isActive: activeItem == "Magic Draw",
                ),
                const SizedBox(width: 24),
                _BottomBarItem(
                  label: "Media",
                  iconPath: "assets/icons/media.svg",
                  onTap: onMedia,
                ),
                const SizedBox(width: 24),
                _BottomBarItem(
                  label: "Stylesheet",
                  iconPath: "assets/icons/stylesheet.svg",
                  onTap: onStylesheet,
                ),
                const SizedBox(width: 24),
                _BottomBarItem(
                  label: "Tools",
                  iconPath: "assets/icons/tools.svg",
                  onTap: onTools,
                ),
                const SizedBox(width: 24),
                _BottomBarItem(
                  label: "Text",
                  iconPath: "assets/icons/text.svg",
                  onTap: onText,
                  isActive: activeItem == "Text",
                ),
                const SizedBox(width: 24),
                _BottomBarItem(
                  label: "Select",
                  iconPath: "assets/icons/select.svg",
                  onTap: onSelect,
                ),
                const SizedBox(width: 24),
                _BottomBarItem(
                  label: "Plugins",
                  iconPath: "assets/icons/plugins.svg",
                  onTap: onPlugins,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomBarItem extends StatelessWidget {
  final String label;
  final String iconPath;
  final VoidCallback onTap;
  final bool isActive;
  const _BottomBarItem({
    required this.label,
    required this.iconPath,
    required this.onTap,
    this.isActive = false,
  });
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              iconPath,
              width: 24,
              colorFilter: ColorFilter.mode(
                isActive ? const Color(0xFF27272A) : const Color(0xFF9F9FA9),
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color:
                    isActive
                        ? const Color(0xFF27272A)
                        : const Color(0xFF9F9FA9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssetPickerSheet extends StatefulWidget {
  final int projectId;
  final ScrollController scrollController;
  final Function(List<String>) onAddAssets; // Accepts List

  const _AssetPickerSheet({
    required this.projectId,
    required this.scrollController,
    required this.onAddAssets,
  });

  @override
  State<_AssetPickerSheet> createState() => _AssetPickerSheetState();
}

class _AssetPickerSheetState extends State<_AssetPickerSheet> {
  List<String> _assets = [];
  bool _isLoading = true;
  Set<String> _selectedPaths = {}; // Supports multi-select

  @override
  void initState() {
    super.initState();
    _loadAssets();
  }

  Future<void> _loadAssets() async {
    try {
      final project = await ProjectRepo().getProjectById(widget.projectId);
      if (mounted) {
        setState(() {
          _assets = project?.assetsPath ?? [];
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading assets: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<File?> _resolveFile(String path) async {
    final file = File(path);
    if (await file.exists()) return file;
    try {
      final filename = p.basename(path);
      final dir = await getApplicationDocumentsDirectory();
      final fixedPath = '${dir.path}/generated_images/$filename';
      final fixedFile = File(fixedPath);
      if (await fixedFile.exists()) return fixedFile;
    } catch (e) {
      debugPrint("Error resolving file: $e");
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Search Bar
          Container(
            height: 40,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                const Icon(Icons.search, color: Colors.grey),
                const SizedBox(width: 8),
                const Text(
                  "Search Stylesheet",
                  style: TextStyle(
                    fontFamily: 'GeneralSans',
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),

          // Category Tabs
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                _buildFilterChip("Assets", true),
                const SizedBox(width: 12),
                _buildFilterChip("Backgrounds & Texture", false),
              ],
            ),
          ),

          // Grid
          Expanded(
            child:
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _assets.isEmpty
                    ? Center(
                      child: Text(
                        "No assets found in stylesheet",
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    )
                    : Stack(
                      children: [
                        GridView.builder(
                          controller: widget.scrollController,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 1.0,
                              ),
                          itemCount: _assets.length,
                          itemBuilder: (context, index) {
                            final assetPath = _assets[index];
                            final isSelected = _selectedPaths.contains(
                              assetPath,
                            );

                            return FutureBuilder<File?>(
                              future: _resolveFile(assetPath),
                              builder: (context, snapshot) {
                                final file = snapshot.data;
                                return _buildAssetTile(
                                  child:
                                      file != null
                                          ? Image.file(file, fit: BoxFit.cover)
                                          : const Icon(
                                            Icons.broken_image,
                                            color: Colors.grey,
                                          ),
                                  isSelected: isSelected,
                                  onTap: () {
                                    if (file != null) {
                                      setState(() {
                                        if (isSelected) {
                                          _selectedPaths.remove(assetPath);
                                        } else {
                                          _selectedPaths.add(assetPath);
                                        }
                                      });
                                    }
                                  },
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
          ),

          // Bottom CTA
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 16, bottom: 16),
              child: ElevatedButton(
                onPressed: () => widget.onAddAssets(_selectedPaths.toList()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF27272A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: const Text(
                  "Add to File",
                  style: TextStyle(
                    fontFamily: 'GeneralSans',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFF4F4F5) : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected ? Colors.transparent : Colors.grey[300]!,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'GeneralSans',
          fontSize: 14,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          color: isSelected ? Colors.black : Colors.grey[600],
        ),
      ),
    );
  }

  Widget _buildAssetTile({
    required Widget child,
    required VoidCallback onTap,
    bool isSelected = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey[200]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (isSelected)
              Container(
                color: Colors.blue.withOpacity(0.1),
                child: const Center(
                  child: Icon(Icons.check_circle, color: Colors.blue),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
