import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/image_service.dart';
import '../../services/note_service.dart';

// --- HELPER CLASS FOR TEMPORARY NOTES ---
class TempNote {
  final double normX;
  final double normY;
  final double normWidth;
  final double normHeight;
  final String content;
  final String category;

  TempNote({
    required this.normX,
    required this.normY,
    required this.normWidth,
    required this.normHeight,
    required this.content,
    required this.category,
  });
}

class ImageSavePage extends StatefulWidget {
  final List<String> imagePaths;
  final int projectId;
  final String projectName;
  final bool isFromShare;

  const ImageSavePage({
    Key? key,
    required this.imagePaths,
    required this.projectId,
    required this.projectName,
    this.isFromShare = true,
  }) : super(key: key);

  @override
  State<ImageSavePage> createState() => _ImageSavePageState();
}

class _ImageSavePageState extends State<ImageSavePage> {
  // --- SERVICES ---
  final ImageService _imageService = ImageService();
  final NoteService _noteService = NoteService();

  // --- STATE ---
  late PageController _pageController;
  int _currentImageIndex = 0;

  // Data storage per image
  final Map<int, Set<String>> _tagsPerImage = {};
  final Map<int, List<TempNote>> _notesPerImage = {};

  // CRITICAL: A unique key for EACH image to calculate drawing coordinates correctly
  late List<GlobalKey> _imageKeys;

  final TextEditingController _commentController = TextEditingController();
  String _selectedCategory = 'Compositions';
  bool _isSaving = false;

  // --- DRAWING STATE ---
  bool _isDrawMode = false;
  Offset? _startPos;
  Offset? _currentPos;
  Rect? _finalSelectionRect;

  // FIXED: Store render size per image index
  final Map<int, Size> _imageRenderSizes = {};

  final List<String> _availableTags = [
    'Compositions',
    'Subject',
    'Fonts',
    'Background',
    'Texture',
    'Colours',
    'Material Look',
    'Lighting',
    'Style',
    'Era',
    'Emotion',
  ];

  final List<String> _categories = [
    'Compositions',
    'Subject',
    'Fonts',
    'Background',
    'Texture',
    'Colours',
    'Material Look',
    'Lighting',
    'Style',
    'Era',
    'Emotion',
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();

    // Generate a unique key for every image path
    _imageKeys = List.generate(widget.imagePaths.length, (_) => GlobalKey());

    // Initialize data maps
    for (int i = 0; i < widget.imagePaths.length; i++) {
      _tagsPerImage[i] = {};
      _notesPerImage[i] = [];
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  // --- ACTIONS ---
  void _activateSelectionMode() {
    setState(() {
      _isDrawMode = true;
      _finalSelectionRect = null;
      _startPos = null;
      _currentPos = null;
    });
  }

  void _toggleTag(String tag) {
    setState(() {
      final currentTags = _tagsPerImage[_currentImageIndex]!;
      if (currentTags.contains(tag)) {
        currentTags.remove(tag);
      } else {
        currentTags.add(tag);
      }
    });
  }

  // --- DRAWING GESTURES (FIXED LOGIC) ---
  // Helper: Convert global screen touch to local image coordinates
  Offset? _getLocalPosition(Offset globalPosition) {
    // Get the key for the currently visible image
    final currentKey = _imageKeys[_currentImageIndex];
    final RenderBox? box =
        currentKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;

    // FIXED: Store the render size for this specific image
    _imageRenderSizes[_currentImageIndex] = box.size;

    // Convert global to local
    final local = box.globalToLocal(globalPosition);

    // Clamp coordinates to ensure we don't draw outside the image
    final dx = local.dx.clamp(0.0, box.size.width);
    final dy = local.dy.clamp(0.0, box.size.height);

    return Offset(dx, dy);
  }

  void _onPanStart(DragStartDetails details) {
    if (!_isDrawMode) return;

    final pos = _getLocalPosition(details.globalPosition);
    if (pos == null) return;

    setState(() {
      _startPos = pos;
      _currentPos = pos;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!_isDrawMode) return;

    final pos = _getLocalPosition(details.globalPosition);
    if (pos == null) return;

    setState(() {
      _currentPos = pos;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (!_isDrawMode || _startPos == null || _currentPos == null) return;

    // Create the rect from the corrected local positions
    final rect = Rect.fromPoints(_startPos!, _currentPos!);
    _finalSelectionRect = rect;

    setState(() {
      _isDrawMode = false;
      _startPos = null;
      _currentPos = null;
    });

    _showNoteModal();
  }

  // --- ADD NOTE MODAL ---
  void _showNoteModal() {
    _commentController.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Add Note",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 16),
                  // Category Dropdown
                  DropdownButtonFormField<String>(
                    value: _selectedCategory,
                    decoration: InputDecoration(
                      labelText: "Category",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items:
                        _categories
                            .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)),
                            )
                            .toList(),
                    onChanged: (v) => setState(() => _selectedCategory = v!),
                  ),
                  const SizedBox(height: 12),
                  // Note Text
                  TextField(
                    controller: _commentController,
                    autofocus: true,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: "Enter details...",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        _addTempNote();
                        Navigator.pop(context);
                      },
                      child: const Text(
                        "Save Note",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _addTempNote() {
    // FIXED: Use the stored render size for the current image index
    final imageSize = _imageRenderSizes[_currentImageIndex];

    if (_finalSelectionRect != null &&
        imageSize != null &&
        _commentController.text.isNotEmpty) {
      // Calculate Normalized Coordinates (0.0 - 1.0)
      final nX = _finalSelectionRect!.center.dx / imageSize.width;
      final nY = _finalSelectionRect!.center.dy / imageSize.height;
      final nW = _finalSelectionRect!.width / imageSize.width;
      final nH = _finalSelectionRect!.height / imageSize.height;

      final newNote = TempNote(
        normX: nX,
        normY: nY,
        normWidth: nW,
        normHeight: nH,
        content: _commentController.text.trim(),
        category: _selectedCategory,
      );

      setState(() {
        _notesPerImage[_currentImageIndex]?.add(newNote);
      });
    }
  }

  // --- FINAL SAVE ---
  Future<void> _onSaveToMoodboard() async {
    setState(() => _isSaving = true);

    try {
      for (int i = 0; i < widget.imagePaths.length; i++) {
        String path = widget.imagePaths[i];
        final file = File(path);
        if (!file.existsSync()) continue;

        // 1. Save Image
        final imageId = await _imageService.saveImage(file, widget.projectId);

        // 2. Save Tags for this specific image
        final tags = _tagsPerImage[i] ?? {};
        if (tags.isNotEmpty) {
          await _imageService.updateTags(imageId, tags.toList());
        }

        // 3. Save Notes for this specific image
        final notes = _notesPerImage[i] ?? [];
        for (var note in notes) {
          await _noteService.addNote(
            imageId,
            note.content,
            note.category,
            normX: note.normX,
            normY: note.normY,
            normWidth: note.normWidth,
            normHeight: note.normHeight,
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All images saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        if (widget.isFromShare) {
          SystemNavigator.pop();
        } else {
          Navigator.popUntil(context, (route) => route.isFirst);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentTags = _tagsPerImage[_currentImageIndex] ?? {};

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            size: 20,
            color: Colors.black,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.projectName,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Column(
        children: [
          // --- HORIZONTAL IMAGE CAROUSEL ---
          Expanded(
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PageView.builder(
                      controller: _pageController,
                      itemCount: widget.imagePaths.length,
                      onPageChanged: (index) {
                        setState(() {
                          _currentImageIndex = index;
                          _isDrawMode = false;
                          _finalSelectionRect = null;
                        });
                      },
                      itemBuilder: (context, index) {
                        return LayoutBuilder(
                          builder: (context, constraints) {
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                InteractiveViewer(
                                  panEnabled: !_isDrawMode,
                                  scaleEnabled: !_isDrawMode,
                                  child: Center(
                                    child: GestureDetector(
                                      onPanStart:
                                          _isDrawMode ? _onPanStart : null,
                                      onPanUpdate:
                                          _isDrawMode ? _onPanUpdate : null,
                                      onPanEnd: _isDrawMode ? _onPanEnd : null,
                                      child: Stack(
                                        children: [
                                          // THE IMAGE WITH UNIQUE KEY
                                          Image.file(
                                            File(widget.imagePaths[index]),
                                            key: _imageKeys[index],
                                            fit: BoxFit.contain,
                                            width: double.infinity,
                                          ),
                                          // DRAWING OVERLAY (Only if drawing on THIS page)
                                          if (_isDrawMode &&
                                              index == _currentImageIndex &&
                                              _startPos != null &&
                                              _currentPos != null)
                                            Positioned.fill(
                                              child: CustomPaint(
                                                painter:
                                                    SelectionOverlayPainter(
                                                      rect: Rect.fromPoints(
                                                        _startPos!,
                                                        _currentPos!,
                                                      ),
                                                    ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                // EXISTING NOTE INDICATORS (Dots)
                                ...(_notesPerImage[index] ?? []).map((note) {
                                  return Positioned(
                                    left:
                                        (note.normX * constraints.maxWidth) -
                                        10,
                                    top:
                                        (note.normY * constraints.maxHeight) -
                                        10,
                                    child: Container(
                                      width: 20,
                                      height: 20,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(
                                              0.3,
                                            ),
                                            blurRadius: 4,
                                            offset: const Offset(0, 1),
                                          ),
                                        ],
                                        border: Border.all(
                                          color: const Color(0xFF7C4DFF),
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ],
                            );
                          },
                        );
                      },
                    ),
                    // PAGE DOTS
                    if (widget.imagePaths.length > 1)
                      Positioned(
                        bottom: 12,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            widget.imagePaths.length,
                            (index) => Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color:
                                    _currentImageIndex == index
                                        ? Colors.blue
                                        : Colors.white.withOpacity(0.5),
                              ),
                            ),
                          ),
                        ),
                      ),
                    // NOTES BUTTON
                    Positioned(
                      bottom: 24,
                      right: 12,
                      child: ElevatedButton.icon(
                        onPressed: _activateSelectionMode,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.assignment_outlined, size: 18),
                        label: const Text(
                          "Notes",
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    // INSTRUCTION OVERLAY
                    if (_isDrawMode && _startPos == null)
                      Positioned(
                        top: 20,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              "Drag on image to select area",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
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
          // --- BOTTOM FORM (TAGS & SAVE) ---
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Tags',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (widget.imagePaths.length > 1)
                      Text(
                        "Image ${_currentImageIndex + 1}/${widget.imagePaths.length}",
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      _availableTags.map((tag) {
                        final isSelected = currentTags.contains(tag);
                        return GestureDetector(
                          onTap: () => _toggleTag(tag),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  isSelected
                                      ? const Color(0xFFEEF0FF)
                                      : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color:
                                    isSelected
                                        ? const Color(0xFF7C4DFF)
                                        : Colors.grey[300]!,
                              ),
                            ),
                            child: Text(
                              tag,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight:
                                    isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                color:
                                    isSelected
                                        ? const Color(0xFF7C4DFF)
                                        : Colors.black87,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _onSaveToMoodboard,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(27),
                      ),
                    ),
                    child:
                        _isSaving
                            ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                            : Text(
                              'Save ${widget.imagePaths.length > 1 ? "All" : ""} to Moodboard',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- OVERLAY PAINTER ---
class SelectionOverlayPainter extends CustomPainter {
  final Rect rect;

  SelectionOverlayPainter({required this.rect});

  @override
  void paint(Canvas canvas, Size size) {
    final Path backgroundPath =
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final Path holePath = Path()..addRect(rect);
    final Path overlayPath = Path.combine(
      ui.PathOperation.difference,
      backgroundPath,
      holePath,
    );

    canvas.drawPath(overlayPath, Paint()..color = Colors.black54);

    final Paint borderPaint =
        Paint()
          ..color = const Color(0xFF448AFF)
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke;

    double dashWidth = 6;
    double dashSpace = 4;
    Path borderPath = Path()..addRect(rect);

    for (ui.PathMetric pathMetric in borderPath.computeMetrics()) {
      double distance = 0.0;
      while (distance < pathMetric.length) {
        canvas.drawPath(
          pathMetric.extractPath(distance, distance + dashWidth),
          borderPaint,
        );
        distance += (dashWidth + dashSpace);
      }
    }

    final Paint dotPaint =
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;

    canvas.drawCircle(
      rect.center,
      8,
      Paint()
        ..color = Colors.black26
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(rect.center, 6, dotPaint);
  }

  @override
  bool shouldRepaint(covariant SelectionOverlayPainter oldDelegate) =>
      rect != oldDelegate.rect;
}
