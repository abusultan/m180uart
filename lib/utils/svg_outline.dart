import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:xml/xml.dart' as xml;

const String _previewStrokeColor = '#1C1C1C';
const double _previewStrokeWidthFallback = 2.6;

double _parsePositive(String? value) {
  if (value == null) return 0;
  final cleaned = value.replaceAll(RegExp(r'[^0-9.+-]'), '');
  return double.tryParse(cleaned) ?? 0;
}

String _resolveStrokeWidth(xml.XmlElement root) {
  final viewBox = root.getAttribute('viewBox');
  if (viewBox != null && viewBox.trim().isNotEmpty) {
    final parts = viewBox
        .trim()
        .split(RegExp(r'[\s,]+'))
        .map((e) => double.tryParse(e))
        .toList();
    if (parts.length == 4 &&
        parts[2] != null &&
        parts[3] != null &&
        parts[2]! > 0 &&
        parts[3]! > 0) {
      final maxDim = math.max(parts[2]!, parts[3]!);
      final dynamicWidth = (maxDim / 120.0).clamp(2.2, 18.0);
      return dynamicWidth.toStringAsFixed(2);
    }
  }

  final width = _parsePositive(root.getAttribute('width'));
  final height = _parsePositive(root.getAttribute('height'));
  if (width > 0 && height > 0) {
    final maxDim = math.max(width, height);
    final dynamicWidth = (maxDim / 120.0).clamp(2.2, 18.0);
    return dynamicWidth.toStringAsFixed(2);
  }

  return _previewStrokeWidthFallback.toStringAsFixed(2);
}

String sanitizeSvg(String svg) {
  String result = svg;
  result = result.replaceAll('\uFEFF', '');
  result = result.replaceAll('\u0000', '');
  result = result.replaceAll(RegExp(r'<\?xml[^>]*\?>'), '');
  result = result.replaceAll(RegExp(r'<!DOCTYPE[^>]*>'), '');
  result = result.replaceAll(
    RegExp(r'<metadata[^>]*>.*?</metadata>', dotAll: true),
    '',
  );
  result = result.replaceAll(
    RegExp(r'<script[^>]*>.*?</script>', caseSensitive: false, dotAll: true),
    '',
  );
  return result;
}

String decodeSvgBytes(Uint8List bytes) {
  if (bytes.isEmpty) return '';

  if (bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
    try {
      final inflated = gzip.decode(bytes);
      return decodeSvgBytes(Uint8List.fromList(inflated));
    } catch (_) {}
  }

  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _decodeUtf16(bytes.sublist(2), littleEndian: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _decodeUtf16(bytes.sublist(2), littleEndian: false);
  }

  final sample = bytes.length < 64 ? bytes.length : 64;
  int zeroEven = 0;
  int zeroOdd = 0;
  for (int i = 0; i < sample; i++) {
    if (bytes[i] == 0) {
      if (i.isEven) {
        zeroEven++;
      } else {
        zeroOdd++;
      }
    }
  }
  if (zeroOdd > zeroEven * 2) {
    return _decodeUtf16(bytes, littleEndian: true);
  }
  if (zeroEven > zeroOdd * 2) {
    return _decodeUtf16(bytes, littleEndian: false);
  }

  return utf8.decode(bytes, allowMalformed: true);
}

String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
  final len = bytes.length - (bytes.length % 2);
  final codeUnits = <int>[];
  for (int i = 0; i < len; i += 2) {
    final unit = littleEndian
        ? (bytes[i] | (bytes[i + 1] << 8))
        : ((bytes[i] << 8) | bytes[i + 1]);
    codeUnits.add(unit);
  }
  return String.fromCharCodes(codeUnits);
}

String toOutlineSvg(String svgText) {
  try {
    final sanitized = sanitizeSvg(svgText);
    final doc = xml.XmlDocument.parse(sanitized);
    final root = doc.rootElement;
    final strokeWidth = _resolveStrokeWidth(root);

    final undesirable = [
      ...doc.findAllElements('style'),
      ...doc.findAllElements('script'),
      ...doc.findAllElements('metadata'),
      ...doc.findAllElements('rect').where((node) {
        final w = node.getAttribute('width');
        final h = node.getAttribute('height');
        return w == '100%' || w == '100' || h == '100%' || h == '100';
      }),
    ];
    for (final node in undesirable.toList()) {
      node.parent?.children.remove(node);
    }

    const shapeTags = [
      'path',
      'rect',
      'circle',
      'ellipse',
      'polyline',
      'polygon',
      'line',
    ];

    for (final node in doc.descendants.whereType<xml.XmlElement>()) {
      final name = node.name.local.toLowerCase();
      node.removeAttribute('style');
      node.removeAttribute('opacity');
      node.removeAttribute('fill-opacity');
      node.removeAttribute('stroke-opacity');

      if (shapeTags.contains(name)) {
        node.removeAttribute('fill');
        node.removeAttribute('stroke-width');
        node.setAttribute('fill', 'none');
        node.setAttribute('stroke', _previewStrokeColor);
        node.setAttribute('stroke-width', strokeWidth);
        node.setAttribute('vector-effect', 'non-scaling-stroke');
        node.setAttribute('stroke-linecap', 'round');
        node.setAttribute('stroke-linejoin', 'round');
        node.setAttribute('stroke-opacity', '1');
        node.setAttribute('display', 'block');
        node.setAttribute('visibility', 'visible');
      } else if (name == 'use') {
        node.setAttribute('fill', 'none');
        node.setAttribute('stroke', _previewStrokeColor);
        node.setAttribute('stroke-width', strokeWidth);
        node.setAttribute('vector-effect', 'non-scaling-stroke');
        node.setAttribute('stroke-linecap', 'round');
        node.setAttribute('stroke-linejoin', 'round');
        node.setAttribute('stroke-opacity', '1');
      } else if (['svg', 'g', 'defs', 'symbol'].contains(name)) {
        node.removeAttribute('fill');
        node.setAttribute('opacity', '1');
      }
    }

    if (root.name.local.toLowerCase() == 'svg') {
      root.setAttribute('fill', 'none');
      root.setAttribute('opacity', '1');
    }

    return doc.toXmlString();
  } catch (_) {
    String result = sanitizeSvg(svgText);
    result = result.replaceAll(
      RegExp(r'fill="[^"]*"', caseSensitive: false),
      'fill="none"',
    );
    result = result.replaceAll(
      RegExp(r'stroke="[^"]*"', caseSensitive: false),
      'stroke="$_previewStrokeColor"',
    );
    result = result.replaceAll(
      RegExp(r'stroke-width="[^"]*"', caseSensitive: false),
      'stroke-width="${_previewStrokeWidthFallback.toStringAsFixed(2)}"',
    );
    result = result.replaceAll(
      RegExp(r'style="[^"]*"', caseSensitive: false),
      '',
    );
    result = result.replaceAll(
      RegExp(r'opacity="[^"]*"', caseSensitive: false),
      'opacity="1"',
    );
    result = result.replaceAll(
      RegExp(r'fill-opacity="[^"]*"', caseSensitive: false),
      'fill-opacity="1"',
    );
    result = result.replaceAll(
      RegExp(r'stroke-opacity="[^"]*"', caseSensitive: false),
      'stroke-opacity="1"',
    );
    return result;
  }
}

String toOutlineSvgLight(String svgText) => toOutlineSvg(svgText);

String toOutlineSvgHeavy(String svgText) => toOutlineSvg(svgText);
