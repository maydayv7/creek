import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../data/models/image_model.dart';
import '../../utils/image_actions_helper.dart';
import '../styles/variables.dart';

class ImageContextMenu extends StatelessWidget {
  final ImageModel image;
  final Widget child;
  final VoidCallback onImageDeleted;

  const ImageContextMenu({
    super.key,
    required this.image,
    required this.child,
    required this.onImageDeleted,
  });

  void _showRadialMenu(BuildContext context, Offset globalPosition) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black12, // Subtle dim
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: _RadialMenuOverlay(
              center: globalPosition,
              image: image,
              onImageDeleted: onImageDeleted,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Get exact touch position
      onLongPressStart:
          (details) => _showRadialMenu(context, details.globalPosition),
      child: child,
    );
  }
}

class _RadialMenuOverlay extends StatefulWidget {
  final Offset center;
  final ImageModel image;
  final VoidCallback onImageDeleted;

  const _RadialMenuOverlay({
    required this.center,
    required this.image,
    required this.onImageDeleted,
  });

  @override
  State<_RadialMenuOverlay> createState() => _RadialMenuOverlayState();
}

class _RadialMenuOverlayState extends State<_RadialMenuOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  // Configuration
  final double radius = 120.0;
  final double buttonSize = 56.0;
  final double arcSpan = 150.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Closes menu with animation
  void _closeAnimated() {
    _controller.reverse().then((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  // ACTIONS

  Future<void> _shareImage() async {
    Navigator.of(context).pop();
    await ImageActionsHelper.shareImage(context, widget.image.filePath);
  }

  void _sendToFiles() {
    Navigator.of(context).pop();
    ImageActionsHelper.sendToFiles(context, widget.image.filePath);
  }

  Future<void> _renameImage() async {
    // Hide buttons to not obstruct dialog
    _controller.reverse();

    await ImageActionsHelper.renameImage(
      context,
      widget.image,
      widget.onImageDeleted, // Triggers refresh in parent
    );

    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _deleteImage() async {
    // Hide buttons
    _controller.reverse();

    await ImageActionsHelper.deleteImage(
      context,
      widget.image,
      widget.onImageDeleted,
    );

    if (mounted) Navigator.of(context).pop();
  }

  void _notImplemented() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          "Coming soon",
          style: TextStyle(fontFamily: 'GeneralSans'),
        ),
        backgroundColor: Variables.textPrimary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(20),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    // 1. Determine Horizontal Side
    final bool isRightSide = widget.center.dx > screenSize.width / 2;
    double baseAngle = isRightSide ? 180 : 0;

    // 2. Determine Vertical clipping adjustments
    double topBoundary = 120;
    double bottomBoundary = screenSize.height - 120;

    double rotationOffset = 0;
    if (widget.center.dy < topBoundary) {
      // Too close to TOP -> Rotate DOWN
      rotationOffset = isRightSide ? -45 : 45;
    } else if (widget.center.dy > bottomBoundary) {
      // Too close to BOTTOM -> Rotate UP
      rotationOffset = isRightSide ? 45 : -45;
    }

    baseAngle += rotationOffset;

    // 3. Define Buttons
    final buttons = [
      _MenuButtonData(
        svgPath: 'assets/icons/share_icon.svg',
        onTap: _shareImage,
      ),
      _MenuButtonData(
        svgPath: 'assets/icons/files_icon.svg',
        onTap: _sendToFiles,
      ),
      _MenuButtonData(
        icon: Icons.drive_file_rename_outline,
        onTap: _renameImage,
      ),
      _MenuButtonData(
        svgPath: 'assets/icons/trash_icon.svg',
        onTap: _deleteImage,
        isDestructive: true,
      ),
      _MenuButtonData(
        svgPath: 'assets/icons/ai-search.svg',
        onTap: _notImplemented,
      ),
    ];

    return Stack(
      children: [
        // Backdrop
        Positioned.fill(
          child: GestureDetector(
            onTap: _closeAnimated,
            behavior: HitTestBehavior.opaque,
            child: Container(color: Colors.transparent),
          ),
        ),

        // Buttons
        ...List.generate(buttons.length, (index) {
          final step = arcSpan / (buttons.length - 1);
          final startAngle = baseAngle - (arcSpan / 2);
          final angleDeg = startAngle + (step * index);

          return _buildAnimatedButton(angleDeg: angleDeg, data: buttons[index]);
        }),
      ],
    );
  }

  Widget _buildAnimatedButton({
    required double angleDeg,
    required _MenuButtonData data,
  }) {
    final rad = angleDeg * (math.pi / 180);

    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        final r = radius * _scaleAnimation.value;
        final dx = widget.center.dx + (r * math.cos(rad)) - (buttonSize / 2);
        final dy = widget.center.dy + (r * math.sin(rad)) - (buttonSize / 2);

        return Positioned(
          left: dx,
          top: dy,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: _FloatingCircleButton(size: buttonSize, data: data),
          ),
        );
      },
    );
  }
}

// Data Helper
class _MenuButtonData {
  final IconData? icon;
  final String? svgPath;
  final VoidCallback onTap;
  final bool isDestructive;

  _MenuButtonData({
    this.icon,
    this.svgPath,
    required this.onTap,
    this.isDestructive = false,
  });
}

class _FloatingCircleButton extends StatefulWidget {
  final double size;
  final _MenuButtonData data;

  const _FloatingCircleButton({required this.size, required this.data});

  @override
  State<_FloatingCircleButton> createState() => _FloatingCircleButtonState();
}

class _FloatingCircleButtonState extends State<_FloatingCircleButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final Color normalIconColor =
        widget.data.isDestructive ? Colors.red : Variables.textPrimary;
    final Color activeIconColor = Colors.white;

    final Color normalBgColor = Colors.white;
    final Color activeBgColor = const Color(0xFF7C4DFF);

    final currentColor = _isPressed ? activeIconColor : normalIconColor;
    final currentBg = _isPressed ? activeBgColor : normalBgColor;
    final scale = _isPressed ? 1.2 : 1.0;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.data.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        width: widget.size,
        height: widget.size,
        transform: Matrix4.identity()..scale(scale),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          color: currentBg,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child:
            widget.data.svgPath != null
                ? SvgPicture.asset(
                  widget.data.svgPath!,
                  width: 18,
                  height: 18,
                  colorFilter: ColorFilter.mode(currentColor, BlendMode.srcIn),
                )
                : Icon(widget.data.icon, color: currentColor, size: 24),
      ),
    );
  }
}
