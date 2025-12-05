import 'package:flutter/material.dart';
import 'package:creekui/ui/styles/variables.dart';

class CommonTextField extends StatelessWidget {
  final String label;
  final String hintText;
  final TextEditingController controller;
  final int maxLines;
  final bool isRequired;
  final ValueChanged<String>? onSubmitted;

  const CommonTextField({
    super.key,
    required this.label,
    required this.hintText,
    required this.controller,
    this.maxLines = 1,
    this.isRequired = false,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: Variables.bodyStyle.copyWith(fontWeight: FontWeight.w500),
            ),
            if (isRequired)
              Text(
                '*',
                style: Variables.bodyStyle.copyWith(
                  color: const Color(0xFF4F39F6),
                  fontSize: 12,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: Variables.borderSubtle,
            borderRadius: BorderRadius.circular(Variables.radiusSmall),
          ),
          child: TextField(
            controller: controller,
            maxLines: maxLines,
            onSubmitted: onSubmitted,
            style: Variables.bodyStyle,
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: Variables.bodyStyle.copyWith(
                color: Variables.textSecondary,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
