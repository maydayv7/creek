import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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

  const StylesheetPage({super.key, required this.projectId});

  @override
  State<StylesheetPage> createState() => _StylesheetPageState();
}

class _StylesheetPageState extends State<StylesheetPage> {
  late int _currentProjectId;
  bool _isLoading = false;

  Map<String, dynamic>? _stylesheetMap;
  String? _rawJsonString;

  List<String> _projectAssets = [];
  final Map<String, String> _fontNameCache = {};

  @override
  void initState() {
    super.initState();
    _currentProjectId = widget.projectId;
    _loadSavedStylesheet();
  }

  // --- PARSING LOGIC ---
  String _cleanJsonString(String raw) {
    // 1. Remove Markdown code blocks if present (common AI artifact)
    String cleaned = raw.replaceAll(RegExp(r'^```json\s*|\s*```$'), '');

    // 2. Fix unquoted keys if necessary (only if standard parse fails)
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'([{,]\s*)([a-zA-Z0-9_\s/]+)(\s*:)'),
      (match) => '${match[1]}"${match[2]?.trim()}"${match[3]}',
    );
    return cleaned;
  }

  String _resolveGoogleFontName(String dirtyName) {
    if (_fontNameCache.containsKey(dirtyName)) {
      return _fontNameCache[dirtyName]!;
    }
    String cleanInput = dirtyName.toLowerCase().replaceAll(RegExp(r'[-_]regular$'), '').replaceAll(RegExp(r'[^a-z0-9]'), '');
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
    final file = File(path);
    if (await file.exists()) return file;
    try {
      final filename = p.basename(path);
      final dir = await getApplicationDocumentsDirectory();
      final fixedPath = p.join(dir.path, 'generated_images', filename);
      final fixedFile = File(fixedPath);
      if (await fixedFile.exists()) return fixedFile;
    } catch (e) {
      debugPrint("Error resolving file path: $e");
    }
    return null;
  }

  Future<void> _loadSavedStylesheet() async {
    final project = await ProjectRepo().getProjectById(_currentProjectId);
    if (project == null) return;

    List<String> currentAssets = project.assetsPath;
    Map<String, dynamic>? parsedMap;
    String? rawJson;

    if (project.globalStylesheet != null && project.globalStylesheet!.isNotEmpty) {
      rawJson = project.globalStylesheet!;
      dynamic parsed;

      // Try standard decode first
      try {
        parsed = jsonDecode(rawJson);
      } catch (e) {
        // Try cleaning markdown and loose keys
        try {
          parsed = jsonDecode(_cleanJsonString(rawJson));
        } catch (_) {}
      }

      if (parsed is String) {
        try {
          parsed = jsonDecode(parsed);
        } catch (_) {}
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
      final images = await ImageRepo().getImages(_currentProjectId);
      final List<String> analysisData = images.map((img) => img.analysisData).where((data) => data != null && data.isNotEmpty).cast<String>().toList();
      final notes = await NoteRepo().getNotesByProjectId(_currentProjectId);
      final List<String> noteAnalysisData = notes.map((n) => n.analysisData).where((data) => data != null && data.isNotEmpty).cast<String>().toList();

      analysisData.addAll(noteAnalysisData);

      if (analysisData.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No analyzed images or notes found.")));
        }
        return;
      }

      final result = await PythonService().generateStylesheet(analysisData);

      if (mounted && result != null) {
        final jsonString = jsonEncode(result);
        await ProjectRepo().updateStylesheet(_currentProjectId, jsonString);
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
      bottomNavigationBar: BottomBar(currentTab: BottomBarItem.stylesheet, projectId: _currentProjectId),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "Are you ready to start building\nthe visual identity",
            style: Variables.headerStyle.copyWith(fontSize: 18),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          _buildGenerateButton("Generate Stylesheet"),
        ],
      ),
    );
  }

  Widget _buildContent() {
    // Added 'Composition' to style lookup to match your screenshot
    final style = _getData(['Style', 'style', 'Composition', 'composition']);
    final lighting = _getData(['Lighting', 'lighting']);
    final colors = _getData(['Colour Palette', 'Color Palette', 'colors']);
    final emotions = _getData(['Emotions', 'emotions']);
    final era = _getData(['Era/Cultural Reference', 'era']);
    final typography = _getData(['Typography', 'fonts']);

    final hasAssets = _projectAssets.isNotEmpty;

    // --- DYNAMIC SECTION GENERATOR ---
    // If the map contains keys we haven't hardcoded above, generate sliders for them.
    // This prevents the "Parsing Error" when valid data exists but the key is new.
    List<Widget> dynamicSections = [];
    List<String> handledKeys = [
      'Style', 'style', 'Composition', 'composition',
      'Lighting', 'lighting',
      'Colour Palette', 'Color Palette', 'colors',
      'Emotions', 'emotions',
      'Era/Cultural Reference', 'era',
      'Typography', 'fonts'
    ];

    if (_stylesheetMap != null) {
      for (var key in _stylesheetMap!.keys) {
        // If we haven't handled this key yet and it looks like a list (slider data)
        if (!handledKeys.any((k) => k.toLowerCase() == key.toLowerCase()) && _stylesheetMap![key] is List) {
           dynamicSections.add(_buildSliderSection(key, _stylesheetMap![key]));
        }
      }
    }

    final foundAny = (style != null || lighting != null || colors != null || emotions != null || era != null || typography != null || hasAssets || dynamicSections.isNotEmpty);

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
                  const Text("Visual Identity", style: TextStyle(fontFamily: 'GeneralSans', fontSize: 24, fontWeight: FontWeight.w600)),
                  IconButton(icon: const Icon(Icons.refresh), onPressed: _generateStylesheet),
                ],
              ),
            ),
            const SizedBox(height: 32),

            if (foundAny) ...[
              if (hasAssets) _buildAssetsSection(_projectAssets),
              if (typography != null) _buildTypographySection(typography),
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
              if (style != null) _buildSliderSection("Style & Aesthetic", style),
              if (emotions != null) _buildSliderSection("Mood & Emotions", emotions),
              if (lighting != null) _buildSliderSection("Lighting", lighting),
              if (era != null) _buildSliderSection("Era & Culture", era),
              
              // Render any extra data found in the JSON
              ...dynamicSections,
              
            ] else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12)),
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
        decoration: BoxDecoration(color: Variables.textPrimary, borderRadius: BorderRadius.circular(112)),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: Variables.buttonTextStyle),
            const SizedBox(width: 8),
            SvgPicture.asset(
              'assets/icons/generate_icon.svg',
              width: 20, 
              height: 20,
              colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(fontFamily: 'GeneralSans', fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Variables.textSecondary),
      ),
    );
  }

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
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.8),
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
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Variables.borderSubtle),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          clipBehavior: Clip.antiAlias,
          child: file != null ? Image.file(file, fit: BoxFit.cover) : Container(color: Colors.grey.shade100, child: const Center(child: Icon(Icons.broken_image, color: Colors.grey, size: 20))),
        );
      },
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
      width: 160, padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Variables.borderSubtle),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text("Aa", style: sampleStyle.copyWith(fontSize: 56, height: 1, fontWeight: FontWeight.w400, color: Colors.black))),
          Text(correctFontName, style: const TextStyle(fontFamily: 'GeneralSans', fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          const Text("Primary Typeface", style: TextStyle(fontFamily: 'GeneralSans', fontSize: 11, color: Variables.textSecondary, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildTypographySection(dynamic data) {
    List<String> fontNames = [];
    if (data is List) {
      for (var item in data) {
        if (item is Map && item.containsKey('label')) {
          fontNames.add(item['label'].toString().trim());
        } else if (item is String) fontNames.add(item.trim());
      }
    } else if (data is Map && data.containsKey('label')) {
      fontNames.add(data['label'].toString().trim());
    } else if (data is String) fontNames.add(data.trim());

    if (fontNames.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: _buildSectionHeader("Typography")),
        SizedBox(
          height: 150,
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

  Widget _buildColorSection(dynamic data) {
    List<Map<String, dynamic>> palette = [];
    if (data is List) {
      for (var item in data) {
        if (item is Map) palette.add({'label': item['label']?.toString() ?? '', 'score': item['score'] ?? 0});
      }
    }
    if (palette.isEmpty) return const SizedBox();

    return GridView.builder(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.8),
      itemCount: palette.length,
      itemBuilder: (context, index) => _buildColorCard(palette[index]['label']),
    );
  }

  Widget _buildColorCard(String label) {
    Color color = _getColorFromLabel(label);
    String hexCode = label.toUpperCase(); 

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Variables.borderSubtle)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: Container(color: color)),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(hexCode, style: const TextStyle(fontFamily: 'GeneralSans', fontSize: 12, fontWeight: FontWeight.bold, color: Variables.textPrimary)),
                  const SizedBox(height: 2),
                  const Text("HEX", style: TextStyle(fontFamily: 'GeneralSans', fontSize: 10, color: Variables.textSecondary, overflow: TextOverflow.ellipsis), maxLines: 1),
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
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: _buildSectionHeader(title)),
        SizedBox(
          height: 120,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = items[index];
              return Container(
                width: 120, height: 120, padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Variables.borderSubtle),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: Center(
                  child: Text(item['label']?.toString().toUpperCase() ?? '', textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'GeneralSans', fontSize: 13, fontWeight: FontWeight.w600, color: Variables.textPrimary, height: 1.2), maxLines: 3, overflow: TextOverflow.ellipsis),
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
    if (label.startsWith('#') || label.length == 6) {
      try {
        String hex = label.replaceAll('#', '');
        if (hex.length == 6) {
          return Color(int.parse('0xFF$hex'));
        }
      } catch (_) {}
    }
    return Colors.grey.shade400; // Fallback
  }
}
