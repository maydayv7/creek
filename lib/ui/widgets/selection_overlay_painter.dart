import 'package:flutter/material.dart';
import 'package:creekui/data/models/canvas_models.dart';
import 'package:creekui/ui/styles/variables.dart';

class SelectionOverlayPainter extends CustomPainter {
  final Rect rect;
  final bool isResizing;
  final DragHandle activeHandle;

  SelectionOverlayPainter({
    required this.rect,
    this.isResizing = false,
    this.activeHandle = DragHandle.none,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Dim the rest of image
    final backgroundPath =
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final selectionPath = Path()..addRect(rect);
    final dimmedPath = Path.combine(
      PathOperation.difference,
      backgroundPath,
      selectionPath,
    );

    final dimPaint =
        Paint()
          ..color = Colors.black.withOpacity(0.5)
          ..style = PaintingStyle.fill;

    canvas.drawPath(dimmedPath, dimPaint);

    // 2. Draw Selection Border
    final paint =
        Paint()
          ..color = Variables.selectionBorder
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;

    // Use a dash effect for the selection box
    _drawDashedRect(canvas, rect, paint);

    // 3. If Resizing, Draw Handles
    if (isResizing) {
      final handlePaint =
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.fill;

      final handleBorderPaint =
          Paint()
            ..color = Variables.selectionBorder
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0;

      final double handleRadius = 6.0;

      final handles = [
        rect.topLeft,
        rect.topRight,
        rect.bottomLeft,
        rect.bottomRight,
      ];

      for (final handle in handles) {
        canvas.drawCircle(handle, handleRadius, handlePaint);
        canvas.drawCircle(handle, handleRadius, handleBorderPaint);
      }

      // 4. Draw Center Handle (Move)
      final centerPaint =
          Paint()
            ..color = Variables.accentMagic.withOpacity(0.5)
            ..style = PaintingStyle.fill;

      canvas.drawCircle(rect.center, 8.0, centerPaint);
    }
  }

  void _drawDashedRect(Canvas canvas, Rect rect, Paint paint) {
    final path = Path()..addRect(rect);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant SelectionOverlayPainter oldDelegate) {
    return oldDelegate.rect != rect ||
        oldDelegate.isResizing != isResizing ||
        oldDelegate.activeHandle != activeHandle;
  }
}
