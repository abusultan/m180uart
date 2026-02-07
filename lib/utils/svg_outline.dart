import 'dart:convert';
import 'dart:typed_data';
import 'package:xml/xml.dart' as xml;

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
  return result;
}

String decodeSvgBytes(Uint8List bytes) {
  if (bytes.isEmpty) return '';
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

  // Heuristic: if many zeros in odd/even positions, treat as UTF-16
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

String toOutlineSvg(String svg) {
  String result = sanitizeSvg(svg);
  const overrideStyle =
      '<style>*{fill:none !important;stroke:black !important;stroke-width:3.5 !important;stroke-opacity:1 !important;}</style>';
  if (result.contains('</style>')) {
    result = result.replaceFirst('</style>', '</style>$overrideStyle');
  } else {
    result = result.replaceFirstMapped(
      RegExp(r'<svg\b[^>]*>'),
      (match) => '${match.group(0)}$overrideStyle',
    );
  }
  return result;
}

// Lighter transform for stricter SVG parsers (e.g. iOS).
String toOutlineSvgLight(String svg) {
  String result = sanitizeSvg(svg);
  const overrideStyle =
      '<style>*{fill:none !important;stroke:black !important;stroke-width:3.5 !important;stroke-opacity:1 !important;}</style>';
  if (result.contains('</style>')) {
    result = result.replaceFirst('</style>', '</style>$overrideStyle');
  } else {
    result = result.replaceFirstMapped(
      RegExp(r'<svg\b[^>]*>'),
      (match) => '${match.group(0)}$overrideStyle',
    );
  }
  return result;
}

String toOutlineSvgHeavy(String svg) {
  final cleaned = sanitizeSvg(svg);
  try {
    final doc = xml.XmlDocument.parse(cleaned);
    for (final node in doc.descendants.whereType<xml.XmlElement>()) {
      final name = node.name.local.toLowerCase();
      if (name == 'path' ||
          name == 'rect' ||
          name == 'circle' ||
          name == 'ellipse' ||
          name == 'polygon' ||
          name == 'polyline' ||
          name == 'line') {
        node.removeAttribute('fill');
        node.removeAttribute('stroke');
        node.removeAttribute('stroke-width');
        node.removeAttribute('fill-opacity');
        node.removeAttribute('stroke-opacity');
        node.removeAttribute('opacity');

        final styleAttr = node.getAttribute('style');
        if (styleAttr != null) {
          final cleanedStyle = styleAttr
              .replaceAll(RegExp(r'fill\s*:[^;]+;?'), '')
              .replaceAll(RegExp(r'stroke\s*:[^;]+;?'), '')
              .replaceAll(RegExp(r'stroke-width\s*:[^;]+;?'), '')
              .replaceAll(RegExp(r'fill-opacity\s*:[^;]+;?'), '')
              .replaceAll(RegExp(r'stroke-opacity\s*:[^;]+;?'), '')
              .replaceAll(RegExp(r'opacity\s*:[^;]+;?'), '')
              .replaceAll(RegExp(r'display\s*:[^;]+;?'), '')
              .replaceAll(RegExp(r'visibility\s*:[^;]+;?'), '');
          if (cleanedStyle.trim().isEmpty) {
            node.removeAttribute('style');
          } else {
            node.setAttribute('style', cleanedStyle);
          }
        }

        node.setAttribute('fill', 'none');
        node.setAttribute('stroke', 'black');
        node.setAttribute('stroke-width', '3.5');
        node.setAttribute('stroke-opacity', '1');
        node.setAttribute('fill-opacity', '1');
        node.setAttribute('opacity', '1');
      }
    }
    return doc.toXmlString(pretty: false);
  } catch (_) {
    // Fallback to light transform if XML parse fails.
    return toOutlineSvgLight(svg);
  }
}
