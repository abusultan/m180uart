import 'dart:typed_data';
import 'package:flutter/services.dart';

class SvgRenderer {
  static const MethodChannel _channel = MethodChannel('svg_renderer');

  static Future<Uint8List?> renderSvgToPng(
    String svg, {
    required int width,
    required int height,
  }) async {
    try {
      final bytes = await _channel.invokeMethod<Uint8List>('renderSvg', {
        'svg': svg,
        'width': width,
        'height': height,
      });
      return bytes;
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> renderSvgBytesToPng(
    Uint8List svgBytes, {
    required int width,
    required int height,
  }) async {
    try {
      final bytes = await _channel.invokeMethod<Uint8List>('renderSvgBytes', {
        'bytes': svgBytes,
        'width': width,
        'height': height,
      });
      return bytes;
    } catch (_) {
      return null;
    }
  }
}
