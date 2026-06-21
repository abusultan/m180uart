import 'dart:convert';
import 'dart:ui';
import 'cut_file_transformer.dart';
import 'sjm_cipher.dart';

class DqSjmTextOverlay {
  static List<int> appendOverlay({
    required List<int> preparedBytes,
    required List<List<Offset>> overlayPolylines,
  }) {
    if (!CutFileTransformer.isSjmBytes(preparedBytes)) {
      return preparedBytes;
    }

    final text = latin1.decode(preparedBytes).trim();
    final plainNumeric = _isPlainNumericSjmPayload(text);

    // Extract seed and generate dynamic key map
    final seed = SjmCipher.extractSeed(text);
    final keyMap = seed != null ? SjmCipher.generateKeyMap(seed) : null;

    final zero = (plainNumeric || keyMap == null)
        ? '0'
        : SjmCipher.encrypt(keyMap, '0');

    String body = text;
    if (body.contains('@')) {
      body = body.substring(0, body.lastIndexOf('@')).trimRight();
    }
    
    final endMarker = 'U$zero,$zero';
    if (body.endsWith(endMarker)) {
      body = body.substring(0, body.length - endMarker.length).trimRight();
    }

    final overlayTokens = (plainNumeric || keyMap == null)
        ? _buildPlainDqSjmOverlayTokens(overlayPolylines)
        : _buildEncodedDqSjmOverlayTokens(overlayPolylines, keyMap);
    if (overlayTokens.isEmpty) {
      return preparedBytes;
    }

    final rebuilt = '$body $overlayTokens U$zero,$zero @ ';
    return latin1.encode(rebuilt);
  }

  static bool _isPlainNumericSjmPayload(String text) {
    return text.contains(RegExp(r'[UD]-?\d+,-?\d+'));
  }

  static String _buildPlainDqSjmOverlayTokens(
    List<List<Offset>> overlayPolylines,
  ) {
    final buffer = StringBuffer();
    for (final polyline in overlayPolylines) {
      for (int i = 0; i < polyline.length; i++) {
        final point = polyline[i];
        final x = point.dx.round();
        final y = point.dy.round();
        if (i == 0) {
          buffer.write('U$y,$x D$y,$x ');
        } else {
          buffer.write('D$y,$x ');
        }
      }
    }
    return buffer.toString().trim();
  }

  static String _buildEncodedDqSjmOverlayTokens(
    List<List<Offset>> overlayPolylines,
    List<String> keyMap,
  ) {
    final buffer = StringBuffer();
    for (final polyline in overlayPolylines) {
      for (int i = 0; i < polyline.length; i++) {
        final point = polyline[i];
        final x = point.dx.round();
        final y = point.dy.round();
        final encodedX = SjmCipher.encrypt(keyMap, x.toString());
        final encodedY = SjmCipher.encrypt(keyMap, y.toString());
        if (i == 0) {
          buffer.write('U$encodedY,$encodedX D$encodedY,$encodedX ');
        } else {
          buffer.write('D$encodedY,$encodedX ');
        }
      }
    }
    return buffer.toString().trim();
  }
}
