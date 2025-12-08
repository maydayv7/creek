import 'package:flutter/material.dart';

class Variables {
  // Colors
  static const Color textWhite = Color(0xFFFAFAFA);
  static const Color textPrimary = Color(0xFF27272A);
  static const Color textSecondary = Color(0xFF71717A);
  static const Color textDisabled = Color(0xFFA1A1AA);

  static const Color surfaceSubtle = Color(0xFFF4F4F5);
  static const Color surfaceBackground = Color(0xFFFAFAFA);
  static const Color background = Colors.white;
  static const Color borderSubtle = Color(0xFFE4E4E7);

  static const Color chipBackground = Color(0xFFE0E7FF);
  static const Color chipText = Color(0xFF7C86FF);

  // Dark Mode
  static const Color surfaceDark = Color(0xFF27272A);
  static const Color backgroundDark = Color(0xFF18181B);
  static const Color borderDark = Color(0xFF3F3F46);

  // Canvas Specific
  static const Color canvasBackground = Color(0xFFE0E0E0);
  static const Color selectionBorder = Color(0xFFB44CFF);
  static const Color accentMagic = Color(0xFFD8705D);
  static const Color defaultBrush = Color(0xFFFF4081);
  static const Color iconActive = Color(0xFF27272A);
  static const Color iconInactive = Color(0xFF9F9FA9);

  // Dimensions
  static const double fontSizeHeader = 20.0;
  static const double lineHeightHeader = 24.0;
  static const double fontSizeBody = 14.0;
  static const double lineHeightBody = 20.0;
  static const double trackingBody = 0.25;
  static const double fontSizeSmall = 12.0;
  static const double fontSizeCaption = 10.0;

  // Radius
  static const double radiusSmall = 8.0;
  static const double radiusMedium = 12.0;
  static const double radiusLarge = 16.0; // Added

  // Text Styles
  static TextStyle get headerStyle => const TextStyle(
    fontFamily: 'GeneralSans',
    fontSize: fontSizeHeader,
    height: lineHeightHeader / fontSizeHeader,
    fontWeight: FontWeight.w500,
    color: textPrimary,
  );

  static TextStyle get bodyStyle => const TextStyle(
    fontFamily: 'GeneralSans',
    fontSize: fontSizeBody,
    height: lineHeightBody / fontSizeBody,
    letterSpacing: trackingBody,
    color: textPrimary,
  );

  static TextStyle get captionStyle => const TextStyle(
    fontFamily: 'GeneralSans',
    fontSize: fontSizeCaption,
    color: textSecondary,
  );

  static TextStyle get buttonTextStyle => const TextStyle(
    fontFamily: 'GeneralSans',
    fontSize: fontSizeBody,
    height: lineHeightBody / fontSizeBody,
    letterSpacing: trackingBody,
    fontWeight: FontWeight.w500,
    color: textWhite,
  );
}
