import 'dart:io';
import 'dart:ui' as ui; 
import 'package:flutter/material.dart';

//services,models
import '../../services/image_service.dart';
import '../../services/note_service.dart';
import '../../data/models/note_model.dart';
import '../../data/models/image_model.dart';

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

  // -- DRAWING STATE --
  bool _isDrawMode = false;
  final GlobalKey _imageKey = GlobalKey();

  Offset? _startPos;
  Offset? _currentPos;
  Rect? _finalSelectionRect;
  Size? _imageRenderSize;

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

  Future<void> _removeTag(String tag) async {
    setState(() {
      _currentTags.remove(tag);
    });
    await _imageService.updateTags(widget.imageId, _currentTags);
  }

  void _activateDrawMode() {
    setState(() {
      _isDrawMode = true;
      _finalSelectionRect = null;
      _startPos = null;
      _currentPos = null;
    });
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

  // --- DRAWING GESTURES ---

  void _onPanStart(DragStartDetails details) {
    if (!_isDrawMode) return;
    setState(() {
      _startPos = details.localPosition;
      _currentPos = details.localPosition;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!_isDrawMode) return;
    setState(() {
      _currentPos = details.localPosition;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (!_isDrawMode || _startPos == null || _currentPos == null) return;

    final rect = Rect.fromPoints(_startPos!, _currentPos!);
    final RenderBox? box =
        _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null) {
      _imageRenderSize = box.size;
    }

    _finalSelectionRect = rect;

    setState(() {
      _isDrawMode = false;
      _startPos = null;
      _currentPos = null;
    });

    _showAddNoteInputDialog();
  }

  // --- ADD NOTE INPUT DIALOG ---
  void _showAddNoteInputDialog() {
    final TextEditingController newNoteController = TextEditingController();
    String newCategory = 'Compositions';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => Padding(
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
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 16),

                    DropdownButtonFormField<String>(
                      value: newCategory,
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
                          [
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
                              ]
                              .map(
                                (c) =>
                                    DropdownMenuItem(value: c, child: Text(c)),
                              )
                              .toList(),
                      onChanged: (v) => newCategory = v!,
                    ),

                    const SizedBox(height: 12),

                    TextField(
                      controller: newNoteController,
                      autofocus: true,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: "Enter note details...",
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
                        onPressed: () async {
                          if (newNoteController.text.isNotEmpty &&
                              _finalSelectionRect != null &&
                              _imageRenderSize != null) {
                            final nX =
                                _finalSelectionRect!.center.dx /
                                _imageRenderSize!.width;
                            final nY =
                                _finalSelectionRect!.center.dy /
                                _imageRenderSize!.height;
                            final nW =
                                _finalSelectionRect!.width /
                                _imageRenderSize!.width;
                            final nH =
                                _finalSelectionRect!.height /
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
                            setState(() {
                              _notes = updatedNotes;
                            });

                            Navigator.pop(context);
                          }
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
          ),
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
                                  return Stack(
                                    fit: StackFit.passthrough,
                                    children: [
                                      InteractiveViewer(
                                        panEnabled: !_isDrawMode,
                                        scaleEnabled: !_isDrawMode,
                                        child: GestureDetector(
                                          onPanStart:
                                              _isDrawMode ? _onPanStart : null,
                                          onPanUpdate:
                                              _isDrawMode ? _onPanUpdate : null,
                                          onPanEnd:
                                              _isDrawMode ? _onPanEnd : null,
                                          child: Stack(
                                            children: [
                                              Image.file(
                                                File(widget.imagePath),
                                                key: _imageKey,
                                                fit: BoxFit.contain,
                                                width: double.infinity,
                                              ),

                                              if (_isDrawMode &&
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

                                      // Notes Button
                                      Positioned(
                                        bottom: 12,
                                        right: 12,
                                        child: ElevatedButton(
                                          onPressed: () => _openNotesSheet(),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.white,
                                            foregroundColor: Colors.black,
                                            elevation: 4,
                                            padding: const EdgeInsets.symmetric(
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
                                                        // Style as "Selected" (Purple with X)
                                                        return GestureDetector(
                                                          onTap:
                                                              () => _removeTag(
                                                                tag,
                                                              ),
                                                          child: Container(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal:
                                                                      12,
                                                                  vertical: 6,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color:
                                                                  const Color(
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
                                                            child: Row(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              children: [
                                                                Text(
                                                                  tag,
                                                                  style: const TextStyle(
                                                                    fontSize:
                                                                        13,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w500,
                                                                    color: Color(
                                                                      0xFF7C4DFF,
                                                                    ),
                                                                  ),
                                                                ),
                                                                const SizedBox(
                                                                  width: 4,
                                                                ),
                                                                const Icon(
                                                                  Icons.close,
                                                                  size: 14,
                                                                  color: Color(
                                                                    0xFF7C4DFF,
                                                                  ),
                                                                ),
                                                              ],
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

// --- NOTES LIST SHEET ---
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
  State<_NotesListSheet> createState() => _NotesListSheetState();
}

class _NotesListSheetState extends State<_NotesListSheet> {
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
