import 'package:flutter/material.dart';
import 'package:creekui/ui/styles/variables.dart';
import 'package:creekui/ui/widgets/primary_button.dart';
import 'package:creekui/ui/widgets/secondary_button.dart';

class ShowDialog extends StatelessWidget {
  final String title;
  final String? description;
  final Widget? content;
  final String primaryButtonText;
  final VoidCallback onPrimaryPressed;
  final String secondaryButtonText;
  final VoidCallback? onSecondaryPressed;
  final bool
  isDestructive; // Makes primary button red if true (future enhancement)
  final bool isLoading;

  const ShowDialog({
    super.key,
    required this.title,
    this.description,
    this.content,
    required this.primaryButtonText,
    required this.onPrimaryPressed,
    this.secondaryButtonText = "Cancel",
    this.onSecondaryPressed,
    this.isDestructive = false,
    this.isLoading = false,
  });

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    String? description,
    Widget? content,
    required String primaryButtonText,
    required VoidCallback onPrimaryPressed,
    String secondaryButtonText = "Cancel",
    VoidCallback? onSecondaryPressed,
    bool isDestructive = false,
    bool isLoading = false,
  }) {
    return showDialog<T>(
      context: context,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Variables.radiusLarge),
            ),
            child: ShowDialog(
              title: title,
              description: description,
              content: content,
              primaryButtonText: primaryButtonText,
              onPrimaryPressed: onPrimaryPressed,
              secondaryButtonText: secondaryButtonText,
              onSecondaryPressed: onSecondaryPressed,
              isDestructive: isDestructive,
              isLoading: isLoading,
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Variables.headerStyle.copyWith(fontSize: 18)),
          if (description != null) ...[
            const SizedBox(height: 8),
            Text(
              description!,
              style: Variables.bodyStyle.copyWith(
                color: Variables.textSecondary,
              ),
            ),
          ],
          if (content != null) ...[const SizedBox(height: 16), content!],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  text: secondaryButtonText,
                  onPressed: onSecondaryPressed ?? () => Navigator.pop(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PrimaryButton(
                  text: primaryButtonText,
                  onPressed: onPrimaryPressed,
                  isLoading: isLoading,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
