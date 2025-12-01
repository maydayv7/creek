import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

class MagicDrawTools extends StatefulWidget {
  final bool isActive;
  final Color selectedColor;
  final double strokeWidth;
  final bool isEraser;
  final Function(Color) onColorChanged;
  final Function(double) onWidthChanged;
  final Function(bool) onEraserToggle;
  final VoidCallback onClose;
  final Function(String) onPromptSubmit; // Callback for prompt submission
  final bool isProcessing; // Loading state
  final List<Color> brandColors;

  const MagicDrawTools({
    super.key,
    required this.isActive,
    required this.selectedColor,
    required this.strokeWidth,
    required this.isEraser,
    required this.onColorChanged,
    required this.onWidthChanged,
    required this.onEraserToggle,
    required this.onClose,
    required this.onPromptSubmit,
    required this.isProcessing,
    required this.brandColors,
  });

  @override
  State<MagicDrawTools> createState() => _MagicDrawToolsState();
}

class _MagicDrawToolsState extends State<MagicDrawTools> {
  bool _showStrokeSlider = false;
  final TextEditingController _promptController = TextEditingController();

  // Initialize recent colors here so they persist
  final List<Color> _recentColors = [
    Colors.blue,
    Colors.purple,
    const Color(0xFFD81B60),
    Colors.pinkAccent,
    Colors.amber,
  ];

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    if (_promptController.text.trim().isNotEmpty && !widget.isProcessing) {
      widget.onPromptSubmit(_promptController.text.trim());
      // Optional: Clear text after submit or keep it? 
      // Usually keeping it is better for iterations, clearing if successful.
      // We'll let the parent decide or just keep it for now.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) return const SizedBox.shrink();

    return Positioned(
      bottom: 140,
      left: 16,
      right: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_showStrokeSlider) _buildTaperedStrokeSlider(),
          const SizedBox(height: 8),
          _buildMagicDrawPanel(),
        ],
      ),
    );
  }

  Widget _buildMagicDrawPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Prompt Bar
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.emergency_recording,
                    color: Color(0xFFD8705D),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _promptController,
                    onSubmitted: (_) => _handleSubmit(),
                    decoration: const InputDecoration.collapsed(
                      hintText: "tap imagination...",
                      hintStyle: TextStyle(fontSize: 14, color: Colors.black54),
                    ),
                  ),
                ),
                const Icon(Icons.mic_none, color: Colors.grey),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _handleSubmit,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Color(0xFF2B2B2B),
                      shape: BoxShape.circle,
                    ),
                    child: widget.isProcessing
                        ? const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(
                            Icons.auto_awesome,
                            color: Colors.white,
                            size: 20,
                          ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey.shade200),
          // Tools Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildToolIcon(Icons.crop_free, false, () {}),
                _buildToolIcon(Icons.brush, !widget.isEraser, () {
                  widget.onEraserToggle(false);
                }),

                // Color Picker Trigger
                GestureDetector(
                  onTap: () => _showAdvancedColorPicker(context),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: widget.selectedColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),

                GestureDetector(
                  onTap: () => setState(
                    () => _showStrokeSlider = !_showStrokeSlider,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _showStrokeSlider
                          ? Colors.grey.shade200
                          : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Colors.black87,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
                _buildToolIcon(
                  Icons.cleaning_services_outlined,
                  widget.isEraser,
                  () {
                    widget.onEraserToggle(true);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolIcon(IconData icon, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isActive ? Colors.grey.shade200 : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: Colors.black54),
      ),
    );
  }

  Widget _buildTaperedStrokeSlider() {
    return Container(
      width: 250,
      height: 50,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(200, 30),
            painter: _TaperedSliderPainter(),
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 0,
              thumbColor: Colors.white,
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 10,
                elevation: 3,
              ),
              overlayShape: SliderComponentShape.noOverlay,
              activeTrackColor: Colors.transparent,
              inactiveTrackColor: Colors.transparent,
            ),
            child: SizedBox(
              width: 210,
              child: Slider(
                value: widget.strokeWidth,
                min: 2.0,
                max: 30.0,
                onChanged: widget.onWidthChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAdvancedColorPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _AdvancedColorPickerSheet(
          initialColor: widget.selectedColor,
          recentColors: _recentColors,
          onColorChanged: widget.onColorChanged,
          brandColors: widget.brandColors,
        );
      },
    );
  }
}

class _TaperedSliderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF2B2B2B)
      ..style = PaintingStyle.fill;
    final path = Path();
    path.moveTo(10, size.height / 2 - 2);
    path.lineTo(size.width - 10, size.height / 2 - 10);
    path.lineTo(size.width - 10, size.height / 2 + 10);
    path.lineTo(10, size.height / 2 + 2);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _AdvancedColorPickerSheet extends StatefulWidget {
  final Color initialColor;
  final ValueChanged<Color> onColorChanged;
  final List<Color> recentColors;
  final List<Color> brandColors;

  const _AdvancedColorPickerSheet({
    required this.initialColor,
    required this.onColorChanged,
    required this.recentColors,
    required this.brandColors,
  });

  @override
  State<_AdvancedColorPickerSheet> createState() =>
      _AdvancedColorPickerSheetState();
}

class _AdvancedColorPickerSheetState extends State<_AdvancedColorPickerSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Color _currentColor;
  late List<Color> _brandPalette;

  // Controllers for RGB Sliders (Integrated from other branch)
  final TextEditingController _rController = TextEditingController();
  final TextEditingController _gController = TextEditingController();
  final TextEditingController _bController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentColor = widget.initialColor;
    _tabController = TabController(length: 3, vsync: this);
    _brandPalette = widget.brandColors; // Integrate real brand colors
    _updateControllers();
  }

  void _updateControllers() {
    _rController.text = _currentColor.red.toString();
    _gController.text = _currentColor.green.toString();
    _bController.text = _currentColor.blue.toString();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _rController.dispose();
    _gController.dispose();
    _bController.dispose();
    super.dispose();
  }

  void _updateColor(Color color) {
    setState(() {
      _currentColor = color;

      // Update recent colors list
      widget.recentColors.removeWhere((c) => c.value == color.value);
      widget.recentColors.insert(0, color);
      if (widget.recentColors.length > 5) {
        widget.recentColors.removeLast();
      }

      _updateControllers();
    });
    widget.onColorChanged(color);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // --- HEADER HANDLE ---
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // --- TABS ---
          TabBar(
            controller: _tabController,
            labelColor: Colors.black,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.black,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
            tabs: const [
              Tab(text: 'Grid'),
              Tab(text: 'Spectrum'),
              Tab(text: 'Sliders'),
            ],
          ),

          const SizedBox(height: 16),

          // --- HEX / HEADER ROW ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text(
                        "Hex",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_down,
                        size: 16,
                        color: Colors.grey,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _currentColor,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      "#${_currentColor.value.toRadixString(16).toUpperCase().substring(2)}",
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.colorize, size: 20, color: Colors.black54),
              ],
            ),
          ),

          const SizedBox(height: 16),
          const Divider(height: 1),

          // --- MAIN CONTENT AREA ---
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildGridTab(),
                _buildSpectrumTab(),
                _buildSlidersTab(),
              ],
            ),
          ),

          // --- FOOTER ---
          _buildSharedFooter(),
        ],
      ),
    );
  }

  // --- HELPER: Generate colors (Integrated from other branch) ---
  List<Color> _generateColorGrid() {
    List<Color> colors = [];

    // 1. Top Row: Grayscale (White -> Black)
    for (int i = 0; i < 9; i++) {
      double lightness = 1.0 - (i / 8); // 1.0 to 0.0
      colors.add(HSLColor.fromAHSL(1.0, 0.0, 0.0, lightness).toColor());
    }

    // 2. Main Grid: Hues (Columns) x Shades (Rows)
    final int hueSteps = 9; // Columns
    final int shadeSteps = 7; // Rows excluding grayscale

    for (int shade = 0; shade < shadeSteps; shade++) {
      for (int hueStep = 0; hueStep < hueSteps; hueStep++) {
        double hue = (hueStep / hueSteps) * 360;
        double saturation = 0.5 + (shade / shadeSteps) * 0.5;
        double lightness = 0.8 - (shade / shadeSteps) * 0.5;

        colors.add(
          HSLColor.fromAHSL(1.0, hue, saturation, lightness).toColor(),
        );
      }
    }
    return colors;
  }

  // --- TAB 1: GRID ---
  Widget _buildGridTab() {
    final gridColors = _generateColorGrid();

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: GridView.builder(
              physics: const BouncingScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 9,
                crossAxisSpacing: 0,
                mainAxisSpacing: 0,
                childAspectRatio: 1.0,
              ),
              itemCount: gridColors.length,
              itemBuilder: (context, index) {
                final color = gridColors[index];
                final isSelected = _currentColor.value == color.value;

                return GestureDetector(
                  onTap: () => _updateColor(color),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: color,
                          border: Border.all(
                            color: Colors.black.withOpacity(0.05),
                            width: 0.5,
                          ),
                        ),
                      ),
                      if (isSelected)
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // --- TAB 2: SPECTRUM ---
  Widget _buildSpectrumTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxHeight < 150) {
            return const Center(child: Text("Rotate device"));
          }
          return SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ColorPicker(
                pickerColor: _currentColor,
                onColorChanged: _updateColor,
                enableAlpha: false,
                labelTypes: const [],
                displayThumbColor: true,
                paletteType: PaletteType.hsvWithHue,
                pickerAreaHeightPercent: 0.8,
                hexInputBar: false,
              ),
            ),
          );
        },
      ),
    );
  }

  // --- TAB 3: SLIDERS ---
  Widget _buildSlidersTab() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: SingleChildScrollView(
        child: Column(
          children: [
            _buildSingleRGBSlider("Red", Colors.red, _currentColor.red, (v) {
              _updateColor(_currentColor.withRed(v.toInt()));
            }),
            const SizedBox(height: 24),
            _buildSingleRGBSlider(
              "Green",
              Colors.green,
              _currentColor.green,
              (v) {
                _updateColor(_currentColor.withGreen(v.toInt()));
              },
            ),
            const SizedBox(height: 24),
            _buildSingleRGBSlider("Blue", Colors.blue, _currentColor.blue, (v) {
              _updateColor(_currentColor.withBlue(v.toInt()));
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildSingleRGBSlider(
    String label,
    Color activeColor,
    int value,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 30,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 6,
                activeTrackColor: activeColor,
                inactiveTrackColor: activeColor.withOpacity(0.15),
                thumbColor: Colors.white,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 14,
                  elevation: 4,
                ),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
                trackShape: const RoundedRectSliderTrackShape(),
              ),
              child: Slider(
                value: value.toDouble(),
                min: 0,
                max: 255,
                onChanged: onChanged,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          width: 50,
          height: 36,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
          ),
          alignment: Alignment.center,
          child: Text(
            value.toString(),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),
      ],
    );
  }

  // --- FOOTER ---
  Widget _buildSharedFooter() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade100)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Recently used",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children:
                    widget.recentColors
                        .map((c) => _buildColorCircle(c))
                        .toList(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Brand Palette",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
                Text(
                  "Edit",
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue[700],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildAddButton(),
                  const SizedBox(width: 12),
                  ..._brandPalette.map((c) => _buildColorCircle(c)).toList(),
                ],
              ),
            ),
            // EXCLUDED: Gradient feature as requested.
          ],
        ),
      ),
    );
  }

  Widget _buildColorCircle(Color color) {
    return GestureDetector(
      onTap: () => _updateColor(color),
      child: Container(
        width: 36,
        height: 36,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.grey.shade200, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddButton() {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: const Icon(Icons.add, size: 20, color: Colors.black54),
    );
  }
}