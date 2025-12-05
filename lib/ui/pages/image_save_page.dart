import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:creekui/services/image_service.dart';
import 'package:creekui/services/note_service.dart';
import 'project_board_page.dart';

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

// --- STATE MACHINE FOR SELECTION MODE ---
enum DragHandle {
  none,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  center, // For dragging the entire box
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

  // --- DRAWING/RESIZING STATE ---
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
      setState(() {
        _isResizing = false;
      });
      _showNoteModal();
    }
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

  // --- DRAWING/RESIZING GESTURES (UPDATED LOGIC) ---
  final double _handleSize =
      25.0; // The size of the touch area for resizing handles

  // Helper: Convert global screen touch to local image coordinates
  Offset? _getLocalPosition(Offset globalPosition) {
    final currentKey = _imageKeys[_currentImageIndex];
    final RenderBox? box =
        currentKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    _imageRenderSizes[_currentImageIndex] = box.size;

    // Convert global to local
    final local = box.globalToLocal(globalPosition);

    // Clamp coordinates to ensure we don't draw/drag outside the image
    final dx = local.dx.clamp(0.0, box.size.width);
    final dy = local.dy.clamp(0.0, box.size.height);

    return Offset(dx, dy);
  }

  // --- INITIAL DRAWING HANDLERS ---
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

    // Create the rect from the corrected local positions, normalizing points
    final rect = Rect.fromPoints(_startPos!, _currentPos!).normalize();

    // Check if the selected area is too small
    if (rect.width < 10 || rect.height < 10) {
      _resetSelectionMode();
      return;
    }

    setState(() {
      _isDrawMode = false;
      _isResizing = true; // Enter resizing/confirming mode
      _finalSelectionRect = rect;
      _startPos = null;
      _currentPos = null;
    });
  }

  // --- RESIZING HANDLERS ---
  DragHandle _getDragHandle(Offset pos) {
    if (_finalSelectionRect == null) return DragHandle.none;

    final rect = _finalSelectionRect!;
    // final center = rect.center; // Not used but helpful for context
    // final top = rect.top;
    // final bottom = rect.bottom;
    // final left = rect.left;
    // final right = rect.right;

    // Check corners
    if (Rect.fromCircle(
      center: rect.topLeft,
      radius: _handleSize,
    ).contains(pos)) {
      return DragHandle.topLeft;
    } else if (Rect.fromCircle(
      center: rect.topRight,
      radius: _handleSize,
    ).contains(pos)) {
      return DragHandle.topRight;
    } else if (Rect.fromCircle(
      center: rect.bottomLeft,
      radius: _handleSize,
    ).contains(pos)) {
      return DragHandle.bottomLeft;
    } else if (Rect.fromCircle(
      center: rect.bottomRight,
      radius: _handleSize,
    ).contains(pos)) {
      return DragHandle.bottomRight;
    }
    // Check if dragging the whole box (center)
    else if (rect.contains(pos)) {
      // Only allow center drag if we are not actively drawing (i.e. we are in resizing mode)
      return DragHandle.center;
    }

    return DragHandle.none;
  }

  void _onResizeStart(DragStartDetails details) {
    if (!_isResizing || _finalSelectionRect == null) return;

    final pos = _getLocalPosition(details.globalPosition);
    if (pos == null) return;

    final handle = _getDragHandle(pos);
    if (handle != DragHandle.none) {
      setState(() {
        _activeHandle = handle;
        // Calculate offset for moving the entire rect, not for resizing
        if (handle == DragHandle.center) {
          _startDragLocalOffset = pos - _finalSelectionRect!.topLeft;
        }
      });
    }
  }

  void _onResizeUpdate(DragUpdateDetails details) {
    if (!_isResizing ||
        _finalSelectionRect == null ||
        _activeHandle == DragHandle.none) {
      return;
    }

    final pos = _getLocalPosition(details.globalPosition);
    if (pos == null) return;

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

      // Clamp the final rectangle to the image boundaries (0,0 to width, height)
      final imageSize = _imageRenderSizes[_currentImageIndex];
      if (imageSize != null) {
        final clampedLeft = newRect.left.clamp(0.0, imageSize.width);
        final clampedTop = newRect.top.clamp(0.0, imageSize.height);
        final clampedRight = newRect.right.clamp(0.0, imageSize.width);
        final clampedBottom = newRect.bottom.clamp(0.0, imageSize.height);

        newRect =
            Rect.fromLTRB(
              clampedLeft,
              clampedTop,
              clampedRight,
              clampedBottom,
            ).normalize();
      } else {
        newRect = newRect.normalize();
      }

      // Ensure min size
      if (newRect.width > 10 && newRect.height > 10) {
        _finalSelectionRect = newRect;
      }
    });
  }

  void _onResizeEnd(DragEndDetails details) {
    if (!_isResizing) return;
    setState(() {
      _activeHandle = DragHandle.none;
      _startDragLocalOffset = null;
    });
  }

  //ADD NOTE MODAL
  void _showNoteModal() {
    _commentController.clear();
    // Ensure we have a valid selection to proceed
    if (_finalSelectionRect == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final mediaQuery = MediaQuery.of(context);

        // 1. Wrap the content variable in StatefulBuilder
        final modalContent = StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- ROW 1: Header ---
                      Row(
                        children: [
                          // Avatar
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFFFAFAFA),
                                width: 1.25,
                              ),
                            ),
                            child: const CircleAvatar(
                              radius: 15,
                              backgroundColor: Colors.grey,
                              child: Icon(
                                Icons.person,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),

                          // User name
                          const Text(
                            "Alex",
                            style: TextStyle(
                              fontFamily: 'GeneralSans',
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                              letterSpacing: 0.4,
                              height: 16 / 12,
                            ),
                          ),

                          const Spacer(),

                          // Dropdown
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE0E7FF),
                              borderRadius: BorderRadius.circular(1000),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value:
                                    _categories.contains(_selectedCategory)
                                        ? _selectedCategory
                                        : null,
                                hint: const Text(
                                  "Type",
                                  style: TextStyle(
                                    fontFamily: 'GeneralSans',
                                    fontSize: 12,
                                    fontWeight: FontWeight.normal,
                                    color: Color(0xFF27272A),
                                    height: 16 / 12,
                                  ),
                                ),
                                isDense: true,
                                icon: const Icon(
                                  Icons.arrow_drop_down,
                                  size: 20,
                                  color: Color(0xFF27272A),
                                ),
                                style: const TextStyle(
                                  fontFamily: 'GeneralSans',
                                  fontSize: 12,
                                  fontWeight: FontWeight.normal,
                                  color: Color(0xFF27272A),
                                  height: 16 / 12,
                                ),
                                focusColor: Colors.transparent,
                                dropdownColor: Colors.white,
                                items:
                                    _categories
                                        .map(
                                          (c) => DropdownMenuItem(
                                            value: c,
                                            child: Text(
                                              c,
                                              style: const TextStyle(
                                                fontFamily: 'GeneralSans',
                                                fontSize: 12,
                                                fontWeight: FontWeight.normal,
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                onChanged: (v) {
                                  setModalState(() {
                                    _selectedCategory = v!;
                                  });
                                },
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // --- ROW 2: Input & Send ---
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFFF4F4F5),
                                border: Border.all(
                                  color: const Color(0xFFE4E4E7),
                                  width: 1,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: TextField(
                                controller: _commentController,
                                autofocus: true,
                                maxLines: null,
                                style: const TextStyle(
                                  fontFamily: 'GeneralSans',
                                  fontSize: 12,
                                  fontWeight: FontWeight.normal,
                                  color: Color(0xFF27272A),
                                  height: 16 / 12,
                                ),
                                decoration: InputDecoration(
                                  hintText:
                                      "I love the serif font and how it is used...",
                                  hintStyle: const TextStyle(
                                    fontFamily: 'GeneralSans',
                                    fontSize: 12,
                                    fontWeight: FontWeight.normal,
                                    color: Color(0xFF27272A),
                                    height: 16 / 12,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 8),

                          // Send button
                          IconButton(
                            icon: const Icon(
                              Icons.send,
                              color: Color(0xFF27272A),
                              size: 24,
                            ),
                            onPressed: () {
                              _addTempNote();
                              Navigator.pop(context);
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 24,
                              minHeight: 24,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
            );
          },
        );

        return NoteModalOverlay(
          modalContent: modalContent,
          screenSize: mediaQuery.size,
        );
      },
    );
  }

  void _addTempNote() {
    // Use the stored render size for the current image index
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
        _finalSelectionRect = null; // Clear selection after saving note
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
        final tags = _tagsPerImage[i] ?? {};
        final imageId = await _imageService.saveOrUpdateImage(
          file,
          widget.projectId,
          tags: tags.toList(),
        );

        // 2. Save Notes for this specific image
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
        // Find the most suitable ScaffoldMessengerState
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All images saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        if (widget.isFromShare) {
          SystemNavigator.pop();
        } else {
          // Navigate to project board page in grid view (alternate view)
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder:
                  (_) => ProjectBoardPage(
                    projectId: widget.projectId,
                    initialShowAlternateView: true, // Show grid view
                  ),
            ),
            (route) => false, // Remove all previous routes
          );
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
          style: const TextStyle(
            fontFamily: 'GeneralSans',
            color: Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.w500,
            height: 24 / 20,
            letterSpacing: 0,
          ),
        ),
        actions: [
          // CONFIRM SELECTION BUTTON (Visible only in resizing mode)
          if (_isResizing && _finalSelectionRect != null)
            IconButton(
              icon: const Icon(Icons.check, color: Color(0xFF7C86FF), size: 24),
              onPressed: _confirmSelectionAndShowModal,
            ),
          // CANCEL SELECTION BUTTON (Visible only in drawing/resizing mode)
          if (_isDrawMode || _isResizing)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.black87, size: 24),
              onPressed: _resetSelectionMode,
            ),
        ],
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
                      // Disable page view scrolling if a selection process is active
                      physics:
                          isPageLocked
                              ? const NeverScrollableScrollPhysics()
                              : const PageScrollPhysics(),
                      itemCount: widget.imagePaths.length,
                      onPageChanged: (index) {
                        setState(() {
                          _currentImageIndex = index;
                          _resetSelectionMode(); // Reset selection mode on page change
                        });
                      },
                      itemBuilder: (context, index) {
                        return LayoutBuilder(
                          builder: (context, constraints) {
                            // Determine the gesture handler based on the mode
                            final onPanStartHandler =
                                _isDrawMode
                                    ? _onPanStart
                                    : (_isResizing ? _onResizeStart : null);
                            final onPanUpdateHandler =
                                _isDrawMode
                                    ? _onPanUpdate
                                    : (_isResizing ? _onResizeUpdate : null);
                            final onPanEndHandler =
                                _isDrawMode
                                    ? _onPanEnd
                                    : (_isResizing ? _onResizeEnd : null);

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
                                          // THE IMAGE WITH UNIQUE KEY
                                          Image.file(
                                            File(widget.imagePaths[index]),
                                            key: _imageKeys[index],
                                            fit: BoxFit.contain,
                                            width: double.infinity,
                                          ),
                                          // DRAWING OVERLAY (if in drawing mode)
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
                                                      isResizing: false,
                                                    ),
                                              ),
                                            ),
                                          // FINAL SELECTION RECT (if in resizing mode)
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
                                // EXISTING NOTE INDICATORS (Dots) - visible only if no selection is active
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
                                              color: Colors.black.withValues(
                                                alpha: 0.3,
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
                                // PAGE DOTS
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
                                        (index) => Container(
                                          margin: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                          ),
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color:
                                                _currentImageIndex == index
                                                    ? Colors.blue
                                                    : Colors.white.withValues(
                                                      alpha: 0.5,
                                                    ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                // NOTES BUTTON (Visible only when not drawing/resizing)
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
                                          height: 20 / 14,
                                          letterSpacing: 0.25,
                                        ),
                                      ),
                                    ),
                                  ),
                                // INSTRUCTION OVERLAY (for initial drawing)
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
                                            fontFamily: 'GeneralSans',
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.normal,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                // INSTRUCTION OVERLAY (for resizing)
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
                                            fontFamily: 'GeneralSans',
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.normal,
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
          // --- BOTTOM FORM (TAGS & SAVE) ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tags box matching Figma design
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEFEFE),
                    border: Border.all(
                      color: const Color(0xFFE4E4E7),
                      width: 1,
                    ),
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
                                color: Colors.black,
                                letterSpacing: 0.25,
                                height: 20 / 14,
                              ),
                            ),
                            if (widget.imagePaths.length > 1)
                              Text(
                                "Image ${_currentImageIndex + 1}/${widget.imagePaths.length}",
                                style: const TextStyle(
                                  fontFamily: 'GeneralSans',
                                  color: Colors.grey,
                                  fontSize: 12,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Divider
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
                                        fontWeight: FontWeight.normal,
                                        height: 20 / 14,
                                        letterSpacing: 0,
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
                                fontFamily: 'GeneralSans',
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                height: 20 / 14,
                                letterSpacing: 0.25,
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

// ---------------------------------------------------------
// --- HELPER CLASSES FOR CUSTOM HALF-PAGE MODAL OVERLAY ---
// ---------------------------------------------------------

class NoteModalOverlay extends StatelessWidget {
  final Widget modalContent;
  final Size screenSize;

  const NoteModalOverlay({
    super.key,
    required this.modalContent,
    required this.screenSize,
  });

  @override
  Widget build(BuildContext context) {
    // The target initial height of the bottom sheet (half the screen height is no longer the minimum)
    final mq = MediaQuery.of(context);
    final keyboardHeight = mq.viewInsets.bottom;
    final systemBottomPadding = mq.padding.bottom;

    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(
          bottom: keyboardHeight, // Moves modal up to avoid keyboard
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: screenSize.height),
          child: Material(
            // Using Material to provide the background, border radius, and shadow.
            color: Colors.white,
            elevation:
                10, // Replicating the box shadow of the old container for visual style.
            shadowColor: Colors.black26,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              // Allows scrolling if content + keyboard height exceed screen height
              child: Padding(
                // Add system bottom padding to respect the safe area/gesture bar
                padding: EdgeInsets.only(bottom: systemBottomPadding),
                child: modalContent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- EXTENSION TO NORMALIZE RECT ---
extension on Rect {
  Rect normalize() {
    return Rect.fromLTRB(
      left < right ? left : right,
      top < bottom ? top : bottom,
      left > right ? left : right,
      top > bottom ? top : bottom,
    );
  }
}

// --- OVERLAY PAINTER (KEPT FOR MAIN IMAGE SELECTION HIGHLIGHT) ---
class SelectionOverlayPainter extends CustomPainter {
  final Rect rect;
  final bool isResizing;
  final DragHandle activeHandle;

  SelectionOverlayPainter({
    required this.rect,
    required this.isResizing,
    this.activeHandle = DragHandle.none,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. DIM BACKGROUND (Black overlay with hole for the selected area)
    if (isResizing) {
      final Path backgroundPath =
          Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
      final Path holePath = Path()..addRect(rect);
      final Path overlayPath = Path.combine(
        ui.PathOperation.difference,
        backgroundPath,
        holePath,
      );

      canvas.drawPath(overlayPath, Paint()..color = Colors.black54);
    }

    // 2. DRAW DASHED BORDER
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

    // 3. DRAW CENTER DOT (Only needed in drawing mode, the app bar button replaces the functionality in resizing mode)
    if (!isResizing) {
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

    // 4. DRAW RESIZE HANDLES (Only in resizing mode)
    if (isResizing) {
      final List<Offset> corners = [
        rect.topLeft,
        rect.topRight,
        rect.bottomLeft,
        rect.bottomRight,
      ];

      final Paint handleShadow =
          Paint()
            ..color = Colors.black.withValues(alpha: 0.3)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

      final Paint handleFill = Paint()..color = Colors.white;
      final Paint handleBorder =
          Paint()
            ..color = const Color(0xFF448AFF)
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke;

      const double handleRadius = 8;

      for (final corner in corners) {
        canvas.drawCircle(corner, handleRadius, handleShadow);
        canvas.drawCircle(corner, handleRadius, handleFill);
        canvas.drawCircle(corner, handleRadius, handleBorder);
      }
    }
  }

  @override
  bool shouldRepaint(covariant SelectionOverlayPainter oldDelegate) =>
      rect != oldDelegate.rect ||
      isResizing != oldDelegate.isResizing ||
      activeHandle != oldDelegate.activeHandle;
}
