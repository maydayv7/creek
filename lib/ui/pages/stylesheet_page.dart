import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:adobe/ui/styles/variables.dart';
import 'package:adobe/ui/widgets/bottom_bar.dart';
import 'package:adobe/ui/widgets/top_bar.dart';
import 'package:adobe/data/repos/image_repo.dart';
import 'package:adobe/data/repos/project_repo.dart';
import 'package:adobe/services/python_service.dart';

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
      RegExp(r'(:\s*)([a-zA-Z_][a-zA-Z0-9_\-\.]*)(\s*[,}])'),
      (match) {
        String val = match[2]!;
        if (val == 'true' || val == 'false' || val == 'null' || double.tryParse(val) != null) {
          return match[0]!;
        }
        return '${match[1]}"$val"${match[3]}';
      }
    );
    return cleaned;
  }

  Future<void> _loadSavedStylesheet() async {
    final project = await ProjectRepo().getProjectById(_currentProjectId);
    if (project?.globalStylesheet != null && project!.globalStylesheet!.isNotEmpty) {
      String raw = project.globalStylesheet!;
      
      dynamic parsed;
      try {
        parsed = jsonDecode(raw);
      } catch (e) {
        try {
          parsed = jsonDecode(_cleanJsonString(raw));
        } catch (_) {}
      }

      if (parsed is String) {
        try { parsed = jsonDecode(parsed); } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _rawJsonString = raw;
          if (parsed is Map<String, dynamic>) {
            if (parsed.containsKey('results') && parsed['results'] is Map) {
              _stylesheetMap = parsed['results'];
            } else {
              _stylesheetMap = parsed;
            }
          } else {
            _stylesheetMap = null;
          }
        });
        
        // --- LOG TYPOGRAPHY ---
        _logTypography();
      }
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
      final analysisData = images
          .map((img) => img.analysisData)
          .where((data) => data != null && data.isNotEmpty)
          .cast<String>()
          .toList();

      if (analysisData.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("No analyzed images found.")),
          );
        }
        return;
      }

      final result = await PythonService().generateStylesheet(analysisData);
      
      if (mounted && result != null) {
        final jsonString = jsonEncode(result);
        await ProjectRepo().updateStylesheet(_currentProjectId, jsonString);
        
        setState(() {
          if (result.containsKey('results') && result['results'] is Map) {
            _stylesheetMap = result['results'];
          } else {
            _stylesheetMap = result;
          }
          _rawJsonString = jsonString;
        });
        
        // --- LOG TYPOGRAPHY ---
        _logTypography();
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

  // --- DEBUG HELPER ---
  void _logTypography() {
    final typography = _getData(['Typography', 'fonts', 'font_family', 'type', 'font']);
    debugPrint("\n\n========== TYPOGRAPHY SECTION ==========");
    debugPrint(typography?.toString() ?? "Typography key not found in JSON.");
    debugPrint("========================================\n");
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
          _loadSavedStylesheet();
        }),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Variables.textPrimary))
          : (_stylesheetMap == null && _rawJsonString == null)
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
    final typography = _getData(['Typography', 'fonts']) ?? "General Sans"; 

    final foundAny = (style != null || lighting != null || colors != null || emotions != null || era != null);

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
              // 1. Typography
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader("Typography"),
                    _buildTypographyCard(typography is String ? typography : "General Sans"),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // 2. Color Palette
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

              // 3. Sliders
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

  Widget _buildTypographyCard(String fontName) {
    TextStyle sampleStyle;
    if (fontName.toLowerCase().contains("general") && fontName.toLowerCase().contains("sans")) {
      sampleStyle = const TextStyle(fontFamily: 'GeneralSans');
    } else {
      try {
        sampleStyle = GoogleFonts.getFont(fontName);
      } catch (_) {
        sampleStyle = const TextStyle(fontFamily: 'GeneralSans');
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Variables.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Aa",
            style: sampleStyle.copyWith(fontSize: 64, height: 1, fontWeight: FontWeight.w400, color: Colors.black),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fontName,
                  style: const TextStyle(
                    fontFamily: 'GeneralSans',
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  "Primary Typeface",
                  style: TextStyle(
                    fontFamily: 'GeneralSans',
                    fontSize: 14,
                    color: Variables.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "ABCDEFGHIJKLMNOPQRSTUVWXYZ\nabcdefghijklmnopqrstuvwxyz\n1234567890",
                  style: sampleStyle.copyWith(
                    fontSize: 14,
                    color: Variables.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
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