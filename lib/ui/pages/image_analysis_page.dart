import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:adobe/services/layout_analyzer_service.dart';
import 'package:adobe/services/texture_analyzer_service.dart';

class ImageAnalysisPage extends StatefulWidget {
  const ImageAnalysisPage({super.key});

  @override
  State<ImageAnalysisPage> createState() => _ImageAnalysisPageState();
}

class _ImageAnalysisPageState extends State<ImageAnalysisPage> {
  File? _selectedImage;
  
  // Results
  Map<String, dynamic>? _layoutResult;
  List<Map<String, dynamic>>? _textureResult;
  Map<String, dynamic>? _colorResult; // Added for Color Style
  
  bool _isAnalyzing = false;
  String? _errorMessage;

  // Texture Service (from main)
  final _textureService = TextureAnalyzerService();

  @override
  void dispose() {
    _textureService.dispose();
    super.dispose();
  }

  // Unified Image Picker (from main)
  Future<void> _pickImage(ImageSource source) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: source);

      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
          _layoutResult = null;
          _textureResult = null;
          _colorResult = null;
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error picking image: $e';
      });
    }
  }

  // Unified Analysis Runner (Combines logic from HEAD and main)
  Future<void> _runAnalysis() async {
    if (_selectedImage == null) return;

    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
      _layoutResult = null;
      _textureResult = null;
      _colorResult = null;
    });

    try {
      // 1. Prepare File
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = _selectedImage!.path.split('/').last;
      final targetPath = '${appDir.path}/$fileName';
      await _selectedImage!.copy(targetPath);

      // 2. Run All Analyses in Parallel
      // NOTE: Ensure LayoutAnalyzerService has 'analyzeColorStyle' implemented.
      final layoutFuture = LayoutAnalyzerService.analyzeLayout(targetPath);
      final textureFuture = _textureService.analyze(targetPath);
      // We assume analyzeColorStyle is added to LayoutAnalyzerService
      final colorFuture = LayoutAnalyzerService.analyzeColorStyle(targetPath); 

      final results = await Future.wait([
        layoutFuture, 
        textureFuture,
        colorFuture
      ]);

      if (mounted) {
        setState(() {
          _isAnalyzing = false;
          
          // 1. Handle Layout Result
          final lResult = results[0] as Map<String, dynamic>?;
          if (lResult != null && lResult['success'] == true) {
            _layoutResult = lResult;
          } else if (lResult != null) {
             // Optional: handle layout specific error
          }

          // 2. Handle Texture Result
          _textureResult = results[1] as List<Map<String, dynamic>>?;

          // 3. Handle Color Result
          final cResult = results[2] as Map<String, dynamic>?;
          if (cResult != null && cResult['success'] == true) {
            _colorResult = cResult; 
          }

          // Generic error if everything failed
          if (_layoutResult == null && (_textureResult == null || _textureResult!.isEmpty) && _colorResult == null) {
            _errorMessage = "Analysis failed to return results.";
          }
        });
      }
    } catch (e) {
      setState(() {
        _isAnalyzing = false;
        _errorMessage = 'Analysis Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Composition & Texture')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image Preview
            Container(
              height: 250,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
                image: _selectedImage != null 
                  ? DecorationImage(image: FileImage(_selectedImage!), fit: BoxFit.cover)
                  : null
              ),
              child: _selectedImage == null 
                ? const Center(child: Icon(Icons.image, size: 50, color: Colors.grey))
                : null,
            ),
            
            const SizedBox(height: 16),
            
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.gallery), 
                icon: const Icon(Icons.photo), label: const Text("Gallery"))
              ),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.camera), 
                icon: const Icon(Icons.camera_alt), label: const Text("Camera"))
              ),
            ]),

            const SizedBox(height: 16),

            ElevatedButton(
              onPressed: (_selectedImage != null && !_isAnalyzing) ? _runAnalysis : null,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
              child: _isAnalyzing 
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text("Analyze Image"),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            ],

            const SizedBox(height: 24),

            // --- RESULTS ---
            
            // 1. Texture Results
            if (_textureResult != null && _textureResult!.isNotEmpty) ...[
              const Text("🧶 Texture & Material", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _textureResult!.map((t) => Chip(
                  avatar: CircleAvatar(
                    backgroundColor: Colors.blue.shade900,
                    child: Text("${(t['score']*100).toInt()}", style: const TextStyle(fontSize: 10, color: Colors.white)),
                  ),
                  label: Text(t['name']),
                  backgroundColor: Colors.blue.shade50,
                )).toList(),
              ),
              const Divider(height: 30),
            ],

            // 2. Color Style Results (Restored from HEAD)
            if (_colorResult != null) ...[
               _buildColorStyleCard(_colorResult!),
               const Divider(height: 30),
            ],

            // 3. Layout Results
            if (_layoutResult != null) ...[
              const Text("📐 Layout & Composition", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              ...(_layoutResult!['top5'] as List).map((item) => ListTile(
                title: Text(item['name']),
                trailing: Text("${(item['score']*100).toStringAsFixed(1)}%", style: const TextStyle(fontWeight: FontWeight.bold)),
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              )),
            ]
          ],
        ),
      ),
    );
  }

  // --- Helper Widget from HEAD for Color Style ---
  Widget _buildColorStyleCard(Map<String, dynamic> colorData) {
    final String topLabel = colorData['top_label']?.toString() ?? 'Unknown';
    final double topScore = (colorData['top_score'] as num?)?.toDouble() ?? 0.0;
    final List predictions = colorData['predictions'] as List? ?? [];

    return Card(
      elevation: 2, // Reduced elevation to match simple look
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            const Row(
              children: [
                Icon(Icons.palette, color: Colors.deepPurple),
                SizedBox(width: 8),
                Text(
                  "Color Style",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),

            // Main Prediction
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  topLabel.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Colors.deepPurple,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Text(
                    "${(topScore * 100).toStringAsFixed(1)}%",
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Main Progress Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: topScore,
                minHeight: 10,
                backgroundColor: Colors.grey[200],
                color: Colors.deepPurple,
              ),
            ),

            // Runner-up predictions
            if (predictions.length > 1) ...[
              const SizedBox(height: 16),
              const Text("Other possibilities:", style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 8),
              ...predictions.skip(1).take(2).map((pred) { // Show top 2 alternatives
                final pLabel = pred['label'].toString();
                final pScore = (pred['score'] as num).toDouble();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 80,
                        child: Text(pLabel, style: const TextStyle(fontWeight: FontWeight.w500)),
                      ),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: pScore,
                          backgroundColor: Colors.grey[100],
                          color: Colors.deepPurple.withOpacity(0.4),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text("${(pScore * 100).toStringAsFixed(0)}%", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
