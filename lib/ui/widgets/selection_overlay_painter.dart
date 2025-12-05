import 'dart:ui' as ui;
import 'package:flutter/material.dart';

enum DragHandle { none, topLeft, topRight, bottomLeft, bottomRight, center }

extension RectUtils on Rect {
  Rect normalize() {
    return Rect.fromLTRB(
      left < right ? left : right,
      top < bottom ? top : bottom,
      left > right ? left : right,
      top > bottom ? top : bottom,
    );
  }
}

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
    // 1. Dim Background
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

    // 2. Draw Dashed Border
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

    // 3. Draw Center Dot (Initial) or Resize Handles (Resizing)
    if (!isResizing) {
      canvas.drawCircle(
        rect.center,
        8,
        Paint()
          ..color = Colors.black26
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawCircle(
        rect.center,
        6,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill,
      );
    } else {
      final List<Offset> corners = [
        rect.topLeft,
        rect.topRight,
        rect.bottomLeft,
        rect.bottomRight,
      ];

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
