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

import 'package:creekui/data/repos/project_repo.dart';
import 'package:creekui/data/models/file_model.dart';
import 'package:creekui/services/stylesheet_service.dart';
import 'package:creekui/services/file_service.dart';
import 'package:creekui/services/flask_service.dart';
import 'package:creekui/ui/styles/variables.dart';
import 'package:creekui/data/models/canvas_models.dart';
import 'package:creekui/ui/painters/canvas_painter.dart';

import 'package:creekui/ui/widgets/canvas/manipulating_box.dart';
import 'package:creekui/ui/widgets/canvas/canvas_bottom_bar.dart';
import 'package:creekui/ui/widgets/canvas/asset_picker_sheet.dart';
import './canvas_toolbar/magic_draw_overlay.dart';
import './canvas_toolbar/text_tools_overlay.dart';
import 'project_file_page.dart';

class CanvasPage extends StatefulWidget {
  final int projectId;
  final double width;
  final double height;
  final File? initialImage;
  final FileModel? existingFile;
  final File? injectedMedia;

  const CanvasPage({
    super.key,
    required this.projectId,
    required this.width,
    required this.height,
    this.initialImage,
    this.existingFile,
    this.injectedMedia,
  });

  @override
  State<CanvasPage> createState() => _CanvasPageState();
}

class _CanvasPageState extends State<CanvasPage> {
  final FileService _fileService = FileService();
  final ChangeStack _changeStack = ChangeStack();
  final ImagePicker _picker = ImagePicker();
  final ChangeStack _magicDrawChangeStack = ChangeStack();

  bool _hasUnsavedChanges = false;
  List<Map<String, dynamic>> elements = [];
  List<DrawingPath> _paths = []; // Keeps normal drawing strokes
  List<DrawingPath> _magicPaths = []; // Keeps temporary magic draw mask strokes

  // Snapshots for undo grouping
  CanvasState? _gestureStartSnapshot;

  // Detection Timer & AI Analysis
  Timer? _inactivityTimer;
  DateTime _lastAnalysisTime = DateTime.now();
  final GlobalKey _canvasGlobalKey = GlobalKey();
  String? _aiDescription;
  bool _isAnalyzing = false;
  bool _isDescriptionExpanded = false; // Track expansion state

  // Magic Draw / Inpainting State
  File? _tempBaseImage;
  bool _isInpainting = false;
  bool _isCapturingBase = false; // Hide strokes during capture

  // Background Removal Banner State
  bool _showBgRemovalBanner = false;
  String? _bgRemovalTargetId;
  String? _bgRemovalTargetPath;
  Timer? _bgRemovalBannerTimer;
  bool _isRemovingBg = false;

  String? selectedId;
  late Size _canvasSize;
  List<Color> _brandColors = [];

  // Tools
  bool _isMagicDrawActive = false;
  bool _isTextToolsActive = false;

  bool _isMagicPanelDisabled = false;
  bool _isViewMode = false;

  // Editing
  bool _isEditingText = false;
  final TextEditingController _textEditingController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();

  // Drawing
  List<DrawingPoint> _currentPoints = [];
  Color _selectedColor = Variables.defaultBrush;
  double _strokeWidth = 10.0;
  bool _isEraser = false;
  final GlobalKey _drawingKey = GlobalKey();

  // Viewport
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
      final double imageWidth = _canvasSize.width * 0.4;
      final double imageHeight = _canvasSize.height * 0.4;
      final Offset centeredPosition = Offset(
        (_canvasSize.width - imageWidth) / 2,
        (_canvasSize.height - imageHeight) / 2,
      );
      elements.add({
        'id': 'bg_${DateTime.now().millisecondsSinceEpoch}',
        'type': 'file_image',
        'content': widget.initialImage!.path,
        'position': centeredPosition,
        'size': Size(imageWidth, imageHeight),
        'rotation': 0.0,
      });
      _hasUnsavedChanges = true;
    }
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    _bgRemovalBannerTimer?.cancel();
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
      debugPrint("[AI] Starting canvas analysis...");

      File? imageFile = await _captureCanvasToFile();
      if (imageFile == null) return;

      final description = await FlaskService().describeImage(
        imagePath: imageFile.path,
      );

      debugPrint("[AI] Service Response: $description");

      if (description != null && mounted) {
        setState(() {
          _aiDescription = description;
          _isDescriptionExpanded = false;
        });
      }
    } catch (e) {
      debugPrint("[AI] Analysis Failed: $e");
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

  // Undo/Redo
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
          // Redo
          setState(() {
            elements = _deepCopyElements(newState.elements);
            _paths = List.from(newState.paths);
            _hasUnsavedChanges = true;
          });
        },
        (val) {
          // Undo
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

  // Actions
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
    if (_isMagicDrawActive) {
      bool hasImageLayers = elements.any((e) => e['type'] == 'file_image');
      if (hasImageLayers && !_isInpainting && _tempBaseImage == null) {
        _ensureBaseImageCaptured();
      }
      return;
    }
    _gestureStartSnapshot = _getCurrentState();
  }

  // Captures the base image by temporarily hiding the magic strokes
  Future<void> _ensureBaseImageCaptured() async {
    if (_tempBaseImage != null) return;

    debugPrint("[Magic Draw] Hiding strokes to capture clean base...");

    setState(() => _isCapturingBase = true);
    await Future.delayed(
      const Duration(milliseconds: 50),
    ); // Wait for frame to render

    try {
      _tempBaseImage = await _captureCanvasToFile();
      debugPrint("[Magic Draw] Base image captured.");
    } catch (e) {
      debugPrint("[Magic Draw] Failed to capture base: $e");
    } finally {
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

      // 4. Convert PNG to JPG
      // TODO: Done on main thread for simplicity
      final img.Image? decodedImage = img.decodePng(pngBytes);

      if (decodedImage == null) {
        throw Exception("Failed to decode image");
      }

      // Encode to JPG
      final Uint8List jpgBytes = img.encodeJpg(decodedImage, quality: 90);

      // 5. Save to Temporary File
      final directory = await getTemporaryDirectory();
      final String fileName =
          "export_${DateTime.now().millisecondsSinceEpoch}.jpg";
      final String filePath = '${directory.path}/$fileName';

      final File imgFile = File(filePath);
      await imgFile.writeAsBytes(jpgBytes);

      // 6. Trigger System Share/Save Dialog
      await Share.shareXFiles([
        XFile(filePath, mimeType: 'image/jpeg'),
      ], text: 'Check out my design created with CreekUI!');
    } catch (e) {
      debugPrint("Export Error: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Export failed: $e")));
    }
  }

  // Save & Load Logic
  Future<void> _handleMagicDrawExit() async {
    if (_magicPaths.isNotEmpty && !_isInpainting) {
      final confirm = await _confirmDiscardMagicDraw();
      if (confirm) {
        _saveAndCloseMagicDraw();
      }
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

      // 1. New File: Ask user for name
      if (isNewFile) {
        final userFileName = await _showNameDialog();
        if (userFileName == null || userFileName.isEmpty) return;
        fileName = userFileName;
      }

      // 2. Generate Preview
      final String? previewPath = await _generatePreviewImage();

      // 3. Serialize Elements and Drawing to JSON
      final jsonList = _elementsToJson(elements);
      final pathsJson = _paths.map((p) => p.toMap()).toList();

      final saveData = {
        'elements': jsonList,
        'paths': pathsJson,
        'width': _canvasSize.width,
        'height': _canvasSize.height,
        'preview_path': previewPath,
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
            elements = _jsonToElements(decoded['elements']);
            if (decoded['paths'] != null) {
              _paths =
                  (decoded['paths'] as List)
                      .map((p) => DrawingPath.fromMap(p))
                      .toList();
            } else {
              _paths = [];
            }
            if (decoded['width'] != null && decoded['height'] != null) {
              _canvasSize = Size(
                (decoded['width'] as num).toDouble(),
                (decoded['height'] as num).toDouble(),
              );
              _hasInitializedView = false;
            }
          } else if (decoded is List) {
            // Legacy support
            elements = _jsonToElements(decoded);
            _paths = [];
            _hasInitializedView = false;
          }
          _hasUnsavedChanges = false;
        });

        // Handle Injected Media
        if (widget.injectedMedia != null) {
          final oldState = _getCurrentState();
          setState(() {
            final double imageWidth = _canvasSize.width * 0.4;
            final double imageHeight = _canvasSize.height * 0.4;
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

  // Bottom Sheet for Assets
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
                (_, controller) => AssetPickerSheet(
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
        final double imageWidth = _canvasSize.width * 0.4;
        final double imageHeight = _canvasSize.height * 0.4;
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

  // UI Builder
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
        backgroundColor: Variables.canvasBackground,
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
                                color: Variables.background,
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
                              return ManipulatingBox(
                                key: ValueKey(e['id']),
                                id: e['id'],
                                position: e['position'],
                                size: e['size'],
                                rotation: e['rotation'],
                                type: e['type'],
                                content: e['content'],
                                styleData: e,
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

                if (_aiDescription != null && _isMagicDrawActive)
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
                  onPromptSubmit:
                      (prompt, serviceId) =>
                          _processInpainting(prompt, serviceId),
                  isProcessing: _isInpainting,
                  onMagicPanelActivityToggle:
                      (disabled) =>
                          setState(() => _isMagicPanelDisabled = disabled),
                  isMagicPanelDisabled: _isMagicPanelDisabled,
                  onViewModeToggle:
                      (enabled) => setState(() => _isViewMode = enabled),
                  hasImageLayers: elements.any(
                    (e) => e['type'] == 'file_image',
                  ),
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

                // Background Removal Banner
                if (_showBgRemovalBanner)
                  Positioned(
                    top: SafeArea(child: Container()).minimum.top + 10,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Variables.surfaceDark,
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_isRemovingBg) ...[
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                "Removing...",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontFamily: 'GeneralSans',
                                  fontSize: 14,
                                ),
                              ),
                            ] else ...[
                              const Text(
                                "Remove background?",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontFamily: 'GeneralSans',
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: _confirmRemoveBackground,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.check,
                                    size: 16,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap:
                                    () => setState(
                                      () => _showBgRemovalBanner = false,
                                    ),
                                child: const Icon(
                                  Icons.close,
                                  size: 18,
                                  color: Colors.white54,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
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

  // Drawing Helpers
  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _currentPoints.add(
        DrawingPoint(offset: details.localPosition, paint: Paint()),
      );
    });

    // Throttle Analysis: Trigger "Describe" every 2.5s while actively drawing
    if (_isMagicDrawActive &&
        !_isAnalyzing &&
        !_isInpainting &&
        DateTime.now().difference(_lastAnalysisTime).inMilliseconds > 2500) {
      _lastAnalysisTime = DateTime.now();
      _analyzeCanvas();
    }
  }

  Future<void> _onPanEnd(DragEndDetails details) async {
    setState(() {
      if (_currentPoints.isNotEmpty) {
        if (_isMagicDrawActive) {
          // Temporary mask
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
          // Normal drawing
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

  // Background Removal Logic
  void _triggerBgRemovalBanner(String elementId, String imagePath) {
    _bgRemovalBannerTimer?.cancel();
    setState(() {
      _showBgRemovalBanner = true;
      _bgRemovalTargetId = elementId;
      _bgRemovalTargetPath = imagePath;
    });

    // Automatically hide after 10 seconds
    _bgRemovalBannerTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) {
        setState(() => _showBgRemovalBanner = false);
      }
    });
  }

  Future<void> _confirmRemoveBackground() async {
    if (_bgRemovalTargetId == null || _bgRemovalTargetPath == null) return;

    _bgRemovalBannerTimer?.cancel();

    setState(() {
      _isRemovingBg = true;
    });

    try {
      final newPath = await FlaskService().generateAsset(
        imagePath: _bgRemovalTargetPath!,
      );

      if (newPath != null && mounted) {
        // Find the element and update its content
        final index = elements.indexWhere((e) => e['id'] == _bgRemovalTargetId);
        if (index != -1) {
          final oldState = _getCurrentState();
          setState(() {
            elements[index]['content'] = newPath;
            _showBgRemovalBanner = false;
            _isRemovingBg = false;
            _hasUnsavedChanges = true;
          });
          _recordChange(oldState);
        }
      }
    } catch (e) {
      debugPrint("BG Removal Failed: $e");
    } finally {
      if (mounted)
        setState(() {
          _isRemovingBg = false;
          _showBgRemovalBanner = false;
        });
    }
  }

  Future<void> _processInpainting(String prompt, String modelId) async {
    FocusScope.of(context).unfocus(); // Lock editing and hide keyboard

    setState(() => _isInpainting = true);
    _resetInactivityTimer();

    try {
      // Check if there are image layers (which dictates the context)
      bool hasImageLayers = elements.any((e) => e['type'] == 'file_image');

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

      String? newImageUrl;

      // Case 1: Inpainting
      if (hasImageLayers) {
        if (modelId == 'inpaint_api') {
          // API Inpainting
          newImageUrl = await FlaskService().inpaintApiImage(
            imagePath: _tempBaseImage!.path,
            maskPath: maskFile.path,
            prompt: prompt,
          );
        } else {
          // Local Inpainting
          newImageUrl = await FlaskService().inpaintImage(
            imagePath: _tempBaseImage!.path,
            maskPath: maskFile.path,
            prompt: prompt,
          );
        }
      }
      // Case 2: Sketch to Image
      else {
        if (modelId == 'sketch_fusion') {
          newImageUrl = await FlaskService().sketchToImage(
            projectId: widget.projectId,
            sketchPath: _tempBaseImage!.path,
            userPrompt: prompt,
            imageDescription: _aiDescription,
          );
        } else if (modelId == 'sketch_advanced') {
          newImageUrl = await FlaskService().sketchToImageAPI(
            projectId: widget.projectId,
            sketchPath: _tempBaseImage!.path,
            userPrompt: prompt,
            option: 1,
            imageDescription: _aiDescription,
          );
        } else if (modelId == 'sketch_creative') {
          newImageUrl = await FlaskService().sketchToImageAPI(
            projectId: widget.projectId,
            sketchPath: _tempBaseImage!.path,
            userPrompt: prompt,
            option: 2,
            imageDescription: _aiDescription,
          );
        }
      }

      if (newImageUrl != null) {
        final id = _addGeneratedImage(newImageUrl);
        setState(() {
          _isMagicDrawActive = false;
        });

        // Trigger Banner for Background Removal (Only for generation, not inpainting)
        if (!hasImageLayers) {
          _triggerBgRemovalBanner(id, newImageUrl);
        }
      }
    } catch (e) {
      debugPrint("Generation Error: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Generation failed")));
    } finally {
      setState(() {
        _isInpainting = false;
        _tempBaseImage = null;
        _magicPaths.clear();
        _magicDrawChangeStack.clear();
      });
    }
  }

  String _addGeneratedImage(String? newImageUrl) {
    String id = '';
    if (newImageUrl != null) {
      debugPrint("Adding generated image to canvas: $newImageUrl");
      id = 'gen_${DateTime.now().millisecondsSinceEpoch}';
      setState(() {
        elements.add({
          'id': id,
          'type': 'file_image',
          'content': newImageUrl,
          'position': const Offset(0, 0),
          'size': _canvasSize,
          'rotation': 0.0,
        });
        _magicPaths.clear();
      });
    }
    return id;
  }

  // Generate mask: Base Image + Drawing Strokes
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
          fit: BoxFit.cover,
        );
      } else {
        // Fallback to black if no base image (shouldn't happen based on logic)
        canvas.drawRect(
          Rect.fromLTWH(0, 0, size.width, size.height),
          Paint()..color = Colors.black,
        );
      }

      // 2. Draw Strokes on top of base image
      for (final path in paths) {
        final paint =
            Paint()
              ..color = path.color
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
      backgroundColor: Variables.background,
      foregroundColor: Variables.textPrimary,
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
          final double imageWidth = _canvasSize.width * 0.4;
          final double imageHeight = _canvasSize.height * 0.4;
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
