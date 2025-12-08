import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:creekui/ui/styles/variables.dart';

class CanvasBottomBar extends StatelessWidget {
  final String? activeItem;
  final VoidCallback onMagicDraw;
  final VoidCallback onMedia;
  final VoidCallback onStylesheet;
  final VoidCallback onTools;
  final VoidCallback onText;
  final VoidCallback onSelect;
  final VoidCallback onPlugins;
  const CanvasBottomBar({
    super.key,
    this.activeItem,
    required this.onMagicDraw,
    required this.onMedia,
    required this.onStylesheet,
    required this.onTools,
    required this.onText,
    required this.onSelect,
    required this.onPlugins,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Variables.background,
        border: Border(top: BorderSide(color: Variables.borderSubtle)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _BottomBarItem(
                  label: "Magic Draw",
                  iconPath: "assets/icons/magic_draw.svg",
                  onTap: onMagicDraw,
                  isActive: activeItem == "Magic Draw",
                ),
                const SizedBox(width: 24),
                _BottomBarItem(
                  label: "Media",
                  iconPath: "assets/icons/media.svg",
                  onTap: onMedia,
                ),
                const SizedBox(width: 24),
                _BottomBarItem(
                  label: "Stylesheet",
                  iconPath: "assets/icons/stylesheet.svg",
                  onTap: onStylesheet,
                ),
                const SizedBox(width: 24),
                _BottomBarItem(
                  label: "Tools",
                  iconPath: "assets/icons/tools.svg",
                  onTap: onTools,
                ),
                const SizedBox(width: 24),
                _BottomBarItem(
                  label: "Text",
                  iconPath: "assets/icons/text.svg",
                  onTap: onText,
                  isActive: activeItem == "Text",
                ),
                const SizedBox(width: 24),
                _BottomBarItem(
                  label: "Select",
                  iconPath: "assets/icons/select.svg",
                  onTap: onSelect,
                ),
                const SizedBox(width: 24),
                _BottomBarItem(
                  label: "Plugins",
                  iconPath: "assets/icons/plugins.svg",
                  onTap: onPlugins,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomBarItem extends StatelessWidget {
  final String label;
  final String iconPath;
  final VoidCallback onTap;
  final bool isActive;
  const _BottomBarItem({
    required this.label,
    required this.iconPath,
    required this.onTap,
    this.isActive = false,
  });
  @override
  Widget build(BuildContext context) {
    final color = isActive ? Variables.iconActive : Variables.iconInactive;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              iconPath,
              width: 24,
              height: 24,
              colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: Variables.captionStyle.copyWith(
                color: color,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
