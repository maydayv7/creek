import 'dart:io';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:creekui/services/project_service.dart';
import 'package:creekui/ui/styles/variables.dart';
import 'package:creekui/ui/widgets/project_selector.dart';
import 'package:creekui/ui/widgets/app_bar.dart';
import 'package:creekui/ui/widgets/dialog.dart';
import 'package:creekui/ui/widgets/text_field.dart';
import 'image_save_page.dart';

class ShareToMoodboardPage extends StatefulWidget {
  final List<File> imageFiles;
  const ShareToMoodboardPage({super.key, required this.imageFiles});

  @override
  State<ShareToMoodboardPage> createState() => _ShareToMoodboardPageState();
}

class _ShareToMoodboardPageState extends State<ShareToMoodboardPage> {
  final ProjectService _projectService = ProjectService();
  Key _selectorKey = UniqueKey(); // Used to refresh list after creation

  Future<void> _createNewProject() async {
    final controller = TextEditingController();
    await ShowDialog.show(
      context,
      title: "New Project",
      primaryButtonText: "Create",
      content: CommonTextField(
        hintText: "Project Title",
        controller: controller,
        autoFocus: true,
      ),
      onPrimaryPressed: () async {
        final title = controller.text.trim();
        if (title.isNotEmpty) {
          Navigator.pop(context); // Close dialog
          final newId = await _projectService.createProject(title);
          setState(() {
            _selectorKey = UniqueKey();
          });
          _navigateToSavePage(newId, title);
        }
      },
    );
  }

  void _navigateToSavePage(
    int projectId,
    String projectName, {
    String? parentProjectName,
  }) {
    _projectService.openProject(projectId);
    ReceiveSharingIntent.instance.reset();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => ImageSavePage(
              imagePaths: widget.imageFiles.map((f) => f.path).toList(),
              projectId: projectId,
              projectName: projectName,
              isFromShare: true,
              parentProjectName: parentProjectName,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Variables.surfaceBackground,
      appBar: CustomAppBar(
        title: "MoodBoards",
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Variables.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Variables.textPrimary, size: 28),
            onPressed: _createNewProject,
            tooltip: "Create New Project",
          ),
        ],
      ),
      body: ProjectSelector(
        key: _selectorKey,
        onProjectSelected: (id, title, parentTitle) {
          _navigateToSavePage(id, title, parentProjectName: parentTitle);
        },
      ),
    );
  }
}
