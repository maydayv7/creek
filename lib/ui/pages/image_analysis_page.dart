import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:creekui/services/analyze/image_analyzer.dart';
import 'package:creekui/ui/styles/variables.dart';

class ImageAnalysisPage extends StatefulWidget {
  const ImageAnalysisPage({super.key});

  @override
  State<ImageAnalysisPage> createState() => _ImageAnalysisPageState();
}

class _ImageAnalysisPageState extends State<ImageAnalysisPage> {
  File? _selectedImage;
  bool _isAnalyzing = false;
  Map<String, dynamic>? _analysisResult;
  String? _errorMessage;

  final ImagePicker _picker = ImagePicker();

  final Set<String> _selectedTags = {};
  final List<String> _availableTags = [
    'Compositions',
    'Colours',
    'Texture',
    'Style',
    'Emotion',
    'Lighting',
    'Era',
    'Fonts',
    'Subject',
  ];

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
          _analysisResult = null;
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Error picking image: $e');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error picking image: $e')));
      }
    }
  }

  Future<void> _runAnalysis() async {
    if (_selectedImage == null) return;

    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
    });

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = _selectedImage!.path.split('/').last;
      final targetPath = '${appDir.path}/$fileName';

      final file = File(_selectedImage!.path);
      await file.copy(targetPath);

      Map<String, dynamic> result;
      if (_selectedTags.isEmpty) {
        result = await ImageAnalyzerService.analyzeFullSuite(targetPath);
      } else {
        result = await ImageAnalyzerService.analyzeSelected(
          targetPath,
          _selectedTags.toList(),
        );
      }

      if (mounted) {
        setState(() {
          _analysisResult = result;
          _isAnalyzing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isAnalyzing = false;
        });
      }
    }
  }

  void _showSourceSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(
                      Icons.camera_alt_outlined,
                      color: Colors.black,
                    ),
                    title: const Text(
                      "Take Photo",
                      style: TextStyle(fontFamily: 'GeneralSans'),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickImage(ImageSource.camera);
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.image_outlined,
                      color: Colors.black,
                    ),
                    title: const Text(
                      "Choose from Gallery",
                      style: TextStyle(fontFamily: 'GeneralSans'),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickImage(ImageSource.gallery);
                    },
                  ),
                ],
              ),
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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
          "Image Analysis",
          style: TextStyle(
            color: Colors.black,
            fontFamily: 'GeneralSans',
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (_selectedImage != null && !_isAnalyzing)
            IconButton(
              icon: const Icon(Icons.play_arrow, color: Variables.textPrimary),
              tooltip: "Run Analysis",
              onPressed: _runAnalysis,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image Preview
            Center(
              child: Container(
                width: double.infinity,
                height: 250,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_selectedImage != null)
                        Image.file(_selectedImage!, fit: BoxFit.contain)
                      else
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.bug_report_outlined,
                              size: 48,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              "Select image to analyze",
                              style: TextStyle(
                                fontFamily: 'GeneralSans',
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      if (_isAnalyzing)
                        Container(
                          color: Colors.black26,
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Tag Selector
            Text(
              "Select Analysis Modules",
              style: Variables.headerStyle.copyWith(fontSize: 16),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  _availableTags.map((tag) {
                    final isSelected = _selectedTags.contains(tag);
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selectedTags.remove(tag);
                          } else {
                            _selectedTags.add(tag);
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color:
                              isSelected
                                  ? const Color(0xFFEEF0FF)
                                  : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color:
                                isSelected
                                    ? const Color(0xFF7C4DFF)
                                    : Colors.grey[300]!,
                            width: 1.0,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isSelected) ...[
                              const Icon(
                                Icons.check,
                                size: 14,
                                color: Color(0xFF7C4DFF),
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              tag,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight:
                                    isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                color:
                                    isSelected
                                        ? const Color(0xFF7C4DFF)
                                        : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
            ),
            const SizedBox(height: 24),

            // Error Message
            if (_errorMessage != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red[100]!),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: Colors.red,
                    fontFamily: 'GeneralSans',
                  ),
                ),
              ),

            // Raw JSON Result
            if (_analysisResult != null) ...[
              const Text(
                "Results",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'GeneralSans',
                ),
              ),
              const SizedBox(height: 12),
              _buildJsonViewer(_analysisResult!),
            ],
            const SizedBox(height: 80),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showSourceSelector,
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        icon: const Icon(Icons.add_photo_alternate),
        label: Text(
          _selectedImage == null ? "Select Image" : "Change Image",
          style: const TextStyle(fontFamily: 'GeneralSans'),
        ),
      ),
    );
  }

  Widget _buildJsonViewer(Map<String, dynamic> data) {
    const encoder = JsonEncoder.withIndent('  ');
    final String prettyJson = encoder.convert(data);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Variables.borderSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[800]!),
      ),
      child: SelectableText(
        prettyJson,
        style: TextStyle(
          fontFamily: Platform.isIOS ? 'Courier' : 'monospace',
          fontSize: 12,
          color: Variables.textPrimary,
          height: 1.3,
        ),
      ),
    );
  }
}
