import 'package:flutter/material.dart';
import 'package:creekui/ui/styles/variables.dart';

class CommonSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final String hintText;
  final Color? backgroundColor;

  const CommonSearchBar({
    super.key,
    required this.controller,
    this.onChanged,
    this.hintText = 'Search',
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: Variables.bodyStyle,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: Variables.bodyStyle.copyWith(
          color: Variables.textSecondary.withOpacity(0.5),
        ),
        prefixIcon: Icon(
          Icons.search,
          size: 18,
          color: Variables.textSecondary.withOpacity(0.5),
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 50,
          minHeight: 18,
        ),
        filled: true,
        fillColor: backgroundColor ?? Variables.surfaceSubtle,
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
    );
  }
}
