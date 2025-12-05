import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:creekui/services/image_service.dart';
import 'package:creekui/services/note_service.dart';
import 'package:creekui/ui/styles/variables.dart';
import 'package:creekui/ui/widgets/primary_button.dart';
import 'package:creekui/ui/widgets/selection_overlay_painter.dart';
import 'package:creekui/ui/widgets/note_input_sheet.dart';
import 'project_board_page.dart';

// Temporary note model
class TempNote {
  final double normX, normY, normWidth, normHeight;
  final String content, category;
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
  final String? parentProjectName;

  const ImageSavePage({
    super.key,
    required this.imagePaths,
    required this.projectId,
    required this.projectName,
    this.isFromShare = true,
    this.parentProjectName,
  });

  @override
  State<ImageSavePage> createState() => _ImageSavePageState();
}

class _ImageSavePageState extends State<ImageSavePage> {
  final ImageService _imageService = ImageService();
  final NoteService _noteService = NoteService();

  late PageController _pageController;
  int _currentImageIndex = 0;

  final Map<int, Set<String>> _tagsPerImage = {};
  final Map<int, List<TempNote>> _notesPerImage = {};

  // A unique key for each image to calculate drawing coordinates correctly
  late List<GlobalKey> _imageKeys;

  bool _isSaving = false;

  // Drawing/Resizing state
  bool _isDrawMode =
      false; // True when initial drag is happening (to create box)
  bool _isResizing =
      false; // True when a selection box is visible and resizable
  Offset? _startPos;
  Offset? _currentPos;
  Rect? _finalSelectionRect;

  // Resizing state
  DragHandle _activeHandle = DragHandle.none;
  Offset? _startDragLocalOffset; // Used for moving the entire rect
  final Map<int, Size> _imageRenderSizes = {};
  final double _handleSize = 25.0;

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

  @override
  void initState() {
    super.initState();
    _pageController = PageController();

    // Generate a unique key for every image path
    _imageKeys = List.generate(widget.imagePaths.length, (_) => GlobalKey());
    for (int i = 0; i < widget.imagePaths.length; i++) {
      _tagsPerImage[i] = {};
      _notesPerImage[i] = [];
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // Actions
  void _activateSelectionMode() {
    setState(() {
      _isDrawMode = true; // Start initial drawing mode
      _isResizing = false;
      _finalSelectionRect = null;
      _startPos = null;
      _currentPos = null;
    });
  }

  void _resetSelectionMode() {
    setState(() {
      _isDrawMode = false;
      _isResizing = false;
      _finalSelectionRect = null;
      _startPos = null;
      _currentPos = null;
      _activeHandle = DragHandle.none;
    });
  }

  void _confirmSelectionAndShowModal() {
    if (_finalSelectionRect != null) {
      // Exit resizing mode before showing the modal to prevent visual conflict
      setState(() => _isResizing = false);
      _showNoteModal();
    }
  }

  void _toggleTag(String tag) {
    setState(() {
      final tags = _tagsPerImage[_currentImageIndex]!;
      if (tags.contains(tag))
        tags.remove(tag);
      else
        tags.add(tag);
    });
  }

  // Gestures
  Offset? _getLocalPosition(Offset globalPosition) {
    final currentKey = _imageKeys[_currentImageIndex];
    final RenderBox? box =
        currentKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    _imageRenderSizes[_currentImageIndex] = box.size;
    final local = box.globalToLocal(globalPosition);

    // Clamp coordinates to ensure we don't draw/drag outside the image
    final dx = local.dx.clamp(0.0, box.size.width);
    final dy = local.dy.clamp(0.0, box.size.height);
    return Offset(dx, dy);
  }

  DragHandle _getDragHandle(Offset pos) {
    if (_finalSelectionRect == null) return DragHandle.none;
    final rect = _finalSelectionRect!;

    // Check corners first
    if (Rect.fromCircle(
      center: rect.topLeft,
      radius: _handleSize,
    ).contains(pos))
      return DragHandle.topLeft;
    if (Rect.fromCircle(
      center: rect.topRight,
      radius: _handleSize,
    ).contains(pos))
      return DragHandle.topRight;
    if (Rect.fromCircle(
      center: rect.bottomLeft,
      radius: _handleSize,
    ).contains(pos))
      return DragHandle.bottomLeft;
    if (Rect.fromCircle(
      center: rect.bottomRight,
      radius: _handleSize,
    ).contains(pos))
      return DragHandle.bottomRight;
    if (rect.contains(pos)) return DragHandle.center;
    return DragHandle.none;
  }

  void _onPanStart(DragStartDetails details) {
    if (_isDrawMode) {
      final pos = _getLocalPosition(details.globalPosition);
      if (pos == null) return;
      setState(() {
        _startPos = pos;
        _currentPos = pos;
      });
    } else if (_isResizing && _finalSelectionRect != null) {
      final pos = _getLocalPosition(details.globalPosition);
      if (pos == null) return;
      final handle = _getDragHandle(pos);
      if (handle != DragHandle.none) {
        setState(() {
          _activeHandle = handle;
          if (handle == DragHandle.center) {
            _startDragLocalOffset = pos - _finalSelectionRect!.topLeft;
          }
        });
      }
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_isDrawMode) {
      final pos = _getLocalPosition(details.globalPosition);
      if (pos == null) return;
      setState(() => _currentPos = pos);
    } else if (_isResizing && _finalSelectionRect != null) {
      final pos = _getLocalPosition(details.globalPosition);
      if (pos == null || _activeHandle == DragHandle.none) return;

      setState(() {
        Rect newRect = _finalSelectionRect!;
        final newPoint = pos;

        switch (_activeHandle) {
          case DragHandle.topLeft:
            newRect = Rect.fromLTRB(
              newPoint.dx,
              newPoint.dy,
              newRect.right,
              newRect.bottom,
            );
            break;
          case DragHandle.topRight:
            newRect = Rect.fromLTRB(
              newRect.left,
              newPoint.dy,
              newPoint.dx,
              newRect.bottom,
            );
            break;
          case DragHandle.bottomLeft:
            newRect = Rect.fromLTRB(
              newPoint.dx,
              newRect.top,
              newRect.right,
              newPoint.dy,
            );
            break;
          case DragHandle.bottomRight:
            newRect = Rect.fromLTRB(
              newRect.left,
              newRect.top,
              newPoint.dx,
              newPoint.dy,
            );
            break;
          case DragHandle.center:
            if (_startDragLocalOffset != null) {
              final newTopLeft = newPoint - _startDragLocalOffset!;
              newRect = Rect.fromLTWH(
                newTopLeft.dx,
                newTopLeft.dy,
                newRect.width,
                newRect.height,
              );
            }
            break;
          case DragHandle.none:
            return;
        }

        final imageSize = _imageRenderSizes[_currentImageIndex];
        if (imageSize != null) {
          final cl = newRect.left.clamp(0.0, imageSize.width);
          final ct = newRect.top.clamp(0.0, imageSize.height);
          final cr = newRect.right.clamp(0.0, imageSize.width);
          final cb = newRect.bottom.clamp(0.0, imageSize.height);
          newRect = Rect.fromLTRB(cl, ct, cr, cb).normalize();
        } else {
          newRect = newRect.normalize();
        }

        if (newRect.width > 10 && newRect.height > 10)
          _finalSelectionRect = newRect;
      });
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (_isDrawMode && _startPos != null && _currentPos != null) {
      final rect = Rect.fromPoints(_startPos!, _currentPos!).normalize();
      if (rect.width < 10 || rect.height < 10) {
        _resetSelectionMode();
        return;
      }
      setState(() {
        _isDrawMode = false;
        _isResizing = true;
        _finalSelectionRect = rect;
        _startPos = null;
        _currentPos = null;
      });
    } else if (_isResizing) {
      setState(() {
        _activeHandle = DragHandle.none;
        _startDragLocalOffset = null;
      });
    }
  }

  // Modal
  void _showNoteModal() {
    String initialCategory = _availableTags.firstOrNull ?? 'General';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => NoteModalOverlay(
            screenSize: MediaQuery.of(context).size,
            modalContent: NoteInputSheet(
              categories: _availableTags,
              initialCategory: initialCategory,
              onSubmit: (content, category) {
                final imageSize = _imageRenderSizes[_currentImageIndex];
                if (_finalSelectionRect != null && imageSize != null) {
                  final nX = _finalSelectionRect!.center.dx / imageSize.width;
                  final nY = _finalSelectionRect!.center.dy / imageSize.height;
                  final nW = _finalSelectionRect!.width / imageSize.width;
                  final nH = _finalSelectionRect!.height / imageSize.height;

                  final newNote = TempNote(
                    normX: nX,
                    normY: nY,
                    normWidth: nW,
                    normHeight: nH,
                    content: content,
                    category: category,
                  );
                  setState(() {
                    _notesPerImage[_currentImageIndex]?.add(newNote);
                    _finalSelectionRect = null;
                  });
                  Navigator.pop(context);
                }
              },
            ),
          ),
    );
  }

  // Final Save
  Future<void> _onSaveToMoodboard() async {
    setState(() => _isSaving = true);
    try {
      for (int i = 0; i < widget.imagePaths.length; i++) {
        String path = widget.imagePaths[i];
        final file = File(path);
        if (!file.existsSync()) continue;

        final tags = _tagsPerImage[i] ?? {};
        final imageId = await _imageService.saveOrUpdateImage(
          file,
          widget.projectId,
          tags: tags.toList(),
        );

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
        if (widget.isFromShare)
          SystemNavigator.pop();
        else
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder:
                  (_) => ProjectBoardPage(
                    projectId: widget.projectId,
                    initialShowAlternateView: true,
                  ),
            ),
            (route) => false,
          );
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
    final String parentName = widget.parentProjectName?.trim() ?? '';
    final String titleText =
        parentName.isNotEmpty
            ? '$parentName / ${widget.projectName}'
            : widget.projectName;

    // Determine if user can pan/zoom the image carousel
    final isPageLocked = _isDrawMode || _isResizing;

    return Scaffold(
      resizeToAvoidBottomInset: false,
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
          titleText,
          style: Variables.headerStyle.copyWith(fontSize: 20),
        ),
        actions: [
          // Confirm Selection Button (Visible only in resizing mode)
          if (_isResizing && _finalSelectionRect != null)
            IconButton(
              icon: const Icon(Icons.check, color: Color(0xFF7C86FF), size: 24),
              onPressed: _confirmSelectionAndShowModal,
            ),
          // Cancel Selection Button (Visible only in drawing/resizing mode)
          if (_isDrawMode || _isResizing)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.black87, size: 24),
              onPressed: _resetSelectionMode,
            ),
        ],
      ),
      body: Column(
        children: [
          // Horizontal Image Carousel
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
                      // Disable page view scrolling if a selection process is active
                      physics:
                          isPageLocked
                              ? const NeverScrollableScrollPhysics()
                              : const PageScrollPhysics(),
                      itemCount: widget.imagePaths.length,
                      onPageChanged:
                          (index) => setState(() {
                            _currentImageIndex = index;
                            _resetSelectionMode();
                          }),
                      itemBuilder: (context, index) {
                        return LayoutBuilder(
                          builder: (context, constraints) {
                            // Determine the gesture handler based on the mode
                            final onPanStartHandler =
                                _isDrawMode
                                    ? _onPanStart
                                    : (_isResizing &&
                                            index == _currentImageIndex
                                        ? _onPanStart
                                        : null);
                            final onPanUpdateHandler =
                                _isDrawMode
                                    ? _onPanUpdate
                                    : (_isResizing &&
                                            index == _currentImageIndex
                                        ? _onPanUpdate
                                        : null);
                            final onPanEndHandler =
                                _isDrawMode
                                    ? _onPanEnd
                                    : (_isResizing &&
                                            index == _currentImageIndex
                                        ? _onPanEnd
                                        : null);

                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                InteractiveViewer(
                                  // Disable pan/scale if selection or resizing is active
                                  panEnabled: !isPageLocked,
                                  scaleEnabled: !isPageLocked,
                                  child: Center(
                                    child: GestureDetector(
                                      onPanStart: onPanStartHandler,
                                      onPanUpdate: onPanUpdateHandler,
                                      onPanEnd: onPanEndHandler,
                                      child: Stack(
                                        children: [
                                          Image.file(
                                            File(widget.imagePaths[index]),
                                            key: _imageKeys[index],
                                            fit: BoxFit.contain,
                                            width: double.infinity,
                                          ),
                                          // Drawing Overlay (if in drawing mode)
                                          if (_isDrawMode &&
                                              index == _currentImageIndex &&
                                              _startPos != null &&
                                              _currentPos != null)
                                            Positioned.fill(
                                              child: CustomPaint(
                                                painter:
                                                    SelectionOverlayPainter(
                                                      rect:
                                                          Rect.fromPoints(
                                                            _startPos!,
                                                            _currentPos!,
                                                          ).normalize(),
                                                      isResizing: false,
                                                    ),
                                              ),
                                            ),
                                          // Final Selection Rect (if in resizing mode)
                                          if (_isResizing &&
                                              index == _currentImageIndex &&
                                              _finalSelectionRect != null)
                                            Positioned.fill(
                                              child: CustomPaint(
                                                painter:
                                                    SelectionOverlayPainter(
                                                      rect:
                                                          _finalSelectionRect!,
                                                      isResizing: true,
                                                      activeHandle:
                                                          _activeHandle,
                                                    ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                // Existing Note Indicators (Dots) - visible only if no selection is active
                                if (!isPageLocked)
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
                                  }),
                                // Page Dots
                                if (widget.imagePaths.length > 1 &&
                                    !isPageLocked)
                                  Positioned(
                                    bottom: 12,
                                    left: 0,
                                    right: 0,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: List.generate(
                                        widget.imagePaths.length,
                                        (i) => Container(
                                          margin: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                          ),
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color:
                                                _currentImageIndex == i
                                                    ? Colors.blue
                                                    : Colors.white.withOpacity(
                                                      0.5,
                                                    ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                // Notes Button (Visible only when not drawing/resizing)
                                if (!isPageLocked)
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
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      icon: const Icon(
                                        Icons.assignment_outlined,
                                        size: 18,
                                      ),
                                      label: const Text(
                                        "Notes",
                                        style: TextStyle(
                                          fontFamily: 'GeneralSans',
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                // Instruction overlay (for initial drawing)
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
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
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
                                // Instruction overlay (for resizing)
                                if (_isResizing &&
                                    _finalSelectionRect != null &&
                                    _activeHandle == DragHandle.none)
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
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: const Text(
                                          "Adjust area or tap checkmark to confirm",
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Bottom Form (Tags & Save)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tags box
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEFEFE),
                    border: Border.all(color: Variables.borderSubtle),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header section
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'What did you like about this image?',
                              style: TextStyle(
                                fontFamily: 'GeneralSans',
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (widget.imagePaths.length > 1)
                              Text(
                                "Image ${_currentImageIndex + 1}/${widget.imagePaths.length}",
                                style: Variables.captionStyle,
                              ),
                          ],
                        ),
                      ),
                      const Divider(
                        height: 0,
                        thickness: 1,
                        color: Color(0xFFE4E4E7),
                      ),
                      // Content section with tags
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Wrap(
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
                                              ? const Color(0xFFE0E7FF)
                                              : Colors.white,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color:
                                            isSelected
                                                ? const Color(0xFF7C86FF)
                                                : Colors.grey[300]!,
                                      ),
                                    ),
                                    child: Text(
                                      tag,
                                      style: TextStyle(
                                        fontFamily: 'GeneralSans',
                                        fontSize: 14,
                                        color:
                                            isSelected
                                                ? const Color(0xFF27272A)
                                                : Colors.black87,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  text:
                      'Save ${widget.imagePaths.length > 1 ? "All" : ""} to Moodboard',
                  isLoading: _isSaving,
                  onPressed: _onSaveToMoodboard,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
