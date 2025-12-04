import 'dart:io';
import 'package:flutter/material.dart';
import 'package:creekui/services/download_service.dart';
import 'package:creekui/services/instagram_download_service.dart';
import 'package:creekui/services/image_service.dart';
import 'share_to_moodboard_page.dart';
import 'share_to_file_page.dart';

class ShareHandlerPage extends StatefulWidget {
  final String sharedText;
  final String destination;

  const ShareHandlerPage({
    super.key,
    required this.sharedText,
    required this.destination,
  });

  @override
  State<ShareHandlerPage> createState() => _ShareHandlerPageState();
}

class _ShareHandlerPageState extends State<ShareHandlerPage> {
  // Services
  final _downloadService = DownloadService();
  final _instagramService = InstagramDownloadService();
  final _imageService = ImageService();

  // State
  bool _hasError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _processSharedContent();
  }

  Future<void> _processSharedContent() async {
    final sharedContent = widget.sharedText.trim();
    List<File> tempFiles = [];

    try {
      // CASE A: It's a Local File Path
      if (await File(sharedContent).exists()) {
        tempFiles.add(File(sharedContent));
      }
      // CASE B: It's a URL
      else {
        final urlRegExp = RegExp(r'(https?://\S+)');
        final match = urlRegExp.firstMatch(sharedContent);

        if (match != null) {
          final url = match.group(0)!;

          if (url.contains('instagram.com')) {
            // Instagram Logic
            final downloadedPaths = await _instagramService
                .downloadInstagramImage(url);
            if (downloadedPaths != null && downloadedPaths.isNotEmpty) {
              tempFiles.addAll(downloadedPaths.map((path) => File(path)));
            }
          } else {
            // Generic Download Logic
            final savedPath = await _downloadService.downloadAndSaveImage(url);
            if (savedPath != null) {
              tempFiles.add(File(savedPath));
            }
          }
        } else {
          throw Exception("Invalid content: Not a valid file path or URL.");
        }
      }

      // SUCCESS: Route based on Destination
      if (tempFiles.isNotEmpty) {
        if (!mounted) return;

        // CHECK DESTINATION
        if (widget.destination == 'files') {
          // --- ROUTE TO FILES ---
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder:
                  (_) => ShareToFilePage(
                    sharedImage: tempFiles.first,
                  ),
            ),
          );
        } else {
          // --- ROUTE TO MOODBOARDS (Default) ---
          List<File> permanentFiles = [];

          for (var file in tempFiles) {
            final id = await _imageService.saveImage(
              file,
              0, // Project 0 = Inbox
              tags: [],
            );

            final savedImage = await _imageService.getImage(id);
            if (savedImage != null) {
              permanentFiles.add(File(savedImage.filePath));
            }
          }

          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder:
                    (_) => ShareToMoodboardPage(imageFiles: permanentFiles),
              ),
            );
          }
        }
      } else {
        throw Exception("Could not retrieve any media files.");
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text("Processing")),
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
                    Text("Downloading media..."),
                  ],
                ),
      ),
    );
  }
}
