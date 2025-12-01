import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
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

import '../../services/file_service.dart';
import '../../data/models/file_model.dart';

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

  // --- STATE ---
  bool _hasUnsavedChanges = false;
  List<Map<String, dynamic>> elements = [];
  List<DrawingPath> _paths = []; // Keeps drawing strokes live

  // Snapshots for undo grouping
  CanvasState? _gestureStartSnapshot;

  String? selectedId;
  late Size _canvasSize;
  List<Color> _brandColors = [];

  // --- TOOLS ---
  bool _isMagicDrawActive = false;
  bool _isTextToolsActive = false;

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
  final GlobalKey _canvasGlobalKey = GlobalKey();

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

    // Inject shared image EXACTLY like gallery images
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.injectedMedia != null && widget.existingFile != null) {
        final oldState = _getCurrentState();
        setState(() {
          elements.add({
            'id': 'shared_${DateTime.now().millisecondsSinceEpoch}',
            'type': 'file_image',
            'content': widget.injectedMedia!.path,
            'position': const Offset(50, 50),
            'size': const Size(150, 150), // EXACT match
            'rotation': 0.0,
          });
          _hasUnsavedChanges = true;
        });
        _recordChange(oldState);
      }
    });

  }

  @override
  void dispose() {
    _textEditingController.dispose();
    _textFocusNode.dispose();
    _transformationController.dispose();
    super.dispose();
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

  void _recordChange(CanvasState oldState) {
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
    _gestureStartSnapshot = _getCurrentState();
  }

  void _handleElementUpdate(
    String id,
    Offset newPos,
    Size newSize,
    double newRotation,
  ) {
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
          }
          _hasUnsavedChanges = false;
        });
         if (widget.injectedMedia != null) {
          final oldState = _getCurrentState();
          setState(() {
            elements.add({
              'id': 'shared_${DateTime.now().millisecondsSinceEpoch}',
              'type': 'file_image',
              'content': widget.injectedMedia!.path,
              'position': const Offset(50, 50),
              'size': const Size(150, 150),
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
                    if (!_isMagicDrawActive) {
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
                    scaleEnabled: !_isMagicDrawActive,
                    panEnabled: !_isMagicDrawActive,
                    child: SizedBox(
                      width: _canvasSize.width,
                      height: _canvasSize.height,
                      child: Stack(
                        children: [
                          // [NEW] WRAPPED IN REPAINT BOUNDARY FOR EXPORT
                          RepaintBoundary(
                            key: _canvasGlobalKey,
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
                                    isSelected:
                                        isSelected && !_isMagicDrawActive,
                                    isEditing:
                                        isSelected &&
                                        _isEditingText &&
                                        e['type'] == 'text',
                                    viewScale:
                                        _transformationController.value
                                            .getMaxScaleOnAxis(),
                                    onTap: () {
                                      if (!_isMagicDrawActive) {
                                        if (_isEditingText &&
                                            selectedId != e['id']) {
                                          _exitEditMode();
                                        }
                                        setState(() {
                                          selectedId = e['id'];
                                          if (e['type'] == 'text') {
                                            _isTextToolsActive = true;
                                          }
                                        });
                                        setState(() {
                                          // Bring to front
                                          elements.remove(e);
                                          elements.add(e);
                                        });
                                      }
                                    },
                                    onDoubleTap: () {
                                      if (e['type'] == 'text')
                                        _enterEditMode(e);
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
                                        isSelected
                                            ? _textEditingController
                                            : null,
                                    focusNode:
                                        isSelected ? _textFocusNode : null,
                                    transformationController:
                                        _transformationController,
                                  );
                                }),
                                // Drawing Layer inside Capture Zone
                                IgnorePointer(
                                  ignoring: !_isMagicDrawActive,
                                  child: RepaintBoundary(
                                    key: _drawingKey,
                                    child: GestureDetector(
                                      onPanStart: (_) {
                                        _gestureStartSnapshot =
                                            _getCurrentState();
                                      },
                                      onPanUpdate: _onPanUpdate,
                                      onPanEnd: (details) {
                                        _onPanEnd(details);
                                        if (_gestureStartSnapshot != null) {
                                          _recordChange(_gestureStartSnapshot!);
                                          _gestureStartSnapshot = null;
                                        }
                                      },
                                      child: CustomPaint(
                                        size: Size.infinite,
                                        painter: CanvasPainter(
                                          paths: _paths,
                                          currentPoints: _currentPoints,
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
                  onClose:
                      _saveAndCloseMagicDraw, // REMOVED as per previous request
                  onColorChanged: (c) => setState(() => _selectedColor = c),
                  onWidthChanged: (w) => setState(() => _strokeWidth = w),
                  onEraserToggle: (e) => setState(() => _isEraser = e),
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
                    onMagicDraw:
                        () => setState(() {
                          _isMagicDrawActive = !_isMagicDrawActive;
                          _isTextToolsActive = false;
                          _exitEditMode();
                        }),
                    onMedia: _pickImageFromGallery,
                    onStylesheet: () => _showComingSoon('Stylesheet'),
                    onTools: () => _showComingSoon('Tools'),
                    onText: _toggleTextTools,
                    onSelect: () => _showComingSoon('Select'),
                    onPlugins: () => _showComingSoon('Plugins'),
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

  void _onPanEnd(DragEndDetails details) {
    setState(() {
      if (_currentPoints.isNotEmpty) {
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
      }
    });
  }

  // Just toggles state; drawing data stays in _paths and is saved via _saveCanvas
  Future<void> _saveAndCloseMagicDraw() async {
    setState(() => _isMagicDrawActive = false);
  }

  PreferredSizeWidget _buildAppBar() {
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
                  _saveAndCloseMagicDraw();
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
                  _changeStack.canUndo ? Colors.black : Colors.grey[400]!,
                  BlendMode.srcIn,
                ),
              ),
              onPressed:
                  _changeStack.canUndo
                      ? () => setState(() => _changeStack.undo())
                      : null,
            ),
            IconButton(
              icon: SvgPicture.asset(
                'assets/icons/arrow-go-forward-line.svg',
                width: 22,
                colorFilter: ColorFilter.mode(
                  _changeStack.canRedo ? Colors.black : Colors.grey[400]!,
                  BlendMode.srcIn,
                ),
              ),
              onPressed:
                  _changeStack.canRedo
                      ? () => setState(() => _changeStack.redo())
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
          elements.add({
            'id': '${DateTime.now().millisecondsSinceEpoch}_$i',
            'type': 'file_image',
            'content': images[i].path,
            'position': const Offset(50, 50),
            'size': const Size(150, 150),
            'rotation': 0.0,
          });
        }
        _hasUnsavedChanges = true;
      });
      _recordChange(oldState);
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

  void _openLayers() => _showComingSoon('Layers');
  void _openSettings() => _showComingSoon('Settings');
  void _showComingSoon([dynamic feature]) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('Coming soon')));
}

// =============================================================================
//  MANIPULATING BOX WIDGET
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
        final double currentZoom = matrix.getMaxScaleOnAxis();
        final double handleScale = (1.0 / currentZoom).clamp(0.1, 5.0);
        final double touchTargetSize = 40.0 * handleScale;
        final double visualSize = 24.0 * handleScale;

        return Positioned(
          left: _pos.dx,
          top: _pos.dy,
          child: Transform.rotate(
            angle: _rot,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: widget.onTap,
                  onDoubleTap: widget.onDoubleTap,
                  onPanStart: (_) => widget.onDragStart(),
                  onPanUpdate: (details) {
                    if (widget.isSelected && !widget.isEditing) {
                      final delta = details.delta;
                      final globalDelta = _rotateVector(delta, _rot);
                      setState(() => _pos += globalDelta);
                      widget.onUpdate(_pos, _size, _rot);
                    }
                  },
                  onPanEnd: (_) => widget.onDragEnd(_pos, _size, _rot),
                  child: Container(
                    width: _size.width,
                    height: _size.height,
                    decoration: BoxDecoration(
                      border:
                          widget.isSelected
                              ? Border.all(
                                color: Colors.blue,
                                width: 2.0 * handleScale,
                              )
                              : (widget.type == 'text'
                                  ? Border.all(
                                    color: Colors.grey.withOpacity(0.3),
                                    width: 1.0 * handleScale,
                                  )
                                  : null),
                    ),
                    child:
                        widget.type == 'file_image'
                            ? Image.file(
                              File(widget.content),
                              fit: BoxFit.contain,
                            )
                            : _buildText(),
                  ),
                ),
                if (widget.isSelected && !widget.isEditing) ...[
                  Positioned(
                    right: -visualSize / 2,
                    bottom: -visualSize / 2,
                    child: _buildHandle(
                      touchSize: touchTargetSize,
                      visualSize: visualSize,
                      icon: Icons.zoom_out_map,
                      color: Colors.blue,
                      onDrag: (delta) {
                        setState(() {
                          final localDelta = _rotateVector(delta, -_rot);
                          _size = Size(
                            (_size.width + localDelta.dx).clamp(50.0, 10000.0),
                            (_size.height + localDelta.dy).clamp(30.0, 10000.0),
                          );
                          final offset = Offset(
                            localDelta.dx / 2,
                            localDelta.dy / 2,
                          );
                          _pos += _rotateVector(offset, _rot);
                        });
                        widget.onUpdate(_pos, _size, _rot);
                      },
                    ),
                  ),
                  Positioned(
                    right: -visualSize / 2,
                    top: -visualSize / 2,
                    child: _buildHandle(
                      touchSize: touchTargetSize,
                      visualSize: visualSize,
                      icon: Icons.rotate_right,
                      color: Colors.green,
                      onDrag: (delta) {
                        setState(() {
                          _rot += (delta.dx + delta.dy) * 0.005;
                        });
                        widget.onUpdate(_pos, _size, _rot);
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
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
  final List<DrawingPoint> currentPoints;
  final Color currentColor;
  final double currentWidth;
  final bool isEraser;
  CanvasPainter({
    required this.paths,
    required this.currentPoints,
    required this.currentColor,
    required this.currentWidth,
    required this.isEraser,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());
    for (final path in paths) {
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
        canvas.drawPoints(ui.PointMode.points, [
          path.points.first.offset,
        ], paint);
      }
    }
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
