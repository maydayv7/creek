import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'canvas_board_page.dart';

class CreateFilePage extends StatefulWidget {
  final File? file; // Made optional for blank canvas creation

  const CreateFilePage({super.key, this.file});

  @override
  State<CreateFilePage> createState() => _CreateFilePageState();
}

class _CreateFilePageState extends State<CreateFilePage> {
  final TextEditingController _searchController = TextEditingController();

  // Master list of presets
  final List<CanvasPreset> _allPresets = [
    CanvasPreset(
      name: 'Custom',
      width: 0,
      height: 0,
      displaySize: 'Custom Size',
    ),
    CanvasPreset(
      name: 'Poster',
      width: 2304,
      height: 3456,
      displaySize: '24 x 36 in',
    ),
    CanvasPreset(
      name: 'Instagram Post',
      width: 1080,
      height: 1080,
      displaySize: '1080 x 1080 px',
      svgPath: 'assets/icons/instagram_poster.svg',
    ),
    CanvasPreset(
      name: 'Invitation',
      width: 480,
      height: 672,
      displaySize: '5 x 7 in',
      svgPath: 'assets/icons/invitation.svg',
    ),
    CanvasPreset(
      name: 'Flyer - A5',
      width: 560,
      height: 794,
      displaySize: '148 x 210 mm',
    ),
    CanvasPreset(
      name: 'Business Card',
      width: 336,
      height: 192,
      displaySize: '3.5 x 2 in',
      svgPath: 'assets/icons/Group.svg',
    ),
    CanvasPreset(
      name: 'Photo Collage',
      width: 1800,
      height: 1800,
      displaySize: '1800 x 1800 px',
    ),
    CanvasPreset(
      name: 'Menu',
      width: 794,
      height: 1123,
      displaySize: '210 x 297 mm',
    ),
    CanvasPreset(
      name: 'Menu Book',
      width: 794,
      height: 1123,
      displaySize: '210 x 297 mm',
    ),
  ];

  List<CanvasPreset> _filteredPresets = [];

  @override
  void initState() {
    super.initState();
    _filteredPresets = _allPresets;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _runFilter(String enteredKeyword) {
    List<CanvasPreset> results = [];
    if (enteredKeyword.isEmpty) {
      results = _allPresets;
    } else {
      results =
          _allPresets
              .where(
                (preset) => preset.name.toLowerCase().contains(
                  enteredKeyword.toLowerCase(),
                ),
              )
              .toList();
    }
    setState(() {
      _filteredPresets = results;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F5F7),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Create Files',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.black),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _runFilter,
                decoration: InputDecoration(
                  hintText: 'Search',
                  hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                  prefixIcon: Icon(
                    Icons.search,
                    color: Colors.grey[400],
                    size: 20,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  suffixIcon:
                      _searchController.text.isNotEmpty
                          ? IconButton(
                            icon: const Icon(
                              Icons.clear,
                              color: Colors.grey,
                              size: 20,
                            ),
                            onPressed: () {
                              _searchController.clear();
                              _runFilter('');
                            },
                          )
                          : null,
                ),
              ),
            ),
          ),

          // Label
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Canvas Sizes',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          // Tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildTab('All', isSelected: true),
                  const SizedBox(width: 12),
                  _buildTab('Saved', isSelected: false),
                  const SizedBox(width: 12),
                  _buildTab('Photo', isSelected: false),
                  const SizedBox(width: 12),
                  _buildTab('Print', isSelected: false),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Grid
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.75,
              ),
              itemCount: _filteredPresets.length,
              itemBuilder: (context, index) {
                return _buildPresetCard(_filteredPresets[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(String label, {required bool isSelected}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.black : Colors.grey,
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildPresetCard(CanvasPreset preset) {
    final bool isCustom = preset.name == 'Custom';

    return InkWell(
      onTap: () {
        if (isCustom) {
          _navigateToEditor(1000, 1000); // Default custom size or show dialog
        } else {
          _navigateToEditor(preset.width, preset.height);
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Section (Blue Box + White Box + Icon)
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E7FF), // Blue BG
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child:
                      isCustom
                          // Custom uses hardcoded Icon
                          ? const Icon(Icons.add, size: 30, color: Colors.blue)
                          // Others use AspectRatio box + SVG
                          : Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: AspectRatio(
                              aspectRatio:
                                  (preset.width > 0 && preset.height > 0)
                                      ? preset.width / preset.height
                                      : 1.0,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(4),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child:
                                      preset.svgPath != null
                                          ? Padding(
                                            padding: const EdgeInsets.all(4.0),
                                            child: SvgPicture.asset(
                                              preset.svgPath!,
                                              fit: BoxFit.contain,
                                            ),
                                          )
                                          : null,
                                ),
                              ),
                            ),
                          ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Bottom Text
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  preset.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  preset.displaySize,
                  style: const TextStyle(color: Colors.grey, fontSize: 9),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToEditor(int width, int height) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => CanvasBoardPage(
              // Generate a random ID for the project
              projectId: 'proj_${DateTime.now().millisecondsSinceEpoch}',
              // Pass the dimensions from the preset
              width: width.toDouble(),
              height: height.toDouble(),
              // Pass the file if it exists (e.g. from "Image to Canvas" flow)
              initialImage: widget.file,
            ),
      ),
    );
  }
}

class CanvasPreset {
  final String name;
  final int width;
  final int height;
  final String displaySize;
  final String? svgPath;

  CanvasPreset({
    required this.name,
    required this.width,
    required this.height,
    required this.displaySize,
    this.svgPath,
  });
}
