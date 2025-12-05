import 'package:flutter/material.dart';
import 'package:creekui/ui/styles/variables.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onTap;
  final Widget? trailing;

  const SectionHeader({
    super.key,
    required this.title,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Text(
          title,
          style: Variables.headerStyle.copyWith(
            fontSize: 16,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const Spacer(),
        if (trailing != null)
          trailing!
        else if (onTap != null)
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Icon(
                  Icons.chevron_right,
                  size: 24,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
