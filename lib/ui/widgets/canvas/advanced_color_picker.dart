import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:creekui/ui/styles/variables.dart';

class AdvancedColorPickerSheet extends StatefulWidget {
  final Color initialColor;
  final ValueChanged<Color> onColorChanged;
  final List<Color> recentColors;
  final List<Color> brandColors;

  const AdvancedColorPickerSheet({
    super.key,
    required this.initialColor,
    required this.onColorChanged,
    required this.recentColors,
    required this.brandColors,
  });

  @override
  State<AdvancedColorPickerSheet> createState() =>
      _AdvancedColorPickerSheetState();
}

class _AdvancedColorPickerSheetState extends State<AdvancedColorPickerSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Color _currentColor;
  late HSVColor _currentHsv;
  late List<Color> _brandPalette;

  final TextEditingController _rController = TextEditingController();
  final TextEditingController _gController = TextEditingController();
  final TextEditingController _bController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentColor = widget.initialColor;
    _currentHsv = HSVColor.fromColor(widget.initialColor);
    _tabController = TabController(length: 3, vsync: this);
    _brandPalette = widget.brandColors;
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

  // Updates the active color and canvas immediately (Live Preview)
  void _handleColorChange(Color color) {
    setState(() {
      _currentColor = color;
      _currentHsv = HSVColor.fromColor(color);
      _updateControllers();
    });
    widget.onColorChanged(color);
  }

  // Handler for Spectrum Tab to avoid HSV->RGB->HSV conversion loss
  void _handleHsvChange(HSVColor hsv) {
    setState(() {
      _currentHsv = hsv;
      _currentColor = hsv.toColor();
      _updateControllers();
    });
    widget.onColorChanged(_currentColor);
  }

  // Saves the current color to the "Recently Used" list
  void _saveToRecent() {
    setState(() {
      widget.recentColors.removeWhere((c) => c.value == _currentColor.value);
      widget.recentColors.insert(0, _currentColor);
      if (widget.recentColors.length > 5) {
        widget.recentColors.removeLast();
      }
    });
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
          // Header: Hex Code & Preview
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
          // Tab Views
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
    );
  }

  // Tab 1: Grid
  List<Color> _generateColorGrid() {
    List<Color> colors = [];
    for (int i = 0; i < 9; i++) {
      double lightness = 1.0 - (i / 8);
      colors.add(HSLColor.fromAHSL(1.0, 0.0, 0.0, lightness).toColor());
    }
    final int hueSteps = 9;
    final int shadeSteps = 7;
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
                  onTap: () {
                    _handleColorChange(color);
                    _saveToRecent(); // Save immediately on tap
                  },
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

  // Tab 2: Spectrum
  Widget _buildSpectrumTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Saturation / Value Box
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return GestureDetector(
                    onPanUpdate: (details) {
                      RenderBox box = context.findRenderObject() as RenderBox;
                      Offset localOffset = box.globalToLocal(
                        details.globalPosition,
                      );

                      double saturation = (localOffset.dx /
                              constraints.maxWidth)
                          .clamp(0.0, 1.0);
                      double value =
                          1.0 -
                          (localOffset.dy / constraints.maxHeight).clamp(
                            0.0,
                            1.0,
                          );

                      _handleHsvChange(
                        _currentHsv.withSaturation(saturation).withValue(value),
                      );
                    },
                    onPanEnd: (_) => _saveToRecent(),
                    child: Stack(
                      children: [
                        // Base Hue Color
                        Container(
                          color:
                              HSVColor.fromAHSV(
                                1.0,
                                _currentHsv.hue,
                                1.0,
                                1.0,
                              ).toColor(),
                        ),
                        // Gradient: White -> Transparent (Saturation)
                        Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.white, Colors.transparent],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                          ),
                        ),
                        // Gradient: Transparent -> Black (Value/Brightness)
                        Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.transparent, Colors.black],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                        // Selector Circle
                        Positioned(
                          left:
                              _currentHsv.saturation * constraints.maxWidth -
                              10,
                          top:
                              (1 - _currentHsv.value) * constraints.maxHeight -
                              10,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: _currentColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: const [
                                BoxShadow(color: Colors.black26, blurRadius: 4),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Hue Slider
          SizedBox(
            height: 40,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Rainbow Background
                Container(
                  height: 12,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFFFF0000),
                        Color(0xFFFFFF00),
                        Color(0xFF00FF00),
                        Color(0xFF00FFFF),
                        Color(0xFF0000FF),
                        Color(0xFFFF00FF),
                        Color(0xFFFF0000),
                      ],
                    ),
                  ),
                ),
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 12,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 14,
                      elevation: 4,
                    ),
                    overlayColor: Colors.transparent,
                    thumbColor: Colors.white,
                    activeTrackColor: Colors.transparent,
                    inactiveTrackColor: Colors.transparent,
                  ),
                  child: Slider(
                    value: _currentHsv.hue,
                    min: 0.0,
                    max: 360.0,
                    onChanged: (newHue) {
                      _handleHsvChange(_currentHsv.withHue(newHue));
                    },
                    onChangeEnd: (_) => _saveToRecent(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  // Tab 3: Sliders
  Widget _buildSlidersTab() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: SingleChildScrollView(
        child: Column(
          children: [
            _buildSingleRGBSlider("Red", Colors.red, _currentColor.red, (v) {
              _handleColorChange(_currentColor.withRed(v.toInt()));
            }),
            const SizedBox(height: 24),
            _buildSingleRGBSlider("Green", Colors.green, _currentColor.green, (
              v,
            ) {
              _handleColorChange(_currentColor.withGreen(v.toInt()));
            }),
            const SizedBox(height: 24),
            _buildSingleRGBSlider("Blue", Colors.blue, _currentColor.blue, (v) {
              _handleColorChange(_currentColor.withBlue(v.toInt()));
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
                onChangeEnd: (_) => _saveToRecent(),
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

  // Footer
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
          ],
        ),
      ),
    );
  }

  Widget _buildColorCircle(Color color) {
    return GestureDetector(
      onTap: () {
        _handleColorChange(color);
        _saveToRecent();
      },
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
