import 'dart:io';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:creekui/services/project_service.dart';
import 'package:creekui/ui/styles/variables.dart';
import 'package:creekui/ui/widgets/project_selector.dart';
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
    final String? title = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text(
              "New Project",
              style: TextStyle(fontFamily: 'GeneralSans'),
            ),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(hintText: "Project Title"),
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: const Text("Create"),
              ),
            ],
          ),
    );

    if (title != null && title.isNotEmpty) {
      final newId = await _projectService.createProject(title);
      setState(() {
        _selectorKey = UniqueKey();
      });
      _navigateToSavePage(newId, title);
    }
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
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "MoodBoards",
          style: Variables.headerStyle.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.add, color: theme.colorScheme.onSurface, size: 28),
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
