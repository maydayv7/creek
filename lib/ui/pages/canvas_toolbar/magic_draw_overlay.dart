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

  const MagicDrawTools({
    super.key,
    required this.isActive,
    required this.selectedColor,
    required this.strokeWidth,
    required this.isEraser,
    required this.onColorChanged,
    required this.onWidthChanged,
    required this.onEraserToggle,
  });

  @override
  State<MagicDrawTools> createState() => _MagicDrawToolsState();
}

class _MagicDrawToolsState extends State<MagicDrawTools> {
  bool _showStrokeSlider = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) return const SizedBox.shrink();

    // Only displaying the bottom tool panel now.
    // The top header is handled by the main Scaffold AppBar.
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
                const Expanded(
                  child: TextField(
                    decoration: InputDecoration.collapsed(
                      hintText: "tap imagination...",
                      hintStyle: TextStyle(fontSize: 14, color: Colors.black54),
                    ),
                  ),
                ),
                const Icon(Icons.mic_none, color: Colors.grey),
                const SizedBox(width: 8),
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0xFF2B2B2B),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: Colors.white,
                    size: 20,
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
                  onTap:
                      () => setState(
                        () => _showStrokeSlider = !_showStrokeSlider,
                      ),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color:
                          _showStrokeSlider
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
          onColorChanged: widget.onColorChanged,
        );
      },
    );
  }
}

class _TaperedSliderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
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

  const _AdvancedColorPickerSheet({
    required this.initialColor,
    required this.onColorChanged,
  });

  @override
  State<_AdvancedColorPickerSheet> createState() =>
      _AdvancedColorPickerSheetState();
}

class _AdvancedColorPickerSheetState extends State<_AdvancedColorPickerSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Color _currentColor;

  final List<Color> _brandPalette = [
    Colors.blue,
    const Color(0xFFCCFF00),
    Colors.purpleAccent,
    const Color(0xFFF0F0F0),
    Colors.black,
  ];

  final List<Color> _recentColors = [
    Colors.blue,
    Colors.purple,
    const Color(0xFFD81B60),
    Colors.pinkAccent,
    Colors.amber,
  ];

  @override
  void initState() {
    super.initState();
    _currentColor = widget.initialColor;
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _updateColor(Color color) {
    setState(() => _currentColor = color);
    widget.onColorChanged(color);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            TabBar(
              controller: _tabController,
              labelColor: Colors.black,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.black,
              labelStyle: const TextStyle(fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: 'Grid'),
                Tab(text: 'Spectrum'),
                Tab(text: 'Sliders'),
              ],
            ),
            const SizedBox(height: 16),
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
            _buildSharedFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildGridTab() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: GridView.builder(
                physics: const BouncingScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 10,
                  crossAxisSpacing: 2,
                  mainAxisSpacing: 2,
                ),
                itemCount: 100,
                itemBuilder: (context, index) {
                  final double hue = (index % 10) * 36.0;
                  final double saturation = ((index ~/ 10) + 1) / 10.0;
                  final color =
                      HSVColor.fromAHSV(1.0, hue, saturation, 0.9).toColor();

                  return GestureDetector(
                    onTap: () => _updateColor(color),
                    child: Container(color: color),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          _buildHueSlider(),
          _buildOpacitySlider(),
        ],
      ),
    );
  }

  Widget _buildSpectrumTab() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Expanded(
            child: ColorPicker(
              pickerColor: _currentColor,
              onColorChanged: _updateColor,
              enableAlpha: false,
              displayThumbColor: true,
              paletteType: PaletteType.hsvWithHue,
              labelTypes: const [],
              pickerAreaHeightPercent: 0.8,
              pickerAreaBorderRadius: BorderRadius.circular(12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlidersTab() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          const SizedBox(height: 20),
          _buildRGBSlider("R", Colors.red, _currentColor.red, (v) {
            _updateColor(_currentColor.withRed(v.toInt()));
          }),
          _buildRGBSlider("G", Colors.green, _currentColor.green, (v) {
            _updateColor(_currentColor.withGreen(v.toInt()));
          }),
          _buildRGBSlider("B", Colors.blue, _currentColor.blue, (v) {
            _updateColor(_currentColor.withBlue(v.toInt()));
          }),
        ],
      ),
    );
  }

  Widget _buildRGBSlider(
    String label,
    Color activeColor,
    int value,
    ValueChanged<double> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 36,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 36,
                  activeTrackColor: activeColor,
                  inactiveTrackColor: activeColor.withOpacity(0.2),
                  thumbColor: Colors.transparent,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 0,
                  ),
                  overlayShape: SliderComponentShape.noOverlay,
                  trackShape: const RectangularSliderTrackShape(),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Slider(
                    value: value.toDouble(),
                    min: 0,
                    max: 255,
                    onChanged: onChanged,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 50,
            padding: const EdgeInsets.all(8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              "$value",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHueSlider() {
    return SizedBox(
      height: 15,
      child: SliderTheme(
        data: SliderThemeData(
          trackHeight: 8,
          trackShape: const RectangularSliderTrackShape(),
          thumbShape: const RoundSliderThumbShape(
            enabledThumbRadius: 10,
            elevation: 2,
          ),
          thumbColor: Colors.white,
          overlayShape: SliderComponentShape.noOverlay,
        ),
        child: ColorPicker(
          pickerColor: _currentColor,
          onColorChanged: _updateColor,
          enableAlpha: false,
          displayThumbColor: true,
          paletteType: PaletteType.hsv,
          labelTypes: const [],
          pickerAreaHeightPercent: 0.0,
        ),
      ),
    );
  }

  Widget _buildOpacitySlider() {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: SizedBox(
        height: 15,
        child: SliderTheme(
          data: SliderThemeData(
            trackHeight: 8,
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 10,
              elevation: 2,
            ),
            thumbColor: Colors.white,
            overlayShape: SliderComponentShape.noOverlay,
          ),
          child: Slider(
            value: 1.0,
            onChanged: (v) {},
            activeColor: Colors.blue,
            inactiveColor: Colors.grey[300],
          ),
        ),
      ),
    );
  }

  Widget _buildSharedFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Recently used",
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: _recentColors.map((c) => _buildColorCircle(c)).toList(),
          ),
          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Brand Palette",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
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
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Icon(Icons.block, size: 16, color: Colors.red[300]),
              ),
              ..._brandPalette.map((c) => _buildColorCircle(c)).toList(),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, size: 18, color: Colors.black54),
              ),
            ],
          ),
          const SizedBox(height: 16),

          const Text(
            "Gradients",
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildGradientCircle(Colors.black, Colors.white),
              _buildGradientCircle(Colors.grey, Colors.black),
              _buildGradientCircle(Colors.white, Colors.grey),
              _buildGradientCircle(Colors.black, Colors.grey),
              const SizedBox(width: 8),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.tune, size: 16, color: Colors.black54),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildColorCircle(Color color) {
    return Container(
      width: 32,
      height: 32,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
    );
  }

  Widget _buildGradientCircle(Color c1, Color c2) {
    return Container(
      width: 32,
      height: 32,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c1, c2],
        ),
      ),
    );
  }
}
