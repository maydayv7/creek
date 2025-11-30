import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:undo/undo.dart';
import './canvas_toolbar/magic_draw_overlay.dart';
import '../../data/repos/project_repo.dart';
import '../../services/stylesheet_service.dart';

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
  List<Color> _brandColors = [];

  // --- NEW MAGIC DRAW STATE ---
  bool _isMagicDrawActive = false;

  // Drawing Data
  List<DrawingPath> _paths = [];
  List<DrawingPoint> _currentPoints = [];
  Color _selectedColor = const Color(0xFFFF4081);
  double _strokeWidth = 10.0;
  bool _isEraser = false;

  // Key to capture the drawing
  final GlobalKey _drawingKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _canvasSize = Size(widget.width, widget.height);

    _fetchBrandColors();

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

  Future<void> _fetchBrandColors() async {
    try {
      final int? pId = int.tryParse(widget.projectId);
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

  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: !_isMagicDrawActive ? _buildAppBar() : null,
      body: Stack(
        children: [
          // -------------------------------------------
          // LAYER 1: INTERACTIVE CANVAS + DRAWING LAYER
          // -------------------------------------------
          InteractiveViewer(
            // Disable panning/zooming when drawing
            scaleEnabled: !_isMagicDrawActive,
            panEnabled: !_isMagicDrawActive,
            boundaryMargin: const EdgeInsets.all(double.infinity),
            minScale: 0.1,
            maxScale: 5.0,
            transformationController: TransformationController(
              Matrix4.identity()
                ..scale(0.85)
                ..translate(40.0, 40.0),
            ),
            child: SizedBox(
              width: 3000,
              height: 3000,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // THE WHITE BOARD CONTAINER
                  Container(
                    width: _canvasSize.width,
                    height: _canvasSize.height,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 24,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRect(
                      child: Stack(
                        children: [
                          // 1. Existing Images/Elements
                          ...elements.map((e) => _buildCanvasElement(e)),

                          // 2. THE DRAWING LAYER (Only visible when active)
                          // Positioned exactly on top, clipped to the board
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

          // -------------------------------------------
          // LAYER 2: MAGIC DRAW TOOLS (Floating UI)
          // -------------------------------------------
          MagicDrawTools(
            isActive: _isMagicDrawActive,
            selectedColor: _selectedColor,
            strokeWidth: _strokeWidth,
            isEraser: _isEraser,
            brandColors: _brandColors, // PASS FETCHED COLORS HERE
            onClose: _saveAndCloseMagicDraw,
            onColorChanged: (c) => setState(() => _selectedColor = c),
            onWidthChanged: (w) => setState(() => _strokeWidth = w),
            onEraserToggle: (e) => setState(() => _isEraser = e),
          ),

          // -------------------------------------------
          // LAYER 3: BOTTOM NAVIGATION
          // -------------------------------------------
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: CanvasBottomBar(
              activeItem: _isMagicDrawActive ? "Magic Draw" : null,
              onMagicDraw:
                  () =>
                      setState(() => _isMagicDrawActive = !_isMagicDrawActive),
              onMedia: _pickImageFromGallery,
              onStylesheet: () => _showComingSoon('Stylesheet'),
              onTools: () => _showComingSoon('Tools'),
              onText: () => _showComingSoon('Text'),
              onSelect: () => _showComingSoon('Select'),
              onPlugins: () => _showComingSoon('Plugins'),
            ),
          ),
        ],
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

    return Positioned(
      left: position.dx,
      top: position.dy,
      child: Transform.rotate(
        angle: rotation,
        child: GestureDetector(
          onTap: () {
            if (!_isMagicDrawActive) setState(() => selectedId = e['id']);
          },
          child: Stack(
            children: [
              // Main Image Container
              Container(
                width: size.width,
                height: size.height,
                decoration: BoxDecoration(
                  border:
                      isSelected
                          ? Border.all(color: Colors.blue, width: 2)
                          : null,
                ),
                child:
                    e['type'] == 'file_image'
                        ? Image.file(File(e['content']), fit: BoxFit.contain)
                        : Container(),
              ),

              // Transform Controls (only when selected)
              if (isSelected && !_isMagicDrawActive) ...[
                // Resize Handle - Bottom Right
                Positioned(
                  right: -8,
                  bottom: -8,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      setState(() {
                        final newWidth = (size.width + details.delta.dx).clamp(
                          50.0,
                          _canvasSize.width,
                        );
                        final newHeight = (size.height + details.delta.dy)
                            .clamp(50.0, _canvasSize.height);
                        e['size'] = Size(newWidth, newHeight);
                      });
                    },
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.zoom_out_map,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

                // Rotate Handle - Top Right
                Positioned(
                  right: -8,
                  top: -8,
                  child: GestureDetector(
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
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.rotate_right,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

                // Move Handle - Center
                Positioned.fill(
                  child: GestureDetector(
                    onPanStart: (details) {
                      setState(() {
                        _dragStartPosition = position;
                      });
                    },
                    onPanUpdate: (details) {
                      setState(() {
                        final newPosition = position + details.delta;
                        e['position'] = Offset(
                          newPosition.dx.clamp(
                            0,
                            _canvasSize.width - size.width,
                          ),
                          newPosition.dy.clamp(
                            0,
                            _canvasSize.height - size.height,
                          ),
                        );
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
