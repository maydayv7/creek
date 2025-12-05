import 'package:flutter/material.dart';
import 'package:creekui/ui/styles/variables.dart';

class CommonSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final String hintText;

  const CommonSearchBar({
    super.key,
    required this.controller,
    this.onChanged,
    this.hintText = 'Search',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          fontFamily: 'GeneralSans',
        ),
        prefixIcon: Icon(
          Icons.search,
          size: 18,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 50,
          minHeight: 18,
        ),
        filled: true,
        fillColor: isDark ? Variables.surfaceDark : Variables.surfaceSubtle,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Variables.radiusSmall),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Variables.radiusSmall),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Variables.radiusSmall),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
      style: TextStyle(
        fontSize: 12,
        fontFamily: 'GeneralSans',
        color: theme.colorScheme.onSurface,
      ),
    );
  }
}
