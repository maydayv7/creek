import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:creekui/data/repos/project_repo.dart';
import 'package:creekui/data/repos/image_repo.dart';
import 'package:creekui/data/repos/note_repo.dart';
import 'package:creekui/services/stylesheet_service.dart';
import 'package:creekui/services/python_service.dart';
import 'package:creekui/ui/widgets/bottom_bar.dart';
import 'package:creekui/ui/widgets/top_bar.dart';
import 'package:creekui/ui/styles/variables.dart';

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
  // State to toggle hex code visibility
  bool _showHexCodes = false;

  StylesheetData? _stylesheetData;
  String? _rawJsonString;

  List<String> _projectAssets = [];
  List<String> _logoPaths = [];
  final ImagePicker _picker = ImagePicker();
  final StylesheetService _stylesheetService = StylesheetService();

  // --- ASSET MAPPING ---
  final Map<String, String> _lightingAssets = {
    'backlit': 'assets/stylesheet/lighting/backlit.png',
    'diffused': 'assets/stylesheet/lighting/diffused.png',
    'dramaticcontrast': 'assets/stylesheet/lighting/dramatic-contrast.png',
    'flatlighting': 'assets/stylesheet/lighting/flat-lighting.png',
    'softlight': 'assets/stylesheet/lighting/soft-light.png',
    'specularhighlights': 'assets/stylesheet/lighting/specular-highlights.png',
    'studiolighting': 'assets/stylesheet/lighting/studio-lighting.png',
  };

  final Map<String, String> _materialAssets = {
    'glossy': 'assets/stylesheet/material-look/glossy.png',
    'laminated': 'assets/stylesheet/material-look/laminated.png',
    'matte': 'assets/stylesheet/material-look/matte.png',
    'mettalic': 'assets/stylesheet/material-look/metallic.png',
    'organic': 'assets/stylesheet/material-look/organic.png',
    'porcelain': 'assets/stylesheet/material-look/porcelain.png',
    'wetlook': 'assets/stylesheet/material-look/wet-look.png',
    'wood': 'assets/stylesheet/material-look/wooden.png',
  };

  final Map<String, String> _textureAssets = {
    'bokehbackground': 'assets/stylesheet/texture/bokeh-background.png',
    'brick': 'assets/stylesheet/texture/brick.png',
    'concrete': 'assets/stylesheet/texture/concrete.png',
    'denim': 'assets/stylesheet/texture/denim.png',
    'fabric': 'assets/stylesheet/texture/fabric.png',
    'grid': 'assets/stylesheet/texture/subtle-grid.png',
    'ground': 'assets/stylesheet/texture/ground.png',
    'motif': 'assets/stylesheet/texture/motifs.png',
    'newspaper': 'assets/stylesheet/texture/newspaper-texture.png',
    'paper': 'assets/stylesheet/texture/paper-grain.png',
    'pattern': 'assets/stylesheet/texture/printed-pattern.png',
    'stone': 'assets/stylesheet/texture/stone.png',
    'studiobackdrop': 'assets/stylesheet/texture/studio-backdrop.png',
  };

  @override
  void initState() {
    super.initState();
    _currentProjectId = widget.projectId;
    if (widget.autoGenerate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _generateStylesheet();
      });
    } else {
      _loadSavedStylesheet();
    }
  }

  // --- UTILS ---

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
    String? rawJson = project.globalStylesheet;
    StylesheetData? data;

    if (rawJson != null && rawJson.isNotEmpty) {
      data = _stylesheetService.parse(rawJson);
    }

    if (mounted) {
      setState(() {
        _projectAssets = currentAssets;
        _rawJsonString = rawJson;
        _stylesheetData = data;
      });
    }
  }

  Future<void> _generateStylesheet() async {
    setState(() {
      _isLoading = true;
      _stylesheetData = null;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Variables.background,
      appBar: TopBar(
        currentProjectId: _currentProjectId,
        onBack: () => Navigator.of(context).pop(),
        onProjectChanged: (p) => setState(() {
          _currentProjectId = p.id!;
          _stylesheetData = null;
          _projectAssets = [];
          _logoPaths = [];
          _loadSavedStylesheet();
        }),
        onSettingsPressed: () {},
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Variables.textPrimary))
          : (_stylesheetData == null && _rawJsonString == null)
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
    final data = _stylesheetData;
    if (data == null) return const SizedBox();

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
            if (data.graphics.isNotEmpty || _projectAssets.isNotEmpty) _buildGraphicsSection(data.graphics),
            if (data.colors.isNotEmpty) _buildColorsSection(data.colors),
            if (data.fonts.isNotEmpty) _buildFontsSection(data.fonts),
            if (data.compositions.isNotEmpty) _buildCompositionsSection(data.compositions),
            if (data.materialLook.isNotEmpty) _buildMaterialLookSection(data.materialLook),
            if (data.textures.isNotEmpty) _buildTexturesSection(data.textures),
            if (data.lighting.isNotEmpty) _buildLightingSection(data.lighting),
            if (data.style.isNotEmpty) _buildStyleSection(data.style),
            if (data.era.isNotEmpty) _buildEraSection(data.era),
            if (data.emotions.isNotEmpty) _buildEmotionsSection(data.emotions),
            
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

  // Modified to support a custom trailing widget (e.g. Eye Icon)
  Widget _buildSectionHeader(String title, {bool showArrow = true, Widget? trailing}) {
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
          if (trailing != null)
            trailing
          else if (showArrow)
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
    List<String> logoPaths = List.from(_logoPaths);

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
  Widget _buildGraphicsSection(List<String> extractedGraphics) {
    List<String> graphicPaths = List.from(_projectAssets);
    graphicPaths.addAll(extractedGraphics);

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
  Widget _buildFontsSection(List<String> fontNames) {
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

  Widget _buildFontCard(String resolvedFontName) {
    final String displayFontName = _formatLabel(resolvedFontName);

    TextStyle sampleStyle;
    try {
      sampleStyle = GoogleFonts.getFont(resolvedFontName);
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
  Widget _buildColorsSection(List<Color> colors) {
    if (colors.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Using custom trailing widget for the Eye Icon toggle
        _buildSectionHeader(
          "Colors", 
          showArrow: false,
          trailing: GestureDetector(
            onTap: () => setState(() => _showHexCodes = !_showHexCodes),
            child: Icon(
              _showHexCodes ? Icons.visibility : Icons.visibility_outlined,
              color: Variables.textPrimary,
              size: 20,
            ),
          ),
        ),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: colors.take(5).map((color) => _buildColorSwatch(color)).toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildColorSwatch(Color color) {
    final String hexCode = '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
    final Color textColor = color.computeLuminance() > 0.5 ? Colors.black : Colors.white;

    return Container(
      width: 104, height: 52,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
      alignment: Alignment.center,
      // Only show text if _showHexCodes is true
      child: _showHexCodes 
        ? Text(
            hexCode,
            style: TextStyle(
              fontFamily: 'GeneralSans',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: textColor,
            ),
          )
        : null,
    );
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

  Widget _buildAttributeSection(String title, List<String> items, Map<String, String>? assetMap) {
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

  Widget _buildCompositionsSection(List<String> data) {
    return _buildAttributeSection("Compositions", data, null);
  }

  Widget _buildMaterialLookSection(List<String> data) {
    return _buildAttributeSection("Material Look", data, _materialAssets);
  }

  Widget _buildTexturesSection(List<String> data) {
    return _buildAttributeSection("Textures", data, _textureAssets);
  }

  Widget _buildLightingSection(List<String> data) {
    return _buildAttributeSection("Lighting", data, _lightingAssets);
  }

  Widget _buildStyleSection(List<String> data) {
    return _buildAttributeSection("Style", data, null);
  }

  Widget _buildEraSection(List<String> data) {
    return _buildAttributeSection("Era", data, null);
  }

  Widget _buildEmotionsSection(List<String> data) {
    return _buildAttributeSection("Emotions", data, null);
  }
}
