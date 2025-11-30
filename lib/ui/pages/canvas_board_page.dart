import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:undo/undo.dart';
import './canvas_toolbar/magic_draw_overlay.dart';
import './canvas_toolbar/text_tools_overlay.dart';

// --- MODELS ---
class DrawingPoint {
  final Offset offset;
  final Paint paint;
  const DrawingPoint({required this.offset, required this.paint});
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
}

class CanvasBoardPage extends StatefulWidget {
  final String projectId;
  final double width;
  final double height;
  final File? initialImage;
  const CanvasBoardPage({
    super.key,
    required this.projectId,
    required this.width,
    required this.height,
    this.initialImage,
  });

  @override
  State<CanvasBoardPage> createState() => _CanvasBoardPageState();
}

class _CanvasBoardPageState extends State<CanvasBoardPage> {
  // --- EXISTING STATE ---
  final ChangeStack _changeStack = ChangeStack();
  final ImagePicker _picker = ImagePicker();
  List<Map<String, dynamic>> elements = [];
  String? selectedId;
  Offset? _dragStartPosition;
  late Size _canvasSize;

  // --- NEW TOOL STATE ---
  bool _isMagicDrawActive = false;
  bool _isTextToolsActive = false;

  // --- INLINE EDITING STATE ---
  bool _isEditingText = false;
  final TextEditingController _textEditingController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();

  // Drawing Data
  List<DrawingPath> _paths = [];
  List<DrawingPoint> _currentPoints = [];
  Color _selectedColor = const Color(0xFFFF4081);
  double _strokeWidth = 10.0;
  bool _isEraser = false;

  // Key to capture the drawing
  final GlobalKey _drawingKey = GlobalKey();

  // --- VIEWPORT CONTROLLER ---
  final TransformationController _transformationController = TransformationController();
  bool _hasInitializedView = false; // To ensure auto-zoom happens only once

  @override
  void initState() {
    super.initState();
    _canvasSize = Size(widget.width, widget.height);

    if (widget.initialImage != null) {
      elements.add({
        'id': 'bg_${DateTime.now().millisecondsSinceEpoch}',
        'type': 'file_image',
        'content': widget.initialImage!.path,
        'position': const Offset(0, 0),
        'size': Size(widget.width, widget.height),
        'rotation': 0.0,
      });
    }
  }

  @override
  void dispose() {
    _textEditingController.dispose();
    _textFocusNode.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  // --- TEXT FEATURE LOGIC ---

  void _toggleTextTools() {
    setState(() {
      _isTextToolsActive = !_isTextToolsActive;
      _isMagicDrawActive = false; // Disable drawing if text is active
      // If closing toolbar, finalize edits and deselect
      if (!_isTextToolsActive) {
        _exitEditMode();
        selectedId = null;
      }
    });
  }

  void _addTextElement() {
    final oldList = _deepCopy(elements);
    final id = 'text_${DateTime.now().millisecondsSinceEpoch}';

    // Place roughly in visual center
    final initialPos = Offset(
      _canvasSize.width / 2 - 110, 
      _canvasSize.height / 2 - 40
    );

    // Scale font size so it's visible on large posters
    final double defaultFontSize = (_canvasSize.width / 20).clamp(24.0, 96.0);

    final newElement = {
      'id': id,
      'type': 'text',
      'content': 'Tap to edit', 
      'position': initialPos,
      'size': Size(220, defaultFontSize * 2), 
      'rotation': 0.0,
      'style_color': Colors.black.value,
      'style_fontSize': defaultFontSize,
    };

    setState(() {
      elements.add(newElement);
      _bringToFront(id); // Ensure it's on top
      selectedId = id; 
      _isTextToolsActive = true; 
    });

    _changeStack.add(Change(
      oldList,
      () => setState(() => elements = _deepCopy(elements)),
      (val) => setState(() => elements = val),
    ));

    // Immediately start editing
    _enterEditMode(newElement);
  }

  void _enterEditMode(Map<String, dynamic> element) {
    setState(() {
      selectedId = element['id'];
      _isEditingText = true;
      _textEditingController.text = element['content'];
      _textEditingController.selection = TextSelection.fromPosition(
        TextPosition(offset: _textEditingController.text.length)
      );
    });

    // Request focus after build
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
        // Save changes
        final oldList = _deepCopy(elements);
        setState(() {
          elements[index]['content'] = _textEditingController.text;
          _isEditingText = false;
        });
        _changeStack.add(Change(
          oldList,
          () => setState(() => elements = _deepCopy(elements)),
          (val) => setState(() => elements = val),
        ));
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
    setState(() {
      elements[index][key] = value;
    });
  }

  void _deleteSelectedElement() {
    if (selectedId == null) return;
    final oldList = _deepCopy(elements);
    setState(() {
      elements.removeWhere((e) => e['id'] == selectedId);
      selectedId = null;
      _isEditingText = false;
    });
    _textFocusNode.unfocus();
    _changeStack.add(Change(
        oldList, 
        () => setState(() => elements = _deepCopy(elements)), 
        (val) => setState(() => elements = val)
    ));
  }

  void _bringToFront(String id) {
    final index = elements.indexWhere((e) => e['id'] == id);
    if (index != -1 && index != elements.length - 1) {
      setState(() {
        final item = elements.removeAt(index);
        elements.add(item);
      });
    }
  }

  Map<String, dynamic>? get _selectedElementData {
    if (selectedId == null) return null;
    try {
      return elements.firstWhere((e) => e['id'] == selectedId);
    } catch (_) {
      return null;
    }
  }

  Widget build(BuildContext context) {
    // Determine overlay state
    final selectedEl = _selectedElementData;
    final bool isTextSelected = selectedEl != null && selectedEl['type'] == 'text';
    final bool showTextOverlay = _isTextToolsActive || isTextSelected;

    return Scaffold(
      backgroundColor: const Color(0xFFE0E0E0), // Darker BG to see canvas bounds
      appBar: !_isMagicDrawActive ? _buildAppBar() : null,
      body: LayoutBuilder(
        builder: (context, constraints) {
          // --- AUTO-ZOOM LOGIC ---
          // Automatically fit large canvases (like Posters) to screen on load
          if (!_hasInitializedView) {
            _hasInitializedView = true;
            final double scaleX = (constraints.maxWidth - 40) / _canvasSize.width;
            final double scaleY = (constraints.maxHeight - 40) / _canvasSize.height;
            final double initialScale = math.min(scaleX, scaleY).clamp(0.01, 1.0);
            
            final double transX = (constraints.maxWidth - (_canvasSize.width * initialScale)) / 2;
            final double transY = (constraints.maxHeight - (_canvasSize.height * initialScale)) / 2;

            _transformationController.value = Matrix4.identity()
              ..translate(transX, transY)
              ..scale(initialScale);
          }

          return Stack(
            children: [
              // -------------------------------------------
              // LAYER 1: INTERACTIVE CANVAS + DRAWING LAYER
              // -------------------------------------------
              GestureDetector(
                // Tap outside to deselect
                onTap: () {
                  if (!_isMagicDrawActive) {
                    _exitEditMode();
                    setState(() => selectedId = null);
                  }
                },
                behavior: HitTestBehavior.translucent, // Catches clicks on empty space
                child: InteractiveViewer(
                  transformationController: _transformationController,
                  // Disable constrained to allow full size posters (e.g. 3000px height)
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
                      alignment: Alignment.center,
                      children: [
                        // THE WHITE BOARD CONTAINER
                        Container(
                          width: double.infinity,
                          height: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 30,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ClipRect(
                            child: Stack(
                              children: [
                                // 1. Existing Images/Elements
                                ...elements.map((e) => _buildCanvasElement(e)),

                                // 2. THE DRAWING LAYER
                                if (_isMagicDrawActive)
                                  RepaintBoundary(
                                    key: _drawingKey,
                                    child: GestureDetector(
                                      onPanStart: _onPanStart,
                                      onPanUpdate: _onPanUpdate,
                                      onPanEnd: _onPanEnd,
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
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // -------------------------------------------
              // LAYER 2: OVERLAYS (Magic Draw & Text Tools)
              // -------------------------------------------
              MagicDrawTools(
                isActive: _isMagicDrawActive,
                selectedColor: _selectedColor,
                strokeWidth: _strokeWidth,
                isEraser: _isEraser,
                onClose: _saveAndCloseMagicDraw,
                onColorChanged: (c) => setState(() => _selectedColor = c),
                onWidthChanged: (w) => setState(() => _strokeWidth = w),
                onEraserToggle: (e) => setState(() => _isEraser = e),
              ),

              // Text Toolbar Overlay
              TextToolsOverlay(
                isActive: showTextOverlay && !_isMagicDrawActive,
                isTextSelected: isTextSelected,
                currentColor: Color(selectedEl?['style_color'] ?? Colors.black.value),
                currentFontSize: (selectedEl?['style_fontSize'] ?? 24.0) as double,
                onClose: () {
                  _exitEditMode();
                  setState(() {
                    _isTextToolsActive = false;
                    selectedId = null;
                  });
                },
                onAddText: _addTextElement, 
                onDelete: _deleteSelectedElement,
                onColorChanged: (c) => _updateSelectedTextProperty('style_color', c.value),
                onFontSizeChanged: (s) => _updateSelectedTextProperty('style_fontSize', s),
              ),

              // -------------------------------------------
              // LAYER 3: BOTTOM NAVIGATION
              // -------------------------------------------
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: CanvasBottomBar(
                  activeItem: _isMagicDrawActive ? "Magic Draw" : (_isTextToolsActive ? "Text" : null),
                  onMagicDraw:
                      () =>
                          setState(() {
                            _isMagicDrawActive = !_isMagicDrawActive;
                            _isTextToolsActive = false;
                            _exitEditMode();
                          }),
                  onMedia: _pickImageFromGallery,
                  onStylesheet: () => _showComingSoon('Stylesheet'),
                  onTools: () => _showComingSoon('Tools'),
                  onText: _toggleTextTools, // UPDATED: Toggles text tools
                  onSelect: () => _showComingSoon('Select'),
                  onPlugins: () => _showComingSoon('Plugins'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- DRAWING LOGIC ---

  void _onPanStart(DragStartDetails details) {
    // No logic needed here for now
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _currentPoints.add(
        DrawingPoint(
          offset:
              details
                  .localPosition, // Uses local coordinates relative to White Board
          paint: Paint(),
        ),
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
      }
    });
  }

  // --- SAVE & CLOSE LOGIC ---

  Future<void> _saveAndCloseMagicDraw() async {
    // 1. If nothing was drawn, just close
    if (_paths.isEmpty && _currentPoints.isEmpty) {
      setState(() => _isMagicDrawActive = false);
      return;
    }

    try {
      // 2. Capture the Drawing Layer as an Image
      RenderRepaintBoundary boundary =
          _drawingKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0); // High res
      ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      // 3. Save to File
      final directory = await getApplicationDocumentsDirectory();
      final String filePath =
          '${directory.path}/drawing_${DateTime.now().millisecondsSinceEpoch}.png';
      File imgFile = File(filePath);
      await imgFile.writeAsBytes(pngBytes);

      // 4. Add as a new Element to the Board
      final oldList = _deepCopy(elements);
      setState(() {
        elements.add({
          'id': 'drawing_${DateTime.now().millisecondsSinceEpoch}',
          'type': 'file_image',
          'content': filePath,
          // Position it over the whole canvas since that's where we drew it
          'position': const Offset(0, 0),
          'size': _canvasSize,
          'rotation': 0.0,
        });

        // 5. Clear the drawing paths and close mode
        _paths.clear();
        _currentPoints.clear();
        _isMagicDrawActive = false;
      });

      // Add to Undo Stack
      _changeStack.add(
        Change(
          oldList,
          () => setState(() => elements = _deepCopy(elements)),
          (val) => setState(() => elements = val),
        ),
      );
    } catch (e) {
      debugPrint("Error saving drawing: $e");
      setState(() => _isMagicDrawActive = false);
    }
  }

  // --- EXISTING LOGIC ---

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      leadingWidth: 140,
      leading: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: SvgPicture.asset(
                'assets/icons/arrow-left-s-line.svg',
                width: 22,
              ),
              onPressed: () => Navigator.of(context).maybePop(),
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
              IconButton(
                icon: SvgPicture.asset(
                  'assets/icons/file-image-line.svg',
                  width: 22,
                ),
                onPressed: _openLayers,
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

  Widget _buildCanvasElement(Map<String, dynamic> e) {
    final isSelected = selectedId == e['id'];
    final position = e['position'] as Offset;
    final size = e['size'] as Size;
    final rotation = (e['rotation'] ?? 0.0) as double;
    final type = e['type'];
    final isEditingThis = isSelected && _isEditingText && type == 'text';

    return Positioned(
      left: position.dx,
      top: position.dy,
      child: Transform.rotate(
        angle: rotation,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent, // Ensures taps work on transparent areas
          onTap: () {
            if (!_isMagicDrawActive) {
              if (_isEditingText && selectedId != e['id']) {
                _exitEditMode();
              }
              setState(() {
                selectedId = e['id'];
                if (type == 'text') _isTextToolsActive = true;
              });
              _bringToFront(e['id']);
            }
          },
          onDoubleTap: () {
            if (type == 'text') {
              _enterEditMode(e);
            }
          },
          child: Stack(
            clipBehavior: Clip.none, // Allow handles to be visible outside element bounds
            children: [
              // Main Element Container
              Container(
                width: size.width,
                height: size.height,
                decoration: BoxDecoration(
                  border:
                      isSelected
                          // Fix border width scaling so it looks consistent at zoom levels
                          ? Border.all(
                              color: Colors.blue, 
                              width: 2.0 / (_transformationController.value.getMaxScaleOnAxis())
                            )
                          : type == 'text'
                              // Dashed-like grey border for unselected text
                              ? Border.all(color: Colors.grey.withOpacity(0.5), width: 1.0)
                              : null,
                  color: type == 'text' ? Colors.white.withOpacity(0.01) : null,
                ),
                child:
                    e['type'] == 'file_image'
                        ? Image.file(File(e['content']), fit: BoxFit.contain)
                        : e['type'] == 'text'
                            ? _buildTextContent(e, isEditingThis)
                            : Container(),
              ),

              // Transform Controls (only when selected and not editing text)
              if (isSelected && !_isMagicDrawActive && !isEditingThis) ...[
                // Resize Handle - Bottom Right
                Positioned(
                  right: -12,
                  bottom: -12,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (details) {
                      setState(() {
                        final newWidth = (size.width + details.delta.dx).clamp(
                          50.0,
                          _canvasSize.width,
                        );
                        final newHeight = (size.height + details.delta.dy)
                            .clamp(30.0, _canvasSize.height);
                        e['size'] = Size(newWidth, newHeight);
                      });
                    },
                    child: _buildHandle(Icons.zoom_out_map, Colors.blue),
                  ),
                ),

                // Rotate Handle - Top Right
                Positioned(
                  right: -12,
                  top: -12,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (details) {
                      setState(() {
                        final center = Offset(
                          position.dx + size.width / 2,
                          position.dy + size.height / 2,
                        );
                        final angle =
                            (details.globalPosition - center).direction;
                        e['rotation'] = angle;
                      });
                    },
                    child: _buildHandle(Icons.rotate_right, Colors.green),
                  ),
                ),

                // Move Handle - Full Overlay
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onPanStart: (details) {
                      setState(() {
                        _dragStartPosition = position;
                      });
                    },
                    onPanUpdate: (details) {
                      setState(() {
                        // Apply zoom scaling to drag distance
                        final scale = _transformationController.value.getMaxScaleOnAxis();
                        final newPosition = position + (details.delta / scale);
                        e['position'] = newPosition;
                      });
                    },
                    onPanEnd: (details) {
                      if (_dragStartPosition != null &&
                          _dragStartPosition != position) {
                        _addDragToUndoStack(
                          e['id'],
                          _dragStartPosition!,
                          position,
                        );
                      }
                      _dragStartPosition = null;
                    },
                    child: Container(color: Colors.transparent),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextContent(Map<String, dynamic> e, bool isEditing) {
    final style = TextStyle(
      fontSize: (e['style_fontSize'] ?? 24.0) as double,
      color: Color(e['style_color'] ?? Colors.black.value),
      fontFamily: 'GeneralSans',
    );

    if (isEditing) {
      // Auto-growing TextField
      return Center(
        child: IntrinsicWidth(
          child: TextField(
            controller: _textEditingController,
            focusNode: _textFocusNode,
            autofocus: true,
            maxLines: null,
            textAlign: TextAlign.center,
            style: style,
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              isDense: true,
            ),
            onChanged: (text) {
              final span = TextSpan(text: text, style: style);
              final tp = TextPainter(text: span, textDirection: TextDirection.ltr);
              tp.layout(maxWidth: _canvasSize.width); 
              setState(() {
                // Resize element to fit text
                e['size'] = Size(tp.width + 40, tp.height + 40); 
              });
            },
          ),
        ),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: Center(
          child: Text(
            e['content'],
            textAlign: TextAlign.center,
            style: style,
          ),
        ),
      );
    }
  }

  Widget _buildHandle(IconData icon, Color color) {
    // Keep handles consistent size regardless of zoom
    final double scale = 1 / _transformationController.value.getMaxScaleOnAxis();
    return Transform.scale(
      scale: scale.clamp(1.0, 5.0),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
        ),
        child: Icon(
          icon,
          size: 14,
          color: Colors.white,
        ),
      ),
    );
  }

  Future<void> _pickImageFromGallery() async {
    final List<XFile> images = await _picker.pickMultiImage();
    if (images.isNotEmpty) {
      final oldList = _deepCopy(elements);

      // Smart grid layout for multiple images
      final double imageSize = 150.0;
      final double padding = 20.0;
      final int columns = ((_canvasSize.width - padding * 2) /
              (imageSize + padding))
          .floor()
          .clamp(1, 100);

      setState(() {
        for (int i = 0; i < images.length; i++) {
          final int row = i ~/ columns;
          final int col = i % columns;

          final double x = padding + (col * (imageSize + padding));
          final double y = padding + (row * (imageSize + padding));

          elements.add({
            'id': '${DateTime.now().millisecondsSinceEpoch}_$i',
            'type': 'file_image',
            'content': images[i].path,
            'position': Offset(
              x.clamp(padding, _canvasSize.width - imageSize - padding),
              y.clamp(padding, _canvasSize.height - imageSize - padding),
            ),
            'size': const Size(150, 150),
            'rotation': 0.0,
          });
        }
      });

      _changeStack.add(
        Change(
          oldList,
          () => setState(() => elements = _deepCopy(elements)),
          (val) => setState(() => elements = val),
        ),
      );
    }
  }

  void _addDragToUndoStack(String id, Offset oldPos, Offset newPos) {
    final oldList = _deepCopy(elements);
    final oldItem = oldList.firstWhere((x) => x['id'] == id);
    oldItem['position'] = oldPos;
    final newList = _deepCopy(elements);
    _changeStack.add(
      Change(
        oldList,
        () => setState(() => elements = newList),
        (val) => setState(() => elements = val),
      ),
    );
  }

  List<Map<String, dynamic>> _deepCopy(List<Map<String, dynamic>> source) {
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
  void _exportProject() => _showComingSoon('Export');
  void _openSettings() => _showComingSoon('Settings');
  void _showComingSoon(String feature) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('$feature coming soon')));
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

    // Draw committed paths
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

    // Draw current stroke
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
      for (int i = 1; i < currentPoints.length; i++) {
        p.lineTo(currentPoints[i].offset.dx, currentPoints[i].offset.dy);
      }
      canvas.drawPath(p, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CanvasPainter oldDelegate) => true;
}

// --- BOTTOM BAR ---

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
        top: false,
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
                isActive ? Colors.blue : Colors.black87,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isActive ? Colors.blue : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
