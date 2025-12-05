import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:creekui/data/repos/project_repo.dart';
import 'package:creekui/ui/styles/variables.dart';

class AssetPickerSheet extends StatefulWidget {
  final int projectId;
  final ScrollController scrollController;
  final Function(List<String>) onAddAssets;

  const AssetPickerSheet({
    super.key,
    required this.projectId,
    required this.scrollController,
    required this.onAddAssets,
  });

  @override
  State<AssetPickerSheet> createState() => _AssetPickerSheetState();
}

class _AssetPickerSheetState extends State<AssetPickerSheet> {
  List<String> _assets = [];
  bool _isLoading = true;
  Set<String> _selectedPaths = {};

  @override
  void initState() {
    super.initState();
    _loadAssets();
  }

  Future<void> _loadAssets() async {
    try {
      final project = await ProjectRepo().getProjectById(widget.projectId);
      if (mounted) {
        setState(() {
          _assets = project?.assetsPath ?? [];
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading assets: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<File?> _resolveFile(String path) async {
    final file = File(path);
    if (await file.exists()) return file;
    try {
      final filename = p.basename(path);
      final dir = await getApplicationDocumentsDirectory();
      final fixedPath = '${dir.path}/generated_images/$filename';
      final fixedFile = File(fixedPath);
      if (await fixedFile.exists()) return fixedFile;
    } catch (e) {
      debugPrint("Error resolving file: $e");
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Variables.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Variables.borderSubtle,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Search Bar
          Container(
            height: 40,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Variables.surfaceSubtle,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                const Icon(Icons.search, color: Variables.textSecondary),
                const SizedBox(width: 8),
                const Text(
                  "Search Stylesheet",
                  style: TextStyle(
                    fontFamily: 'GeneralSans',
                    color: Variables.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // Category Tabs
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                _buildFilterChip("Assets", true),
                const SizedBox(width: 12),
                _buildFilterChip("Backgrounds & Texture", false),
              ],
            ),
          ),

          // Grid
          Expanded(
            child:
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _assets.isEmpty
                    ? Center(
                      child: Text(
                        "No assets found in stylesheet",
                        style: TextStyle(color: Variables.textSecondary),
                      ),
                    )
                    : Stack(
                      children: [
                        GridView.builder(
                          controller: widget.scrollController,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 1.0,
                              ),
                          itemCount: _assets.length,
                          itemBuilder: (context, index) {
                            final assetPath = _assets[index];
                            final isSelected = _selectedPaths.contains(
                              assetPath,
                            );

                            return FutureBuilder<File?>(
                              future: _resolveFile(assetPath),
                              builder: (context, snapshot) {
                                final file = snapshot.data;
                                return _buildAssetTile(
                                  child:
                                      file != null
                                          ? Image.file(file, fit: BoxFit.cover)
                                          : const Icon(
                                            Icons.broken_image,
                                            color: Colors.grey,
                                          ),
                                  isSelected: isSelected,
                                  onTap: () {
                                    if (file != null) {
                                      setState(() {
                                        if (isSelected) {
                                          _selectedPaths.remove(assetPath);
                                        } else {
                                          _selectedPaths.add(assetPath);
                                        }
                                      });
                                    }
                                  },
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
          ),

          // Bottom CTA
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 16, bottom: 16),
              child: ElevatedButton(
                onPressed: () => widget.onAddAssets(_selectedPaths.toList()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Variables.surfaceDark,
                  foregroundColor: Variables.textWhite,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: const Text(
                  "Add to File",
                  style: TextStyle(
                    fontFamily: 'GeneralSans',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? Variables.surfaceSubtle : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected ? Colors.transparent : Variables.borderSubtle,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'GeneralSans',
          fontSize: 14,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          color: isSelected ? Variables.textPrimary : Variables.textSecondary,
        ),
      ),
    );
  }

  Widget _buildAssetTile({
    required Widget child,
    required VoidCallback onTap,
    bool isSelected = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.blue : Variables.borderSubtle,
            width: isSelected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (isSelected)
              Container(
                color: Colors.blue.withOpacity(0.1),
                child: const Center(
                  child: Icon(Icons.check_circle, color: Colors.blue),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
