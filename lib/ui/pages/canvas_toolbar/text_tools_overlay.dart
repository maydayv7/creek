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
      bottom: 120, // Positioned above the bottom bar
      left: 20,
      right: 20,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // --- Close / Done ---
              IconButton(
                icon: const Icon(Icons.check, color: Colors.green),
                onPressed: onClose,
                tooltip: "Done",
              ),
              
              Container(width: 1, height: 20, color: Colors.grey[300]),
              const SizedBox(width: 8),

              // --- Add Text Button ---
              IconButton(
                icon: const Icon(Icons.add_circle_outline, color: Colors.black87),
                onPressed: onAddText,
                tooltip: "Add Text",
              ),

              // --- Edit Tools (Only if text is selected) ---
              if (isTextSelected) ...[
                Container(width: 1, height: 20, color: Colors.grey[300]),
                const SizedBox(width: 8),

                // Font Size
                const Icon(Icons.text_fields, size: 16, color: Colors.grey),
                SizedBox(
                  width: 100,
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      activeTrackColor: Colors.black87,
                      inactiveTrackColor: Colors.grey[200],
                      thumbColor: Colors.black,
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: Slider(
                      value: currentFontSize.clamp(10.0, 100.0),
                      min: 10.0,
                      max: 100.0,
                      onChanged: onFontSizeChanged,
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // Color Picker
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

                const SizedBox(width: 8),
                Container(width: 1, height: 20, color: Colors.grey[300]),
                const SizedBox(width: 8),

                // Delete
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
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
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Text Color", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            BlockPicker(
              pickerColor: currentColor,
              onColorChanged: (c) {
                onColorChanged(c);
                Navigator.pop(ctx);
              },
              layoutBuilder: (context, colors, child) => SizedBox(
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
