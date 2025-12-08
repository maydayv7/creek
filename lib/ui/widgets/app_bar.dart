import 'package:flutter/material.dart';
import 'package:creekui/ui/styles/variables.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final Widget? titleWidget;
  final bool showBack;
  final VoidCallback? onBack;
  final List<Widget>? actions;
  final Widget? leading;
  final double? leadingWidth;
  final bool centerTitle;

  const CustomAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.showBack = true,
    this.onBack,
    this.actions,
    this.leading,
    this.leadingWidth,
    this.centerTitle = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title:
          titleWidget ??
          (title != null ? Text(title!, style: Variables.headerStyle) : null),
      backgroundColor: Variables.surfaceBackground,
      elevation: 0,
      centerTitle: centerTitle,
      leadingWidth: leadingWidth ?? (showBack ? 50 : 0),
      titleSpacing: showBack ? 0 : 16,
      automaticallyImplyLeading: false,
      leading:
          leading ??
          (showBack
              ? IconButton(
                icon: const Icon(
                  Icons.arrow_back,
                  size: 20,
                  color: Variables.textPrimary,
                ),
                onPressed: onBack ?? () => Navigator.pop(context),
              )
              : null),
      actions: actions,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
