import 'package:flutter/material.dart';
import 'package:creekui/ui/styles/variables.dart';

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: Variables.textDisabled),
          const SizedBox(height: 16),
          Text(
            title,
            style: Variables.bodyStyle.copyWith(
              fontWeight: FontWeight.w600,
              color: Variables.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Variables.captionStyle,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
