import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:adobe/ui/styles/variables.dart';
import 'package:adobe/ui/pages/project_board_page.dart';
import 'package:adobe/ui/pages/stylesheet_page.dart';
import 'package:adobe/ui/pages/project_file_page.dart';

enum BottomBarItem { moodboard, stylesheet, files }

class BottomBar extends StatelessWidget {
  final BottomBarItem currentTab;
  final int projectId;

  const BottomBar({
    super.key,
    required this.currentTab,
    required this.projectId,
  });

  void _onTap(BuildContext context, BottomBarItem item) {
    if (item == currentTab) return;

    Widget nextPage;
    switch (item) {
      case BottomBarItem.moodboard:
        nextPage = ProjectBoardPage(projectId: projectId);
        break;
      case BottomBarItem.stylesheet:
        nextPage = StylesheetPage(projectId: projectId);
        break;
      case BottomBarItem.files:
        nextPage = ProjectFilePage(projectId: projectId);
        break;
    }

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, anim1, anim2) => nextPage,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // System Safe Area Padding
    final double safeBottom = MediaQuery.of(context).padding.bottom;
    final double effectiveBottomPadding = max(safeBottom, 24.0);

    return Container(
      decoration: const BoxDecoration(
        color: Variables.background,
        border: Border(
          top: BorderSide(color: Variables.borderSubtle, width: 1),
        ),
      ),
      padding: EdgeInsets.only(bottom: effectiveBottomPadding, top: 12),
      child: SizedBox(
        height: 54,
        child: Row(
          children: [
            Expanded(
              child: _buildNavItem(
                context,
                BottomBarItem.moodboard,
                "Moodboard",
                "assets/icons/moodboard_icon.svg",
              ),
            ),
            Expanded(
              child: _buildNavItem(
                context,
                BottomBarItem.stylesheet,
                "Stylesheet",
                "assets/icons/stylesheet_icon.svg",
              ),
            ),
            Expanded(
              child: _buildNavItem(
                context,
                BottomBarItem.files,
                "Files",
                "assets/icons/files_icon.svg",
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context,
    BottomBarItem item,
    String label,
    String assetPath,
  ) {
    final bool isSelected = item == currentTab;
    final Color color =
        isSelected ? Variables.textPrimary : Variables.textDisabled;

    return GestureDetector(
      onTap: () => _onTap(context, item),
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              assetPath,
              width: 24,
              height: 24,
              colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: Variables.captionStyle.copyWith(
                color: color,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
