import 'dart:ui';
import 'font_glyphs_data.dart';

class CutTextFontProfile {
  const CutTextFontProfile({
    required this.glyphs,
    this.widthScale = 1,
    this.heightScale = 1,
    this.gapScale = 1,
    this.shearX = 0,
    this.invertY = false,
    this.baselineHeight = 1.6,
  });

  final Map<String, List<List<Offset>>> glyphs;
  final double widthScale;
  final double heightScale;
  final double gapScale;
  final double shearX;
  final bool invertY;
  final double baselineHeight;
}

class TextOverlayFonts {
  static const Map<String, List<List<Offset>>> _stickGlyphs = {
    'A': [
      [
        Offset(0.0, 1.6),
        Offset(0.12, 0.42),
        Offset(0.5, 0.0),
        Offset(0.88, 0.42),
        Offset(1.0, 1.6),
      ],
      [Offset(0.22, 0.86), Offset(0.78, 0.86)],
    ],
    'B': [
      [Offset(0.0, 0.0), Offset(0.0, 1.6)],
      [
        Offset(0.0, 0.0),
        Offset(0.72, 0.0),
        Offset(1.0, 0.22),
        Offset(1.0, 0.58),
        Offset(0.72, 0.8),
        Offset(0.0, 0.8),
      ],
      [
        Offset(0.0, 0.8),
        Offset(0.72, 0.8),
        Offset(1.0, 1.02),
        Offset(1.0, 1.38),
        Offset(0.72, 1.6),
        Offset(0.0, 1.6),
      ],
    ],
    'C': [
      [
        Offset(1.0, 0.16),
        Offset(0.72, 0.0),
        Offset(0.22, 0.0),
        Offset(0.0, 0.28),
        Offset(0.0, 1.32),
        Offset(0.22, 1.6),
        Offset(0.72, 1.6),
        Offset(1.0, 1.44),
      ],
    ],
    'D': [
      [Offset(0.0, 0.0), Offset(0.0, 1.6)],
      [
        Offset(0.0, 0.0),
        Offset(0.62, 0.0),
        Offset(1.0, 0.3),
        Offset(1.0, 1.3),
        Offset(0.62, 1.6),
        Offset(0.0, 1.6),
      ],
    ],
    'E': [
      [Offset(0.0, 0.0), Offset(0.0, 1.6)],
      [Offset(0.0, 0.0), Offset(1.0, 0.0)],
      [Offset(0.0, 0.8), Offset(0.76, 0.8)],
      [Offset(0.0, 1.6), Offset(1.0, 1.6)],
    ],
    'F': [
      [Offset(0.0, 0.0), Offset(0.0, 1.6)],
      [Offset(0.0, 0.0), Offset(1.0, 0.0)],
      [Offset(0.0, 0.8), Offset(0.74, 0.8)],
    ],
    'G': [
      [
        Offset(1.0, 0.16),
        Offset(0.72, 0.0),
        Offset(0.22, 0.0),
        Offset(0.0, 0.28),
        Offset(0.0, 1.32),
        Offset(0.22, 1.6),
        Offset(0.72, 1.6),
        Offset(1.0, 1.44),
        Offset(1.0, 1.0),
        Offset(0.58, 1.0),
      ],
    ],
    'H': [
      [Offset(0.0, 0.0), Offset(0.0, 1.6)],
      [Offset(1.0, 0.0), Offset(1.0, 1.6)],
      [Offset(0.0, 0.8), Offset(1.0, 0.8)],
    ],
    'I': [
      [Offset(0.0, 0.0), Offset(1.0, 0.0)],
      [Offset(0.5, 0.0), Offset(0.5, 1.6)],
      [Offset(0.0, 1.6), Offset(1.0, 1.6)],
    ],
    'J': [
      [Offset(0.0, 0.0), Offset(1.0, 0.0)],
      [
        Offset(0.8, 0.0),
        Offset(0.8, 1.28),
        Offset(0.56, 1.6),
        Offset(0.22, 1.6),
        Offset(0.0, 1.34),
      ],
    ],
    'K': [
      [Offset(0.0, 0.0), Offset(0.0, 1.6)],
      [Offset(1.0, 0.0), Offset(0.0, 0.88)],
      [Offset(0.34, 0.76), Offset(1.0, 1.6)],
    ],
    'L': [
      [Offset(0.0, 0.0), Offset(0.0, 1.6), Offset(1.0, 1.6)],
    ],
    'M': [
      [
        Offset(0.0, 1.6),
        Offset(0.0, 0.0),
        Offset(0.5, 0.72),
        Offset(1.0, 0.0),
        Offset(1.0, 1.6),
      ],
    ],
    'N': [
      [Offset(0.0, 1.6), Offset(0.0, 0.0), Offset(1.0, 1.6), Offset(1.0, 0.0)],
    ],
    'O': [
      [
        Offset(0.2, 0.0),
        Offset(0.8, 0.0),
        Offset(1.0, 0.28),
        Offset(1.0, 1.32),
        Offset(0.8, 1.6),
        Offset(0.2, 1.6),
        Offset(0.0, 1.32),
        Offset(0.0, 0.28),
        Offset(0.2, 0.0),
      ],
    ],
    'P': [
      [
        Offset(0.0, 1.6),
        Offset(0.0, 0.0),
        Offset(0.74, 0.0),
        Offset(1.0, 0.24),
        Offset(1.0, 0.56),
        Offset(0.74, 0.8),
        Offset(0.0, 0.8),
      ],
    ],
    'Q': [
      [
        Offset(0.2, 0.0),
        Offset(0.8, 0.0),
        Offset(1.0, 0.28),
        Offset(1.0, 1.32),
        Offset(0.8, 1.6),
        Offset(0.2, 1.6),
        Offset(0.0, 1.32),
        Offset(0.0, 0.28),
        Offset(0.2, 0.0),
      ],
      [Offset(0.62, 1.08), Offset(1.0, 1.6)],
    ],
    'R': [
      [
        Offset(0.0, 1.6),
        Offset(0.0, 0.0),
        Offset(0.74, 0.0),
        Offset(1.0, 0.24),
        Offset(1.0, 0.56),
        Offset(0.74, 0.8),
        Offset(0.0, 0.8),
      ],
      [Offset(0.46, 0.8), Offset(1.0, 1.6)],
    ],
    'S': [
      [
        Offset(1.0, 0.16),
        Offset(0.74, 0.0),
        Offset(0.22, 0.0),
        Offset(0.0, 0.24),
        Offset(0.0, 0.7),
        Offset(0.22, 0.82),
        Offset(0.78, 0.82),
        Offset(1.0, 0.94),
        Offset(1.0, 1.36),
        Offset(0.78, 1.6),
        Offset(0.2, 1.6),
        Offset(0.0, 1.44),
      ],
    ],
    'T': [
      [Offset(0.0, 0.0), Offset(1.0, 0.0)],
      [Offset(0.5, 0.0), Offset(0.5, 1.6)],
    ],
    'U': [
      [
        Offset(0.0, 0.0),
        Offset(0.0, 1.28),
        Offset(0.2, 1.6),
        Offset(0.8, 1.6),
        Offset(1.0, 1.28),
        Offset(1.0, 0.0),
      ],
    ],
    'V': [
      [Offset(0.0, 0.0), Offset(0.5, 1.6), Offset(1.0, 0.0)],
    ],
    'W': [
      [
        Offset(0.0, 0.0),
        Offset(0.2, 1.6),
        Offset(0.5, 0.88),
        Offset(0.8, 1.6),
        Offset(1.0, 0.0),
      ],
    ],
    'X': [
      [Offset(0.0, 0.0), Offset(1.0, 1.6)],
      [Offset(1.0, 0.0), Offset(0.0, 1.6)],
    ],
    'Y': [
      [Offset(0.0, 0.0), Offset(0.5, 0.8), Offset(1.0, 0.0)],
      [Offset(0.5, 0.8), Offset(0.5, 1.6)],
    ],
    'Z': [
      [Offset(0.0, 0.0), Offset(1.0, 0.0), Offset(0.0, 1.6), Offset(1.0, 1.6)],
    ],
    '0': [
      [
        Offset(0.2, 0.0),
        Offset(0.8, 0.0),
        Offset(1.0, 0.28),
        Offset(1.0, 1.32),
        Offset(0.8, 1.6),
        Offset(0.2, 1.6),
        Offset(0.0, 1.32),
        Offset(0.0, 0.28),
        Offset(0.2, 0.0),
      ],
      [Offset(0.26, 1.34), Offset(0.74, 0.26)],
    ],
    '1': [
      [Offset(0.36, 0.32), Offset(0.5, 0.0), Offset(0.5, 1.6)],
      [Offset(0.24, 1.6), Offset(0.78, 1.6)],
    ],
    '2': [
      [
        Offset(0.0, 0.22),
        Offset(0.2, 0.0),
        Offset(0.8, 0.0),
        Offset(1.0, 0.24),
        Offset(1.0, 0.6),
        Offset(0.0, 1.6),
        Offset(1.0, 1.6),
      ],
    ],
    '3': [
      [
        Offset(0.0, 0.18),
        Offset(0.22, 0.0),
        Offset(0.8, 0.0),
        Offset(1.0, 0.24),
        Offset(0.74, 0.8),
        Offset(1.0, 1.36),
        Offset(0.8, 1.6),
        Offset(0.22, 1.6),
        Offset(0.0, 1.42),
      ],
    ],
    '4': [
      [Offset(0.82, 0.0), Offset(0.82, 1.6)],
      [Offset(0.0, 0.92), Offset(1.0, 0.92)],
      [Offset(0.0, 0.92), Offset(0.72, 0.0)],
    ],
    '5': [
      [
        Offset(1.0, 0.0),
        Offset(0.12, 0.0),
        Offset(0.12, 0.78),
        Offset(0.78, 0.78),
        Offset(1.0, 1.02),
        Offset(1.0, 1.36),
        Offset(0.78, 1.6),
        Offset(0.18, 1.6),
        Offset(0.0, 1.42),
      ],
    ],
    '6': [
      [
        Offset(0.92, 0.2),
        Offset(0.76, 0.0),
        Offset(0.22, 0.0),
        Offset(0.0, 0.28),
        Offset(0.0, 1.3),
        Offset(0.22, 1.6),
        Offset(0.78, 1.6),
        Offset(1.0, 1.34),
        Offset(1.0, 1.02),
        Offset(0.78, 0.78),
        Offset(0.0, 0.78),
      ],
    ],
    '7': [
      [Offset(0.0, 0.0), Offset(1.0, 0.0), Offset(0.36, 1.6)],
    ],
    '8': [
      [
        Offset(0.2, 0.0),
        Offset(0.8, 0.0),
        Offset(1.0, 0.24),
        Offset(1.0, 0.62),
        Offset(0.8, 0.82),
        Offset(0.2, 0.82),
        Offset(0.0, 0.62),
        Offset(0.0, 0.24),
        Offset(0.2, 0.0),
      ],
      [
        Offset(0.2, 0.82),
        Offset(0.8, 0.82),
        Offset(1.0, 1.02),
        Offset(1.0, 1.38),
        Offset(0.8, 1.6),
        Offset(0.2, 1.6),
        Offset(0.0, 1.38),
        Offset(0.0, 1.02),
        Offset(0.2, 0.82),
      ],
    ],
    '9': [
      [
        Offset(1.0, 0.82),
        Offset(0.78, 0.6),
        Offset(0.22, 0.6),
        Offset(0.0, 0.34),
        Offset(0.0, 0.2),
        Offset(0.22, 0.0),
        Offset(0.78, 0.0),
        Offset(1.0, 0.28),
        Offset(1.0, 1.3),
        Offset(0.78, 1.6),
        Offset(0.22, 1.6),
        Offset(0.08, 1.42),
      ],
    ],
    '-': [
      [Offset(0.15, 0.8), Offset(0.85, 0.8)],
    ],
    '_': [
      [Offset(0.1, 1.6), Offset(0.9, 1.6)],
    ],
    '/': [
      [Offset(0.16, 1.6), Offset(0.84, 0.0)],
    ],
    '\\': [
      [Offset(0.16, 0.0), Offset(0.84, 1.6)],
    ],
    '+': [
      [Offset(0.16, 0.8), Offset(0.84, 0.8)],
      [Offset(0.5, 0.18), Offset(0.5, 1.42)],
    ],
    '.': [
      [Offset(0.46, 1.44), Offset(0.54, 1.56)],
    ],
    '(': [
      [
        Offset(0.74, 0.0),
        Offset(0.38, 0.34),
        Offset(0.22, 0.8),
        Offset(0.38, 1.26),
        Offset(0.74, 1.6),
      ],
    ],
    ')': [
      [
        Offset(0.26, 0.0),
        Offset(0.62, 0.34),
        Offset(0.78, 0.8),
        Offset(0.62, 1.26),
        Offset(0.26, 1.6),
      ],
    ],
    ' ': [],
  };

  static final Map<String, List<List<Offset>>> _adobeGothicGlyphs =
      FontGlyphsData.adobeGothic;

  static final Map<String, List<List<Offset>>> _alibabaBlackGlyphs =
      FontGlyphsData.alibabaBlack;

  static final Map<String, List<List<Offset>>> _stencilRegularGlyphs =
      FontGlyphsData.stencilRegular;
      
  static final Map<String, List<List<Offset>>> _oswaldGlyphs =
      FontGlyphsData.oswaldGlyphs;
      
  static final Map<String, List<List<Offset>>> _righteousGlyphs =
      FontGlyphsData.righteousGlyphs;
      
  static final Map<String, List<List<Offset>>> _cinzelGlyphs =
      FontGlyphsData.cinzelGlyphs;

  static final Map<String, CutTextFontProfile> registry = {
    'AdobeGothic': CutTextFontProfile(glyphs: _adobeGothicGlyphs),
    'AlibabaBlack': CutTextFontProfile(
      glyphs: _alibabaBlackGlyphs,
      widthScale: 1.05,
      heightScale: 1.0,
      gapScale: 0.9,
    ),
    'Stencil': CutTextFontProfile(
      glyphs: _stencilRegularGlyphs,
      widthScale: 1.1,
      heightScale: 1.0,
      gapScale: 1.0,
      invertY: true,
      baselineHeight: 1.0,
    ),
    'Oswald': CutTextFontProfile(
      glyphs: _oswaldGlyphs,
      widthScale: 1.0,
      heightScale: 1.0,
      gapScale: 1.0,
      invertY: true,
      baselineHeight: 1.0,
    ),

  };

  static String normalizeText(String raw, {String fontFamily = 'AdobeGothic'}) {
      final glyphs =
          (registry[fontFamily] ?? registry['AdobeGothic']!).glyphs;
      final upper = raw.trim().toUpperCase();
      final normalized = upper
          .replaceAll(RegExp(r'\s+'), ' ')
          .split('')
          .where((char) => glyphs.containsKey(char))
          .join();
      return normalized.trim();
    }
  
}
