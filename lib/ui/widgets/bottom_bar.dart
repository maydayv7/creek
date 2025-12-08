import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:creekui/ui/styles/variables.dart';
import 'package:creekui/ui/pages/project_board_page.dart';
import 'package:creekui/ui/pages/stylesheet_page.dart';
import 'package:creekui/ui/pages/project_file_page.dart';

enum BottomBarItem { moodboard, stylesheet, files }

class BottomBar extends StatelessWidget {
  final BottomBarItem currentTab;
  final int projectId;

  const BottomBar({
    super.key,
    required this.currentTab,
    required this.projectId,
  });

  void _onItemTapped(BuildContext context, BottomBarItem item) {
    if (item == currentTab) return;

    Widget page;
    switch (item) {
      case BottomBarItem.moodboard:
        page = ProjectBoardPage(projectId: projectId);
        break;
      case BottomBarItem.stylesheet:
        page = StylesheetPage(projectId: projectId);
        break;
      case BottomBarItem.files:
        page = ProjectFilePage(projectId: projectId);
        break;
    }

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => page,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80, // Fixed height for consistency
      decoration: BoxDecoration(
        color: Variables.background,
        border: Border(top: BorderSide(color: Variables.borderSubtle)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavBarItem(
            iconPath: 'assets/icons/moodboard_icon.svg',
            label: 'Moodboard',
            isActive: currentTab == BottomBarItem.moodboard,
            onTap: () => _onItemTapped(context, BottomBarItem.moodboard),
          ),
          _NavBarItem(
            iconPath: 'assets/icons/stylesheet.svg',
            label: 'Stylesheet',
            isActive: currentTab == BottomBarItem.stylesheet,
            onTap: () => _onItemTapped(context, BottomBarItem.stylesheet),
          ),
          _NavBarItem(
            iconPath: 'assets/icons/files_icon.svg',
            label: 'Files',
            isActive: currentTab == BottomBarItem.files,
            onTap: () => _onItemTapped(context, BottomBarItem.files),
          ),
        ],
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  final String iconPath;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.iconPath,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? Variables.iconActive : Variables.iconInactive;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              iconPath,
              width: 24,
              height: 24,
              colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Variables.captionStyle.copyWith(
                color: color,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
