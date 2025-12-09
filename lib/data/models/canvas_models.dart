import 'dart:ui';
import 'package:flutter/material.dart';

enum DragHandle { none, topLeft, topRight, bottomLeft, bottomRight, center }

enum LayerType { sketch, image }

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

// Layer Models
abstract class CanvasLayer {
  final String id;
  final LayerType type;
  bool isVisible;

  CanvasLayer({required this.id, required this.type, this.isVisible = true});

  Map<String, dynamic> toMap();

  static CanvasLayer fromMap(Map<String, dynamic> map) {
    if (map['type'] == 'sketch') {
      return SketchLayer.fromMap(map);
    } else {
      return ImageLayer.fromMap(map);
    }
  }
}

class SketchLayer extends CanvasLayer {
  final List<DrawingPath> paths;
  final bool isMagicDraw;

  SketchLayer({
    required String id,
    this.paths = const [],
    this.isMagicDraw = false,
    bool isVisible = true,
  }) : super(id: id, type: LayerType.sketch, isVisible: isVisible);

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': 'sketch',
      'paths': paths.map((p) => p.toMap()).toList(),
      'isMagicDraw': isMagicDraw,
      'isVisible': isVisible,
    };
  }

  factory SketchLayer.fromMap(Map<String, dynamic> map) {
    return SketchLayer(
      id: map['id'],
      paths: (map['paths'] as List).map((p) => DrawingPath.fromMap(p)).toList(),
      isMagicDraw: map['isMagicDraw'] ?? false,
      isVisible: map['isVisible'] ?? true,
    );
  }
}

class ImageLayer extends CanvasLayer {
  final Map<String, dynamic> data;

  ImageLayer({required String id, required this.data, bool isVisible = true})
    : super(id: id, type: LayerType.image, isVisible: isVisible);

  @override
  Map<String, dynamic> toMap() {
    return {'id': id, 'type': 'image', 'data': data, 'isVisible': isVisible};
  }

  factory ImageLayer.fromMap(Map<String, dynamic> map) {
    final data = Map<String, dynamic>.from(map['data']);
    // Restore Offset/Size objects
    if (data['position'] is Map) {
      data['position'] = Offset(data['position']['dx'], data['position']['dy']);
    }
    if (data['size'] is Map) {
      data['size'] = Size(data['size']['width'], data['size']['height']);
    }

    return ImageLayer(
      id: map['id'],
      data: data,
      isVisible: map['isVisible'] ?? true,
    );
  }
}

class CanvasState {
  final List<CanvasLayer> layers;
  CanvasState(this.layers);
}
