import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:adobe/services/analyze/image_analyzer.dart';

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

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
          _analysisResult = null;
          _errorMessage = null;
        });
        // Auto-run analysis when a new image is picked
        _runAnalysis(image.path);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Error picking image: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  Future<void> _runAnalysis(String sourcePath) async {
    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
    });

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = sourcePath.split('/').last;
      final targetPath = '${appDir.path}/$fileName';

      final file = File(sourcePath);
      await file.copy(targetPath);

      final result = await ImageAnalyzerService.analyzeFullSuite(targetPath);

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
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined, color: Colors.black),
                title: const Text("Take Photo", style: TextStyle(fontFamily: 'GeneralSans')),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.image_outlined, color: Colors.black),
                title: const Text("Choose from Gallery", style: TextStyle(fontFamily: 'GeneralSans')),
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
          if (_selectedImage != null)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.black),
              tooltip: "Re-analyze",
              onPressed: () => _runAnalysis(_selectedImage!.path),
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
                height: 300,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_selectedImage != null)
                        Image.file(_selectedImage!, fit: BoxFit.contain)
                      else
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate_outlined,
                                size: 48, color: Colors.grey[400]),
                            const SizedBox(height: 12),
                            Text(
                              "Select an image to analyze",
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
                            child: CircularProgressIndicator(color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
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
                  style: const TextStyle(color: Colors.red, fontFamily: 'GeneralSans'),
                ),
              ),
            if (_analysisResult != null) ...[
              const Text(
                "Results",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'GeneralSans',
                ),
              ),
              
              const SizedBox(height: 16),
              _buildFormattedResults(_analysisResult!),
              const SizedBox(height: 32),
              ExpansionTile(
                title: const Text(
                  "View Raw JSON",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'GeneralSans',
                    color: Colors.grey,
                  ),
                ),
                children: [_buildJsonViewer(_analysisResult!)],
              ),
            ],
            const SizedBox(height: 80),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showSourceSelector,
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        icon: const Icon(Icons.camera_alt),
        label: Text(
          _selectedImage == null ? "Pick Image" : "Change Image",
          style: const TextStyle(fontFamily: 'GeneralSans'),
        ),
      ),
    );
  }

  Widget _buildFormattedResults(Map<String, dynamic> root) {
    final data = root['data'];
    if (data == null || data['results'] == null) {
      return const Text("No detailed results found.");
    }
    final results = data['results'] as Map<String, dynamic>;

    return Column(
      children: [
        _buildList("Style", results['Style']),
        _buildList("Era", results['Era']),
        _buildList("Emotions", results['Emotions']),
        _buildList("Lighting", results['Lighting']),
        _buildList("Layout Composition", results['Layout']),
        _buildList("Color Palette", results['Colour Palette']),
        _buildList("Texture", results['Texture']),
        _buildList("Font", results['Font']),
      ],
    );
  }

  Widget _buildList(String title, dynamic categoryData) {
    if (categoryData == null || categoryData['scores'] == null) {
      return const SizedBox.shrink();
    }

    final scoresMap = categoryData['scores'] as Map<String, dynamic>;
    
    final sortedEntries = scoresMap.entries.toList()
      ..sort((a, b) => (b.value as num).compareTo(a.value as num));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
              fontFamily: 'GeneralSans',
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),
          ...sortedEntries.map((e) {
            final val = e.value as num;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      e.key,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black87,
                        fontFamily: 'GeneralSans',
                      ),
                    ),
                  ),
                  Text(
                    val.toStringAsFixed(4), // High precision for debugging
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: Platform.isIOS ? 'Courier' : 'monospace',
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
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
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: SelectableText(
        prettyJson,
        style: TextStyle(
          fontFamily: Platform.isIOS ? 'Courier' : 'monospace',
          fontSize: 11,
          color: Colors.grey[800],
          height: 1.3,
        ),
      ),
    );
  }
}
