import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:adobe/ui/styles/variables.dart';
import 'package:adobe/ui/widgets/bottom_bar.dart';
import 'package:adobe/ui/widgets/top_bar.dart';
import 'package:adobe/data/repos/image_repo.dart';
import 'package:adobe/data/repos/project_repo.dart';
import 'package:adobe/services/python_service.dart';

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
  bool _isLoading = false;
  String? _resultJson;

  @override
  void initState() {
    super.initState();
    _currentProjectId = widget.projectId;
    _loadSavedStylesheet();
  }

  Future<void> _loadSavedStylesheet() async {
    final project = await ProjectRepo().getProjectById(_currentProjectId);
    if (project?.globalStylesheet != null && project!.globalStylesheet!.isNotEmpty) {
      try {
        final parsed = jsonDecode(project.globalStylesheet!);
        const encoder = JsonEncoder.withIndent('  ');
        setState(() {
          _resultJson = encoder.convert(parsed);
        });
      } catch (_) {
      }
    }
  }

  Future<void> _generateStylesheet() async {
    setState(() {
      _isLoading = true;
      _resultJson = null; 
    });

    try {
      // 1. Fetch images for this project
      final images = await ImageRepo().getImages(_currentProjectId);

      // 2. Extract valid analysis data
      final List<String> analysisDataList = images
          .map((img) => img.analysisData)
          .where((data) => data != null && data.isNotEmpty)
          .cast<String>()
          .toList();

      if (analysisDataList.isEmpty) {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("No analyzed images found for this project.")),
          );
        }
        setState(() { _isLoading = false; });
        return;
      }

      // 3. Call Python Service
      final result = await PythonService().generateStylesheet(analysisDataList);
      if (mounted) {
        if (result != null) {
          const encoder = JsonEncoder.withIndent('  ');
          final jsonString = encoder.convert(result);

          // 4. Save to Database
          await ProjectRepo().updateStylesheet(_currentProjectId, jsonString);
          setState(() {
            _resultJson = jsonString;
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Failed to generate stylesheet.")),
          );
        }
      }
    } catch (e) {
      debugPrint("Error generating stylesheet: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
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
            _resultJson = null;
            _loadSavedStylesheet();
          });
        },
      ),

      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight,
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // No saved result
                      if (_resultJson == null && !_isLoading) ...[
                         Text(
                          "Are you ready to start\nbuilding the visual identity?",
                          textAlign: TextAlign.center,
                          style: Variables.headerStyle,
                        ),
                        const SizedBox(height: 32),
                      ],

                      // Loading
                      if (_isLoading)
                        const CircularProgressIndicator(color: Variables.textPrimary),

                      // Result JSON
                      if (_resultJson != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          margin: const EdgeInsets.only(bottom: 24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Text(
                            _resultJson!,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                          ),
                        ),

                      // Button
                      if (!_isLoading) ...[
                        if (_resultJson != null) const SizedBox(height: 24),
                        GestureDetector(
                          onTap: _generateStylesheet,
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
                                  _resultJson == null ? "Generate Stylesheet" : "Regenerate Stylesheet",
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
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),

      bottomNavigationBar: BottomBar(
        currentTab: BottomBarItem.stylesheet,
        projectId: _currentProjectId,
      ),
    );
  }
}
