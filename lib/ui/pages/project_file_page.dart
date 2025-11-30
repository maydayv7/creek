import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../data/models/file_model.dart';
import '../../services/file_service.dart';
import 'create_file_page.dart'; // 1. Add this import

class ProjectFilePage extends StatefulWidget {
  final int projectId;

  const ProjectFilePage({super.key, required this.projectId});

  @override
  State<ProjectFilePage> createState() => _ProjectFilePageState();
}

class _ProjectFilePageState extends State<ProjectFilePage> {
  final _fileService = FileService();
  final _imagePicker = ImagePicker();

  List<FileModel> _files = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final files = await _fileService.getFiles(widget.projectId);
      if (mounted) {
        setState(() {
          _files = files;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading files: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickAndAddFile() async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );

      if (pickedFile != null && mounted) {
        _showAddFileDialog(File(pickedFile.path));
      }
    } catch (e) {
      debugPrint("Error picking file: $e");
    }
  }

  Future<void> _showAddFileDialog(File file) async {
    final nameController = TextEditingController(
      text: file.path.split('/').last,
    );
    final descriptionController = TextEditingController();

    if (!mounted) return;

    await showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text(
              "Save File",
              style: TextStyle(
                fontFamily: 'GeneralSans',
                fontWeight: FontWeight.w600,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: "File Name",
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontFamily: 'GeneralSans'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: "Description (optional)",
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                  style: const TextStyle(fontFamily: 'GeneralSans'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (nameController.text.trim().isNotEmpty) {
                    try {
                      await _fileService.saveFile(
                        file,
                        widget.projectId,
                        name: nameController.text.trim(),
                        description:
                            descriptionController.text.trim().isEmpty
                                ? null
                                : descriptionController.text.trim(),
                      );
                      if (context.mounted) {
                        Navigator.pop(context);
                        _loadData();
                      }
                    } catch (e) {
                      debugPrint("Error saving file: $e");
                    }
                  }
                },
                child: const Text("Save"),
              ),
            ],
          ),
    );
  }

  Future<void> _deleteFile(String fileId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text("Delete File?"),
            content: const Text("This action cannot be undone."),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text("Delete"),
              ),
            ],
          ),
    );

    if (confirm == true) {
      await _fileService.deleteFile(fileId);
      _loadData();
    }
  }

  // 2. Navigation method for blank canvas
  void _navigateToCreateFile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        // Passing no file implies a "Blank Canvas"
        builder: (_) => const CreateFilePage(),
      ),
    ).then((_) => _loadData());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Project Files"),
        backgroundColor: theme.appBarTheme.backgroundColor,
        actions: [
          // 3. The + button on top right
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: "Create New File",
            onPressed: _navigateToCreateFile,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickAndAddFile,
        child: const Icon(
          Icons.upload_file,
        ), // Changed to distinguish from top +
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                onRefresh: _loadData,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildSectionHeader("Files", theme),
                          Text(
                            "${_files.length} items",
                            style: TextStyle(
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.6,
                              ),
                              fontFamily: 'GeneralSans',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_files.isEmpty)
                        _buildEmptyState(isDark)
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _files.length,
                          separatorBuilder:
                              (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final file = _files[index];
                            return _buildFileCard(file, theme, isDark);
                          },
                        ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
        ),
      ),
      child: Column(
        children: [
          Icon(Icons.folder_open, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 8),
          Text("No files added yet", style: TextStyle(color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, ThemeData theme) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        fontFamily: 'GeneralSans',
        color: theme.colorScheme.onSurface,
      ),
    );
  }

  Widget _buildFileCard(FileModel file, ThemeData theme, bool isDark) {
    final dateStr = DateFormat.yMMMd().format(file.lastUpdated);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.insert_drive_file,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'GeneralSans',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Updated $dateStr",
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                        fontFamily: 'GeneralSans',
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  if (value == 'delete') {
                    _deleteFile(file.id);
                  } else if (value == 'open') {
                    _fileService.openFile(file.id);
                  }
                },
                itemBuilder:
                    (context) => [
                      const PopupMenuItem(value: 'open', child: Text("Open")),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          "Delete",
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
              ),
            ],
          ),
          if (file.description != null && file.description!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              file.description!,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurface.withOpacity(0.7),
                fontFamily: 'GeneralSans',
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (file.tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children:
                  file.tags
                      .map(
                        (tag) => Chip(
                          label: Text(
                            tag,
                            style: const TextStyle(fontSize: 10),
                          ),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                      .toList(),
            ),
          ],
        ],
      ),
    );
  }
}
