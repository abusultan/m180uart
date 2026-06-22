import 'package:flutter_project/core/sjm_cipher.dart';
import 'package:flutter_project/core/text_overlay_fonts.dart';
import 'package:flutter_project/core/cut_file_transformer.dart';
import 'package:flutter_project/core/cut_text_overlay_service.dart';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

class SunshineTextOverlayService {
  static const String _sunshineMapping = '6240092912';

  static CutPathData generatePreviewData({
    required CutPathData baseData,
    required CutTextOverlaySpec spec,
    bool flipX = false,
  }) {
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
    required int? maxWidth,
    List<int>? preparedBytes,
    bool flipX = false,
  }) {
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
    );
    if (overlayPolylines.isEmpty) {
      throw const FormatException('text_overlay_error_empty');
    }

    final overlayPreviewData = _calculateBounds(
      overlayPolylines
          .expand((polyline) => polyline)
          .toList(growable: false),
      _overlayDrawFlags(overlayPolylines),
    );
    
    final mergedPreview = _mergePathData(baseData, overlayPolylines);

    final bytes = preparedBytes != null
        ? _appendOverlayToSunshineSjc(
            preparedBytes: preparedBytes,
            overlayPolylines: overlayPolylines,
            maxWidth: maxWidth,
            spec: normalizedSpec,
            swapCoordinates: flipX,
          )
        : <int>[];

    return CutTextOverlayBuildResult(
      previewData: mergedPreview,
      overlayPreviewData: overlayPreviewData,
      bytes: bytes,
      normalizedText: normalizedText,
      transport: CutTextOverlayTransport.sunshineSjc,
    );
  }

  static List<List<Offset>> _buildTextPolylines({
    required CutPathData baseData,
    required CutTextOverlaySpec spec,
    required bool flipX,
  }) {
    final text = spec.text;
    final fontProfile =
        TextOverlayFonts.registry[spec.fontFamily] ?? TextOverlayFonts.registry['AdobeGothic']!;
    
    final baseGlyphHeight = 120.0;
    final baseGlyphWidth = baseGlyphHeight * 0.7 * fontProfile.widthScale;
    final baseGlyphGap = baseGlyphWidth * 0.22 * fontProfile.gapScale;
    final baseEffectiveGlyphHeight = baseGlyphHeight * fontProfile.heightScale;
    
    final totalWidth = (text.length * baseGlyphWidth) + (max(0, text.length - 1) * baseGlyphGap);
    final totalHeight = baseEffectiveGlyphHeight;
    
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
  }) {
    if (polylines.isEmpty) return polylines;

    final double baseCenterX = (baseData.minX + baseData.maxX) / 2.0;
    final double baseCenterY = (baseData.minY + baseData.maxY) / 2.0;
    
    final double targetX = baseCenterX + spec.dx;
    final double targetY = baseCenterY + spec.dy;

    final double cosR = cos(spec.rotation);
    final double sinR = sin(spec.rotation);

    var transformed = polylines.map((polyline) {
        return polyline.map((point) {
        final bool shouldFlipX = spec.flipHorizontally || flipX;
        double px = shouldFlipX ? -point.dx : point.dx;
        double py = point.dy;
        px *= spec.scale;
        py *= spec.scale;
        final double rx = px * cosR - py * sinR;
        final double ry = px * sinR + py * cosR;
        return Offset(rx + targetX, ry + targetY);
      }).toList(growable: false);
    }).toList(growable: false);

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
      minY: minY,
      maxX: maxX,
      maxY: maxY,
    );
  }

  static List<bool> _overlayDrawFlags(List<List<Offset>> polylines) {
    return polylines
        .expand(
          (polyline) => List<bool>.generate(polyline.length, (i) => i != 0),
        )
        .toList(growable: false);
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
          buffer.write('D$encodedX,$encodedY ');
        } else {
          buffer.write('D$encodedX,$encodedY ');
        }
      }
    }
    return buffer.toString().trim();
  }
}
