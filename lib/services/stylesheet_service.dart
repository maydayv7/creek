import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A simple model to hold the extracted design tokens
class StylesheetData {
  final List<Color> colors;
  final List<String> fonts;

  StylesheetData({required this.colors, required this.fonts});
}

class StylesheetService {
  /// Main entry point: Parses a raw (potentially dirty) JSON string
  /// and returns a structured [StylesheetData] object.
  StylesheetData parse(String? rawJson) {
    if (rawJson == null || rawJson.isEmpty) {
      return StylesheetData(colors: [], fonts: []);
    }

    // 1. Parse the string into a Map
    Map<String, dynamic> data = _parseRawJson(rawJson);

    // 2. Extract and Process Fonts
    List<String> fonts = _extractFonts(data);

    // 3. Extract and Process Colors
    List<Color> colors = _extractColors(data);

    return StylesheetData(colors: colors, fonts: fonts);
  }

  // ---------------------------------------------------------------------------
  // PARSING LOGIC
  // ---------------------------------------------------------------------------

  /// Safely parses the raw string into a Map, handling dirty AI output.
  Map<String, dynamic> _parseRawJson(String rawString) {
    try {
      // Try standard decode first
      return _normalizeResult(jsonDecode(rawString));
    } catch (e) {
      try {
        // Try cleaning regex then decoding
        final cleaned = _cleanJsonString(rawString);
        return _normalizeResult(jsonDecode(cleaned));
      } catch (_) {
        return {};
      }
    }
  }

  /// Cleans "dirty" JSON strings by fixing quotes and unquoted keys.
  String _cleanJsonString(String raw) {
    String cleaned = raw;
    // Add quotes to keys
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'([{,]\s*)([a-zA-Z0-9_\s/]+)(\s*:)'),
      (match) => '${match[1]}"${match[2]?.trim()}"${match[3]}',
    );
    // Add quotes to string values that aren't booleans or numbers
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'(:\s*)([a-zA-Z0-9_\-\.\/\s]+)(?=\s*[,}])'),
      (match) {
        String val = match[2]!.trim();
        if (val == 'true' ||
            val == 'false' ||
            val == 'null' ||
            double.tryParse(val) != null) {
          return match[0]!;
        }
        return '${match[1]}"$val"';
      },
    );
    return cleaned;
  }

  /// Normalizes the structure if the API returns { "results": ... }
  Map<String, dynamic> _normalizeResult(dynamic parsed) {
    if (parsed is String) {
      try {
        parsed = jsonDecode(parsed);
      } catch (_) {}
    }

    if (parsed is Map<String, dynamic>) {
      if (parsed.containsKey('results') && parsed['results'] is Map) {
        return parsed['results'];
      }
      return parsed;
    }
    return {};
  }

  // ---------------------------------------------------------------------------
  // EXTRACTION LOGIC
  // ---------------------------------------------------------------------------

  /// Extracts font names and resolves them to valid Google Font strings.
  List<String> _extractFonts(Map<String, dynamic> data) {
    dynamic fontData = _findValue(data, ['Typography', 'fonts', 'typography']);
    if (fontData == null) return [];

    List<String> rawNames = [];
    if (fontData is List) {
      for (var item in fontData) {
        if (item is Map && item.containsKey('label')) {
          rawNames.add(item['label'].toString().trim());
        } else if (item is String) {
          rawNames.add(item.trim());
        }
      }
    } else if (fontData is Map && fontData.containsKey('label')) {
      rawNames.add(fontData['label'].toString().trim());
    } else if (fontData is String) {
      rawNames.add(fontData.trim());
    }

    return rawNames.map((name) => _resolveGoogleFontName(name)).toList();
  }

  /// Extracts colors from Hex codes or semantic labels.
  List<Color> _extractColors(Map<String, dynamic> data) {
    dynamic colorData = _findValue(data, [
      'Colour Palette',
      'Color Palette',
      'colors',
    ]);
    if (colorData == null) return [];

    List<Color> resolvedColors = [];

    if (colorData is List) {
      for (var item in colorData) {
        String? label;
        if (item is Map) {
          label = item['label']?.toString();
        } else if (item is String) {
          label = item;
        }

        if (label != null) {
          resolvedColors.add(_parseColor(label));
        }
      }
    }
    return resolvedColors;
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  dynamic _findValue(Map<String, dynamic> map, List<String> keys) {
    for (var k in keys) {
      if (map.containsKey(k)) return map[k];
      // Case-insensitive check
      for (var mapKey in map.keys) {
        if (mapKey.toLowerCase() == k.toLowerCase()) return map[mapKey];
      }
    }
    return null;
  }

  String _resolveGoogleFontName(String dirtyName) {
    // 1. Exact match check (fastest)
    try {
      GoogleFonts.getFont(dirtyName);
      return dirtyName;
    } catch (_) {}

    // 2. Fuzzy match
    String cleanInput = dirtyName
        .toLowerCase()
        .replaceAll(RegExp(r'[-_]regular$'), '')
        .replaceAll(RegExp(r'[^a-z0-9]'), '');

    final allFonts = GoogleFonts.asMap().keys;
    for (String officialName in allFonts) {
      String cleanOfficial = officialName.toLowerCase().replaceAll(
        RegExp(r'[^a-z0-9]'),
        '',
      );
      if (cleanOfficial == cleanInput) {
        return officialName;
      }
    }
    return dirtyName; // Fallback
  }

  Color _parseColor(String input) {
    if (input.startsWith('#') || input.length == 6) {
      try {
        String hex = input.replaceAll('#', '');
        if (hex.length == 6) {
          return Color(int.parse('0xFF$hex'));
        }
      } catch (_) {}
    }
    return Colors.grey.shade400; // Default fallback
  }
}
