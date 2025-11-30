import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

class TextToolsOverlay extends StatelessWidget {
  final bool isActive;
  final bool isTextSelected;
  final Color currentColor;
  final double currentFontSize;
  final VoidCallback onClose;
  final VoidCallback onAddText;
  final Function(Color) onColorChanged;
  final Function(double) onFontSizeChanged;
  final VoidCallback onDelete;

  const TextToolsOverlay({
    super.key,
    required this.isActive,
    required this.isTextSelected,
    required this.currentColor,
    required this.currentFontSize,
    required this.onClose,
    required this.onAddText,
    required this.onColorChanged,
    required this.onFontSizeChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (!isActive) return const SizedBox.shrink();

    return Positioned(
      bottom: 100,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.check_circle, color: Colors.black87),
                onPressed: onClose,
                tooltip: "Done",
              ),
              Container(width: 1, height: 20, color: Colors.grey[300]),
              const SizedBox(width: 8),

              IconButton(
                icon: const Icon(
                  Icons.add_circle_outline,
                  color: Colors.black87,
                ),
                onPressed: onAddText,
                tooltip: "Add Text",
              ),

              if (isTextSelected) ...[
                const SizedBox(width: 8),
                Container(width: 1, height: 20, color: Colors.grey[300]),
                const SizedBox(width: 12),

                const Icon(Icons.text_fields, size: 18, color: Colors.black54),
                SizedBox(
                  width: 100,
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                      activeTrackColor: Colors.black87,
                      inactiveTrackColor: Colors.grey[200],
                      thumbColor: Colors.black,
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: Slider(
                      value: currentFontSize.clamp(10.0, 200.0),
                      min: 10.0,
                      max: 200.0,
                      onChanged: onFontSizeChanged,
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                GestureDetector(
                  onTap: () => _showColorPicker(context),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: currentColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey[300]!, width: 1),
                    ),
                  ),
                ),

                const SizedBox(width: 12),
                Container(width: 1, height: 20, color: Colors.grey[300]),
                const SizedBox(width: 8),

                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: onDelete,
                  tooltip: "Delete",
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showColorPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (ctx) => Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Text Color",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                BlockPicker(
                  pickerColor: currentColor,
                  onColorChanged: (c) {
                    onColorChanged(c);
                    Navigator.pop(ctx);
                  },
                  layoutBuilder:
                      (context, colors, child) => SizedBox(
                        width: 300,
                        height: 160,
                        child: GridView.count(
                          crossAxisCount: 5,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          children: [for (Color color in colors) child(color)],
                        ),
                      ),
                ),
              ],
            ),
          ),
    );
  }
}
