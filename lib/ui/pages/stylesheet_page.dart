import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:adobe/ui/styles/variables.dart';
import 'package:adobe/ui/widgets/bottom_bar.dart';
import 'package:adobe/ui/widgets/top_bar.dart';

class StylesheetPage extends StatefulWidget {
  final int projectId;

  const StylesheetPage({
    super.key, 
    required this.projectId,
  });

  @override
  State<StylesheetPage> createState() => _StylesheetPageState();
}

class _StylesheetPageState extends State<StylesheetPage> {
  late int _currentProjectId;

  @override
  void initState() {
    super.initState();
    _currentProjectId = widget.projectId;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Variables.background,
      
      appBar: TopBar(
        currentProjectId: _currentProjectId,
        onBack: () => Navigator.of(context).pop(),
        onProjectChanged: (newProject) {
          setState(() {
            _currentProjectId = newProject.id!;
            // If required, reload any page-specific content
          });
        },
      ),

      // Body
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "Are you ready to start\nbuilding the visual identity?",
                textAlign: TextAlign.center,
                style: Variables.headerStyle,
              ),
              const SizedBox(height: 32),
              
              // Pill Button
              GestureDetector(
                onTap: () {
                  // TODO
                },
                child: Container(
                  width: 274,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Variables.textPrimary,
                    borderRadius: BorderRadius.circular(112),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Generate Stylesheet",
                        style: Variables.buttonTextStyle,
                      ),
                      const SizedBox(width: 8),
                      SvgPicture.asset(
                        "assets/icons/generate_icon.svg",
                        width: 18,
                        height: 18,
                        colorFilter: const ColorFilter.mode(
                          Variables.textWhite,
                          BlendMode.srcIn,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),

      bottomNavigationBar: BottomBar(
        currentTab: BottomBarItem.stylesheet,
        projectId: _currentProjectId,
      ),
    );
  }
}
