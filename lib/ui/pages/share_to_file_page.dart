import 'dart:io';
import 'package:flutter/material.dart';
import '../../services/file_service.dart';
import '../../data/models/file_model.dart';
import 'create_file_page.dart'; // Import the new creation page

class ShareToFilePage extends StatefulWidget {
  final File sharedImage; // This is the image passed from ShareHandler

  const ShareToFilePage({super.key, required this.sharedImage});

  @override
  State<ShareToFilePage> createState() => _ShareToFilePageState();
}

class _ShareToFilePageState extends State<ShareToFilePage> {
  final FileService _fileService = FileService();
  final TextEditingController _searchController = TextEditingController();

  List<FileModel> _allFiles = [];
  List<FileModel> _filteredFiles = [];
  List<FileModel> _recentFiles = [];
  bool _isLoading = true;
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _fetchFiles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchFiles() async {
    try {
      setState(() => _isLoading = true);

      // Assuming projectId 0 is your 'Inbox' or default folder
      final files = await _fileService.getFiles(0);

      // Sort by last updated to get recent files
      files.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));

      setState(() {
        _allFiles = files;
        _filteredFiles = files;
        _recentFiles = files.take(3).toList(); // Get 3 most recent files
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error fetching files: $e");
      setState(() => _isLoading = false);
    }
  }

  void _filterFiles(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredFiles = _allFiles;
      } else {
        final q = query.toLowerCase();
        _filteredFiles =
            _allFiles
                .where((file) => file.name.toLowerCase().contains(q))
                .toList();
      }
    });
  }

  void _onAddPressed() {
    // Redirect to the CreateFilePage (Canvas Selection) with the shared image
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateFilePage(file: widget.sharedImage),
      ),
    );
  }

  void _onFileSelected(FileModel file) {
    // TODO: Handle file selection - maybe open editor with this file
    // For now, just show a snackbar
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Selected: ${file.name}')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Your Files',
          style: TextStyle(
            color: Color(0xFF27272A),
            fontFamily: 'GeneralSans',
            fontSize: 20,
            fontWeight: FontWeight.w500,
            height: 1.2,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.black, size: 28),
            onPressed: _onAddPressed,
            tooltip: "Create New File",
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _allFiles.isEmpty
              ? _buildEmptyState()
              : Column(
                children: [
                  // --- Search Bar ---
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: SizedBox(
                      height: 42,
                      child: TextField(
                        controller: _searchController,
                        onChanged: _filterFiles,
                        style: const TextStyle(
                          fontFamily: "GeneralSans",
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF71717B),
                          height: 1.4,
                        ),
                        decoration: InputDecoration(
                          hintText: "Search",
                          hintStyle: const TextStyle(
                            fontFamily: "GeneralSans",
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                            color: Color(0xFF71717B),
                          ),
                          prefixIcon: const Icon(
                            Icons.search,
                            size: 20,
                            color: Color(0xFF9F9FA9),
                          ),
                          filled: true,
                          fillColor: const Color(0xFFE4E4E7),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 16,
                          ),
                          suffixIcon:
                              _searchQuery.isNotEmpty
                                  ? IconButton(
                                    icon: const Icon(
                                      Icons.clear,
                                      size: 20,
                                      color: Color(0xFF9F9FA9),
                                    ),
                                    padding: EdgeInsets.zero,
                                    onPressed: () {
                                      _searchController.clear();
                                      _filterFiles("");
                                    },
                                  )
                                  : null,
                        ),
                      ),
                    ),
                  ),

                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // --- RECENT FILES SECTION ---
                          if (_searchQuery.isEmpty &&
                              _recentFiles.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 8,
                              ),
                              child: Text(
                                "Recent Files",
                                style: TextStyle(
                                  fontFamily: 'GeneralSans',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  color: Color(0xFF27272A),
                                  height: 1.43,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              child: Column(
                                children:
                                    _recentFiles
                                        .map(
                                          (file) => _buildRecentFileItem(file),
                                        )
                                        .toList(),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],

                          // --- ALL FILES SECTION ---
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 8,
                            ),
                            child: Text(
                              _searchQuery.isEmpty
                                  ? "All Files"
                                  : "Search Results",
                              style: const TextStyle(
                                fontFamily: 'GeneralSans',
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                                color: Color(0xFF27272A),
                                height: 1.43,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _filteredFiles.length,
                              itemBuilder:
                                  (context, index) =>
                                      _buildFileItem(_filteredFiles[index]),
                            ),
                          ),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            "No files yet",
            style: TextStyle(color: Colors.grey[500], fontSize: 16),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _onAddPressed,
            child: const Text("Create your first file"),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentFileItem(FileModel file) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _onFileSelected(file),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 4, 0, 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE4E4E7), width: 1),
          ),
          child: Row(
            children: [
              // File Thumbnail
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child:
                      File(file.filePath).existsSync()
                          ? Image.file(
                            File(file.filePath),
                            fit: BoxFit.cover,
                            errorBuilder:
                                (_, __, ___) => Icon(
                                  Icons.image,
                                  color: Colors.grey[400],
                                  size: 28,
                                ),
                          )
                          : Icon(
                            Icons.image,
                            color: Colors.grey[400],
                            size: 28,
                          ),
                ),
              ),
              const SizedBox(width: 10),
              // File Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      file.name,
                      style: const TextStyle(
                        fontFamily: 'GeneralSans',
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF27272A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatDate(file.lastUpdated),
                      style: const TextStyle(
                        fontFamily: 'GeneralSans',
                        fontSize: 12,
                        color: Color(0xFF71717B),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileItem(FileModel file) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _onFileSelected(file),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 4, 0, 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE4E4E7), width: 1),
          ),
          child: Row(
            children: [
              // File Thumbnail
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child:
                      File(file.filePath).existsSync()
                          ? Image.file(
                            File(file.filePath),
                            fit: BoxFit.cover,
                            errorBuilder:
                                (_, __, ___) => Icon(
                                  Icons.description,
                                  color: Colors.grey[400],
                                  size: 24,
                                ),
                          )
                          : Icon(
                            Icons.description,
                            color: Colors.grey[400],
                            size: 24,
                          ),
                ),
              ),
              const SizedBox(width: 12),
              // File Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      file.name,
                      style: const TextStyle(
                        fontFamily: 'GeneralSans',
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF27272A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatDate(file.lastUpdated),
                      style: const TextStyle(
                        fontFamily: 'GeneralSans',
                        fontSize: 12,
                        color: Color(0xFF71717B),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return "Today";
    } else if (difference.inDays == 1) {
      return "Yesterday";
    } else if (difference.inDays < 7) {
      return "${difference.inDays} days ago";
    } else {
      return "${date.day}/${date.month}/${date.year}";
    }
  }
}
