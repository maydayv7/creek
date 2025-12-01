import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:adobe/ui/styles/variables.dart';
import 'package:adobe/ui/widgets/bottom_bar.dart';
import 'package:adobe/ui/widgets/top_bar.dart';
import 'package:adobe/data/repos/image_repo.dart';
import 'package:adobe/data/repos/project_repo.dart';
import 'package:adobe/services/python_service.dart';
import 'package:adobe/data/repos/note_repo.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
  
  Map<String, dynamic>? _stylesheetMap;
  String? _rawJsonString;
  
  // New state variable to hold assets from ProjectRepo
  List<String> _projectAssets = [];

  // Cache for font name lookups
  final Map<String, String> _fontNameCache = {};

  @override
  void initState() {
    super.initState();
    _currentProjectId = widget.projectId;
    _loadSavedStylesheet();
  }

  // --- PARSING LOGIC ---
  String _cleanJsonString(String raw) {
    String cleaned = raw;
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'([{,]\s*)([a-zA-Z0-9_\s/]+)(\s*:)'), 
      (match) => '${match[1]}"${match[2]?.trim()}"${match[3]}'
    );
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'(:\s*)([a-zA-Z0-9_\-\.\/\s]+)(?=\s*[,}])'),
      (match) {
        String val = match[2]!.trim();
        if (val == 'true' || val == 'false' || val == 'null' || double.tryParse(val) != null) {
          return match[0]!;
        }
        return '${match[1]}"$val"';
      }
    );
    return cleaned;
  }

  String _resolveGoogleFontName(String dirtyName) {
    if (_fontNameCache.containsKey(dirtyName)) {
      return _fontNameCache[dirtyName]!;
    }

    String cleanInput = dirtyName.toLowerCase()
        .replaceAll(RegExp(r'[-_]regular$'), '')
        .replaceAll(RegExp(r'[^a-z0-9]'), '');

    final allFonts = GoogleFonts.asMap().keys;
    
    for (String officialName in allFonts) {
      String cleanOfficial = officialName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (cleanOfficial == cleanInput) {
        _fontNameCache[dirtyName] = officialName;
        return officialName;
      }
    }
    return dirtyName; 
  }

  Future<File?> _resolveFile(String path) async {
    // 1. Try the path exactly as saved
    final file = File(path);
    if (await file.exists()) return file;

    // 2. If that fails (iOS UUID change?), try to find it in the current docs dir
    try {
      final filename = p.basename(path); // Get "image_123.png" from the long path
      final dir = await getApplicationDocumentsDirectory();
      
      // Reconstruct path: CurrentDir + generated_images + filename
      final fixedPath = p.join(dir.path, 'generated_images', filename);
      
      final fixedFile = File(fixedPath);
      if (await fixedFile.exists()) {
        return fixedFile;
      }
    } catch (e) {
      debugPrint("Error resolving file path: $e");
    }

    return null;
  }

  Future<void> _loadSavedStylesheet() async {
    final project = await ProjectRepo().getProjectById(_currentProjectId);
    
    if (project == null) return;

    // 1. Load Assets directly from Project Model
    List<String> currentAssets = project.assetsPath;

    // 2. Load Stylesheet JSON
    Map<String, dynamic>? parsedMap;
    String? rawJson;

    if (project.globalStylesheet != null && project.globalStylesheet!.isNotEmpty) {
      rawJson = project.globalStylesheet!;
      dynamic parsed;
      
      try {
        parsed = jsonDecode(rawJson);
      } catch (e) {
        try {
          parsed = jsonDecode(_cleanJsonString(rawJson));
        } catch (_) {}
      }

      if (parsed is String) {
        try { parsed = jsonDecode(parsed); } catch (_) {}
      }

      if (parsed is Map<String, dynamic>) {
        if (parsed.containsKey('results') && parsed['results'] is Map) {
          parsedMap = parsed['results'];
        } else {
          parsedMap = parsed;
        }
      }
    }

    if (mounted) {
      setState(() {
        _projectAssets = currentAssets;
        _rawJsonString = rawJson;
        _stylesheetMap = parsedMap;
      });
    }
  }

  Future<void> _generateStylesheet() async {
    setState(() {
      _isLoading = true;
      _stylesheetMap = null;
      _rawJsonString = null;
    });

    try {
      // 1. Fetch Image Analysis Data
      final images = await ImageRepo().getImages(_currentProjectId);
      final List<String> analysisData = images
          .map((img) => img.analysisData)
          .where((data) => data != null && data.isNotEmpty)
          .cast<String>()
          .toList();

      // 2. Fetch Note Analysis Data
      final notes = await NoteRepo().getNotesByProjectId(_currentProjectId);
      final List<String> noteAnalysisData = notes
          .map((n) => n.analysisData)
          .where((data) => data != null && data.isNotEmpty)
          .cast<String>()
          .toList();

      // 3. Combine both
      analysisData.addAll(noteAnalysisData);

      if (analysisData.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("No analyzed images or notes found.")),
          );
        }
        return;
      }

      final result = await PythonService().generateStylesheet(analysisData);

      if (mounted && result != null) {
        final jsonString = jsonEncode(result);
        await ProjectRepo().updateStylesheet(_currentProjectId, jsonString);
        
        // Reload everything (assets + stylesheet) to keep sync
        await _loadSavedStylesheet();
      }
    } catch (e) {
      debugPrint("Gen Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  dynamic _getData(List<String> keys) {
    if (_stylesheetMap == null) return null;
    for (var k in keys) {
      if (_stylesheetMap!.containsKey(k)) return _stylesheetMap![k];
      for (var mapKey in _stylesheetMap!.keys) {
        if (mapKey.toLowerCase() == k.toLowerCase()) return _stylesheetMap![mapKey];
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Variables.background,
      appBar: TopBar(
        currentProjectId: _currentProjectId,
        onBack: () => Navigator.of(context).pop(),
        onProjectChanged: (p) => setState(() {
          _currentProjectId = p.id!;
          _stylesheetMap = null;
          _projectAssets = [];
          _loadSavedStylesheet();
        }),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Variables.textPrimary))
          : (_stylesheetMap == null && _rawJsonString == null && _projectAssets.isEmpty)
              ? _buildEmptyState()
              : _buildContent(),
      bottomNavigationBar: BottomBar(
        currentTab: BottomBarItem.stylesheet,
        projectId: _currentProjectId,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text("No stylesheet data.", style: Variables.headerStyle.copyWith(fontSize: 18)),
          const SizedBox(height: 24),
          _buildGenerateButton("Generate Stylesheet"),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final style = _getData(['Style', 'style']);
    final lighting = _getData(['Lighting', 'lighting']);
    final colors = _getData(['Colour Palette', 'Color Palette', 'colors']);
    final emotions = _getData(['Emotions', 'emotions']);
    final era = _getData(['Era/Cultural Reference', 'era']);
    final typography = _getData(['Typography', 'fonts']);
    
    // We check _projectAssets.isNotEmpty to determine if we show the section
    final hasAssets = _projectAssets.isNotEmpty;
    
    final foundAny = (style != null || lighting != null || colors != null || emotions != null || era != null || typography != null || hasAssets);

    return RefreshIndicator(
      onRefresh: _generateStylesheet,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Visual Identity",
                    style: TextStyle(fontFamily: 'GeneralSans', fontSize: 24, fontWeight: FontWeight.w600),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _generateStylesheet,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            if (foundAny) ...[
              // 1. Assets / Subjects Section (From Project Repo)
              if (hasAssets)
                _buildAssetsSection(_projectAssets),

              // 2. Typography (Now a Slider)
              if (typography != null) 
                _buildTypographySection(typography),

              // 3. Color Palette
              if (colors != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader("Color Palette"),
                      _buildColorSection(colors),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],

              // 4. Slider Sections
              if (style != null) _buildSliderSection("Style & Aesthetic", style),
              if (emotions != null) _buildSliderSection("Mood & Emotions", emotions),
              if (lighting != null) _buildSliderSection("Lighting", lighting),
              if (era != null) _buildSliderSection("Era & Culture", era),

            ] else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text("Parsing Error. Raw Data:\n\n$_rawJsonString"),
                ),
              ),
            ],
            
            const SizedBox(height: 40),
            Center(child: _buildGenerateButton("Regenerate")),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildGenerateButton(String label) {
    return GestureDetector(
      onTap: _generateStylesheet,
      child: Container(
        width: 200, height: 44,
        decoration: BoxDecoration(
          color: Variables.textPrimary,
          borderRadius: BorderRadius.circular(112),
        ),
        alignment: Alignment.center,
        child: Text(label, style: Variables.buttonTextStyle),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontFamily: 'GeneralSans', fontSize: 12, fontWeight: FontWeight.bold,
          letterSpacing: 1.2, color: Variables.textSecondary,
        ),
      ),
    );
  }

  // --- ASSETS SECTION ---
  Widget _buildAssetsSection(List<String> imagePaths) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _buildSectionHeader("Subjects & Assets"),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.8,
            ),
            itemCount: imagePaths.length,
            itemBuilder: (context, index) => _buildAssetCard(imagePaths[index]),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildAssetCard(String savedPath) {
    return FutureBuilder<File?>(
      future: _resolveFile(savedPath),
      builder: (context, snapshot) {
        final File? file = snapshot.data;
        final bool exists = file != null;

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12), // Matching color card radius
            border: Border.all(color: Variables.borderSubtle),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: exists
                    ? Image.file(file, fit: BoxFit.cover)
                    : Container(
                        color: Colors.grey.shade100,
                        child: const Center(
                          child: Icon(Icons.broken_image, color: Colors.grey, size: 20),
                        ),
                      ),
              ),
              // Container(
              //   padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              //   color: Colors.white,
              //   child: const Text(
              //     "Asset",
              //     textAlign: TextAlign.center,
              //     style: TextStyle(
              //       fontFamily: 'GeneralSans',
              //       fontSize: 10,
              //       fontWeight: FontWeight.w600,
              //       color: Variables.textPrimary,
              //     ),
              //     maxLines: 1,
              //     overflow: TextOverflow.ellipsis,
              //   ),
              // )
            ],
          ),
        );
      },
    );
  }

  // --- TYPOGRAPHY SECTION (UPDATED TO SLIDER) ---
  Widget _buildTypographySection(dynamic data) {
    List<String> fontNames = [];

    if (data is List) {
      for (var item in data) {
        if (item is Map && item.containsKey('label')) {
          fontNames.add(item['label'].toString().trim());
        } else if (item is String) {
          fontNames.add(item.trim());
        }
      }
    } else if (data is Map && data.containsKey('label')) {
      fontNames.add(data['label'].toString().trim());
    } else if (data is String) {
      fontNames.add(data.trim());
    }

    if (fontNames.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _buildSectionHeader("Typography"),
        ),
        SizedBox(
          height: 150, // Height for the cards
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: fontNames.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) => _buildTypographyCard(fontNames[index]),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildTypographyCard(String rawFontName) {
    final String correctFontName = _resolveGoogleFontName(rawFontName);
    TextStyle sampleStyle;
    
    try {
      sampleStyle = GoogleFonts.getFont(correctFontName);
    } catch (_) {
      sampleStyle = const TextStyle(fontFamily: 'GeneralSans');
    }

    return Container(
      width: 160, // Fixed Width for Horizontal List
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Variables.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Big "Aa" Preview
          Expanded(
            child: Text(
              "Aa",
              style: sampleStyle.copyWith(
                fontSize: 56, 
                height: 1, 
                fontWeight: FontWeight.w400, 
                color: Colors.black
              ),
            ),
          ),
          // 2. Font Name
          Text(
            correctFontName,
            style: const TextStyle(
              fontFamily: 'GeneralSans',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          // 3. Label
          const Text(
            "Primary Typeface",
            style: TextStyle(
              fontFamily: 'GeneralSans',
              fontSize: 11,
              color: Variables.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorSection(dynamic data) {
    List<Map<String, dynamic>> palette = [];
    if (data is List) {
      for (var item in data) {
        if (item is Map) {
          palette.add({
            'label': item['label']?.toString() ?? '',
            'score': item['score'] ?? 0,
          });
        }
      }
    }

    if (palette.isEmpty) return const SizedBox();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.8,
      ),
      itemCount: palette.length,
      itemBuilder: (context, index) {
        return _buildColorCard(palette[index]['label']);
      },
    );
  }

  Widget _buildColorCard(String label) {
    Color color = _getColorFromLabel(label);
    String hexCode = "#${color.value.toRadixString(16).substring(2).toUpperCase()}";

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Variables.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Container(color: color),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    hexCode,
                    style: const TextStyle(
                      fontFamily: 'GeneralSans',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Variables.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label.toUpperCase(),
                    style: const TextStyle(
                      fontFamily: 'GeneralSans',
                      fontSize: 10,
                      color: Variables.textSecondary,
                      overflow: TextOverflow.ellipsis,
                    ),
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderSection(String title, dynamic data) {
    if (data is! List) return const SizedBox();

    List<Map> items = [];
    for (var i in data) {
      if (i is Map) items.add(i);
    }
    items.sort((a, b) => (b['score'] ?? 0).compareTo(a['score'] ?? 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _buildSectionHeader(title),
        ),
        SizedBox(
          height: 120, 
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = items[index];
              final label = item['label']?.toString() ?? '';
              
              return Container(
                width: 120,
                height: 120,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Variables.borderSubtle),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    label.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'GeneralSans',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Variables.textPrimary,
                      height: 1.2,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Color _getColorFromLabel(String label) {
    label = label.toLowerCase();
    if (label.contains('neon')) return const Color(0xFF39FF14);
    if (label.contains('earth')) return const Color(0xFF8D6E63);
    if (label.contains('pastel')) return const Color(0xFFFFB7B2);
    if (label.contains('neutral')) return const Color(0xFFE0E0E0);
    if (label.contains('vintage')) return const Color(0xFFD2B48C);
    if (label.contains('modern')) return const Color(0xFF212121);
    if (label.contains('warm')) return const Color(0xFFFF9800);
    if (label.contains('cool')) return const Color(0xFF00BCD4);
    if (label.contains('dark')) return const Color(0xFF1a1a1a);
    return Colors.grey.shade400;
  }
}
