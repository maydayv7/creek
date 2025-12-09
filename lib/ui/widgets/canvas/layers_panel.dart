import 'dart:io';
import 'package:flutter/material.dart';
import 'package:creekui/data/models/canvas_models.dart';

class LayersPanel extends StatefulWidget {
  final List<CanvasLayer> layers;
  final String? activeLayerId;
  final bool isOpen;
  final VoidCallback onToggle;
  final Function(int oldIndex, int newIndex) onReorder;
  final Function(String id) onDelete;
  final Function(String id) onToggleVisibility;
  final Function(String id) onLayerTap;
  final VoidCallback? onAddLayer;

  const LayersPanel({
    Key? key,
    required this.layers,
    required this.activeLayerId,
    required this.isOpen,
    required this.onToggle,
    required this.onReorder,
    required this.onDelete,
    required this.onToggleVisibility,
    required this.onLayerTap,
    this.onAddLayer,
  }) : super(key: key);

  @override
  State<LayersPanel> createState() => _LayersPanelState();
}

class _LayersPanelState extends State<LayersPanel> {
  @override
  Widget build(BuildContext context) {
    // Reverse list for UI so Top Layer is index 0
    final displayLayers = widget.layers.reversed.toList();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      width: widget.isOpen ? 260 : 56,
      // Use constrained height calculation based on state
      height: widget.isOpen ? 400 : 56,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child:
            widget.isOpen
                ? _buildPanelContent(displayLayers)
                : _buildCollapsedButton(),
      ),
    );
  }

  Widget _buildCollapsedButton() {
    return InkWell(
      onTap: widget.onToggle,
      borderRadius: BorderRadius.circular(16),
      child: const Center(
        child: Icon(Icons.layers_outlined, color: Colors.black),
      ),
    );
  }

  Widget _buildPanelContent(List<CanvasLayer> displayLayers) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topRight,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min, // Shrink to fit content
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Add Layer Button
                  if (widget.onAddLayer != null) ...[
                    InkWell(
                      onTap: widget.onAddLayer,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.add,
                          size: 20,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                  ],

                  const Spacer(),

                  // Layers Icon
                  InkWell(
                    onTap: widget.onToggle,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.layers,
                        size: 20,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 0.5),

            // List
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                buildDefaultDragHandles: false,
                itemCount: displayLayers.length,
                onReorder: widget.onReorder,
                itemBuilder: (context, index) {
                  final layer = displayLayers[index];
                  return _buildLayerItem(context, layer, index);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLayerItem(BuildContext context, CanvasLayer layer, int index) {
    final bool isActive = layer.id == widget.activeLayerId;

    Widget preview;
    String label = "";

    if (layer is ImageLayer) {
      final type = layer.data['type'];
      final content = layer.data['content'];

      if (type == 'text') {
        preview = const Icon(
          Icons.text_fields,
          size: 18,
          color: Colors.black54,
        );
        label = content.toString();
      } else {
        preview = Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.grey[300]!),
            image: DecorationImage(
              image: FileImage(File(content)),
              fit: BoxFit.cover,
            ),
          ),
        );
        label = "Image";
      }
    } else if (layer is SketchLayer) {
      preview = const Icon(Icons.brush, size: 18, color: Colors.purpleAccent);
      label = layer.isMagicDraw ? "Magic Draw" : "Sketch";
    } else {
      preview = const SizedBox();
    }

    return Dismissible(
      key: ValueKey(layer.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => widget.onDelete(layer.id),
      background: Container(
        color: Colors.redAccent,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 12),
        child: const Icon(Icons.delete, color: Colors.white, size: 20),
      ),
      child: Material(
        color: isActive ? Colors.grey.withOpacity(0.1) : Colors.transparent,
        child: InkWell(
          onTap: () => widget.onLayerTap(layer.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              children: [
                const SizedBox(width: 12),
                preview,
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                IconButton(
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    layer.isVisible ? Icons.visibility : Icons.visibility_off,
                    size: 18,
                    color: layer.isVisible ? Colors.black54 : Colors.grey,
                  ),
                  onPressed: () => widget.onToggleVisibility(layer.id),
                ),

                const SizedBox(width: 4),

                ReorderableDragStartListener(
                  index: index,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
                    color: Colors.transparent,
                    child: const Icon(
                      Icons.drag_handle,
                      size: 20,
                      color: Colors.grey,
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
}
