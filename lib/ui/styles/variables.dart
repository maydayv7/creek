import 'package:flutter/material.dart';

class Variables {
  // Colors
  static const Color textWhite = Color(0xFFFAFAFA);
  static const Color textPrimary = Color(0xFF27272A);
  static const Color textSecondary = Color(0xFF71717A);
  static const Color textDisabled = Color(0xFFA1A1AA);
  
  static const Color surfaceSubtle = Color(0xFFF4F4F5);
  static const Color background = Colors.white;
  
  static const Color borderSubtle = Color(0xFFE4E4E7);

  // Dimensions
  static const double fontSizeHeader = 20.0;
  static const double lineHeightHeader = 24.0;
  
  static const double fontSizeBody = 14.0;
  static const double lineHeightBody = 20.0;
  static const double trackingBody = 0.25;

  static const double fontSizeSmall = 12.0;
  
  static const double fontSizeCaption = 10.0;

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
