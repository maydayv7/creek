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
import 'package:creekui/utils/image_utils.dart';

import 'package:creekui/ui/widgets/canvas/manipulating_box.dart';
import 'package:creekui/ui/widgets/canvas/canvas_bottom_bar.dart';
import 'package:creekui/ui/widgets/canvas/asset_picker_sheet.dart';
import 'package:creekui/ui/widgets/canvas/layers_panel.dart';
import 'package:creekui/ui/widgets/app_bar.dart';
import 'package:creekui/ui/widgets/dialog.dart';
import 'package:creekui/ui/widgets/text_field.dart';
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

  // Stack for magic draw actions
  final ChangeStack _magicDrawChangeStack = ChangeStack();

  bool _hasUnsavedChanges = false;

  // Layer state
  // Bottom-most layer is at index 0
  List<CanvasLayer> _layers = [];
  String? _activeLayerId;
  bool _showLayersPanel = false;

  // Magic Draw & Flashing
  String? _magicDrawLayerId;
  String? _flashingLayerId;
  Timer? _flashTimer;

  // Snapshots for undo grouping
  CanvasState? _gestureStartSnapshot;

  // AI & Inpainting State
  Timer? _inactivityTimer;
  DateTime _lastAnalysisTime = DateTime.now();
  final GlobalKey _canvasGlobalKey = GlobalKey();
  String? _aiDescription;
  bool _isAnalyzing = false;
  bool _isDescriptionExpanded = false;
  File? _tempBaseImage;
  bool _isInpainting = false;
  bool _isCapturingBase = false; // Hide strokes during capture

  // Background Removal Banner State
  bool _showBgRemovalBanner = false;
  String? _bgRemovalTargetId;
  String? _bgRemovalTargetPath;
  Timer? _bgRemovalBannerTimer;
  bool _isRemovingBg = false;

  late Size _canvasSize;
  List<Color> _brandColors = [];

  // Tools
  bool _isMagicDrawActive = false;
  bool _isTextToolsActive = false;
  bool _isMagicPanelDisabled = false;
  bool _isViewMode = false;

  // Text Editing
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
    } else {
      _initializeNewCanvas();
    }
  }

  void _initializeNewCanvas() {
    // Add initial image layer if present
    if (widget.initialImage != null) {
      final double imageWidth = _canvasSize.width * 0.4;
      final double imageHeight = _canvasSize.height * 0.4;
      final Offset centeredPosition = Offset(
        (_canvasSize.width - imageWidth) / 2,
        (_canvasSize.height - imageHeight) / 2,
      );

      final bgId = 'bg_${DateTime.now().millisecondsSinceEpoch}';
      _layers.add(
        ImageLayer(
          id: bgId,
          data: {
            'id': bgId,
            'type': 'file_image',
            'content': widget.initialImage!.path,
            'position': centeredPosition,
            'size': Size(imageWidth, imageHeight),
            'rotation': 0.0,
          },
        ),
      );
      _activeLayerId = bgId;
    }

    if (widget.injectedMedia != null) {
      _addAssetsToCanvas([widget.injectedMedia!.path]);
    }
    _hasUnsavedChanges = true;
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    _bgRemovalBannerTimer?.cancel();
    _flashTimer?.cancel();
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

  // LAYER MANAGEMENT
  void _handleLayerReorder(int oldUiIndex, int newUiIndex) {
    setState(() {
      // The UI shows layers Top -> Bottom (reversed order of stack)
      List<CanvasLayer> uiList = _layers.reversed.toList();

      if (oldUiIndex < newUiIndex) {
        newUiIndex -= 1;
      }
      final CanvasLayer item = uiList.removeAt(oldUiIndex);
      uiList.insert(newUiIndex, item);

      // Restore stack order (Bottom -> Top)
      _layers = uiList.reversed.toList();
      _hasUnsavedChanges = true;
    });
  }

  void _handleLayerDelete(String id) {
    final oldState = _getCurrentState();
    setState(() {
      _layers.removeWhere((l) => l.id == id);

      if (_activeLayerId == id) {
        // If active layer is deleted, select the new top-most layer
        _activeLayerId = _layers.isNotEmpty ? _layers.last.id : null;
      }

      _hasUnsavedChanges = true;
    });
    _recordChange(oldState);
  }

  void _handleLayerVisibility(String id) {
    final index = _layers.indexWhere((l) => l.id == id);
    if (index != -1) {
      setState(() {
        _layers[index].isVisible = !_layers[index].isVisible;
      });
    }
  }

  void _setActiveLayer(String id) {
    setState(() {
      _activeLayerId = id;
      _flashLayer(id); // Visual feedback

      final layer = _layers.firstWhere((l) => l.id == id);

      // Auto-enable text tools if selecting a text layer
      if (layer is ImageLayer && layer.data['type'] == 'text') {
        _isTextToolsActive = true;
      } else {
        _isTextToolsActive = false;
        _exitEditMode();
      }
    });
  }

  void _flashLayer(String id) {
    _flashTimer?.cancel();
    setState(() => _flashingLayerId = id);
    _flashTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _flashingLayerId = null);
    });
  }

  // DRAWING LOGIC
  void _startMagicDraw() {
    // Capture the base canvas (everything currently visible)
    _ensureBaseImageCaptured().then((_) {
      setState(() {
        _isMagicDrawActive = true;
        _isTextToolsActive = false;
        _exitEditMode();

        // Add an initial sketch layer
        _addNewMagicLayer();
        _magicDrawChangeStack.clear();
      });
    });
  }

  void _addNewMagicLayer() {
    final id = 'magic_${DateTime.now().millisecondsSinceEpoch}';
    final magicLayer = SketchLayer(id: id, isMagicDraw: true, paths: []);
    setState(() {
      _layers.add(magicLayer);
      _activeLayerId = id;
      _magicDrawLayerId = id;
    });
  }

  Future<void> _handleMagicDrawExit() async {
    // Check if there is any content in any magic draw layer
    bool hasDrawing = _layers.any(
      (l) => l is SketchLayer && l.isMagicDraw && l.paths.isNotEmpty,
    );

    if (hasDrawing && !_isInpainting) {
      final confirm = await _confirmDiscardMagicDraw();
      if (confirm) {
        _cleanupMagicDraw();
      }
    } else {
      _cleanupMagicDraw();
    }
  }

  Future<bool> _confirmDiscardMagicDraw() async {
    return await ShowDialog.show<bool>(
          context,
          title: "Discard Magic Draw?",
          description:
              "Leaving Magic Draw will remove your sketches. Continue?",
          primaryButtonText: "Discard",
          isDestructive: true,
          onPrimaryPressed: () => Navigator.pop(context, true),
          secondaryButtonText: "Stay",
          onSecondaryPressed: () => Navigator.pop(context, false),
        ) ??
        false;
  }

  void _cleanupMagicDraw() {
    setState(() {
      // Remove all magic draw layers
      _layers.removeWhere((l) => l is SketchLayer && l.isMagicDraw);
      _isMagicDrawActive = false;
      _activeLayerId = _layers.isNotEmpty ? _layers.last.id : null;
      _magicDrawChangeStack.clear();
      _tempBaseImage = null;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!_isMagicDrawActive) return;

    setState(() {
      _currentPoints.add(
        DrawingPoint(offset: details.localPosition, paint: Paint()),
      );
    });

    // Throttle AI analysis
    if (DateTime.now().difference(_lastAnalysisTime).inMilliseconds > 2500) {
      _lastAnalysisTime = DateTime.now();
      _analyzeCanvas();
    }
  }

  Future<void> _onPanEnd(DragEndDetails details) async {
    if (!_isMagicDrawActive) return;

    setState(() {
      if (_currentPoints.isNotEmpty) {
        CanvasLayer? targetLayer;

        // 1. Try active layer
        if (_activeLayerId != null) {
          final index = _layers.indexWhere((l) => l.id == _activeLayerId);
          if (index != -1 &&
              _layers[index] is SketchLayer &&
              (_layers[index] as SketchLayer).isMagicDraw) {
            targetLayer = _layers[index];
          }
        }

        // 2. If not valid, find any magic layer or create one
        if (targetLayer == null) {
          try {
            targetLayer = _layers.lastWhere(
              (l) => l is SketchLayer && (l as SketchLayer).isMagicDraw,
            );
            _activeLayerId = targetLayer.id;
          } catch (_) {
            _addNewMagicLayer();
            targetLayer = _layers.last;
          }
        }

        if (targetLayer is SketchLayer) {
          final oldPaths = List<DrawingPath>.from(targetLayer.paths);
          targetLayer.paths.add(
            DrawingPath(
              points: List.from(_currentPoints),
              color: _selectedColor,
              strokeWidth: _strokeWidth,
              isEraser: _isEraser,
            ),
          );
          _recordMagicChange(oldPaths, targetLayer.id);
        }
        _currentPoints = [];
      }
    });
  }

  // GENERATION & INPAINTING
  Future<void> _processInpainting(String prompt, String modelId) async {
    FocusScope.of(context).unfocus();
    setState(() => _isInpainting = true);
    _resetInactivityTimer();

    try {
      // Check if there are image layers (which dictates the context)
      bool hasImageLayers = _layers.any((l) => l is ImageLayer);

      if (_tempBaseImage == null) {
        _tempBaseImage = await _captureCanvasToFile();
      }
      if (_tempBaseImage == null) return;

      // Consolidate paths from all active magic layers for mask
      List<DrawingPath> combinedPaths = [];
      for (var layer in _layers) {
        if (layer is SketchLayer && layer.isMagicDraw) {
          combinedPaths.addAll(layer.paths);
        }
      }

      File? maskFile = await _generateMaskImageFromPaths(
        combinedPaths,
        _canvasSize,
        _tempBaseImage,
      );
      if (maskFile == null) throw Exception("Failed to generate mask");

      String? newImageUrl;

      // Case 1: Inpainting
      if (hasImageLayers) {
        // API Inpainting
        if (modelId == 'inpaint_api') {
          newImageUrl = await FlaskService().inpaintApiImage(
            imagePath: _tempBaseImage!.path,
            maskPath: maskFile.path,
            prompt: prompt,
          );
        } else {
          // Local inpainting
          newImageUrl = await FlaskService().inpaintImage(
            imagePath: _tempBaseImage!.path,
            maskPath: maskFile.path,
            prompt: prompt,
          );
        }
      } else {
      // Case 2: Sketch to Image
        if (modelId == 'sketch_fusion') {
          newImageUrl = await FlaskService().sketchToImage(
            projectId: widget.projectId,
            sketchPath: _tempBaseImage!.path,
            userPrompt: prompt,
            imageDescription: _aiDescription,
          );
        } else {
          newImageUrl = await FlaskService().sketchToImage(
            projectId: widget.projectId,
            sketchPath: _tempBaseImage!.path,
            userPrompt: prompt,
            imageDescription: _aiDescription,
          );
        }
      }

      if (newImageUrl != null) {
        _addGeneratedImage(newImageUrl);
        if (!hasImageLayers && _layers.isNotEmpty) {
          _triggerBgRemovalBanner(_layers.last.id, newImageUrl);
        }
      }
    } catch (e) {
      debugPrint("Gen Error: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Generation failed")));
    } finally {
      setState(() {
        _isInpainting = false;
        _layers.removeWhere((l) => l is SketchLayer && l.isMagicDraw);
        _isMagicDrawActive = false;
        _tempBaseImage = null;
        // Select newly generated image
        if (_layers.isNotEmpty) _activeLayerId = _layers.last.id;
      });
    }
  }

  void _addGeneratedImage(String newImageUrl) {
    final id = 'gen_${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _layers.add(
        ImageLayer(
          id: id,
          data: {
            'id': id,
            'type': 'file_image',
            'content': newImageUrl,
            'position': const Offset(0, 0),
            'size': _canvasSize,
            'rotation': 0.0,
          },
        ),
      );
    });
  }

  // UI BUILDER
  @override
  Widget build(BuildContext context) {
    Map<String, dynamic>? selectedEl;
    if (_activeLayerId != null) {
      try {
        final layer = _layers.firstWhere((l) => l.id == _activeLayerId);
        if (layer is ImageLayer) selectedEl = layer.data;
      } catch (_) {}
    }

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
                    // Tapping background clears selection (unless inside magic draw)
                    if (!_isMagicDrawActive || _isMagicPanelDisabled) {
                      _exitEditMode();
                      setState(() => _activeLayerId = null);
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

                            // Render Layers
                            ..._layers.map((layer) {
                              if (!layer.isVisible)
                                return const SizedBox.shrink();

                              bool isFlashing = layer.id == _flashingLayerId;

                              if (layer is ImageLayer) {
                                final e = layer.data;
                                final bool isSelected =
                                    _activeLayerId == layer.id;

                                return ManipulatingBox(
                                  key: ValueKey(layer.id),
                                  id: e['id'],
                                  position: e['position'],
                                  size: e['size'],
                                  rotation: e['rotation'],
                                  type: e['type'],
                                  content: e['content'],
                                  styleData: e,
                                  isSelected: isSelected && !_isMagicDrawActive,
                                  isEditing: isSelected && _isEditingText,
                                  isFlashing: isFlashing,
                                  viewScale:
                                      _transformationController.value
                                          .getMaxScaleOnAxis(),
                                  transformationController:
                                      _transformationController,
                                  onTap: () {
                                    if (!_isMagicDrawActive)
                                      _setActiveLayer(layer.id);
                                  },
                                  onDoubleTap: () {
                                    if (e['type'] == 'text') _enterEditMode(e);
                                  },
                                  onDragStart: _handleGestureStart,
                                  onUpdate:
                                      (newPos, newSize, newRot) =>
                                          _handleElementUpdate(
                                            layer.id,
                                            newPos,
                                            newSize,
                                            newRot,
                                          ),
                                  onDragEnd: (newPos, newSize, newRot) {
                                    _handleElementUpdate(
                                      layer.id,
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
                                  focusNode: isSelected ? _textFocusNode : null,
                                );
                              } else if (layer is SketchLayer) {
                                return IgnorePointer(
                                  ignoring: true,
                                  child: RepaintBoundary(
                                    child: CustomPaint(
                                      size: Size.infinite,
                                      painter: CanvasPainter(
                                        paths: layer.paths,
                                        currentPoints: [],
                                        currentColor: Colors.transparent,
                                        currentWidth: 0,
                                        isEraser: false,
                                        overrideColor:
                                            isFlashing
                                                ? Colors.greenAccent
                                                : null,
                                      ),
                                    ),
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            }).toList(),

                            // Active Drawing Surface
                            IgnorePointer(
                              ignoring:
                                  !(_isMagicDrawActive &&
                                      !_isMagicPanelDisabled),
                              child: GestureDetector(
                                onPanStart: (d) {},
                                onPanUpdate: _onPanUpdate,
                                onPanEnd: _onPanEnd,
                                child: CustomPaint(
                                  size: Size.infinite,
                                  painter: CanvasPainter(
                                    paths: [],
                                    currentPoints:
                                        _isCapturingBase ? [] : _currentPoints,
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
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // AI Description Overlay
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
                  onPromptSubmit: _processInpainting,
                  isProcessing: _isInpainting,
                  onMagicPanelActivityToggle:
                      (d) => setState(() => _isMagicPanelDisabled = d),
                  isMagicPanelDisabled: _isMagicPanelDisabled,
                  onViewModeToggle: (e) => setState(() => _isViewMode = e),
                  hasImageLayers: _layers.any((l) => l is ImageLayer),
                ),

                TextToolsOverlay(
                  isActive: showTextOverlay && !_isMagicDrawActive,
                  isTextSelected: isTextSelected,
                  currentColor: Color(
                    (selectedEl?['style_color'] ?? Colors.black.value),
                  ),
                  currentFontSize:
                      (selectedEl?['style_fontSize'] ?? 24.0) as double,
                  onClose: () {
                    _exitEditMode();
                    setState(() => _activeLayerId = null);
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
                                  fontSize: 14,
                                ),
                              ),
                            ] else ...[
                              const Text(
                                "Remove background?",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: _confirmRemoveBackground,
                                child: const Icon(
                                  Icons.check,
                                  color: Colors.white,
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
                                  color: Colors.white54,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),

                // Layers Panel
                Positioned(
                  right: 16,
                  top:
                      SafeArea(child: Container()).minimum.top +
                      (_isMagicDrawActive ? 80 : 10), // Prevent overlap with description overlay
                  child: LayersPanel(
                    layers: _layers,
                    activeLayerId: _activeLayerId,
                    isOpen: _showLayersPanel,
                    onToggle:
                        () => setState(
                          () => _showLayersPanel = !_showLayersPanel,
                        ),
                    onReorder: _handleLayerReorder,
                    onDelete: _handleLayerDelete,
                    onToggleVisibility: _handleLayerVisibility,
                    onLayerTap: _setActiveLayer,
                    onAddLayer: _isMagicDrawActive ? _addNewMagicLayer : null,
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
                        _handleMagicDrawExit();
                      } else {
                        _startMagicDraw();
                      }
                    },
                    onMedia: () async {
                      if (_isMagicDrawActive) {
                        if (!await _confirmDiscardMagicDraw()) return;
                        _cleanupMagicDraw();
                      }
                      _pickImageFromGallery();
                    },
                    onStylesheet: () async {
                      if (_isMagicDrawActive) {
                        if (!await _confirmDiscardMagicDraw()) return;
                        _cleanupMagicDraw();
                      }
                      _openStylesheet();
                    },
                    onTools: () async {
                      if (_isMagicDrawActive) {
                        if (!await _confirmDiscardMagicDraw()) return;
                        _cleanupMagicDraw();
                      }
                      _showComingSoon('Tools');
                    },
                    onText: () async {
                      if (_isMagicDrawActive) {
                        if (!await _confirmDiscardMagicDraw()) return;
                        _cleanupMagicDraw();
                      }
                      _toggleTextTools();
                    },
                    onSelect: () async {
                      if (_isMagicDrawActive) {
                        if (!await _confirmDiscardMagicDraw()) return;
                        _cleanupMagicDraw();
                      }
                      _showComingSoon('Select');
                    },
                    onPlugins: () async {
                      if (_isMagicDrawActive) {
                        if (!await _confirmDiscardMagicDraw()) return;
                        _cleanupMagicDraw();
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

  // Helpers
  Future<void> _ensureBaseImageCaptured() async {
    if (_tempBaseImage != null) return;
    setState(() => _isCapturingBase = true);
    await Future.delayed(const Duration(milliseconds: 50));
    try {
      _tempBaseImage = await _captureCanvasToFile();
    } catch (e) {
      debugPrint("Failed to capture base: $e");
    } finally {
      if (mounted) setState(() => _isCapturingBase = false);
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
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
        '${tempDir.path}/canvas_capture_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await tempFile.writeAsBytes(byteData.buffer.asUint8List());
      return tempFile;
    } catch (e) {
      return null;
    }
  }

  Future<void> _analyzeCanvas() async {
    if (_isAnalyzing || _isInpainting) return;
    setState(() => _isAnalyzing = true);
    try {
      File? imageFile = await _captureCanvasToFile();
      if (imageFile == null) return;
      final description = await FlaskService().describeImage(
        imagePath: imageFile.path,
      );
      if (description != null && mounted) {
        setState(() {
          _aiDescription = description;
          _isDescriptionExpanded = false;
        });
      }
    } catch (e) {
      debugPrint("AI Error: $e");
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  Future<void> _fetchBrandColors() async {
    try {
      final int? pId = widget.projectId;
      if (pId == null) return;
      final project = await ProjectRepo().getProjectById(pId);
      if (project != null && project.globalStylesheet != null) {
        final styleData = StylesheetService().parse(project.globalStylesheet);
        if (mounted && styleData.colors.isNotEmpty)
          setState(() => _brandColors = styleData.colors);
      }
    } catch (e) {
      debugPrint("Error loading brand colors: $e");
    }
  }

  void _recordMagicChange(List<DrawingPath> oldPaths, String layerId) {
    final newPaths = List<DrawingPath>.from(
      (_layers.firstWhere((l) => l.id == layerId) as SketchLayer).paths,
    );
    _magicDrawChangeStack.add(
      Change(
        oldPaths,
        () {
          // Redo
          final index = _layers.indexWhere((l) => l.id == layerId);
          if (index != -1) {
            setState(
              () =>
                  _layers[index] = SketchLayer(
                    id: _layers[index].id,
                    isMagicDraw: true,
                    paths: newPaths,
                    isVisible: _layers[index].isVisible,
                  ),
            );
          }
        },
        (val) {
          // Undo
          final index = _layers.indexWhere((l) => l.id == layerId);
          if (index != -1) {
            setState(
              () =>
                  _layers[index] = SketchLayer(
                    id: _layers[index].id,
                    isMagicDraw: true,
                    paths: List.from(val),
                    isVisible: _layers[index].isVisible,
                  ),
            );
          }
        },
      ),
    );
  }

  void _recordChange(CanvasState oldState) {
    _resetInactivityTimer();
    final newState = CanvasState(_deepCopyLayers(_layers));
    _changeStack.add(
      Change(
        oldState,
        () => setState(() {
          _layers = _deepCopyLayers(newState.layers);
          _hasUnsavedChanges = true;
        }),
        (val) => setState(() {
          _layers = _deepCopyLayers(val.layers);
          _hasUnsavedChanges = true;
        }),
      ),
    );
    setState(() => _hasUnsavedChanges = true);
  }

  CanvasState _getCurrentState() => CanvasState(_deepCopyLayers(_layers));

  List<CanvasLayer> _deepCopyLayers(List<CanvasLayer> layers) {
    return layers.map((l) {
      if (l is SketchLayer) {
        return SketchLayer(
          id: l.id,
          paths: List<DrawingPath>.from(l.paths),
          isMagicDraw: l.isMagicDraw,
          isVisible: l.isVisible,
        );
      } else if (l is ImageLayer) {
        return ImageLayer(
          id: l.id,
          data: Map<String, dynamic>.from(l.data),
          isVisible: l.isVisible,
        );
      }
      return l;
    }).toList();
  }

  void _toggleTextTools() {
    setState(() {
      _isTextToolsActive = !_isTextToolsActive;
      _isMagicDrawActive = false;
      if (!_isTextToolsActive) {
        _exitEditMode();
        _activeLayerId = null;
      }
    });
  }

  void _addTextElement() {
    final oldState = _getCurrentState();
    final id = 'text_${DateTime.now().millisecondsSinceEpoch}';
    final initialPos = Offset(
      _canvasSize.width / 2 - 150,
      _canvasSize.height / 2 - 50,
    );
    final newElementData = {
      'id': id,
      'type': 'text',
      'content': 'Double tap to edit',
      'position': initialPos,
      'size': Size(300, 60),
      'rotation': 0.0,
      'style_color': Colors.black.value,
      'style_fontSize': 30.0,
    };
    setState(() {
      _layers.add(ImageLayer(id: id, data: newElementData));
      _activeLayerId = id;
      _isTextToolsActive = true;
    });
    _recordChange(oldState);
    _enterEditMode(newElementData);
  }

  void _enterEditMode(Map<String, dynamic> element) {
    setState(() {
      _activeLayerId = element['id'];
      _isEditingText = true;
      _textEditingController.text = element['content'];
      _textEditingController.selection = TextSelection.fromPosition(
        TextPosition(offset: _textEditingController.text.length),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_textFocusNode.canRequestFocus) _textFocusNode.requestFocus();
    });
  }

  void _exitEditMode() {
    if (_isEditingText && _activeLayerId != null) {
      final index = _layers.indexWhere((l) => l.id == _activeLayerId);
      if (index != -1 && _layers[index] is ImageLayer) {
        final layer = _layers[index] as ImageLayer;
        if (layer.data['content'] != _textEditingController.text) {
          final oldState = _getCurrentState();
          setState(() {
            layer.data['content'] = _textEditingController.text;
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
    if (_activeLayerId == null) return;
    final index = _layers.indexWhere((l) => l.id == _activeLayerId);
    if (index != -1 && _layers[index] is ImageLayer) {
      final oldState = _getCurrentState();
      setState(() => (_layers[index] as ImageLayer).data[key] = value);
      _recordChange(oldState);
    }
  }

  void _deleteSelectedElement() {
    if (_activeLayerId != null) {
      _handleLayerDelete(_activeLayerId!);
      setState(() {
        _isEditingText = false;
        _isTextToolsActive = false;
      });
      _textFocusNode.unfocus();
    }
  }

  void _handleElementUpdate(
    String id,
    Offset newPos,
    Size newSize,
    double newRot,
  ) {
    final index = _layers.indexWhere((l) => l.id == id);
    if (index != -1 && _layers[index] is ImageLayer) {
      setState(() {
        (_layers[index] as ImageLayer).data['position'] = newPos;
        (_layers[index] as ImageLayer).data['size'] = newSize;
        (_layers[index] as ImageLayer).data['rotation'] = newRot;
        _hasUnsavedChanges = true;
      });
    }
  }

  void _handleGestureEnd() {
    if (_gestureStartSnapshot != null) {
      _recordChange(_gestureStartSnapshot!);
      _gestureStartSnapshot = null;
    }
  }

  void _handleGestureStart() {
    if (_isMagicDrawActive) return;
    _gestureStartSnapshot = _getCurrentState();
  }

  void _triggerBgRemovalBanner(String elementId, String imagePath) {
    _bgRemovalBannerTimer?.cancel();
    setState(() {
      _showBgRemovalBanner = true;
      _bgRemovalTargetId = elementId;
      _bgRemovalTargetPath = imagePath;
    });

    // Automatically hide after 10 seconds
    _bgRemovalBannerTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _showBgRemovalBanner = false);
    });
  }

  Future<void> _confirmRemoveBackground() async {
    if (_bgRemovalTargetId == null || _bgRemovalTargetPath == null) return;
    _bgRemovalBannerTimer?.cancel();
    setState(() => _isRemovingBg = true);
    try {
      final newPath = await FlaskService().generateAsset(
        imagePath: _bgRemovalTargetPath!,
      );
      if (newPath != null && mounted) {
        final index = _layers.indexWhere((e) => e.id == _bgRemovalTargetId);
        if (index != -1 && _layers[index] is ImageLayer) {
          final oldState = _getCurrentState();
          setState(() {
            (_layers[index] as ImageLayer).data['content'] = newPath;
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
        paintImage(
          canvas: canvas,
          rect: Rect.fromLTWH(0, 0, size.width, size.height),
          image: frameInfo.image,
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
          for (int i = 1; i < path.points.length; i++)
            p.lineTo(path.points[i].offset.dx, path.points[i].offset.dy);
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
      return null;
    }
  }

  void _showComingSoon(String feature) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('$feature Coming soon')));
  void _openSettings() => _showComingSoon('Settings');

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
                  onAddAssets: _addAssetsToCanvas,
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
        final id =
            'asset_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(1000)}';
        _layers.add(
          ImageLayer(
            id: id,
            data: {
              'id': id,
              'type': 'file_image',
              'content': path,
              'position': centeredPosition,
              'size': Size(imageWidth, imageHeight),
              'rotation': 0.0,
            },
          ),
        );
        _activeLayerId = id;
      }
      _hasUnsavedChanges = true;
    });
    _recordChange(oldState);
  }

  Future<void> _handleBackNavigation() async {
    if (_isMagicDrawActive) {
      _handleMagicDrawExit();
      return;
    }
    if (!_hasUnsavedChanges && widget.existingFile != null) {
      Navigator.pop(context);
      return;
    }
    ShowDialog.show(
      context,
      title: "Save Changes?",
      description: "Do you want to save your canvas before leaving?",
      primaryButtonText: "Save",
      onPrimaryPressed: () async {
        Navigator.pop(context);
        await _saveCanvas();
        if (mounted && widget.existingFile != null) Navigator.pop(context);
      },
      secondaryButtonText: "Discard",
      onSecondaryPressed: () {
        Navigator.pop(context);
        Navigator.pop(context);
      },
    );
  }

  Future<String?> _showNameDialog() async {
    final nameController = TextEditingController(text: "Untitled Canvas");
    return await showDialog<String>(
      context: context,
      builder:
          (ctx) => Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Variables.radiusLarge),
            ),
            child: ShowDialog(
              title: "Save Canvas",
              content: CommonTextField(
                hintText: "Enter a name for your file",
                controller: nameController,
                autoFocus: true,
              ),
              primaryButtonText: "Save",
              onPrimaryPressed:
                  () => Navigator.pop(ctx, nameController.text.trim()),
              secondaryButtonText: "Cancel",
              onSecondaryPressed: () => Navigator.pop(ctx),
            ),
          ),
    );
  }

  Future<String?> _generatePreviewImage() async {
    try {
      final boundary =
          _canvasGlobalKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) return null;
      final directory = await getApplicationDocumentsDirectory();
      final previewDir = Directory('${directory.path}/previews');
      if (!await previewDir.exists()) await previewDir.create(recursive: true);
      final String filePath =
          '${previewDir.path}/preview_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(filePath).writeAsBytes(byteData.buffer.asUint8List());
      return filePath;
    } catch (e) {
      return null;
    }
  }

  Future<void> _saveCanvas() async {
    try {
      String fileName = "Canvas ${DateTime.now().toString().split(' ')[0]}";
      if (widget.existingFile == null) {
        final userFileName = await _showNameDialog();
        if (userFileName == null || userFileName.isEmpty) return;
        fileName = userFileName;
      }
      final String? previewPath = await _generatePreviewImage();
      final layersJson = _layers.map((l) => l.toMap()).toList();
      final canvasData = {
        'version': 2,
        'layers': layersJson,
        'width': _canvasSize.width,
        'height': _canvasSize.height,
        'preview_path': previewPath,
      };
      await _fileService.saveCanvasFile(
        projectId: widget.projectId,
        canvasData: canvasData,
        fileId: widget.existingFile?.id,
        fileName: widget.existingFile == null ? fileName : null,
      );
      setState(() => _hasUnsavedChanges = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Canvas Saved Successfully")),
        );
        if (widget.existingFile == null)
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ProjectFilePage(projectId: widget.projectId),
            ),
          );
      }
    } catch (e) {
      debugPrint("Save Error: $e");
    }
  }

  Future<void> _loadCanvasFromFile() async {
    try {
      final meta = await _fileService.getFileMetadata(
        widget.existingFile!.filePath,
      );
      if (meta.width > 0 && meta.height > 0)
        setState(() {
          _canvasSize = Size(meta.width, meta.height);
          _hasInitializedView = false;
        });
      final file = File(widget.existingFile!.filePath);
      if (await file.exists()) {
        final jsonString = await file.readAsString();
        final dynamic decoded = jsonDecode(jsonString);
        setState(() {
          _layers.clear();
          if (decoded is Map && decoded.containsKey('layers')) {
            for (var item in decoded['layers'])
              _layers.add(CanvasLayer.fromMap(item));
          } else if (decoded is Map && decoded.containsKey('elements')) {
            for (var e in _jsonToElements(decoded['elements']))
              _layers.add(ImageLayer(id: e['id'], data: e));
            if (decoded['paths'] != null) {
              final paths =
                  (decoded['paths'] as List)
                      .map((p) => DrawingPath.fromMap(p))
                      .toList();
              if (paths.isNotEmpty)
                _layers.add(SketchLayer(id: 'legacy_sketch', paths: paths));
            }
          }
          _hasUnsavedChanges = false;
          _activeLayerId = _layers.isNotEmpty ? _layers.last.id : null;
        });
        if (widget.injectedMedia != null)
          _addAssetsToCanvas([widget.injectedMedia!.path]);
      }
    } catch (e) {
      debugPrint("Error loading: $e");
      _initializeNewCanvas();
    }
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
          final id = '${DateTime.now().millisecondsSinceEpoch}_$i';
          _layers.add(
            ImageLayer(
              id: id,
              data: {
                'id': id,
                'type': 'file_image',
                'content': images[i].path,
                'position': centeredPosition,
                'size': Size(imageWidth, imageHeight),
                'rotation': 0.0,
              },
            ),
          );
          _activeLayerId = id;
        }
        _hasUnsavedChanges = true;
      });
      _recordChange(oldState);
    }
  }

  List<Map<String, dynamic>> _jsonToElements(List<dynamic> jsonList) {
    return jsonList.map((item) {
      final e = Map<String, dynamic>.from(item);
      if (e['position'] is Map)
        e['position'] = Offset(e['position']['dx'], e['position']['dy']);
      if (e['size'] is Map)
        e['size'] = Size(e['size']['width'], e['size']['height']);
      e['rotation'] = (e['rotation'] as num).toDouble();
      return e;
    }).toList();
  }

  Future<void> _exportProject() async {
    try {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Generating image...")));
      final boundary =
          _canvasGlobalKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) return;
      final img.Image? decodedImage = img.decodePng(
        byteData.buffer.asUint8List(),
      );
      if (decodedImage == null) return;
      final Uint8List jpgBytes = img.encodeJpg(decodedImage, quality: 90);
      final directory = await getTemporaryDirectory();
      final String filePath =
          '${directory.path}/export_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(filePath).writeAsBytes(jpgBytes);
      await Share.shareXFiles([
        XFile(filePath, mimeType: 'image/jpeg'),
      ], text: 'Check out my design created with CreekUI!');
    } catch (e) {
      debugPrint("Export Error: $e");
    }
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
              onPressed: _handleBackNavigation,
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
      actions: [
        SafeArea(
          child: Row(
            children: [
              if (_activeLayerId != null)
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
}
