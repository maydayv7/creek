import 'package:flutter/material.dart';
import 'package:creekui/ui/styles/variables.dart';

class SecondaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;

  const SecondaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Variables.borderSubtle,
          foregroundColor: Variables.textPrimary,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(100),
          ),
          elevation: 0,
        ),
        child:
            isLoading
                ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    color: Variables.textPrimary,
                    strokeWidth: 2,
                  ),
                )
                : Text(
                  text,
                  style: Variables.buttonTextStyle.copyWith(
                    color: Variables.textPrimary,
                  ),
                ),
      ),
    );
  }
}
