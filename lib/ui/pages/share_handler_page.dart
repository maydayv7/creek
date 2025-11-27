import 'dart:io';
import 'package:flutter/material.dart';
import 'package:adobe/services/download_service.dart';
import 'package:adobe/services/instagram_download_service.dart';
import 'package:adobe/ui/pages/share_to_moodboard_page.dart';

class ShareHandlerPage extends StatefulWidget {
  final String sharedText;

  const ShareHandlerPage({super.key, required this.sharedText});

  @override
  State<ShareHandlerPage> createState() => _ShareHandlerPageState();
}

class _ShareHandlerPageState extends State<ShareHandlerPage> {
  // Services
  final _downloadService = DownloadService();
  final _instagramService = InstagramDownloadService();

  // State
  bool _isProcessing = true;
  bool _hasError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _processSharedContent();
  }

  Future<void> _processSharedContent() async {
    final sharedContent = widget.sharedText.trim();
    File? finalFile;

    try {
      // CASE A: It's a Local File Path
      if (await File(sharedContent).exists()) {
        finalFile = File(sharedContent);
      }
      // CASE B: It's a URL
      else {
        final urlRegExp = RegExp(r'(https?://\S+)');
        final match = urlRegExp.firstMatch(sharedContent);

        if (match != null) {
          final url = match.group(0)!;

          if (url.contains('instagram.com')) {
            // Instagram Logic
            // Assuming the service returns a List of file paths
            final downloadedPaths = await _instagramService
                .downloadInstagramImage(url);

            if (downloadedPaths != null && downloadedPaths.isNotEmpty) {
              finalFile = File(downloadedPaths.first);
            }
          } else {
            // Generic Download Logic
            // Ensure this service returns the String path of the saved file
            final savedPath = await _downloadService.downloadAndSaveImage(url);

            if (savedPath != null) {
              finalFile = File(savedPath);
            }
          }
        } else {
          throw Exception("Invalid content: Not a valid file path or URL.");
        }
      }

      // SUCCESS: Navigate to ShareToMoodboardPage
      if (finalFile != null && await finalFile.exists()) {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ShareToMoodboardPage(imageFile: finalFile!),
            ),
          );
        }
      } else {
        throw Exception("Could not retrieve image file.");
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text("Processing...")),
      body: Center(
        child:
            _hasError
                ? Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 50,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "Error processing media",
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage ?? "Unknown Error",
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("Close"),
                      ),
                    ],
                  ),
                )
                : const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 20),
                    Text("Analyzing & Preparing Image..."),
                  ],
                ),
      ),
    );
  }
}
