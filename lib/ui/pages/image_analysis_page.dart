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
  
  bool _isAnalyzing = false;
  String? _errorMessage;

  final _textureService = TextureAnalyzerService();

  @override
  void dispose() {
    _textureService.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: source);

      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
          _layoutResult = null;
          _textureResult = null;
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error picking image: $e';
      });
    }
  }

  Future<void> _runAnalysis() async {
    if (_selectedImage == null) return;

    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
      _layoutResult = null;
      _textureResult = null;
    });

    try {
      // 1. Prepare File
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = _selectedImage!.path.split('/').last;
      final targetPath = '${appDir.path}/$fileName';
      await _selectedImage!.copy(targetPath);

      // 2. Run Analyses in Parallel
      final layoutFuture = LayoutAnalyzerService.analyzeImage(targetPath);
      final textureFuture = _textureService.analyze(targetPath);

      final results = await Future.wait([layoutFuture, textureFuture]);

      if (mounted) {
        setState(() {
          _isAnalyzing = false;
          
          // Handle Layout Result
          final lResult = results[0] as Map<String, dynamic>?;
          if (lResult != null && lResult['success'] == true) {
            _layoutResult = lResult;
          } else {
            _errorMessage = lResult?['error'] ?? 'Layout analysis failed';
          }

          // Handle Texture Result
          _textureResult = results[1] as List<Map<String, dynamic>>?;
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
            
            // Texture Results
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

            // Layout Results
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
}
