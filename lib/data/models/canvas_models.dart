import 'dart:ui';

enum DragHandle { none, topLeft, topRight, bottomLeft, bottomRight, center }

class DrawingPoint {
  final Offset offset;
  final Paint paint;
  const DrawingPoint({required this.offset, required this.paint});

  Map<String, dynamic> toMap() => {'dx': offset.dx, 'dy': offset.dy};

  factory DrawingPoint.fromMap(Map<String, dynamic> map) {
    return DrawingPoint(
      offset: Offset(map['dx'] ?? 0, map['dy'] ?? 0),
      paint: Paint(),
    );
  }
}

class DrawingPath {
  final List<DrawingPoint> points;
  final Color color;
  final double strokeWidth;
  final bool isEraser;

  DrawingPath({
    required this.points,
    required this.color,
    required this.strokeWidth,
    required this.isEraser,
  });

  Map<String, dynamic> toMap() {
    return {
      'points': points.map((p) => p.toMap()).toList(),
      'color': color.value,
      'strokeWidth': strokeWidth,
      'isEraser': isEraser,
    };
  }

  factory DrawingPath.fromMap(Map<String, dynamic> map) {
    return DrawingPath(
      points:
          (map['points'] as List).map((p) => DrawingPoint.fromMap(p)).toList(),
      color: Color(map['color']),
      strokeWidth: (map['strokeWidth'] as num).toDouble(),
      isEraser: map['isEraser'] ?? false,
    );
  }
}

// Helper to snapshot the entire canvas state for undo/redo
class CanvasState {
  final List<Map<String, dynamic>> elements;
  final List<DrawingPath> paths;
  CanvasState(this.elements, this.paths);
}
