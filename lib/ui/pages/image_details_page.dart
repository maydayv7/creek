import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/image_service.dart';
import '../../services/note_service.dart';
import '../../data/models/note_model.dart';
import '../../data/models/image_model.dart';

// --- STATE MACHINE FOR SELECTION MODE ---
enum DragHandle {
  none,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  center, // For dragging the entire box
}

// --- HELPER CLASS FOR TEMPORARY NOTES (Needed for consistency) ---
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

class ImageDetailsPage extends StatefulWidget {
  final String imagePath;
  final String imageId;
  final int projectId;

  const ImageDetailsPage({
    Key? key,
    required this.imagePath,
    required this.imageId,
    required this.projectId,
  }) : super(key: key);

  @override
  State<ImageDetailsPage> createState() => _ImageDetailsPageState();
}

class _ImageDetailsPageState extends State<ImageDetailsPage> {
  // Services
  final NoteService _noteService = NoteService();
  final ImageService _imageService = ImageService();

  // State
  ImageModel? _imageModel;
  List<NoteModel> _notes = [];
  List<String> _currentTags = [];
  bool _isLoading = true;
  int? _activeNoteId;

  // -- DRAWING/RESIZING STATE --
  bool _isDrawMode = false;
  bool _isResizing = false;
  final GlobalKey _imageKey = GlobalKey();

  Offset? _startPos;
  Offset? _currentPos;
  Rect? _finalSelectionRect;
  Size? _imageRenderSize;

  // Resizing state
  DragHandle _activeHandle = DragHandle.none;
  Offset? _startDragLocalOffset;

  final double _handleSize = 25.0; // Resizing constant

  // Master List of Tags
  final List<String> _allAvailableTags = [
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
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final image = await _imageService.getImage(widget.imageId);
      final notes = await _noteService.getNotesForImage(widget.imageId);
      final tags = await _imageService.getTags(widget.imageId);

      if (mounted) {
        setState(() {
          _imageModel = image;
          _notes = notes;
          _currentTags = tags;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading details: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- ACTIONS ---

  void _resetSelectionMode() {
    setState(() {
      _isDrawMode = false;
      _isResizing = false;
      _finalSelectionRect = null;
      _startPos = null;
      _currentPos = null;
      _activeHandle = DragHandle.none;
      _startDragLocalOffset = null;
    });
  }

  void _activateDrawMode() {
    _resetSelectionMode(); // Reset any previous selection
    setState(() {
      _isDrawMode = true; // Start initial drawing mode
    });
  }

  void _confirmSelectionAndShowModal() {
    if (_finalSelectionRect != null) {
      // Exit resizing mode before showing the modal
      setState(() {
        _isResizing = false;
        _activeHandle = DragHandle.none;
      });
      _showAddNoteInputDialog();
    }
  }

  void _openNotesSheet({int? highlightId}) {
    setState(() => _activeNoteId = highlightId);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => _NotesListSheet(
            notes: _notes,
            highlightId: highlightId,
            onAddNotePressed: () {
              Navigator.pop(context);
              _activateDrawMode();
            },
          ),
    ).whenComplete(() {
      setState(() => _activeNoteId = null);
    });
  }

  // --- DRAWING/RESIZING GESTURES ---

  Offset? _getLocalPosition(Offset globalPosition) {
    final RenderBox? box =
        _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;

    // Store the render size
    _imageRenderSize = box.size;

    // Convert global to local
    final local = box.globalToLocal(globalPosition);

    // Clamp coordinates to ensure we don't draw/drag outside the image
    final dx = local.dx.clamp(0.0, box.size.width);
    final dy = local.dy.clamp(0.0, box.size.height);

    return Offset(dx, dy);
  }

  // --- DRAWING HANDLERS ---
  void _onPanStart(DragStartDetails details) {
    if (_isDrawMode) {
      // START DRAWING
      final pos = _getLocalPosition(details.globalPosition);
      if (pos == null) return;
      setState(() {
        _startPos = pos;
        _currentPos = pos;
      });
    } else if (_isResizing && _finalSelectionRect != null) {
      // START RESIZING/MOVING
      _onResizeStart(details);
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_isDrawMode) {
      // DRAWING
      final pos = _getLocalPosition(details.globalPosition);
      if (pos == null) return;
      setState(() {
        _currentPos = pos;
      });
    } else if (_isResizing && _finalSelectionRect != null) {
      // RESIZING/MOVING
      _onResizeUpdate(details);
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (_isDrawMode && _startPos != null && _currentPos != null) {
      // END DRAWING, TRANSITION TO RESIZING MODE
      final rect = Rect.fromPoints(_startPos!, _currentPos!).normalize();

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
    } else if (_isResizing) {
      // END RESIZING/MOVING
      _onResizeEnd(details);
    }
  }

  // --- RESIZING HANDLERS ---
  DragHandle _getDragHandle(Offset pos) {
    if (_finalSelectionRect == null) return DragHandle.none;

    final rect = _finalSelectionRect!;

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
        // Calculate offset for moving the entire rect
        if (handle == DragHandle.center) {
          _startDragLocalOffset = pos - _finalSelectionRect!.topLeft;
        }
      });
    }
  }

  void _onResizeUpdate(DragUpdateDetails details) {
    if (!_isResizing ||
        _finalSelectionRect == null ||
        _activeHandle == DragHandle.none)
      return;

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
      final imageSize = _imageRenderSize;
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

  // --- ADD NOTE INPUT DIALOG (FIXED KEYBOARD/MARGIN) ---
  void _showAddNoteInputDialog() {
    final TextEditingController newNoteController = TextEditingController();
    // Default to the first tag or 'Compositions', ensure it exists in the list to prevent crashes
    String newCategory =
        _allAvailableTags.contains('Compositions')
            ? 'Compositions'
            : (_allAvailableTags.isNotEmpty
                ? _allAvailableTags.first
                : 'General');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent, // Crucial for the overlay wrapper
      builder: (context) {
        final mediaQuery = MediaQuery.of(context);

        // 1. Wrap content in StatefulBuilder for Dropdown updates
        final modalContent = StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 20,
                  ),
                  child: Column(
                    children: [
                      // --- ROW 1: Header (Avatar, Name, Pill Dropdown) ---
                      Row(
                        children: [
                          // Avatar
                          const CircleAvatar(
                            radius: 18,
                            backgroundColor: Colors.grey,
                            child: Icon(
                              Icons.person,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Name
                          const Text(
                            "User",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.black87,
                            ),
                          ),

                          const Spacer(),

                          // Dropdown
                          Container(
                            height: 40,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE0E5FF),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value:
                                    _allAvailableTags.contains(newCategory)
                                        ? newCategory
                                        : null,
                                hint: const Text("Type"),
                                isDense: true,
                                icon: const Icon(
                                  Icons.keyboard_arrow_down,
                                  size: 20,
                                  color: Colors.black54,
                                ),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                                focusColor: Colors.transparent,
                                dropdownColor: Colors.white,
                                items:
                                    _allAvailableTags
                                        .map(
                                          (c) => DropdownMenuItem(
                                            value: c,
                                            child: Text(c),
                                          ),
                                        )
                                        .toList(),
                                onChanged: (v) {
                                  // Update local state for the modal
                                  setModalState(() {
                                    newCategory = v!;
                                  });
                                },
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // --- ROW 2: Input Field & Send Button ---
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: newNoteController,
                              autofocus: true,
                              maxLines: 1,
                              style: const TextStyle(fontSize: 14),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: const Color(0xFFF3F4F6),
                                hintText: "Enter note details...",
                                hintStyle: TextStyle(color: Colors.grey[600]),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Send Button with YOUR Logic
                          Container(
                            margin: const EdgeInsets.only(bottom: 2),
                            child: IconButton(
                              icon: const Icon(Icons.send_outlined),
                              color: Colors.black87,
                              iconSize: 28,
                              onPressed: () async {
                                // --- YOUR ORIGINAL SAVE LOGIC ---
                                if (newNoteController.text.isNotEmpty &&
                                    _finalSelectionRect != null &&
                                    _imageRenderSize != null) {
                                  // Normalization logic
                                  final normalizedRect =
                                      _finalSelectionRect!.normalize();
                                  final nX =
                                      normalizedRect.center.dx /
                                      _imageRenderSize!.width;
                                  final nY =
                                      normalizedRect.center.dy /
                                      _imageRenderSize!.height;
                                  final nW =
                                      normalizedRect.width /
                                      _imageRenderSize!.width;
                                  final nH =
                                      normalizedRect.height /
                                      _imageRenderSize!.height;

                                  await _noteService.addNote(
                                    widget.imageId,
                                    newNoteController.text.trim(),
                                    newCategory,
                                    normX: nX,
                                    normY: nY,
                                    normWidth: nW,
                                    normHeight: nH,
                                  );

                                  final updatedNotes = await _noteService
                                      .getNotesForImage(widget.imageId);

                                  // Update the main state of ImageDetailsPage
                                  if (mounted) {
                                    setState(() {
                                      _notes = updatedNotes;
                                      _finalSelectionRect =
                                          null; // Clear selection
                                    });
                                  }

                                  Navigator.pop(context);
                                }
                              },
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

  // --- EDIT TAGS DIALOG ---
  void _openEditTagsDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        List<String> tempTags = List.from(_currentTags);
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text(
                "Edit Tags",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      _allAvailableTags.map((tag) {
                        final isSelected = tempTags.contains(tag);
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              if (isSelected)
                                tempTags.remove(tag);
                              else
                                tempTags.add(tag);
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
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
                                width: 1.0,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isSelected) ...[
                                  const Icon(
                                    Icons.close,
                                    size: 14,
                                    color: Color(0xFF7C4DFF),
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Text(
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
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "Cancel",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    this.setState(() => _currentTags = tempTags);
                    await _imageService.updateTags(widget.imageId, tempTags);
                    Navigator.pop(context);
                  },
                  child: const Text(
                    "Save",
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Determine if user can pan/zoom the image carousel
    final isSelectionModeActive = _isDrawMode || _isResizing;

    return Scaffold(
      // FIX: Prevents the main screen from pushing up when the keyboard opens
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
          _imageModel?.name ?? "Image Details",
          style: const TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          // CONFIRM SELECTION BUTTON (Visible only in resizing mode)
          if (_isResizing && _finalSelectionRect != null)
            IconButton(
              icon: const Icon(
                Icons.check_circle_outline,
                color: Color(0xFF7C4DFF),
              ),
              onPressed: _confirmSelectionAndShowModal,
            ),
          // CANCEL SELECTION BUTTON (Visible only in drawing/resizing mode)
          if (isSelectionModeActive)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.black),
              onPressed: _resetSelectionMode,
            ),
        ],
      ),
      body:
          _isLoading
              ? const Center(
                child: CircularProgressIndicator(color: Colors.black),
              )
              : Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // --- 1. IMAGE CONTAINER ---
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            constraints: const BoxConstraints(maxHeight: 500),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  // Unified Pan Handlers
                                  final onPanStartHandler =
                                      isSelectionModeActive
                                          ? _onPanStart
                                          : null;
                                  final onPanUpdateHandler =
                                      isSelectionModeActive
                                          ? _onPanUpdate
                                          : null;
                                  final onPanEndHandler =
                                      isSelectionModeActive ? _onPanEnd : null;

                                  return Stack(
                                    fit: StackFit.passthrough,
                                    children: [
                                      InteractiveViewer(
                                        // Disable pan/scale if selection or resizing is active
                                        panEnabled: !isSelectionModeActive,
                                        scaleEnabled: !isSelectionModeActive,
                                        child: GestureDetector(
                                          onPanStart: onPanStartHandler,
                                          onPanUpdate: onPanUpdateHandler,
                                          onPanEnd: onPanEndHandler,
                                          child: Stack(
                                            children: [
                                              Image.file(
                                                File(widget.imagePath),
                                                key: _imageKey,
                                                fit: BoxFit.contain,
                                                width: double.infinity,
                                              ),

                                              // DRAWING OVERLAY (if in drawing mode)
                                              if (_isDrawMode &&
                                                  _startPos != null &&
                                                  _currentPos != null)
                                                Positioned.fill(
                                                  child: CustomPaint(
                                                    painter:
                                                        ResizingSelectionOverlayPainter(
                                                          rect:
                                                              Rect.fromPoints(
                                                                _startPos!,
                                                                _currentPos!,
                                                              ).normalize(),
                                                          isResizing: false,
                                                        ),
                                                  ),
                                                ),

                                              // FINAL SELECTION RECT (if in resizing mode)
                                              if (_isResizing &&
                                                  _finalSelectionRect != null)
                                                Positioned.fill(
                                                  child: CustomPaint(
                                                    painter:
                                                        ResizingSelectionOverlayPainter(
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

                                      // Existing Note Indicators
                                      ..._notes.map((note) {
                                        final x =
                                            note.normX * constraints.maxWidth;
                                        final y =
                                            note.normY * constraints.maxHeight;
                                        final isActive =
                                            note.id == _activeNoteId;

                                        return Positioned(
                                          left: x - 10,
                                          top: y - 10,
                                          child: GestureDetector(
                                            onTap:
                                                () => _openNotesSheet(
                                                  highlightId: note.id,
                                                ),
                                            child: Container(
                                              width: 20,
                                              height: 20,
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                shape: BoxShape.circle,
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withOpacity(0.3),
                                                    blurRadius: 4,
                                                    offset: const Offset(0, 1),
                                                  ),
                                                ],
                                                border:
                                                    isActive
                                                        ? Border.all(
                                                          color: const Color(
                                                            0xFF7C4DFF,
                                                          ),
                                                          width: 3,
                                                        )
                                                        : null,
                                              ),
                                            ),
                                          ),
                                        );
                                      }).toList(),

                                      // Notes Button (Show only when not in selection mode)
                                      if (!isSelectionModeActive)
                                        Positioned(
                                          bottom: 12,
                                          right: 12,
                                          child: ElevatedButton(
                                            onPressed: () => _openNotesSheet(),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.white,
                                              foregroundColor: Colors.black,
                                              elevation: 4,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 12,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: const [
                                                Text(
                                                  "Notes",
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                SizedBox(width: 8),
                                                Icon(
                                                  Icons.assignment_outlined,
                                                  size: 18,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),

                                      // INSTRUCTION OVERLAYS
                                      if (_isDrawMode && _startPos == null)
                                        Positioned(
                                          top: 20,
                                          left: 0,
                                          right: 0,
                                          child: Center(
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 8,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.black87,
                                                borderRadius:
                                                    BorderRadius.circular(20),
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
                                      if (_isResizing &&
                                          _finalSelectionRect != null &&
                                          _activeHandle == DragHandle.none)
                                        Positioned(
                                          top: 20,
                                          left: 0,
                                          right: 0,
                                          child: Center(
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 8,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.black87,
                                                borderRadius:
                                                    BorderRadius.circular(20),
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
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          // --- 2. INFO SECTION ---
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _imageModel?.name ?? "Untitled Image",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.black87,
                                  ),
                                ),

                                const SizedBox(height: 24),

                                // Tags Box
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF9F9F9),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Colors.grey[200]!,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text(
                                            "Tags",
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: _openEditTagsDialog,
                                            child: const Icon(
                                              Icons.edit_outlined,
                                              size: 18,
                                              color: Colors.black54,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Divider(
                                        height: 1,
                                        color: Colors.grey[300],
                                      ),
                                      const SizedBox(height: 16),

                                      // Main View: Only show selected tags
                                      SizedBox(
                                        width: double.infinity,
                                        child:
                                            _currentTags.isEmpty
                                                ? const Text(
                                                  "No tags yet.",
                                                  style: TextStyle(
                                                    color: Colors.grey,
                                                  ),
                                                )
                                                : Wrap(
                                                  spacing: 8,
                                                  runSpacing: 8,
                                                  children:
                                                      _currentTags.map((tag) {
                                                        return Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 12,
                                                                vertical: 6,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color: const Color(
                                                              0xFFEEF0FF,
                                                            ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  20,
                                                                ),
                                                            border: Border.all(
                                                              color:
                                                                  const Color(
                                                                    0xFF7C4DFF,
                                                                  ),
                                                              width: 1,
                                                            ),
                                                          ),
                                                          child: Text(
                                                            tag,
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 13,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w500,
                                                                  color: Color(
                                                                    0xFF7C4DFF,
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
                              ],
                            ),
                          ),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
    );
  }
}

// --- NOTES LIST SHEET (Remains unchanged as it uses DraggableScrollableSheet) ---
class _NotesListSheet extends StatefulWidget {
  final List<NoteModel> notes;
  final int? highlightId;
  final VoidCallback onAddNotePressed;

  const _NotesListSheet({
    Key? key,
    required this.notes,
    this.highlightId,
    required this.onAddNotePressed,
  }) : super(key: key);

  @override
  State<_NotesListSheet> createState() => __NotesListSheetState();
}

class __NotesListSheetState extends State<_NotesListSheet> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.highlightId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final index = widget.notes.indexWhere(
          (n) => n.id == widget.highlightId,
        );
        if (index != -1 && _scrollController.hasClients) {
          _scrollController.animateTo(
            index * 80.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (_, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Notes (${widget.notes.length})",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  itemCount: widget.notes.length,
                  itemBuilder: (context, index) {
                    final note = widget.notes[index];
                    final isHighlighted = note.id == widget.highlightId;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color:
                            isHighlighted
                                ? const Color(0xFFF3F0FF)
                                : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color:
                              isHighlighted
                                  ? const Color(0xFF7C4DFF)
                                  : Colors.grey[200]!,
                          width: isHighlighted ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEEF0FF),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                note.category,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF7C4DFF),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            note.content,
                            style: const TextStyle(
                              fontSize: 15,
                              color: Colors.black87,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              // --- ADD NOTE BUTTON (BOTTOM OF SHEET) ---
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: widget.onAddNotePressed,
                  icon: const Icon(Icons.add),
                  label: const Text("Add Note"),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }
}

// --- REUSABLE WIDGETS FOR MODAL OVERLAY (Keyboard Fix and Shadow Removal) ---

class NoteModalOverlay extends StatelessWidget {
  final Widget modalContent;
  final Size screenSize;

  const NoteModalOverlay({
    Key? key,
    required this.modalContent,
    required this.screenSize,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Note: modalMinHeight is kept only for potential use with MaxHeight, but is not enforced as a minimum.
    final mq = MediaQuery.of(context);
    final keyboardHeight = mq.viewInsets.bottom;
    final systemBottomPadding = mq.padding.bottom;

    return Align(
      alignment: Alignment.bottomCenter,
      // FIX 1: Use AnimatedPadding on the outside to correctly handle keyboard elevation smoothly.
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(
          bottom: keyboardHeight, // Moves modal up to avoid keyboard
        ),
        child: ConstrainedBox(
          // FIX 2: Removed minHeight constraint entirely. The Column inside uses mainAxisSize.min,
          // allowing the dialog to shrink to fit content and preventing it from sitting "too high".
          constraints: BoxConstraints(maxHeight: screenSize.height),
          child: Material(
            // Using Material to provide the background, border radius, and shadow.
            color: Colors.white,
            elevation: 10, // Replicating the box shadow for visual style.
            shadowColor: Colors.black26,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              // Allows the content inside to scroll if keyboard reduces available space
              child: Padding(
                // Only apply system bottom padding for safe area/gesture bar here
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

// --- FULL OVERLAY PAINTER WITH RESIZING LOGIC ---
class ResizingSelectionOverlayPainter extends CustomPainter {
  final Rect rect;
  final bool isResizing;
  final DragHandle activeHandle;

  ResizingSelectionOverlayPainter({
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

    // 3. DRAW CENTER DOT/RESIZE HANDLES
    if (!isResizing) {
      // Draw center dot in initial draw mode
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
    } else {
      // Draw resize handles in resizing mode
      final List<Offset> corners = [
        rect.topLeft,
        rect.topRight,
        rect.bottomLeft,
        rect.bottomRight,
      ];

      const double handleRadius = 8;
      final Paint handleShadow =
          Paint()
            ..color = Colors.black.withOpacity(0.3)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      final Paint handleFill = Paint()..color = Colors.white;
      final Paint handleBorder =
          Paint()
            ..color = const Color(0xFF448AFF)
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke;

      for (final corner in corners) {
        canvas.drawCircle(corner, handleRadius, handleShadow);
        canvas.drawCircle(corner, handleRadius, handleFill);
        canvas.drawCircle(corner, handleRadius, handleBorder);
      }
    }
  }

  @override
  bool shouldRepaint(covariant ResizingSelectionOverlayPainter oldDelegate) =>
      rect != oldDelegate.rect ||
      isResizing != oldDelegate.isResizing ||
      activeHandle != oldDelegate.activeHandle;
}
