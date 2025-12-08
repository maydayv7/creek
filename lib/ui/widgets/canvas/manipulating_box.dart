import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:creekui/ui/styles/variables.dart';

class ManipulatingBox extends StatefulWidget {
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

  const ManipulatingBox({
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
  State<ManipulatingBox> createState() => _ManipulatingBoxState();
}

class _ManipulatingBoxState extends State<ManipulatingBox> {
  late Offset _pos;
  late Size _size;
  late double _rot;

  // Gesture state
  double _initialRotation = 0.0;
  double _initialScale = 1.0;
  bool _isTwoFingerGesture = false;
  Offset _previousFocalPoint = Offset.zero;

  @override
  void initState() {
    super.initState();
    _updateInternalState();
  }

  @override
  void didUpdateWidget(ManipulatingBox oldWidget) {
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
        final double zoom = matrix.getMaxScaleOnAxis();
        final double handleScale = (1 / zoom).clamp(0.2, 5.0);
        final double edgeThickness = 18 * handleScale;

        return Positioned(
          left: _pos.dx,
          top: _pos.dy,
          child: Transform.rotate(
            angle: _rot,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onTap,
                  onDoubleTap: widget.onDoubleTap,
                  // Handle both single-finger drag and two-finger rotate/zoom using scale gestures
                  onScaleStart: (details) {
                    if (widget.isSelected && !widget.isEditing) {
                      _previousFocalPoint = details.focalPoint;
                      if (details.pointerCount == 2) {
                        // Two-finger gesture: rotate and zoom
                        _isTwoFingerGesture = true;
                        _initialRotation = _rot;
                        _initialScale = _size.width * _size.height;
                      } else {
                        // Single-finger gesture: prepare for drag
                        _isTwoFingerGesture = false;
                      }
                      widget.onDragStart();
                    }
                  },
                  onScaleUpdate: (details) {
                    if (widget.isSelected && !widget.isEditing) {
                      if (_isTwoFingerGesture && details.pointerCount == 2) {
                        // Two-finger: handle rotation and zoom
                        final newRotation = _initialRotation + details.rotation;

                        // Handle scale (zoom) - maintain aspect ratio
                        final scaleFactor = details.scale;
                        final newArea =
                            _initialScale * scaleFactor * scaleFactor;
                        final aspectRatio = _size.width / _size.height;
                        final newWidth = math
                            .sqrt(newArea * aspectRatio)
                            .clamp(20.0, 5000.0);
                        final newHeight = newWidth / aspectRatio;

                        setState(() {
                          _rot = newRotation % (2 * math.pi);
                          _size = Size(newWidth, newHeight);
                        });

                        widget.onUpdate(_pos, _size, _rot);
                      } else if (!_isTwoFingerGesture &&
                          details.pointerCount == 1) {
                        // Single-finger: handle drag using incremental focal point delta
                        final currentFocalPoint = details.focalPoint;
                        final delta = currentFocalPoint - _previousFocalPoint;
                        // Convert to canvas coordinates by dividing by zoom
                        final zoom = widget.viewScale;
                        final scaledDelta = delta / zoom;
                        // Rotate delta to account for element rotation
                        final rotated = _rotateVector(scaledDelta, -_rot);
                        setState(() {
                          _pos += scaledDelta;
                          _previousFocalPoint = currentFocalPoint;
                        });
                        widget.onUpdate(_pos, _size, _rot);
                      }
                    }
                  },
                  onScaleEnd: (details) {
                    if (widget.isSelected && !widget.isEditing) {
                      _isTwoFingerGesture = false;
                      widget.onDragEnd(_pos, _size, _rot);
                    }
                  },
                  child: Container(
                    width: _size.width,
                    height: _size.height,
                    decoration:
                        widget.isSelected
                            ? BoxDecoration(
                              border: Border.all(
                                color: Variables.selectionBorder,
                                width: 2 * handleScale,
                              ),
                            )
                            : null,
                    child:
                        widget.type == "file_image"
                            ? Image.file(
                              File(widget.content),
                              fit: BoxFit.contain,
                            )
                            : _buildText(),
                  ),
                ),

                // RESIZE Edges

                // Right edge
                if (widget.isSelected && !widget.isEditing)
                  Positioned(
                    right: -edgeThickness / 2,
                    top: 0,
                    bottom: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanUpdate: (d) {
                        setState(() {
                          _size = Size(_size.width + d.delta.dx, _size.height);
                        });
                        widget.onUpdate(_pos, _size, _rot);
                      },
                      onPanStart: (_) => widget.onDragStart(),
                      onPanEnd: (_) => widget.onDragEnd(_pos, _size, _rot),
                      child: Container(
                        width: edgeThickness,
                        color: Colors.transparent,
                      ),
                    ),
                  ),

                // Left edge
                if (widget.isSelected && !widget.isEditing)
                  Positioned(
                    left: -edgeThickness / 2,
                    top: 0,
                    bottom: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanUpdate: (d) {
                        setState(() {
                          _pos += Offset(d.delta.dx, 0);
                          _size = Size(_size.width - d.delta.dx, _size.height);
                        });
                        widget.onUpdate(_pos, _size, _rot);
                      },
                      onPanStart: (_) => widget.onDragStart(),
                      onPanEnd: (_) => widget.onDragEnd(_pos, _size, _rot),
                      child: Container(
                        width: edgeThickness,
                        color: Colors.transparent,
                      ),
                    ),
                  ),

                // Top edge
                if (widget.isSelected && !widget.isEditing)
                  Positioned(
                    top: -edgeThickness / 2,
                    left: 0,
                    right: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanUpdate: (d) {
                        setState(() {
                          _pos += Offset(0, d.delta.dy);
                          _size = Size(_size.width, _size.height - d.delta.dy);
                        });
                        widget.onUpdate(_pos, _size, _rot);
                      },
                      onPanStart: (_) => widget.onDragStart(),
                      onPanEnd: (_) => widget.onDragEnd(_pos, _size, _rot),
                      child: Container(
                        height: edgeThickness,
                        color: Colors.transparent,
                      ),
                    ),
                  ),

                // Bottom edge
                if (widget.isSelected && !widget.isEditing)
                  Positioned(
                    bottom: -edgeThickness / 2,
                    left: 0,
                    right: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanUpdate: (d) {
                        setState(() {
                          _size = Size(_size.width, _size.height + d.delta.dy);
                        });
                        widget.onUpdate(_pos, _size, _rot);
                      },
                      onPanStart: (_) => widget.onDragStart(),
                      onPanEnd: (_) => widget.onDragEnd(_pos, _size, _rot),
                      child: Container(
                        height: edgeThickness,
                        color: Colors.transparent,
                      ),
                    ),
                  ),
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
      color: Color(
        widget.styleData['style_color'] ?? Variables.textPrimary.value,
      ),
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

  Offset _rotateVector(Offset vector, double angle) {
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);
    return Offset(
      vector.dx * cosA - vector.dy * sinA,
      vector.dx * sinA + vector.dy * cosA,
    );
  }
}
