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
          _logoPaths = [];
          _loadSavedStylesheet();
        }),
        onSettingsPressed: () {
          // Handle settings action
        },
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Variables.textPrimary))
          : (_stylesheetMap == null && _rawJsonString == null && _projectAssets.isEmpty && _logoPaths.isEmpty)
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
            "Are you ready to start building\nyour stylesheet",
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
    // Extract data in order matching Figma design
    final graphics = _getData(['Graphics', 'graphics']);
    final colors = _getData(['Colour Palette', 'Color Palette', 'colors', 'Colors']);
    final typography = _getData(['Typography', 'fonts', 'Fonts']);
    final compositions = _getData(['Compositions', 'compositions']);
    final materialLook = _getData(['Material look', 'Material Look', 'material_look']);
    final textures = _getData(['Textures', 'textures']);
    final lighting = _getData(['Lighting', 'lighting']);
    final style = _getData(['Style', 'style']);
    final era = _getData(['Era/Cultural Reference', 'era', 'Era']);
    final emotions = _getData(['Emotions', 'emotions']);

    return RefreshIndicator(
      onRefresh: _generateStylesheet,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(left: 16, right: 16, top: 24, bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Regenerate Button
            Center(
              child: _buildGenerateButton("Regenerate Stylesheet"),
            ),
            const SizedBox(height: 24),
            // Logos Section - always show for manual upload
            _buildLogosSection(null),
            
            // Graphics Section - includes project assets
            if (graphics != null || _projectAssets.isNotEmpty) _buildGraphicsSection(graphics),
            
            // Colors Section
            if (colors != null) _buildColorsSection(colors),
            
            // Fonts Section
            if (typography != null) _buildFontsSection(typography),
            
            // Compositions Section
            if (compositions != null) _buildCompositionsSection(compositions),
            
            // Material look Section
            if (materialLook != null) _buildMaterialLookSection(materialLook),
            
            // Textures Section
            if (textures != null) _buildTexturesSection(textures),
            
            // Lighting Section
            if (lighting != null) _buildLightingSection(lighting),
            
            // Style Section
            if (style != null) _buildStyleSection(style),
            
            // Era Section
            if (era != null) _buildEraSection(era),
            
            // Emotions Section
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
              angle: 3.14159, // 180 degrees
              child: SvgPicture.asset(
                'assets/icons/arrow-left-s-line.svg',
                width: 24,
                height: 24,
                colorFilter: const ColorFilter.mode(
                  Variables.textPrimary,
                  BlendMode.srcIn,
                ),
              ),
            ),
        ],
      ),
    );
  }

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking logo: $e')),
        );
      }
    }
  }

  Widget _buildLogosSection(dynamic data) {
    // Use manually uploaded logos
    List<String> logoPaths = List.from(_logoPaths);
    
    // Also add any logos from data if present
    if (data is List) {
      for (var item in data) {
        if (item is Map && item.containsKey('path')) {
          logoPaths.add(item['path'].toString());
        } else if (item is String) {
          logoPaths.add(item);
        }
      }
    } else if (data is String) {
      logoPaths.add(data);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader("Logos"),
        const SizedBox(height: 12),
        SizedBox(
          height: 76,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: logoPaths.length + 1, // +1 for add button
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
                        width: 20,
                        height: 20,
                        colorFilter: const ColorFilter.mode(
                          Variables.textSecondary,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                );
              }
              return _buildLogoCard(logoPaths[index]);
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildLogoCard(String savedPath) {
    return FutureBuilder<File?>(
      future: _resolveFile(savedPath),
      builder: (context, snapshot) {
        final File? file = snapshot.data;
        return Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
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

  Widget _buildGraphicsSection(dynamic data) {
    List<String> graphicPaths = [];
    
    // Add project assets (subjects and assets) to graphics
    graphicPaths.addAll(_projectAssets);
    
    // Add graphics from data if present
    if (data is List) {
      for (var item in data) {
        if (item is Map && item.containsKey('path')) {
          graphicPaths.add(item['path'].toString());
        } else if (item is String) {
          graphicPaths.add(item);
        }
      }
    } else if (data is String) {
      graphicPaths.add(data);
    }

    if (graphicPaths.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader("Graphics"),
        const SizedBox(height: 12),
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

  Widget _buildGraphicCard(String savedPath) {
    return FutureBuilder<File?>(
      future: _resolveFile(savedPath),
      builder: (context, snapshot) {
        final File? file = snapshot.data;
        return Container(
          width: 104,
          height: 106,
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


  Widget _buildFontCard(String rawFontName) {
    final String correctFontName = _resolveGoogleFontName(rawFontName);
    TextStyle sampleStyle;
    try {
      sampleStyle = GoogleFonts.getFont(correctFontName);
    } catch (_) {
      sampleStyle = const TextStyle(fontFamily: 'GeneralSans');
    }

    // Get font info (styles count) - simplified for now
    String fontInfo = "16 styles + variable cut";

    return Builder(
      builder: (context) => Container(
        width: (MediaQuery.of(context).size.width - 32 - 16) / 3, // 3 cards with spacing
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
              fontInfo,
              style: const TextStyle(
                fontFamily: 'GeneralSans',
                fontSize: 12,
                height: 16 / 12,
                color: Variables.textSecondary,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFontsSection(dynamic data) {
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
        _buildSectionHeader("Fonts"),
        const SizedBox(height: 12),
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

  Widget _buildColorsSection(dynamic data) {
    List<String> colorList = [];
    if (data is List) {
      for (var item in data) {
        if (item is Map && item.containsKey('label')) {
          colorList.add(item['label'].toString());
        } else if (item is String) {
          colorList.add(item);
        }
      }
    } else if (data is String) {
      colorList.add(data);
    }

    if (colorList.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader("Colors", showArrow: false),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: colorList.take(5).map((color) => _buildColorSwatch(color)).toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildColorSwatch(String label) {
    Color color = _getColorFromLabel(label);
    return Container(
      width: 104,
      height: 52,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  Widget _buildCompositionsSection(dynamic data) {
    List<String> compositionPaths = [];
    if (data is List) {
      for (var item in data) {
        if (item is Map && item.containsKey('path')) {
          compositionPaths.add(item['path'].toString());
        } else if (item is String) {
          compositionPaths.add(item);
        }
      }
    } else if (data is String) {
      compositionPaths.add(data);
    }

    if (compositionPaths.isEmpty) return const SizedBox();

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        _buildSectionHeader("Compositions"),
        const SizedBox(height: 12),
        SizedBox(
          height: 106,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: compositionPaths.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) => _buildCompositionCard(compositionPaths[index]),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildCompositionCard(String savedPath) {
    return FutureBuilder<File?>(
      future: _resolveFile(savedPath),
      builder: (context, snapshot) {
        final File? file = snapshot.data;
        return Container(
          width: 104,
          height: 106,
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

  Widget _buildMaterialLookSection(dynamic data) {
    List<String> materialPaths = [];
    if (data is List) {
      for (var item in data) {
        if (item is Map && item.containsKey('path')) {
          materialPaths.add(item['path'].toString());
        } else if (item is String) {
          materialPaths.add(item);
        }
      }
    } else if (data is String) {
      materialPaths.add(data);
    }

    if (materialPaths.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader("Material look"),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: materialPaths.take(2).map((path) => _buildMaterialCard(path)).toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildMaterialCard(String savedPath) {
    return FutureBuilder<File?>(
      future: _resolveFile(savedPath),
      builder: (context, snapshot) {
        final File? file = snapshot.data;
        return Container(
          width: 106,
          height: 106,
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

  Widget _buildTexturesSection(dynamic data) {
    List<String> texturePaths = [];
    if (data is List) {
      for (var item in data) {
        if (item is Map && item.containsKey('path')) {
          texturePaths.add(item['path'].toString());
        } else if (item is String) {
          texturePaths.add(item);
        }
      }
    } else if (data is String) {
      texturePaths.add(data);
    }

    if (texturePaths.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader("Textures"),
        const SizedBox(height: 12),
        SizedBox(
          height: 106,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: texturePaths.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) => _buildTextureCard(texturePaths[index]),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildTextureCard(String savedPath) {
    return FutureBuilder<File?>(
      future: _resolveFile(savedPath),
      builder: (context, snapshot) {
        final File? file = snapshot.data;
              return Container(
          width: 104,
          height: 106,
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

  Widget _buildLightingSection(dynamic data) {
    List<String> lightingPaths = [];
    if (data is List) {
      for (var item in data) {
        if (item is Map && item.containsKey('path')) {
          lightingPaths.add(item['path'].toString());
        } else if (item is String) {
          lightingPaths.add(item);
        }
      }
    } else if (data is String) {
      lightingPaths.add(data);
    }

    if (lightingPaths.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader("Lighting"),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: lightingPaths.take(3).map((path) => _buildLightingCard(path)).toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildLightingCard(String savedPath) {
    return FutureBuilder<File?>(
      future: _resolveFile(savedPath),
      builder: (context, snapshot) {
        final File? file = snapshot.data;
        return Container(
          width: 106,
          height: 106,
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

  Widget _buildStyleSection(dynamic data) {
    List<String> styleTags = [];
    if (data is List) {
      for (var item in data) {
        if (item is Map && item.containsKey('label')) {
          styleTags.add(item['label'].toString());
        } else if (item is String) {
          styleTags.add(item);
        }
      }
    } else if (data is String) {
      styleTags.add(data);
    }

    if (styleTags.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader("Style"),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: styleTags.take(4).map((tag) => _buildTagCard(tag)).toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildEraSection(dynamic data) {
    List<String> eraTags = [];
    if (data is List) {
      for (var item in data) {
        if (item is Map && item.containsKey('label')) {
          eraTags.add(item['label'].toString());
        } else if (item is String) {
          eraTags.add(item);
        }
      }
    } else if (data is String) {
      eraTags.add(data);
    }

    if (eraTags.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader("Era"),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: eraTags.take(4).map((tag) => _buildTagCard(tag)).toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildEmotionsSection(dynamic data) {
    List<String> emotionTags = [];
    if (data is List) {
      for (var item in data) {
        if (item is Map && item.containsKey('label')) {
          emotionTags.add(item['label'].toString());
        } else if (item is String) {
          emotionTags.add(item);
        }
      }
    } else if (data is String) {
      emotionTags.add(data);
    }

    if (emotionTags.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader("Emotions"),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: emotionTags.take(4).map((tag) => _buildTagCard(tag)).toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildTagCard(String label) {
    return Container(
      width: 160,
      height: 54,
      decoration: BoxDecoration(
        color: Variables.surfaceSubtle,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'GeneralSans',
          fontSize: 16,
          fontWeight: FontWeight.w500,
          height: 24 / 16,
          color: Variables.textPrimary,
        ),
      ),
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
