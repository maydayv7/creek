import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:adobe/services/image_analyzer_service.dart';
import 'package:adobe/data/models/image_model.dart';
import '../widgets/analysis_dialog.dart';

class ImageAnalysisPage extends StatefulWidget {
  const ImageAnalysisPage({super.key});

  @override
  State<ImageAnalysisPage> createState() => _ImageAnalysisPageState();
}

class _ImageAnalysisPageState extends State<ImageAnalysisPage> {
  File? _selectedImage;
  Map<String, dynamic>? _fullResult;
  bool _isAnalyzing = false;
  String? _errorMessage;

  Future<void> _pickImage(ImageSource source) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: source);
      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
          _fullResult = null;
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error: $e');
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
      await _selectedImage!.copy(targetPath);

      // Use the centralized master runner
      final result = await ImageAnalyzerService.analyzeFullSuite(targetPath);

      if (mounted) {
        setState(() {
          _isAnalyzing = false;
          _fullResult = result;
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
      appBar: AppBar(title: const Text('Image Analysis')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
            
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top:16),
                child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              ),

            const SizedBox(height: 24),

            // Re-use the AnalysisDialog logic by mocking an ImageModel
            if (_fullResult != null)
              // We wrap the result in a dummy ImageModel to reuse the visualization widget
              LayoutBuilder(
                builder: (context, constraints) {
                  // Mocking the data format stored in DB
                  final mockImage = ImageModel(
                    id: 'temp', 
                    filePath: _selectedImage!.path, 
                    analysisData: json.encode(_fullResult)
                  );
                  
                  // Display the content of AnalysisDialog inline
                  return SizedBox(
                    height: 600,
                    child: AnalysisDialog(image: mockImage),
                  );
                },
              )
          ],
        ),
      ),
    );
  }
}
