import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:creekui/data/models/canvas_models.dart';

class CanvasPainter extends CustomPainter {
  final List<DrawingPath> paths;
  final List<DrawingPoint> currentPoints;
  final Color currentColor;
  final double currentWidth;
  final bool isEraser;

  // Visual highlight/flash
  final Color? overrideColor;

  CanvasPainter({
    required this.paths,
    required this.currentPoints,
    required this.currentColor,
    required this.currentWidth,
    required this.isEraser,
    this.overrideColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());

    // Draw saved paths
    for (final path in paths) {
      _drawPath(canvas, path);
    }

    // Draw active stroke
    if (currentPoints.isNotEmpty) {
      final paint =
          Paint()
            ..color =
                isEraser ? Colors.transparent : (overrideColor ?? currentColor)
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

  void _drawPath(Canvas canvas, DrawingPath path) {
    final paint =
        Paint()
          ..color =
              path.isEraser ? Colors.transparent : (overrideColor ?? path.color)
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
      canvas.drawPoints(ui.PointMode.points, [path.points.first.offset], paint);
    }
  }

  @override
  bool shouldRepaint(covariant CanvasPainter oldDelegate) => true;
}
