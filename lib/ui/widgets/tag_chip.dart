import 'package:flutter/material.dart';
import 'package:creekui/ui/styles/variables.dart';

class TagChip extends StatelessWidget {
  final String label;
  final VoidCallback onDelete;
  final Widget? icon;

  const TagChip({
    super.key,
    required this.label,
    required this.onDelete,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Variables.chipBackground,
        borderRadius: BorderRadius.circular(48),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[icon!, const SizedBox(width: 8)],
          Text(
            label,
            style: Variables.captionStyle.copyWith(
              fontSize: 12,
              color: Variables.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onDelete,
            child: const Icon(
              Icons.close,
              size: 16,
              color: Variables.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
