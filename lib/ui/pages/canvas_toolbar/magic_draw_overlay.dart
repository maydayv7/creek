import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../widgets/canvas/advanced_color_picker.dart';
import '../../styles/variables.dart';

// Dropdown
class AIModelOption {
  final String id;
  final String name;
  final String? badge;

  AIModelOption({required this.id, required this.name, this.badge});
}

class MagicDrawTools extends StatefulWidget {
  final bool isActive;
  final Color selectedColor;
  final double strokeWidth;
  final bool isEraser;
  final Function(Color) onColorChanged;
  final Function(double) onWidthChanged;
  final Function(bool) onEraserToggle;
  final VoidCallback onClose;
  final Function(String prompt, String modelId) onPromptSubmit;
  final bool isProcessing;
  final List<Color> brandColors;
  final Function(bool) onViewModeToggle;
  final Function(bool) onMagicPanelActivityToggle;
  final bool isMagicPanelDisabled;

  // To decide which dropdown list to show
  final bool hasImageLayers;

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
    required this.onViewModeToggle,
    required this.onMagicPanelActivityToggle,
    required this.isMagicPanelDisabled,
    required this.hasImageLayers,
  });

  @override
  State<MagicDrawTools> createState() => _MagicDrawToolsState();
}

class _MagicDrawToolsState extends State<MagicDrawTools> {
  bool _showStrokeSlider = false;
  final TextEditingController _promptController = TextEditingController();

  final List<Color> _recentColors = [
    Colors.blue,
    Colors.purple,
    const Color(0xFFD81B60),
    Colors.pinkAccent,
    Colors.amber,
  ];

  bool _isViewMode = false;
  bool _showModelMenu = false;
  late AIModelOption _selectedModel;

  // 1. List for inpainting (When Image Exists)
  final List<AIModelOption> _inpaintingModels = [
    AIModelOption(
      id: 'inpaint_standard',
      name: 'Stable Diffusion Inpainting',
      badge: "Recommended",
    ),
    AIModelOption(id: 'inpaint_api', name: 'FLUX LoRa Fill', badge: null),
  ];

  // 2. List for sketch to image (When No Image Exists)
  final List<AIModelOption> _sketchModels = [
    AIModelOption(id: 'sketch_advanced', name: 'Nano Banana', badge: 'Premium'),
    AIModelOption(id: 'sketch_creative', name: 'FLUX Dev', badge: 'Fast'),
    AIModelOption(
      id: 'sketch_fusion',
      name: 'Stable Diffusion v1.5',
      badge: null,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _updateSelectedModelGroup();
  }

  @override
  void didUpdateWidget(MagicDrawTools oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the layer state changes (image added/removed), reset selection to correct group
    if (oldWidget.hasImageLayers != widget.hasImageLayers) {
      _updateSelectedModelGroup();
    }

    // Clear prompt when opening the tool
    if (!oldWidget.isActive && widget.isActive) {
      _promptController.clear();
    }
  }

  void _updateSelectedModelGroup() {
    if (widget.hasImageLayers) {
      _selectedModel = _inpaintingModels.first;
    } else {
      _selectedModel = _sketchModels.first;
    }
  }

  List<AIModelOption> get _currentModelList {
    return widget.hasImageLayers ? _inpaintingModels : _sketchModels;
  }

  @override
  void dispose() {
    if (_isViewMode) {
      widget.onViewModeToggle(false);
    }
    _promptController.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    if (!widget.isProcessing && !widget.isMagicPanelDisabled) {
      widget.onPromptSubmit(_promptController.text.trim(), _selectedModel.id);
    }
  }

  void _toggleViewMode() {
    final newViewMode = !_isViewMode;
    setState(() {
      _isViewMode = newViewMode;
      _showStrokeSlider = false;
      _showModelMenu = false;
    });
    widget.onViewModeToggle(newViewMode);
  }

  void _toggleModelMenu() {
    setState(() {
      if (!_showModelMenu) _showStrokeSlider = false;
      _showModelMenu = !_showModelMenu;
    });
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

          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_showModelMenu) _buildModelDropdown(),
                _buildMagicDrawPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolIcon(dynamic icon, bool isActive, VoidCallback onTap) {
    final Color activeColor = Variables.textPrimary;
    final Color inactiveColor = Variables.textSecondary;
    final Color iconColor = isActive ? activeColor : inactiveColor;

    final Widget iconWidget =
        (icon is IconData)
            ? Icon(icon, size: 20, color: iconColor)
            : SvgPicture.asset(
              icon,
              width: 20,
              height: 20,
              colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
            );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isActive ? Variables.surfaceSubtle : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: iconWidget,
      ),
    );
  }

  Widget _buildModelDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.hasImageLayers ? 'Inpainting Models' : 'Sketch Models',
            style: Variables.captionStyle.copyWith(fontSize: 12),
          ),
          const SizedBox(height: 4),

          ..._currentModelList.map((model) {
            final isSelected = model.id == _selectedModel.id;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedModel = model;
                  _showModelMenu = false;
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  children: [
                    Icon(
                      Icons.star_half,
                      color: isSelected ? Variables.accentMagic : Colors.grey,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      model.name,
                      style: Variables.bodyStyle.copyWith(
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    const Spacer(),
                    if (model.badge != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          model.badge!,
                          style: const TextStyle(
                            color: Color(0xFF0D47A1), // Dark blue
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'GeneralSans',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }).toList(),
          const Divider(height: 1, color: Variables.borderSubtle),
        ],
      ),
    );
  }

  Widget _buildMagicDrawPanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              GestureDetector(
                onTap: _toggleModelMenu,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color:
                        _showModelMenu ? Variables.surfaceSubtle : Colors.white,
                    border: Border.all(color: Variables.borderSubtle),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.star_half,
                    color: Variables.accentMagic,
                    size: 20,
                  ),
                ),
              ),

              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _promptController,
                  enabled: !widget.isProcessing,
                  onSubmitted: (_) => _handleSubmit(),
                  style: Variables.bodyStyle,
                  decoration: InputDecoration.collapsed(
                    hintText: "tap imagination...",
                    hintStyle: Variables.captionStyle.copyWith(fontSize: 14),
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
                    color: Variables.textPrimary,
                    shape: BoxShape.circle,
                  ),
                  child:
                      widget.isProcessing
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
        const Divider(height: 1, color: Variables.borderSubtle),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildToolIcon(Icons.pan_tool, widget.isMagicPanelDisabled, () {
                setState(() => _showStrokeSlider = false);
                _showModelMenu = false;

                if (!widget.isMagicPanelDisabled) {
                  widget.onEraserToggle(false);
                }

                widget.onMagicPanelActivityToggle(!widget.isMagicPanelDisabled);
              }),
              _buildToolIcon(
                'assets/icons/brush-line.svg',
                !widget.isEraser &&
                    !_isViewMode &&
                    !widget.isMagicPanelDisabled,
                () {
                  setState(() {
                    _showStrokeSlider = false;
                    _showModelMenu = false;
                  });

                  if (_isViewMode) {
                    setState(() => _isViewMode = false);
                    widget.onViewModeToggle(false);
                  }
                  if (widget.isMagicPanelDisabled) {
                    widget.onMagicPanelActivityToggle(false);
                  }

                  widget.onEraserToggle(false);
                },
              ),

              GestureDetector(
                onTap: () {
                  setState(() {
                    _showStrokeSlider = false;
                    _showModelMenu = false;
                  });

                  if (_isViewMode) {
                    setState(() => _isViewMode = false);
                    widget.onViewModeToggle(false);
                  }

                  _showAdvancedColorPicker(context);
                },
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
                onTap: () {
                  if (_isViewMode) {
                    setState(() => _isViewMode = false);
                    widget.onViewModeToggle(false);
                  }

                  setState(() {
                    _showStrokeSlider = !_showStrokeSlider;
                    _showModelMenu = false;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color:
                        _showStrokeSlider
                            ? Variables.surfaceSubtle
                            : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Variables.textPrimary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),

              _buildToolIcon(
                'assets/icons/eraser-line.svg',
                widget.isEraser && !_isViewMode && !widget.isMagicPanelDisabled,
                () {
                  setState(() {
                    _showStrokeSlider = false;
                    _showModelMenu = false;
                  });

                  if (_isViewMode) {
                    setState(() => _isViewMode = false);
                    widget.onViewModeToggle(false);
                  }
                  if (widget.isMagicPanelDisabled) {
                    widget.onMagicPanelActivityToggle(false);
                  }

                  widget.onEraserToggle(true);
                },
              ),
            ],
          ),
        ),
      ],
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
                min: 5.0,
                max: 60.0,
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
        return AdvancedColorPickerSheet(
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
