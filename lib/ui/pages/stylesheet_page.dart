import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
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
  final bool autoGenerate;

  const StylesheetPage({super.key, required this.projectId, this.autoGenerate = false});

  @override
  State<StylesheetPage> createState() => _StylesheetPageState();
}

class _StylesheetPageState extends State<StylesheetPage> {
  late int _currentProjectId;
  bool _isLoading = false;

  Map<String, dynamic>? _stylesheetMap;
  String? _rawJsonString;

  List<String> _projectAssets = [];
  List<String> _logoPaths = [];
  final Map<String, String> _fontNameCache = {};
  final ImagePicker _picker = ImagePicker();

  // --- ASSET MAPPING ---
  final Map<String, String> _lightingAssets = {
    'backlit': 'assets/stylesheet/lighting/backlit.png',
    'diffused': 'assets/stylesheet/lighting/diffused.png',
    'dramaticcontrast': 'assets/stylesheet/lighting/dramatic-contrast.png',
    'flatlighting': 'assets/stylesheet/lighting/flat-lighting.png',
    'softlight': 'assets/stylesheet/lighting/soft-light.png',
    'spectacularhighlights': 'assets/stylesheet/lighting/spectacular-highlights.png',
    'specularhighlights': 'assets/stylesheet/lighting/spectacular-highlights.png',
    'studiolighting': 'assets/stylesheet/lighting/studio-lighting.png',
  };

  final Map<String, String> _materialAssets = {
    'glossy': 'assets/stylesheet/material-look/glossy.png',
    'laminated': 'assets/stylesheet/material-look/laminated.png',
    'matte': 'assets/stylesheet/material-look/matte.png',
    'metallic': 'assets/stylesheet/material-look/metallic.png',
    'mettalic': 'assets/stylesheet/material-look/metallic.png',
    'organic': 'assets/stylesheet/material-look/organic.png',
    'porcelain': 'assets/stylesheet/material-look/porcelain.png',
    'wetlook': 'assets/stylesheet/material-look/wet-look.png',
    'wooden': 'assets/stylesheet/material-look/wooden.png',
    'wood': 'assets/stylesheet/material-look/wooden.png',
    'plastic': 'assets/stylesheet/material-look/laminated.png',
  };

  final Map<String, String> _textureAssets = {
    'bokehbackground': 'assets/stylesheet/texture/bokeh-background.png',
    'concrete': 'assets/stylesheet/texture/concrete.png',
    'stone': 'assets/stylesheet/texture/concrete.png',
    'motifs': 'assets/stylesheet/texture/motifs.png',
    'motif': 'assets/stylesheet/texture/motifs.png',
    'newspapertexture': 'assets/stylesheet/texture/newspaper-texture.png',
    'newspaper': 'assets/stylesheet/texture/newspaper-texture.png',
    'papergrain': 'assets/stylesheet/texture/paper-grain.png',
    'printedpattern': 'assets/stylesheet/texture/printed-pattern.png',
    'studiobackdrop': 'assets/stylesheet/texture/studio-backdrop.png',
    'studio_backdrop': 'assets/stylesheet/texture/studio-backdrop.png',
    'subtlegrid': 'assets/stylesheet/texture/subtle-grid.png',
    'grid': 'assets/stylesheet/texture/subtle-grid.png',
  };

  @override
  void initState() {
    super.initState();
    _currentProjectId = widget.projectId;
    if (widget.autoGenerate) {
      // Generate stylesheet automatically after a short delay to ensure page is built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _generateStylesheet();
      });
    } else {
      _loadSavedStylesheet();
    }
  }

  // --- UTILS ---
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

  String _formatLabel(String label) {
    String clean = label.replaceAll(RegExp(r'[-_]'), ' ');
    List<String> words = clean.split(' ');
    return words.map((w) {
      if (w.isEmpty) return '';
      return w[0].toUpperCase() + w.substring(1).toLowerCase();
    }).join(' ');
  }

  String? _findAssetPath(Map<String, String> assetMap, String label) {
    String normalized = label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return assetMap[normalized];
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
          _logoPaths = [];
          _loadSavedStylesheet();
        }),
        onSettingsPressed: () {},
      ),
      // Only show content once full stylesheet is parsed atleast once
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Variables.textPrimary))
          : (_stylesheetMap == null && _rawJsonString == null)
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
            "Are you ready to start building\nyour visual identity",
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
    final graphics = _getData(['Graphics', 'graphics']);
    final colors = _getData(['Colour Palette', 'Color Palette', 'colors', 'Colors']);
    final typography = _getData(['Typography', 'fonts', 'Fonts']);
    final compositions = _getData(['Compositions', 'Composition', 'compositions']);
    final materialLook = _getData(['Material look', 'Material Look', 'material_look']);
    final textures = _getData(['Textures', 'Background/Texture', 'textures']);
    final lighting = _getData(['Lighting', 'lighting']);
    final style = _getData(['Style', 'style']);
    final era = _getData(['Era/Cultural Reference', 'Era', 'era']);
    final emotions = _getData(['Emotions', 'Emotional', 'emotions']);

    return RefreshIndicator(
      onRefresh: _generateStylesheet,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: _buildGenerateButton("Regenerate Stylesheet")),
            const SizedBox(height: 24),
            
            _buildLogosSection(null),
            if (graphics != null || _projectAssets.isNotEmpty) _buildGraphicsSection(graphics),
            if (colors != null) _buildColorsSection(colors),
            if (typography != null) _buildFontsSection(typography),
            if (compositions != null) _buildCompositionsSection(compositions),
            if (materialLook != null) _buildMaterialLookSection(materialLook),
            if (textures != null) _buildTexturesSection(textures),
            if (lighting != null) _buildLightingSection(lighting),
            if (style != null) _buildStyleSection(style),
            if (era != null) _buildEraSection(era),
            if (emotions != null) _buildEmotionsSection(emotions),
            
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildGenerateButton(String label) {
    return GestureDetector(
      onTap: _generateStylesheet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: Variables.textPrimary, 
          borderRadius: BorderRadius.circular(112)
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: Variables.buttonTextStyle),
            const SizedBox(width: 8),
            SvgPicture.asset(
              'assets/icons/generate_icon.svg',
              width: 18, 
              height: 18,
              colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, {bool showArrow = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontFamily: 'GeneralSans',
                fontSize: 16,
                fontWeight: FontWeight.w500,
                height: 24 / 16,
                color: Variables.textPrimary,
              ),
            ),
          ),
          if (showArrow)
            Transform.rotate(
              angle: 3.14159,
              child: SvgPicture.asset(
                'assets/icons/arrow-left-s-line.svg',
                width: 24,
                height: 24,
                colorFilter: const ColorFilter.mode(Variables.textPrimary, BlendMode.srcIn),
              ),
            ),
        ],
      ),
    );
  }

  // --- Logos ---
  Future<void> _pickLogo() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() {
          _logoPaths.add(pickedFile.path);
        });
      }
    } catch (e) {
      debugPrint("Error picking logo: $e");
    }
  }

  Widget _buildLogosSection(dynamic data) {
    // Use manually uploaded logos
    List<String> logoPaths = List.from(_logoPaths);

    // Also add any logos from data if present
    if (data is List) {
      for (var item in data) {
        if (item is Map && item.containsKey('path')) logoPaths.add(item['path'].toString());
        else if (item is String) logoPaths.add(item);
      }
    } else if (data is String) logoPaths.add(data);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader("Logos"),
        SizedBox(
          height: 76,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: logoPaths.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              if (index == logoPaths.length) {
                // Add button
                return GestureDetector(
                  onTap: _pickLogo,
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      border: Border.all(color: Variables.borderSubtle),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: SvgPicture.asset(
                        'assets/icons/add-line.svg',
                        width: 20, height: 20,
                        colorFilter: const ColorFilter.mode(Variables.textSecondary, BlendMode.srcIn),
                      ),
                    ),
                  ),
                );
              }
              return _buildGraphicCard(logoPaths[index], size: 76);
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // --- Graphics ---
  Widget _buildGraphicsSection(dynamic data) {
    List<String> graphicPaths = List.from(_projectAssets);
    if (data is List) {
      for (var item in data) {
        if (item is Map && item.containsKey('path')) graphicPaths.add(item['path'].toString());
        else if (item is String) graphicPaths.add(item);
      }
    } else if (data is String) graphicPaths.add(data);

    if (graphicPaths.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader("Graphics"),
        SizedBox(
          height: 106,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: graphicPaths.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) => _buildGraphicCard(graphicPaths[index]),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildGraphicCard(String savedPath, {double size = 104}) {
    return FutureBuilder<File?>(
      future: _resolveFile(savedPath),
      builder: (context, snapshot) {
        final File? file = snapshot.data;
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Variables.surfaceSubtle,
          ),
          clipBehavior: Clip.antiAlias,
          child: file != null
              ? Image.file(file, fit: BoxFit.cover)
              : Container(
                  color: Variables.surfaceSubtle,
                  child: const Center(
                    child: Icon(Icons.broken_image, color: Colors.grey, size: 20),
                  ),
                ),
        );
      },
    );
  }

  // --- Fonts ---
  Widget _buildFontsSection(dynamic data) {
    List<String> fontNames = [];
    if (data is List) {
      for (var item in data) {
        if (item is Map && item.containsKey('label')) fontNames.add(item['label'].toString().trim());
        else if (item is String) fontNames.add(item.trim());
      }
    } else if (data is Map && data.containsKey('label')) {
      fontNames.add(data['label'].toString().trim());
    }

    if (fontNames.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader("Fonts"),
        SizedBox(
          height: 120,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: fontNames.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) => _buildFontCard(fontNames[index]),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildFontCard(String rawFontName) {
    final String correctFontName = _resolveGoogleFontName(rawFontName);
    final String displayFontName = _formatLabel(rawFontName);
    
    TextStyle sampleStyle;
    try {
      sampleStyle = GoogleFonts.getFont(correctFontName);
    } catch (_) {
      sampleStyle = const TextStyle(fontFamily: 'GeneralSans');
    }

    return Container(
      width: (MediaQuery.of(context).size.width - 32 - 16) / 3,
      height: 120,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        border: Border.all(color: Variables.borderSubtle),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "Aa",
            style: sampleStyle.copyWith(
              fontSize: 28, 
              height: 1.2, 
              fontWeight: FontWeight.w400, 
              color: Variables.textPrimary,
            ),
          ),
          Text(
            displayFontName, 
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'GeneralSans', fontSize: 12, height: 16 / 12,
              color: Variables.textSecondary, fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  // --- Colors ---
  Widget _buildColorsSection(dynamic data) {
    List<String> colorList = [];
    if (data is List) {
      for (var item in data) {
        if (item is Map && item.containsKey('label')) colorList.add(item['label'].toString());
        else if (item is String) colorList.add(item);
      }
    }

    if (colorList.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader("Colors", showArrow: false),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: colorList.take(5).map((color) => _buildColorSwatch(color)).toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildColorSwatch(String label) {
    Color color = _getColorFromLabel(label);
    return Container(
      width: 104, height: 52,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
    );
  }

  Color _getColorFromLabel(String label) {
    if (label.startsWith('#') || label.length == 6) {
      try {
        String hex = label.replaceAll('#', '');
        if (hex.length == 6) return Color(int.parse('0xFF$hex'));
      } catch (_) {}
    }
    return Colors.grey.shade400;
  }

  // --- Unified Card Builder ---
  Widget _buildUnifiedCard(String label, String? assetPath) {
    final formattedLabel = _formatLabel(label);

    if (assetPath != null) {
      return Container(
        width: 106,
        height: 106,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.white,
          border: Border.all(color: Variables.borderSubtle.withOpacity(0.5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                assetPath,
                fit: BoxFit.cover,
                errorBuilder: (c, o, s) => Container(color: Variables.surfaceSubtle),
              ),
            ),
            Positioned(
              left: 0, right: 0, bottom: 0,
              height: 40,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 4, right: 4, bottom: 4,
              child: Text(
                formattedLabel,
                style: const TextStyle(
                  fontFamily: 'GeneralSans',
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    } else {
      return Container(
        width: 120,
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Variables.surfaceSubtle,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          formattedLabel,
          style: const TextStyle(
            fontFamily: 'GeneralSans',
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Variables.textPrimary,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
  }

  Widget _buildAttributeSection(String title, dynamic data, Map<String, String>? assetMap) {
    List<String> items = [];
    if (data is List) {
      for (var item in data) {
        if (item is Map && item.containsKey('label')) items.add(item['label'].toString());
        else if (item is String) items.add(item);
      }
    } else if (data is String) items.add(data);

    if (items.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(title),
        SizedBox(
          height: (assetMap != null) ? 106 : 54,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              String label = items[index];
              String? assetPath = assetMap != null ? _findAssetPath(assetMap, label) : null;
              return _buildUnifiedCard(label, assetPath);
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildCompositionsSection(dynamic data) {
    return _buildAttributeSection("Compositions", data, null);
  }

  Widget _buildMaterialLookSection(dynamic data) {
    return _buildAttributeSection("Material Look", data, _materialAssets);
  }

  Widget _buildTexturesSection(dynamic data) {
    return _buildAttributeSection("Textures", data, _textureAssets);
  }

  Widget _buildLightingSection(dynamic data) {
    return _buildAttributeSection("Lighting", data, _lightingAssets);
  }

  Widget _buildStyleSection(dynamic data) {
    return _buildAttributeSection("Style", data, null);
  }

  Widget _buildEraSection(dynamic data) {
    return _buildAttributeSection("Era", data, null);
  }

  Widget _buildEmotionsSection(dynamic data) {
    return _buildAttributeSection("Emotions", data, null);
  }
}
