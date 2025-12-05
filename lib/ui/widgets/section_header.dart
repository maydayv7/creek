import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:creekui/ui/styles/variables.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool showArrow;

  const SectionHeader({
    super.key,
    required this.title,
    this.onTap,
    this.trailing,
    this.showArrow = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontFamily: 'GeneralSans',
                fontSize: 16,
                fontWeight: FontWeight.w500,
                height: 24 / 16,
                color: Variables.textPrimary,
              ),
            ),
          ),
          if (trailing != null)
            trailing!
          else if (showArrow)
            Transform.rotate(
              angle: 3.14159,
              child: SvgPicture.asset(
                'assets/icons/arrow-left-s-line.svg',
                width: 24,
                height: 24,
                colorFilter: const ColorFilter.mode(
                  Variables.textPrimary,
                  BlendMode.srcIn,
                ),
              ),
            ),
        ],
      ),
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: content,
      );
    }

    return content;
  }
}
