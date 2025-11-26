import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:adobe/data/repos/image_repo.dart';
import 'package:html/parser.dart' as parser;

class DownloadService {
  final _repo = ImageRepository();
  final _uuid = const Uuid();

  String _unescapeUrl(String s) {
    if (s.isEmpty) return s;
    // unescape common JS/HTML escapes: \xNN, \uNNNN, \/, &amp;
    try {
      s = s.replaceAll('\\/', '/');
      s = s.replaceAll('&amp;', '&');

      s = s.replaceAllMapped(RegExp(r"\\x([0-9A-Fa-f]{2})"), (m) {
        final code = int.parse(m.group(1)!, radix: 16);
        return String.fromCharCode(code);
      });

      s = s.replaceAllMapped(RegExp(r"\\u([0-9A-Fa-f]{4})"), (m) {
        final code = int.parse(m.group(1)!, radix: 16);
        return String.fromCharCode(code);
      });

      // decode percent-encoding if present
      try {
        s = Uri.decodeFull(s);
      } catch (_) {}
    } catch (_) {}
    return s;
  }

  Future<String?> downloadAndSaveImage(String url) async {
    debugPrint("📥 START PROCESS: $url");

    try {
      // Fetch URL
      var response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        },
      );

      if (response.statusCode != 200) {
        debugPrint("❌ HTTP Error: ${response.statusCode}");
        return null;
      }

      var contentType = response.headers['content-type'];
      debugPrint("🔹 Type: $contentType");

      
      // CASE A → HTML webpage (NOT a direct image)
      
      if (contentType != null && !contentType.startsWith('image/')) {
        debugPrint("📄 It's a website. Extracting real image...");
        final document = parser.parse(response.body);

       
        // 1️⃣ GOOGLE PHOTOS / GOOGLEUSERCONTENT.COM
       
        RegExp googlePhotosRegex = RegExp(
          r'https:\/\/lh3\.googleusercontent\.com\/[a-zA-Z0-9\-\._=]+'
        );

        var matchPhotos = googlePhotosRegex.firstMatch(response.body);
        if (matchPhotos != null) {
          String cdn = matchPhotos.group(0)!;

          // Force highest resolution
          cdn = _unescapeUrl(cdn);
          cdn = "${cdn.split("=").first}=s0";
          debugPrint("📸 Google Photos Image Found: $cdn");

          return downloadAndSaveImage(cdn);
        }

      
        // 2️⃣ GOOGLE IMAGE SEARCH (encrypted-tbn / gstatic)
        
       RegExp googleImageRegex = RegExp(
          "https:\\/\\/(?:encrypted\\-tbn\\d\\.gstatic\\.com|(?:\\w+\\.)?gstatic\\.com)\\/[^\"'\\s<>]+",
        );




        var matchGImg = googleImageRegex.firstMatch(response.body);
        if (matchGImg != null) {
          String imgUrl = matchGImg.group(0)!;
          imgUrl = _unescapeUrl(imgUrl);
          debugPrint("🔍 Google Images Real URL: $imgUrl");

          return downloadAndSaveImage(imgUrl);
        }

        // 3️⃣ GOOGLE VIEWER internal imageUrl='https://...'
  
        RegExp viewerImageRegex =
            RegExp(r"imageUrl='(https:\/\/[^']+)'");

        var viewerMatch = viewerImageRegex.firstMatch(response.body);
        if (viewerMatch != null) {
          String imgUrl = viewerMatch.group(1)!;
          imgUrl = _unescapeUrl(imgUrl);
          debugPrint("🖼️ Google Viewer Direct Image: $imgUrl");

          return downloadAndSaveImage(imgUrl);
        }

        // 4️⃣ OG IMAGE → Pinterest / Instagram / Wikipedia

        final metaTags = document.getElementsByTagName('meta');
        for (var meta in metaTags) {
          if (meta.attributes['property'] == 'og:image') {
            String? ogImg = meta.attributes['content'];
            if (ogImg != null) {
              ogImg = _unescapeUrl(ogImg);
              debugPrint("🎯 OG Image Found: $ogImg");
              return downloadAndSaveImage(ogImg);
            }
          }
        }

        debugPrint("❌ No valid image found inside this page.");
        return null;
      }

     
      // CASE B → DIRECT IMAGE FILE (content-type starts with image/)
      final dir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${dir.path}/images');

      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }

      // Detect extension
      String extension = "png";
      if (contentType != null) {
        if (contentType.contains("jpeg") || contentType.contains("jpg")) {
          extension = "jpg";
        } else if (contentType.contains("gif")) {
          extension = "gif";
        } else if (contentType.contains("webp")) {
          extension = "webp";
        }
      }

      final imageId = _uuid.v4();
      final filePath = "${imagesDir.path}/$imageId.$extension";

      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);

      await _repo.insertImage(imageId, filePath);

      debugPrint("✅ Saved Successfully! → $filePath");
      return imageId;
    } catch (e) {
      debugPrint("❌ Error: $e");
      return null;
    }
  }
}
