import 'text_overlay_fonts.dart';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'cut_file_transformer.dart';
import 'sjm_cipher.dart';
import 'package:flutter_project/features/sunshine/services/sunshine_text_overlay.dart';
import 'package:flutter_project/features/dq/services/dq_sjm_text_overlay.dart';

enum CutTextOverlayDirection { horizontal, vertical }

enum CutTextOverlayPlacement { start, center, end }

enum CutTextOverlaySize { small, medium, large }

enum CutTextOverlayTransport { sunshineSjc, dqPlt, dqSjm }

class CutTextOverlaySpec {
  const CutTextOverlaySpec({
    required this.text,
    this.dx = 0,
    this.dy = 0,
    this.scale = 0.5,
    this.rotation = 0.0,
    this.flipHorizontally = false,
    this.fontFamily = 'AdobeGothic',
  });

  final String text;
  final double dx;
  final double dy;
  final double scale;
  final double rotation;
  final bool flipHorizontally;
  final String fontFamily;

  CutTextOverlaySpec copyWith({
    String? text,
    double? dx,
    double? dy,
    double? scale,
    double? rotation,
    bool? flipHorizontally,
    String? fontFamily,
  }) {
    return CutTextOverlaySpec(
      text: text ?? this.text,
      dx: dx ?? this.dx,
      dy: dy ?? this.dy,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      flipHorizontally: flipHorizontally ?? this.flipHorizontally,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }
}

class CutTextOverlayBuildResult {
  const CutTextOverlayBuildResult({
    required this.previewData,
    required this.overlayPreviewData,
    required this.bytes,
    required this.normalizedText,
    required this.transport,
  });

  final CutPathData previewData;
  final CutPathData overlayPreviewData;
  final List<int> bytes;
  final String normalizedText;
  final CutTextOverlayTransport transport;
}

class CutTextOverlayService {
  static const String _sunshineMapping = '6240092912';
  static const String _dqSjmSeed = '515167676782828';
  static const Map<String, String> _sunshineDigitMap = {
    '0': '2',
    '1': '0',
    '2': '9',
    '3': '7',
    '4': '8',
    '5': '6',
    '6': '4',
    '7': '3',
    '8': '5',
    '9': '1',
    '-': '-',
  };


  static const Map<String, List<List<Offset>>> _stencilGlyphs = {
    'A': [
      [
        Offset(0.0, 1.6),
        Offset(0.4, 0.0),
        Offset(0.6, 0.0),
        Offset(1.0, 1.6),
        Offset(0.8, 1.6),
        Offset(0.7, 1.2),
        Offset(0.3, 1.2),
        Offset(0.2, 1.6),
        Offset(0.0, 1.6),
      ],
      [Offset(0.4, 0.8), Offset(0.6, 0.8), Offset(0.5, 0.4), Offset(0.4, 0.8)],
    ],
    'B': [
      [
        Offset(0.0, 0.0),
        Offset(0.7, 0.0),
        Offset(1.0, 0.4),
        Offset(0.7, 0.8),
        Offset(0.0, 0.8),
        Offset(0.0, 0.0),
      ],
      [
        Offset(0.0, 0.8),
        Offset(0.7, 0.8),
        Offset(1.0, 1.2),
        Offset(0.7, 1.6),
        Offset(0.0, 1.6),
        Offset(0.0, 0.8),
      ],
      [
        Offset(0.2, 0.2),
        Offset(0.5, 0.2),
        Offset(0.5, 0.6),
        Offset(0.2, 0.6),
        Offset(0.2, 0.2),
      ],
      [
        Offset(0.2, 1.0),
        Offset(0.5, 1.0),
        Offset(0.5, 1.4),
        Offset(0.2, 1.4),
        Offset(0.2, 1.0),
      ],
    ],
    'C': [
      [
        Offset(1.0, 0.4),
        Offset(0.7, 0.0),
        Offset(0.3, 0.0),
        Offset(0.0, 0.4),
        Offset(0.0, 1.2),
        Offset(0.3, 1.6),
        Offset(0.7, 1.6),
        Offset(1.0, 1.2),
        Offset(0.8, 1.2),
        Offset(0.6, 1.4),
        Offset(0.4, 1.4),
        Offset(0.2, 1.1),
        Offset(0.2, 0.5),
        Offset(0.4, 0.2),
        Offset(0.6, 0.2),
        Offset(0.8, 0.4),
        Offset(1.0, 0.4),
      ],
    ],
    'D': [
      [
        Offset(0.0, 0.0),
        Offset(0.6, 0.0),
        Offset(1.0, 0.4),
        Offset(1.0, 1.2),
        Offset(0.6, 1.6),
        Offset(0.0, 1.6),
        Offset(0.0, 0.0),
      ],
      [
        Offset(0.2, 0.2),
        Offset(0.5, 0.2),
        Offset(0.8, 0.5),
        Offset(0.8, 1.1),
        Offset(0.5, 1.4),
        Offset(0.2, 1.4),
        Offset(0.2, 0.2),
      ],
    ],
    'E': [
      [
        Offset(1.0, 0.0),
        Offset(0.0, 0.0),
        Offset(0.0, 1.6),
        Offset(1.0, 1.6),
        Offset(1.0, 1.4),
        Offset(0.2, 1.4),
        Offset(0.2, 0.9),
        Offset(0.8, 0.9),
        Offset(0.8, 0.7),
        Offset(0.2, 0.7),
        Offset(0.2, 0.2),
        Offset(1.0, 0.2),
        Offset(1.0, 0.0),
      ],
    ],
    'F': [
      [
        Offset(1.0, 0.0),
        Offset(0.0, 0.0),
        Offset(0.0, 1.6),
        Offset(0.2, 1.6),
        Offset(0.2, 0.9),
        Offset(0.8, 0.9),
        Offset(0.8, 0.7),
        Offset(0.2, 0.7),
        Offset(0.2, 0.2),
        Offset(1.0, 0.2),
        Offset(1.0, 0.0),
      ],
    ],
    'G': [
      [
        Offset(1.0, 0.4),
        Offset(0.7, 0.0),
        Offset(0.3, 0.0),
        Offset(0.0, 0.4),
        Offset(0.0, 1.2),
        Offset(0.3, 1.6),
        Offset(0.7, 1.6),
        Offset(1.0, 1.2),
        Offset(1.0, 0.8),
        Offset(0.6, 0.8),
        Offset(0.6, 1.0),
        Offset(0.8, 1.0),
        Offset(0.8, 1.1),
        Offset(0.7, 1.4),
        Offset(0.3, 1.4),
        Offset(0.2, 1.1),
        Offset(0.2, 0.5),
        Offset(0.4, 0.2),
        Offset(0.6, 0.2),
        Offset(0.8, 0.4),
        Offset(1.0, 0.4),
      ],
    ],
    'H': [
      [
        Offset(0.0, 0.0),
        Offset(0.2, 0.0),
        Offset(0.2, 0.7),
        Offset(0.8, 0.7),
        Offset(0.8, 0.0),
        Offset(1.0, 0.0),
        Offset(1.0, 1.6),
        Offset(0.8, 1.6),
        Offset(0.8, 0.9),
        Offset(0.2, 0.9),
        Offset(0.2, 1.6),
        Offset(0.0, 1.6),
        Offset(0.0, 0.0),
      ],
    ],
    'I': [
      [
        Offset(0.3, 0.0),
        Offset(0.7, 0.0),
        Offset(0.7, 0.2),
        Offset(0.6, 0.2),
        Offset(0.6, 1.4),
        Offset(0.7, 1.4),
        Offset(0.7, 1.6),
        Offset(0.3, 1.6),
        Offset(0.3, 1.4),
        Offset(0.4, 1.4),
        Offset(0.4, 0.2),
        Offset(0.3, 0.2),
        Offset(0.3, 0.0),
      ],
    ],
    'J': [
      [
        Offset(0.5, 0.0),
        Offset(1.0, 0.0),
        Offset(1.0, 1.2),
        Offset(0.7, 1.6),
        Offset(0.3, 1.6),
        Offset(0.0, 1.3),
        Offset(0.2, 1.1),
        Offset(0.4, 1.4),
        Offset(0.7, 1.4),
        Offset(0.8, 1.1),
        Offset(0.8, 0.2),
        Offset(0.5, 0.2),
        Offset(0.5, 0.0),
      ],
    ],
    'K': [
      [
        Offset(0.0, 0.0),
        Offset(0.2, 0.0),
        Offset(0.2, 0.6),
        Offset(0.7, 0.0),
        Offset(1.0, 0.0),
        Offset(0.4, 0.8),
        Offset(1.0, 1.6),
        Offset(0.7, 1.6),
        Offset(0.2, 1.0),
        Offset(0.2, 1.6),
        Offset(0.0, 1.6),
        Offset(0.0, 0.0),
      ],
    ],
    'L': [
      [
        Offset(0.0, 0.0),
        Offset(0.2, 0.0),
        Offset(0.2, 1.4),
        Offset(1.0, 1.4),
        Offset(1.0, 1.6),
        Offset(0.0, 1.6),
        Offset(0.0, 0.0),
      ],
    ],
    'M': [
      [
        Offset(0.0, 1.6),
        Offset(0.0, 0.0),
        Offset(0.5, 0.5),
        Offset(1.0, 0.0),
        Offset(1.0, 1.6),
        Offset(0.8, 1.6),
        Offset(0.8, 0.4),
        Offset(0.5, 0.7),
        Offset(0.2, 0.4),
        Offset(0.2, 1.6),
        Offset(0.0, 1.6),
      ],
    ],
    'N': [
      [
        Offset(0.0, 1.6),
        Offset(0.0, 0.0),
        Offset(0.3, 0.0),
        Offset(0.8, 1.1),
        Offset(0.8, 0.0),
        Offset(1.0, 0.0),
        Offset(1.0, 1.6),
        Offset(0.7, 1.6),
        Offset(0.2, 0.5),
        Offset(0.2, 1.6),
        Offset(0.0, 1.6),
      ],
    ],
    'O': [
      [
        Offset(0.3, 0.0),
        Offset(0.7, 0.0),
        Offset(1.0, 0.3),
        Offset(1.0, 1.3),
        Offset(0.7, 1.6),
        Offset(0.3, 1.6),
        Offset(0.0, 1.3),
        Offset(0.0, 0.3),
        Offset(0.3, 0.0),
      ],
      [
        Offset(0.3, 0.3),
        Offset(0.7, 0.3),
        Offset(0.8, 0.4),
        Offset(0.8, 0.7),
        Offset(0.2, 0.7),
        Offset(0.2, 0.4),
        Offset(0.3, 0.3),
      ],
      [
        Offset(0.2, 0.9),
        Offset(0.8, 0.9),
        Offset(0.8, 1.2),
        Offset(0.7, 1.3),
        Offset(0.3, 1.3),
        Offset(0.2, 1.2),
        Offset(0.2, 0.9),
      ],
    ],
    'P': [
      [
        Offset(0.0, 0.0),
        Offset(0.7, 0.0),
        Offset(1.0, 0.4),
        Offset(0.7, 0.8),
        Offset(0.2, 0.8),
        Offset(0.2, 1.6),
        Offset(0.0, 1.6),
        Offset(0.0, 0.0),
      ],
      [
        Offset(0.2, 0.2),
        Offset(0.6, 0.2),
        Offset(0.8, 0.4),
        Offset(0.6, 0.6),
        Offset(0.2, 0.6),
        Offset(0.2, 0.2),
      ],
    ],
    'Q': [
      [
        Offset(0.3, 0.0),
        Offset(0.7, 0.0),
        Offset(1.0, 0.3),
        Offset(1.0, 1.3),
        Offset(0.7, 1.6),
        Offset(0.6, 1.6),
        Offset(1.0, 1.6),
        Offset(0.8, 1.4),
        Offset(0.7, 1.3),
        Offset(0.3, 1.3),
        Offset(0.0, 1.3),
        Offset(0.0, 0.3),
        Offset(0.3, 0.0),
      ],
      [
        Offset(0.3, 0.3),
        Offset(0.7, 0.3),
        Offset(0.8, 0.4),
        Offset(0.8, 0.7),
        Offset(0.2, 0.7),
        Offset(0.2, 0.4),
        Offset(0.3, 0.3),
      ],
      [
        Offset(0.2, 0.9),
        Offset(0.8, 0.9),
        Offset(0.8, 1.2),
        Offset(0.7, 1.3),
        Offset(0.3, 1.3),
        Offset(0.2, 1.2),
        Offset(0.2, 0.9),
      ],
    ],
    'R': [
      [
        Offset(0.0, 0.0),
        Offset(0.7, 0.0),
        Offset(1.0, 0.4),
        Offset(0.7, 0.8),
        Offset(1.0, 1.6),
        Offset(0.8, 1.6),
        Offset(0.5, 0.8),
        Offset(0.2, 0.8),
        Offset(0.2, 1.6),
        Offset(0.0, 1.6),
        Offset(0.0, 0.0),
      ],
      [
        Offset(0.2, 0.2),
        Offset(0.6, 0.2),
        Offset(0.8, 0.4),
        Offset(0.6, 0.6),
        Offset(0.2, 0.6),
        Offset(0.2, 0.2),
      ],
    ],
    'S': [
      [
        Offset(1.0, 0.3),
        Offset(0.7, 0.0),
        Offset(0.3, 0.0),
        Offset(0.0, 0.3),
        Offset(0.0, 0.6),
        Offset(0.8, 1.0),
        Offset(1.0, 1.3),
        Offset(0.7, 1.6),
        Offset(0.3, 1.6),
        Offset(0.0, 1.3),
        Offset(0.2, 1.3),
        Offset(0.3, 1.4),
        Offset(0.7, 1.4),
        Offset(0.8, 1.2),
        Offset(0.8, 1.0),
        Offset(0.0, 0.6),
        Offset(0.0, 0.3),
        Offset(0.3, 0.2),
        Offset(0.7, 0.2),
        Offset(0.8, 0.3),
        Offset(1.0, 0.3),
      ],
    ],
    'T': [
      [
        Offset(0.0, 0.0),
        Offset(1.0, 0.0),
        Offset(1.0, 0.2),
        Offset(0.6, 0.2),
        Offset(0.6, 1.6),
        Offset(0.4, 1.6),
        Offset(0.4, 0.2),
        Offset(0.0, 0.2),
        Offset(0.0, 0.0),
      ],
    ],
    'U': [
      [
        Offset(0.0, 0.0),
        Offset(0.2, 0.0),
        Offset(0.2, 1.3),
        Offset(0.4, 1.4),
        Offset(0.6, 1.4),
        Offset(0.8, 1.3),
        Offset(0.8, 0.0),
        Offset(1.0, 0.0),
        Offset(1.0, 1.3),
        Offset(0.7, 1.6),
        Offset(0.3, 1.6),
        Offset(0.0, 1.3),
        Offset(0.0, 0.0),
      ],
    ],
    'V': [
      [
        Offset(0.0, 0.0),
        Offset(0.2, 0.0),
        Offset(0.5, 1.3),
        Offset(0.8, 0.0),
        Offset(1.0, 0.0),
        Offset(0.6, 1.6),
        Offset(0.4, 1.6),
        Offset(0.0, 0.0),
      ],
    ],
    'W': [
      [
        Offset(0.0, 0.0),
        Offset(0.2, 0.0),
        Offset(0.3, 1.2),
        Offset(0.5, 0.5),
        Offset(0.7, 1.2),
        Offset(0.8, 0.0),
        Offset(1.0, 0.0),
        Offset(0.8, 1.6),
        Offset(0.6, 1.6),
        Offset(0.5, 0.8),
        Offset(0.4, 1.6),
        Offset(0.2, 1.6),
        Offset(0.0, 0.0),
      ],
    ],
    'X': [
      [
        Offset(0.0, 0.0),
        Offset(0.3, 0.0),
        Offset(0.5, 0.6),
        Offset(0.7, 0.0),
        Offset(1.0, 0.0),
        Offset(0.6, 0.8),
        Offset(1.0, 1.6),
        Offset(0.7, 1.6),
        Offset(0.5, 1.0),
        Offset(0.3, 1.6),
        Offset(0.0, 1.6),
        Offset(0.4, 0.8),
        Offset(0.0, 0.0),
      ],
    ],
    'Y': [
      [
        Offset(0.0, 0.0),
        Offset(0.3, 0.0),
        Offset(0.5, 0.6),
        Offset(0.7, 0.0),
        Offset(1.0, 0.0),
        Offset(0.6, 0.8),
        Offset(0.6, 1.6),
        Offset(0.4, 1.6),
        Offset(0.4, 0.8),
        Offset(0.0, 0.0),
      ],
    ],
    'Z': [
      [
        Offset(0.0, 0.0),
        Offset(1.0, 0.0),
        Offset(1.0, 0.3),
        Offset(0.3, 1.4),
        Offset(1.0, 1.4),
        Offset(1.0, 1.6),
        Offset(0.0, 1.6),
        Offset(0.0, 1.3),
        Offset(0.7, 0.2),
        Offset(0.0, 0.2),
        Offset(0.0, 0.0),
      ],
    ],
    '0': [
      [
        Offset(0.3, 0.0),
        Offset(0.7, 0.0),
        Offset(1.0, 0.3),
        Offset(1.0, 1.3),
        Offset(0.7, 1.6),
        Offset(0.3, 1.6),
        Offset(0.0, 1.3),
        Offset(0.0, 0.3),
        Offset(0.3, 0.0),
      ],
      [
        Offset(0.3, 0.3),
        Offset(0.7, 0.3),
        Offset(0.8, 0.4),
        Offset(0.8, 0.7),
        Offset(0.2, 0.7),
        Offset(0.2, 0.4),
        Offset(0.3, 0.3),
      ],
      [
        Offset(0.2, 0.9),
        Offset(0.8, 0.9),
        Offset(0.8, 1.2),
        Offset(0.7, 1.3),
        Offset(0.3, 1.3),
        Offset(0.2, 1.2),
        Offset(0.2, 0.9),
      ],
    ],
    '1': [
      [
        Offset(0.3, 0.3),
        Offset(0.5, 0.0),
        Offset(0.7, 0.0),
        Offset(0.7, 1.6),
        Offset(0.5, 1.6),
        Offset(0.5, 0.3),
        Offset(0.3, 0.5),
        Offset(0.3, 0.3),
      ],
    ],
    '2': [
      [
        Offset(0.0, 0.3),
        Offset(0.3, 0.0),
        Offset(0.7, 0.0),
        Offset(1.0, 0.3),
        Offset(1.0, 0.6),
        Offset(0.3, 1.4),
        Offset(1.0, 1.4),
        Offset(1.0, 1.6),
        Offset(0.0, 1.6),
        Offset(0.0, 1.3),
        Offset(0.6, 0.5),
        Offset(0.6, 0.3),
        Offset(0.3, 0.3),
        Offset(0.2, 0.4),
        Offset(0.0, 0.3),
      ],
    ],
    '3': [
      [
        Offset(0.0, 0.3),
        Offset(0.3, 0.0),
        Offset(0.7, 0.0),
        Offset(1.0, 0.3),
        Offset(0.8, 0.8),
        Offset(1.0, 1.3),
        Offset(0.7, 1.6),
        Offset(0.3, 1.6),
        Offset(0.0, 1.3),
        Offset(0.2, 1.3),
        Offset(0.3, 1.4),
        Offset(0.7, 1.4),
        Offset(0.8, 1.2),
        Offset(0.6, 0.9),
        Offset(0.4, 0.9),
        Offset(0.6, 0.7),
        Offset(0.8, 0.4),
        Offset(0.7, 0.2),
        Offset(0.3, 0.2),
        Offset(0.2, 0.3),
        Offset(0.0, 0.3),
      ],
    ],
    '4': [
      [
        Offset(0.7, 1.6),
        Offset(0.7, 0.0),
        Offset(1.0, 0.0),
        Offset(1.0, 1.6),
        Offset(0.7, 1.6),
      ],
      [
        Offset(0.7, 0.0),
        Offset(0.0, 1.0),
        Offset(0.0, 1.2),
        Offset(0.7, 1.2),
        Offset(0.7, 1.0),
        Offset(0.2, 1.0),
        Offset(0.7, 0.2),
        Offset(0.7, 0.0),
      ],
    ],
    '5': [
      [
        Offset(1.0, 0.0),
        Offset(0.1, 0.0),
        Offset(0.1, 0.7),
        Offset(0.7, 0.7),
        Offset(1.0, 1.0),
        Offset(1.0, 1.3),
        Offset(0.7, 1.6),
        Offset(0.1, 1.6),
        Offset(0.1, 1.4),
        Offset(0.7, 1.4),
        Offset(0.8, 1.2),
        Offset(0.8, 1.0),
        Offset(0.6, 0.9),
        Offset(0.0, 0.9),
        Offset(0.0, 0.2),
        Offset(1.0, 0.2),
        Offset(1.0, 0.0),
      ],
    ],
    '6': [
      [
        Offset(0.9, 0.2),
        Offset(0.7, 0.0),
        Offset(0.3, 0.0),
        Offset(0.0, 0.3),
        Offset(0.0, 1.3),
        Offset(0.3, 1.6),
        Offset(0.7, 1.6),
        Offset(1.0, 1.3),
        Offset(1.0, 1.0),
        Offset(0.7, 0.7),
        Offset(0.0, 0.7),
        Offset(0.0, 0.3),
        Offset(0.2, 0.3),
        Offset(0.2, 0.6),
        Offset(0.7, 0.6),
        Offset(0.8, 0.8),
        Offset(0.8, 1.2),
        Offset(0.7, 1.4),
        Offset(0.3, 1.4),
        Offset(0.2, 1.2),
        Offset(0.2, 0.9),
        Offset(0.4, 0.7),
        Offset(0.7, 0.2),
        Offset(0.9, 0.2),
      ],
    ],
    '7': [
      [
        Offset(0.0, 0.0),
        Offset(1.0, 0.0),
        Offset(0.3, 1.6),
        Offset(0.1, 1.6),
        Offset(0.8, 0.2),
        Offset(0.0, 0.2),
        Offset(0.0, 0.0),
      ],
    ],
    '8': [
      [
        Offset(0.3, 0.0),
        Offset(0.7, 0.0),
        Offset(1.0, 0.3),
        Offset(0.8, 0.8),
        Offset(1.0, 1.3),
        Offset(0.7, 1.6),
        Offset(0.3, 1.6),
        Offset(0.0, 1.3),
        Offset(0.2, 0.8),
        Offset(0.0, 0.3),
        Offset(0.3, 0.0),
      ],
      [
        Offset(0.3, 0.2),
        Offset(0.7, 0.2),
        Offset(0.8, 0.4),
        Offset(0.6, 0.7),
        Offset(0.4, 0.7),
        Offset(0.2, 0.4),
        Offset(0.3, 0.2),
      ],
      [
        Offset(0.4, 0.9),
        Offset(0.6, 0.9),
        Offset(0.8, 1.2),
        Offset(0.7, 1.4),
        Offset(0.3, 1.4),
        Offset(0.2, 1.2),
        Offset(0.4, 0.9),
      ],
    ],
    '9': [
      [
        Offset(0.1, 1.4),
        Offset(0.3, 1.6),
        Offset(0.7, 1.6),
        Offset(1.0, 1.3),
        Offset(1.0, 0.3),
        Offset(0.7, 0.0),
        Offset(0.3, 0.0),
        Offset(0.0, 0.3),
        Offset(0.0, 0.6),
        Offset(0.3, 0.9),
        Offset(1.0, 0.9),
        Offset(1.0, 1.3),
        Offset(0.8, 1.3),
        Offset(0.8, 1.0),
        Offset(0.3, 1.0),
        Offset(0.2, 0.8),
        Offset(0.2, 0.4),
        Offset(0.3, 0.2),
        Offset(0.7, 0.2),
        Offset(0.8, 0.4),
        Offset(0.8, 0.7),
        Offset(0.6, 0.9),
        Offset(0.3, 1.4),
        Offset(0.1, 1.4),
      ],
    ],
    '-': [
      [
        Offset(0.1, 0.7),
        Offset(0.9, 0.7),
        Offset(0.9, 0.9),
        Offset(0.1, 0.9),
        Offset(0.1, 0.7),
      ],
    ],
    ' ': [],
  };

  static final Map<String, List<List<Offset>>> _cleanCutoutGlyphs = {
    ..._stencilGlyphs,
    'O': [
      [
        Offset(0.3, 0.0),
        Offset(0.7, 0.0),
        Offset(1.0, 0.3),
        Offset(1.0, 1.3),
        Offset(0.7, 1.6),
        Offset(0.3, 1.6),
        Offset(0.0, 1.3),
        Offset(0.0, 0.3),
        Offset(0.3, 0.0),
      ],
      [
        Offset(0.28, 0.28),
        Offset(0.72, 0.28),
        Offset(0.82, 0.42),
        Offset(0.82, 1.18),
        Offset(0.72, 1.32),
        Offset(0.28, 1.32),
        Offset(0.18, 1.18),
        Offset(0.18, 0.42),
        Offset(0.28, 0.28),
      ],
    ],
    '0': [
      [
        Offset(0.3, 0.0),
        Offset(0.7, 0.0),
        Offset(1.0, 0.3),
        Offset(1.0, 1.3),
        Offset(0.7, 1.6),
        Offset(0.3, 1.6),
        Offset(0.0, 1.3),
        Offset(0.0, 0.3),
        Offset(0.3, 0.0),
      ],
      [
        Offset(0.28, 0.28),
        Offset(0.72, 0.28),
        Offset(0.82, 0.42),
        Offset(0.82, 1.18),
        Offset(0.72, 1.32),
        Offset(0.28, 1.32),
        Offset(0.18, 1.18),
        Offset(0.18, 0.42),
        Offset(0.28, 0.28),
      ],
    ],
    'Q': [
      [
        Offset(0.3, 0.0),
        Offset(0.7, 0.0),
        Offset(1.0, 0.3),
        Offset(1.0, 1.3),
        Offset(0.7, 1.6),
        Offset(0.3, 1.6),
        Offset(0.0, 1.3),
        Offset(0.0, 0.3),
        Offset(0.3, 0.0),
      ],
      [
        Offset(0.28, 0.28),
        Offset(0.72, 0.28),
        Offset(0.82, 0.42),
        Offset(0.82, 1.18),
        Offset(0.72, 1.32),
        Offset(0.28, 1.32),
        Offset(0.18, 1.18),
        Offset(0.18, 0.42),
        Offset(0.28, 0.28),
      ],
      [Offset(0.58, 1.06), Offset(0.98, 1.58)],
    ],
  };



  static bool supports({
    required CutTextOverlayTransport transport,
    required List<int> rawBytes,
  }) {
    switch (transport) {
      case CutTextOverlayTransport.sunshineSjc:
        return CutFileTransformer.isSjcBytes(rawBytes);
      case CutTextOverlayTransport.dqPlt:
        return CutFileTransformer.isPltBytes(rawBytes);
      case CutTextOverlayTransport.dqSjm:
        return CutFileTransformer.supportsEditableSjmBytes(rawBytes);
    }
  }


  static CutPathData generatePreviewData({
    required CutPathData baseData,
    required CutTextOverlaySpec spec,
    required CutTextOverlayTransport transport,
    bool flipX = false,
  }) {
    if (transport == CutTextOverlayTransport.sunshineSjc) {
      return SunshineTextOverlayService.generatePreviewData(
        baseData: baseData,
        spec: spec,
        flipX: flipX,
      );
    }

    final normalizedText = TextOverlayFonts.normalizeText(
      spec.text,
      fontFamily: spec.fontFamily,
    );
    if (normalizedText.isEmpty) {
      throw const FormatException('text_overlay_error_empty');
    }

    final normalizedSpec = spec.copyWith(text: normalizedText);

    final overlayPolylines = _buildTextPolylines(
      baseData: baseData,
      spec: normalizedSpec,
      flipX: flipX,
      isSjm: false, // calculatePreview uses standard logic, UI rotates later
    );
    
    if (overlayPolylines.isEmpty) {
      throw const FormatException('text_overlay_error_empty');
    }

    return _calculateBounds(
      overlayPolylines
          .expand((polyline) => polyline)
          .toList(growable: false),
      _overlayDrawFlags(overlayPolylines),
    );
  }

  static CutTextOverlayBuildResult build({
    required CutPathData baseData,
    required CutTextOverlaySpec spec,
    required CutTextOverlayTransport transport,
    required int? maxWidth,
    List<int>? preparedBytes,
    bool flipX = false,
  }) {
    if (transport == CutTextOverlayTransport.sunshineSjc) {
      return SunshineTextOverlayService.build(
        baseData: baseData,
        spec: spec,
        maxWidth: maxWidth,
        preparedBytes: preparedBytes,
        flipX: flipX,
      );
    }

    final normalizedText = TextOverlayFonts.normalizeText(
      spec.text,
      fontFamily: spec.fontFamily,
    );
    if (normalizedText.isEmpty) {
      throw const FormatException('text_overlay_error_empty');
    }

    final normalizedSpec = spec.copyWith(text: normalizedText);

    // For DQ SJM files: baseData coordinates are stored as (Y,X) internally.
    // We need to swap them to (X,Y) for correct text layout calculation,
    // then swap the result back to (Y,X) for the machine.
    final overlayPolylinesPreview = _buildTextPolylines(
      baseData: baseData,
      spec: normalizedSpec,
      flipX: false,
      isSjm: transport == CutTextOverlayTransport.dqSjm,
    );
    if (overlayPolylinesPreview.isEmpty) {
      throw const FormatException('text_overlay_error_empty');
    }

    final overlayPolylinesMachine = _buildTextPolylines(
      baseData: baseData,
      spec: normalizedSpec.copyWith(flipHorizontally: !normalizedSpec.flipHorizontally),
      flipX: false,
      isSjm: transport == CutTextOverlayTransport.dqSjm,
    );

    final overlayPreviewData = _calculateBounds(
      overlayPolylinesPreview
          .expand((polyline) => polyline)
          .toList(growable: false),
      _overlayDrawFlags(overlayPolylinesPreview),
    );
    final mergedPreview = _mergePathData(baseData, overlayPolylinesPreview);

    final bytes = switch (transport) {
      CutTextOverlayTransport.sunshineSjc =>
        preparedBytes != null && preparedBytes.isNotEmpty && CutFileTransformer.isSjcBytes(preparedBytes)
            ? _appendOverlayToSunshineSjc(
                preparedBytes: preparedBytes,
                overlayPolylines: overlayPolylinesMachine,
                maxWidth: maxWidth,
                spec: normalizedSpec,
                swapCoordinates: flipX,
              )
            : _serializeSunshineSjc(mergedPreview, maxWidth: maxWidth),
      CutTextOverlayTransport.dqPlt =>
        preparedBytes != null && preparedBytes.isNotEmpty
            ? _appendOverlayToPlt(
                preparedBytes: preparedBytes,
                overlayPolylines: overlayPolylinesMachine,
              )
            : _serializePlt(_mergePathData(baseData, overlayPolylinesMachine)),
      CutTextOverlayTransport.dqSjm =>
        preparedBytes != null && preparedBytes.isNotEmpty && CutFileTransformer.isSjmBytes(preparedBytes)
            ? DqSjmTextOverlay.appendOverlay(
                preparedBytes: preparedBytes,
                overlayPolylines: overlayPolylinesMachine,
              )
            : _serializeDqSjm(_mergePathData(baseData, overlayPolylinesMachine)),
    };

    return CutTextOverlayBuildResult(
      previewData: mergedPreview,
      overlayPreviewData: overlayPreviewData,
      bytes: bytes,
      normalizedText: normalizedText,
      transport: transport,
    );
  }

  static List<int> serializePlt(CutPathData data) => _serializePlt(data);
  static List<int> serializeDqSjm(CutPathData data, {String? seed}) =>
      _serializeDqSjm(data, seed: seed);
  static List<int> serializeSunshineSjc(
    CutPathData data, {
    int? maxWidth,
    List<String>? mapping,
  }) => _serializeSunshineSjc(data, maxWidth: maxWidth, mapping: mapping);

  static List<List<Offset>> _buildTextPolylines({
    required CutPathData baseData,
    required CutTextOverlaySpec spec,
    required bool flipX,
    bool isSjm = false,
  }) {
    final text = spec.text;
    final fontProfile =
        TextOverlayFonts.registry[spec.fontFamily] ?? TextOverlayFonts.registry['AdobeGothic']!;
    
    // We build the text around a local origin (0,0) horizontally
    // Standard unscaled glyph height
    final baseGlyphHeight = 40.0;
    final baseGlyphWidth = baseGlyphHeight * 0.7 * fontProfile.widthScale;
    final baseGlyphGap = baseGlyphWidth * 0.22 * fontProfile.gapScale;
    final baseEffectiveGlyphHeight = baseGlyphHeight * fontProfile.heightScale;
    
    final totalWidth = (text.length * baseGlyphWidth) + (max(0, text.length - 1) * baseGlyphGap);
    final totalHeight = baseEffectiveGlyphHeight;
    
    // Start drawing from the local origin (-totalWidth/2, -totalHeight/2)
    double startX = -totalWidth / 2.0;
    final double startY = -totalHeight / 2.0;
    
    final polylines = <List<Offset>>[];
    
    for (final char in text.split('')) {
      polylines.addAll(
        _buildGlyphPolylines(
          char: char,
          fontFamily: spec.fontFamily,
          startX: startX,
          startY: startY,
          glyphWidth: baseGlyphWidth,
          glyphHeight: baseEffectiveGlyphHeight,
        ),
      );
      startX += baseGlyphWidth + baseGlyphGap;
    }
    
    return _transformPolylines(
      polylines,
      baseData: baseData,
      spec: spec,
      flipX: flipX,
      isSjm: isSjm,
    );
  }

  static List<List<Offset>> _buildGlyphPolylines({
    required String char,
    required String fontFamily,
    required double startX,
    required double startY,
    required double glyphWidth,
    required double glyphHeight,
  }) {
    final fontProfile =
        TextOverlayFonts.registry[fontFamily] ?? TextOverlayFonts.registry['AdobeGothic']!;
    final glyphs = fontProfile.glyphs;
    final glyphPolylines = glyphs[char] ?? const <List<Offset>>[];
    final polylines = <List<Offset>>[];

    for (final glyph in glyphPolylines) {
      if (glyph.length < 2) continue;
      polylines.add([
        for (final point in glyph)
          () {
            double py = point.dy;
            if (fontProfile.invertY) py = fontProfile.baselineHeight - py;
            final normalizedY = py / fontProfile.baselineHeight;
            final shearedX =
                point.dx + ((1 - normalizedY) * fontProfile.shearX);
            return Offset(
              startX + (shearedX * glyphWidth),
              startY + (normalizedY * glyphHeight),
            );
          }(),
      ]);
    }

    return polylines;
  }

  static List<List<Offset>> _transformPolylines(
    List<List<Offset>> polylines, {
    required CutPathData baseData,
    required CutTextOverlaySpec spec,
    required bool flipX,
    bool isSjm = false,
  }) {
    if (polylines.isEmpty) return polylines;

    // Transformations are relative to the text's local center (0,0)
    // Then we translate to the center of the baseData + spec.dx, spec.dy
    final double baseCenterX = (baseData.minX + baseData.maxX) / 2.0;
    final double baseCenterY = (baseData.minY + baseData.maxY) / 2.0;
    
    double targetX = baseCenterX;
    double targetY = baseCenterY;
    double rotation = spec.rotation;

    if (isSjm) {
      targetX += spec.dx;
      targetY += spec.dy;
    } else {
      targetX += spec.dx;
      targetY += spec.dy;
    }

    final double cosR = cos(rotation);
    final double sinR = sin(rotation);

    var transformed = polylines.map((polyline) {
      return polyline.map((point) {
        // 1. Flip horizontally if needed (user spec or machine requires it)
        final bool shouldFlipX = spec.flipHorizontally || flipX;
        double px = shouldFlipX ? -point.dx : point.dx;
        double py = point.dy;

        // 2. Scale
        px *= spec.scale;
        py *= spec.scale;

        // 3. Rotate around origin
        final double rx = px * cosR - py * sinR;
        double ry = px * sinR + py * cosR;

        // 4. Translate to target position
        return Offset(rx + targetX, ry + targetY);
      }).toList(growable: false);
    }).toList(growable: false);

    // Bounding box clamp to prevent exceeding machine limits (baseData bounds)
    double shiftedMinX = transformed.first.first.dx;
    double shiftedMaxX = transformed.first.first.dx;
    double shiftedMinY = transformed.first.first.dy;
    double shiftedMaxY = transformed.first.first.dy;
    for (final polyline in transformed) {
      for (final point in polyline) {
        if (point.dx < shiftedMinX) shiftedMinX = point.dx;
        if (point.dx > shiftedMaxX) shiftedMaxX = point.dx;
        if (point.dy < shiftedMinY) shiftedMinY = point.dy;
        if (point.dy > shiftedMaxY) shiftedMaxY = point.dy;
      }
    }

    double clampDx = 0;
    double clampDy = 0;
    if (shiftedMinX < baseData.minX) {
      clampDx = baseData.minX - shiftedMinX;
    } else if (shiftedMaxX > baseData.maxX) {
      clampDx = baseData.maxX - shiftedMaxX;
    }
    if (shiftedMinY < baseData.minY) {
      clampDy = baseData.minY - shiftedMinY;
    } else if (shiftedMaxY > baseData.maxY) {
      clampDy = baseData.maxY - shiftedMaxY;
    }

    // Apply clamp if it drifted outside
    if (clampDx != 0 || clampDy != 0) {
      transformed = transformed.map((polyline) {
        return polyline.map((point) => Offset(point.dx + clampDx, point.dy + clampDy)).toList(growable: false);
      }).toList(growable: false);
    }

    return transformed;
  }

  static CutPathData _mergePathData(
    CutPathData baseData,
    List<List<Offset>> overlayPolylines,
  ) {
    final points = List<Offset>.from(baseData.points);
    final drawFlags = List<bool>.from(baseData.drawFlags);

    for (final polyline in overlayPolylines) {
      for (int i = 0; i < polyline.length; i++) {
        points.add(polyline[i]);
        drawFlags.add(i != 0);
      }
    }

    return _calculateBounds(points, drawFlags);
  }

  static CutPathData _calculateBounds(
    List<Offset> points,
    List<bool> drawFlags,
  ) {
    double minX = points.first.dx;
    double maxX = points.first.dx;
    double minY = points.first.dy;
    double maxY = points.first.dy;

    for (final point in points) {
      if (point.dx < minX) minX = point.dx;
      if (point.dx > maxX) maxX = point.dx;
      if (point.dy < minY) minY = point.dy;
      if (point.dy > maxY) maxY = point.dy;
    }

    return CutPathData(
      points: points,
      drawFlags: drawFlags,
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
    );
  }

  static List<bool> _overlayDrawFlags(List<List<Offset>> overlayPolylines) {
    final flags = <bool>[];
    for (final polyline in overlayPolylines) {
      for (int i = 0; i < polyline.length; i++) {
        flags.add(i != 0);
      }
    }
    return flags;
  }

  static List<int> _serializePlt(CutPathData data) {
    final normalized = _normalizePositivePoints(data);
    final buffer = StringBuffer('IN;');

    for (int i = 0; i < normalized.points.length; i++) {
      final point = normalized.points[i];
      final x = point.dx.round();
      final y = point.dy.round();
      if (i == 0 || !normalized.drawFlags[i]) {
        buffer.write('PU$x,$y;');
      } else {
        buffer.write('PD$x,$y;');
      }
    }

    buffer.write('PU0,0;');
    return latin1.encode(buffer.toString());
  }

  static List<int> _appendOverlayToPlt({
    required List<int> preparedBytes,
    required List<List<Offset>> overlayPolylines,
  }) {
    final overlayTokens = _buildPltOverlayTokens(overlayPolylines);
    if (overlayTokens.isEmpty) {
      return preparedBytes;
    }

    final base = latin1.decode(preparedBytes).trimRight();
    final rebuilt = '$base$overlayTokens';
    return latin1.encode(rebuilt);
  }

  static String _buildPltOverlayTokens(List<List<Offset>> overlayPolylines) {
    final buffer = StringBuffer();
    for (final polyline in overlayPolylines) {
      for (int i = 0; i < polyline.length; i++) {
        final point = polyline[i];
        final x = point.dx.round();
        final y = point.dy.round();
        if (i == 0) {
          buffer.write('PU$x,$y;');
          buffer.write('PD$x,$y;');
        } else {
          buffer.write('PD$x,$y;');
        }
      }
    }
    buffer.write('PU0,0;');
    return buffer.toString();
  }

  static List<int> _serializeSunshineSjc(
    CutPathData data, {
    required int? maxWidth,
    List<String>? mapping,
  }) {
    final normalized = _normalizePositivePoints(data);
    final String mappingStr = mapping != null
        ? mapping.join('')
        : _sunshineMapping;
    final encodedZero = mapping != null
        ? CutFileTransformer.encodeWithDigitMapping('0', mapping)
        : _encodeSunshineNumber('0');
    final encodedForty = mapping != null
        ? CutFileTransformer.encodeWithDigitMapping('40', mapping)
        : _encodeSunshineNumber('40');
    final width = max(0, normalized.maxX.round() - normalized.minX.round());
    final height = max(0, normalized.maxY.round() - normalized.minY.round());

    final buffer = StringBuffer('IN WSJP=$mappingStr ');
    if (maxWidth != null && maxWidth > 0 && maxWidth < 160) {
      buffer.write('FSIZE$height,$width;');
    }
    buffer.write('U$encodedZero,$encodedZero ');
    buffer.write('D$encodedZero,$encodedZero ');
    buffer.write('D$encodedZero,$encodedForty ');
    buffer.write('U$encodedZero,$encodedZero ');

    for (int i = 0; i < normalized.points.length; i++) {
      final point = normalized.points[i];
      final x = point.dx.round();
      final y = point.dy.round();
      final encodedX = mapping != null
          ? CutFileTransformer.encodeWithDigitMapping(x.toString(), mapping)
          : _encodeSunshineNumber(x.toString());
      final encodedY = mapping != null
          ? CutFileTransformer.encodeWithDigitMapping(y.toString(), mapping)
          : _encodeSunshineNumber(y.toString());
      if (i == 0 || !normalized.drawFlags[i]) {
        buffer.write('U$encodedX,$encodedY ');
      } else {
        buffer.write('D$encodedX,$encodedY ');
      }
    }

    buffer.write('U$encodedZero,$encodedZero @ ');
    return latin1.encode(buffer.toString());
  }

  static List<int> _appendOverlayToSunshineSjc({
    required List<int> preparedBytes,
    required List<List<Offset>> overlayPolylines,
    required int? maxWidth,
    required CutTextOverlaySpec spec,
    required bool swapCoordinates,
  }) {
    if (!CutFileTransformer.isSjcBytes(preparedBytes)) {
      return preparedBytes;
    }

    final text = latin1.decode(preparedBytes).trim();
    final mapping = CutFileTransformer.extractSjcEncodingMap(preparedBytes);
    if (mapping == null || mapping.length != 10) {
      return preparedBytes;
    }
    final encodedZero = CutFileTransformer.encodeWithDigitMapping('0', mapping);
    final suffix = 'U$encodedZero,$encodedZero @';
    if (!text.endsWith(suffix)) {
      return preparedBytes;
    }

    final overlayTokens = _buildSunshineOverlayTokens(
      overlayPolylines,
      spec: spec,
      mapping: mapping,
      swapCoordinates: swapCoordinates,
    );
    if (overlayTokens.isEmpty) {
      return preparedBytes;
    }

    final body = text.substring(0, text.length - suffix.length).trimRight();
    final rebuilt = '$body $overlayTokens $suffix ';
    return latin1.encode(rebuilt);
  }

  static String _buildSunshineOverlayTokens(
    List<List<Offset>> overlayPolylines, {
    required CutTextOverlaySpec spec,
    required List<String> mapping,
    required bool swapCoordinates,
  }) {
    final buffer = StringBuffer();

    for (final polyline in overlayPolylines) {
      if (polyline.length < 2) continue;
      for (int i = 0; i < polyline.length; i++) {
        final point = polyline[i];
        final x = point.dx.round();
        final y = point.dy.round();
        final first = swapCoordinates ? y : x;
        final second = swapCoordinates ? x : y;
        final encodedX = CutFileTransformer.encodeWithDigitMapping(
          first.toString(),
          mapping,
        );
        final encodedY = CutFileTransformer.encodeWithDigitMapping(
          second.toString(),
          mapping,
        );
        if (i == 0) {
          buffer.write('U$encodedX,$encodedY ');
        } else {
          buffer.write('D$encodedX,$encodedY ');
        }
      }
    }
    return buffer.toString().trim();
  }

  static List<int> _serializeDqSjm(CutPathData data, {String? seed}) {
    final normalized = _normalizePositivePoints(data);
    final activeSeed = seed ?? _dqSjmSeed;
    final keyMap = SjmCipher.generateKeyMap(activeSeed)!;
    final encodedZero = SjmCipher.encrypt(keyMap, '0');
    final width = max(0, normalized.maxX.round() - normalized.minX.round());
    final height = max(0, normalized.maxY.round() - normalized.minY.round());

    final buffer = StringBuffer('IN SJM=$activeSeed FSIZE$height,$width;');
    
    for (int i = 0; i < normalized.points.length; i++) {
      final point = normalized.points[i];
      final x = point.dx.round();
      final y = point.dy.round();
      final encodedX = SjmCipher.encrypt(keyMap, x.toString());
      final encodedY = SjmCipher.encrypt(keyMap, y.toString());
      if (i == 0 || !normalized.drawFlags[i]) {
        buffer.write('U$encodedX,$encodedY ');
      } else {
        buffer.write('D$encodedX,$encodedY ');
      }
    }

    buffer.write('U$encodedZero,$encodedZero @ ');
    return latin1.encode(buffer.toString());
  }

  static _NormalizedPathData _normalizePositivePoints(CutPathData data) {
    final shiftX = data.minX < 0 ? -data.minX : 0.0;
    final shiftY = data.minY < 0 ? -data.minY : 0.0;

    final points = data.points
        .map((point) => Offset(point.dx + shiftX, point.dy + shiftY))
        .toList(growable: false);

    return _NormalizedPathData(
      points: points,
      drawFlags: List<bool>.from(data.drawFlags),
      minX: data.minX + shiftX,
      maxX: data.maxX + shiftX,
      minY: data.minY + shiftY,
      maxY: data.maxY + shiftY,
    );
  }

  static String _encodeSunshineNumber(String value) {
    final buffer = StringBuffer();
    for (final char in value.split('')) {
      buffer.write(_sunshineDigitMap[char] ?? char);
    }
    return buffer.toString();
  }

  static bool _isPlainNumericSjmPayload(String text) {
    final cleaned = text
        .replaceAll('IN ', '')
        .replaceAll('@', '')
        .replaceAll(';', ' ')
        .trim();
    if (!cleaned.contains('SJM=')) {
      return false;
    }

    final tokens = cleaned
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    int coordinateCount = 0;

    for (final token in tokens) {
      if (token == 'IN' ||
          token.contains('SJM=') ||
          token.startsWith('FSIZE')) {
        continue;
      }

      final parts = token.split(',');
      if (parts.length != 2) continue;
      final left = _stripCommandPrefix(parts[0]);
      final right = _stripCommandPrefix(parts[1]);
      if (_isAsciiInteger(left) && _isAsciiInteger(right)) {
        coordinateCount++;
        continue;
      }
      return false;
    }

    return coordinateCount > 0;
  }

  static String _stripCommandPrefix(String value) {
    if (value.isEmpty) return value;
    final first = value[0];
    if (first == 'U' || first == 'D') {
      return value.substring(1);
    }
    return value;
  }

  static bool _isAsciiInteger(String value) {
    if (value.isEmpty) return false;
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      if (char == '-') continue;
      if (int.tryParse(char) == null) {
        return false;
      }
    }
    return true;
  }
}

class _NormalizedPathData {
  const _NormalizedPathData({
    required this.points,
    required this.drawFlags,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });

  final List<Offset> points;
  final List<bool> drawFlags;
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;
}
