import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:creekui/services/image_service.dart';
import 'package:creekui/services/note_service.dart';
import 'package:creekui/data/models/note_model.dart';
import 'package:creekui/data/models/image_model.dart';
import 'package:creekui/data/models/canvas_models.dart';
import 'package:creekui/utils/image_actions_helper.dart';
import 'package:creekui/utils/image_utils.dart';
import 'package:creekui/ui/styles/variables.dart';
import 'package:creekui/ui/widgets/primary_button.dart';
import 'package:creekui/ui/widgets/empty_state.dart';
import 'package:creekui/ui/widgets/selection_overlay_painter.dart';
import 'package:creekui/ui/widgets/note_input_sheet.dart';
import 'package:creekui/ui/widgets/app_bar.dart';
import 'package:creekui/ui/widgets/dialog.dart';
import 'package:creekui/ui/widgets/tag_chip.dart';

class ImageDetailsPage extends StatefulWidget {
  final String imagePath;
  final String imageId;
  final int projectId;

  const ImageDetailsPage({
    super.key,
    required this.imagePath,
    required this.imageId,
    required this.projectId,
  });

  @override
  State<ImageDetailsPage> createState() => _ImageDetailsPageState();
}

class _ImageDetailsPageState extends State<ImageDetailsPage> {
  final NoteService _noteService = NoteService();
  final ImageService _imageService = ImageService();

  ImageModel? _imageModel;
  List<NoteModel> _notes = [];
  List<String> _currentTags = [];
  bool _isLoading = true;
  int? _activeNoteId;

  // Drawing/Resizing
  bool _isDrawMode = false;
  bool _isResizing = false;
  final GlobalKey _imageKey = GlobalKey();

  Offset? _startPos;
  Offset? _currentPos;
  Rect? _finalSelectionRect;
  Size? _imageRenderSize;

  DragHandle _activeHandle = DragHandle.none;
  Offset? _startDragLocalOffset;
  final double _handleSize = 25.0;

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

  // Actions
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
    _resetSelectionMode();
    setState(() => _isDrawMode = true);
  }

  void _confirmSelectionAndShowModal() {
    if (_finalSelectionRect != null) {
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
    ).whenComplete(() => setState(() => _activeNoteId = null));
  }

  // Gestures
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

  // Resizing Handlers
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

        if (_imageRenderSize != null) {
          final cl = newRect.left.clamp(0.0, _imageRenderSize!.width);
          final ct = newRect.top.clamp(0.0, _imageRenderSize!.height);
          final cr = newRect.right.clamp(0.0, _imageRenderSize!.width);
          final cb = newRect.bottom.clamp(0.0, _imageRenderSize!.height);
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

  // Show modal
  void _showAddNoteInputDialog() {
    String initialCategory =
        _allAvailableTags.contains('Compositions')
            ? 'Compositions'
            : (_allAvailableTags.firstOrNull ?? 'General');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return NoteModalOverlay(
          screenSize: MediaQuery.of(context).size,
          modalContent: NoteInputSheet(
            categories: _allAvailableTags,
            initialCategory: initialCategory,
            onSubmit: (content, category) async {
              if (_finalSelectionRect != null && _imageRenderSize != null) {
                final normRect = _finalSelectionRect!.normalize();
                await _noteService.addNote(
                  widget.imageId,
                  content,
                  category,
                  normX: normRect.center.dx / _imageRenderSize!.width,
                  normY: normRect.center.dy / _imageRenderSize!.height,
                  normWidth: normRect.width / _imageRenderSize!.width,
                  normHeight: normRect.height / _imageRenderSize!.height,
                );
                final updatedNotes = await _noteService.getNotesForImage(
                  widget.imageId,
                );
                if (mounted)
                  setState(() {
                    _notes = updatedNotes;
                    _finalSelectionRect = null;
                  });
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        );
      },
    );
  }

  // Edit Tags Dialog
  void _openEditTagsDialog() {
    List<String> tempTags = List.from(_currentTags);
    showDialog(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder: (context, setLocalState) {
              return Dialog(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Variables.radiusLarge),
                ),
                child: ShowDialog(
                  title: "Edit Tags",
                  primaryButtonText: "Save",
                  onPrimaryPressed: () async {
                    setState(() => _currentTags = tempTags);
                    await _imageService.updateTags(widget.imageId, tempTags);
                    if (mounted) Navigator.pop(context);
                  },
                  content: SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children:
                          _allAvailableTags.map((tag) {
                            final isSelected = tempTags.contains(tag);
                            return GestureDetector(
                              onTap: () {
                                setLocalState(() {
                                  isSelected
                                      ? tempTags.remove(tag)
                                      : tempTags.add(tag);
                                });
                              },
                              child: TagChip(
                                label: tag,
                                icon:
                                    isSelected
                                        ? const Icon(
                                          Icons.check,
                                          size: 14,
                                          color: Variables.chipText,
                                        )
                                        : null,
                              ),
                            );
                          }).toList(),
                    ),
                  ),
                ),
              );
            },
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Determine if user can pan/zoom the image carousel
    final isSelectionModeActive = _isDrawMode || _isResizing;

    return Scaffold(
      // Prevents the main screen from pushing up when the keyboard opens
      resizeToAvoidBottomInset: false,
      backgroundColor: Variables.surfaceBackground,
      appBar: CommonAppBar(
        showBack: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            size: 20,
            color: Variables.textPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        titleWidget:
            (!isSelectionModeActive && _imageModel != null)
                ? Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: Variables.surfaceSubtle,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(30),
                    onTap:
                        () => ImageActionsHelper.sendToFiles(
                          context,
                          _imageModel!.filePath,
                        ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SvgPicture.asset(
                            'assets/icons/files_icon.svg',
                            width: 18,
                            height: 18,
                            colorFilter: const ColorFilter.mode(
                              Variables.textPrimary,
                              BlendMode.srcIn,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "Send to File",
                            style: Variables.headerStyle.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                : null,
        actions: [
          // 1. Confirm Selection (Resizing mode)
          if (_isResizing && _finalSelectionRect != null)
            IconButton(
              icon: const Icon(
                Icons.check_circle_outline,
                color: Color(0xFF7C4DFF),
              ),
              onPressed: _confirmSelectionAndShowModal,
            ),

          // 2. Cancel Selection (Any selection mode)
          if (isSelectionModeActive)
            IconButton(
              icon: const Icon(Icons.close, color: Variables.textPrimary),
              onPressed: _resetSelectionMode,
            ),

          // 3. Standard Actions (when NOT selecting)
          if (!isSelectionModeActive && _imageModel != null) ...[
            // Share Button
            IconButton(
              onPressed:
                  () => ImageActionsHelper.shareImage(
                    context,
                    _imageModel!.filePath,
                  ),
              icon: SvgPicture.asset(
                'assets/icons/share_icon.svg',
                width: 20,
                height: 20,
                colorFilter: const ColorFilter.mode(
                  Variables.textPrimary,
                  BlendMode.srcIn,
                ),
              ),
            ),

            // Rename Button
            IconButton(
              onPressed:
                  () => ImageActionsHelper.renameImage(
                    context,
                    _imageModel!,
                    () => _loadData(),
                  ),
              icon: const Icon(
                Icons.drive_file_rename_outline,
                color: Variables.textPrimary,
              ),
            ),
          ],
        ],
      ),
      body:
          _isLoading
              ? const Center(
                child: CircularProgressIndicator(color: Variables.textPrimary),
              )
              : Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Image Container
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
                                        // Disable pan/scale if selection or resizing is active
                                        panEnabled: !isSelectionModeActive,
                                        scaleEnabled: !isSelectionModeActive,
                                        child: GestureDetector(
                                          onPanStart: _onPanStart,
                                          onPanUpdate: _onPanUpdate,
                                          onPanEnd: _onPanEnd,
                                          child: Stack(
                                            children: [
                                              Image.file(
                                                File(widget.imagePath),
                                                key: _imageKey,
                                                fit: BoxFit.contain,
                                                width: double.infinity,
                                              ),

                                              // Drawing Overlay (if in drawing mode)
                                              if (_isDrawMode &&
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

                                      // Existing Note Indicators
                                      ..._notes.map((note) {
                                        final x =
                                            note.normX * constraints.maxWidth;
                                        final y =
                                            note.normY * constraints.maxHeight;
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
                                                    note.id == _activeNoteId
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
                                      }),

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

                                      // Instruction Overlays
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

                          // 2. Info Section
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _imageModel?.name ?? "Untitled Image",
                                  style: Variables.bodyStyle.copyWith(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
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
                                      color: Variables.borderSubtle,
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
                                              color: Variables.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      const Divider(
                                        height: 1,
                                        color: Variables.borderSubtle,
                                      ),
                                      const SizedBox(height: 16),
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
                                                      _currentTags
                                                          .map(
                                                            (tag) => TagChip(
                                                              label: tag,
                                                              icon: null,
                                                            ),
                                                          )
                                                          .toList(),
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

// Notes List Sheet
class _NotesListSheet extends StatefulWidget {
  final List<NoteModel> notes;
  final int? highlightId;
  final VoidCallback onAddNotePressed;
  const _NotesListSheet({
    required this.notes,
    this.highlightId,
    required this.onAddNotePressed,
  });
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
                child:
                    widget.notes.isEmpty
                        ? const EmptyState(
                          icon: Icons.comment,
                          title: "No notes yet",
                          subtitle: "Tap 'Add Note' to start",
                        )
                        : ListView.builder(
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
                                  Container(
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
              // Add Note Button
              const SizedBox(height: 10),
              PrimaryButton(
                text: "Add Note",
                onPressed: widget.onAddNotePressed,
                iconPath: "assets/icons/add-line.svg",
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }
}
