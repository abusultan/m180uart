import 'text_overlay_fonts.dart';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'cut_file_transformer.dart';
import 'sunshine_text_overlay.dart';

enum CutTextOverlayDirection { horizontal, vertical }

enum CutTextOverlayPlacement { start, center, end }

enum CutTextOverlaySize { small, medium, large }

enum CutTextOverlayTransport { sunshineSjc, dqPlt, dqSjm }

class CutTextOverlaySpec {
  const CutTextOverlaySpec({
    required this.text,
    this.dx = 0,
    this.dy = 0,
    this.scale = 15.0,
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
  static bool supports({
    required CutTextOverlayTransport transport,
    required List<int> rawBytes,
  }) {
    if (transport == CutTextOverlayTransport.sunshineSjc) {
      return CutFileTransformer.isSjcBytes(rawBytes);
    }
    return false;
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
    throw UnimplementedError('Only Sunshine Sjc text overlay is supported in this stage.');
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
    throw UnimplementedError('Only Sunshine Sjc text overlay is supported in this stage.');
  }
}
