import 'dart:convert';
import 'dart:math';
import 'dart:ui';

class CutFileTransformer {
  static CutPathData? decodePathData(List<int> inputBytes) {
    String text;
    try {
      text = latin1.decode(inputBytes);
    } catch (_) {
      return null;
    }

    final trimmed = text.trim();
    if (!trimmed.contains('WSJP=')) return null;

    final normalized =
        trimmed.replaceAll('IN ', '').replaceAll(' @', '').trim();
    final parts = normalized.split(RegExp(r'\s+'));
    if (parts.isEmpty) return null;

    final header = parts.first;
    if (!header.contains('WSJP=')) return null;

    final mappingStr = header.replaceAll('WSJP=', '');
    final mapping = _buildMapping(mappingStr);
    if (mapping == null || mapping.length != 10) return null;

    final points = <Offset>[];
    final drawFlags = <bool>[];

    for (int i = 1; i < parts.length; i++) {
      final token = parts[i];
      final split = token.split(',');
      if (split.length != 2) continue;

      final xPart = split[0];
      final yPart = split[1];
      final draw = _prefixOf(xPart) == 'D' || _prefixOf(yPart) == 'D';

      final xDecoded = _decodeNumber(_stripPrefix(xPart), mapping);
      final yDecoded = _decodeNumber(_stripPrefix(yPart), mapping);
      if (xDecoded == null || yDecoded == null) continue;

      final xVal = int.tryParse(xDecoded);
      final yVal = int.tryParse(yDecoded);
      if (xVal == null || yVal == null) continue;
      if (xVal == 0 && yVal == 0) continue;

      points.add(Offset(xVal.toDouble(), yVal.toDouble()));
      drawFlags.add(draw);
    }

    if (points.isEmpty) return null;

    double minX = points.first.dx;
    double maxX = points.first.dx;
    double minY = points.first.dy;
    double maxY = points.first.dy;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
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

  static CutPathData rotatePathData(
    CutPathData data,
    double angleDegrees,
  ) {
    if (angleDegrees == 0) return data;

    final centerX = data.minX + ((data.maxX - data.minX) / 2.0);
    final centerY = data.minY + ((data.maxY - data.minY) / 2.0);
    final radians = (angleDegrees * 0.5) * pi / 180.0;
    final sinA = sin(radians);
    final cosA = cos(radians);

    final rotatedPoints = <Offset>[];
    for (final p in data.points) {
      final dx = p.dx - centerX;
      final dy = p.dy - centerY;
      final rx = (dx * cosA) - (dy * sinA) + centerX;
      final ry = (dx * sinA) + (dy * cosA) + centerY;
      rotatedPoints.add(Offset(rx, ry));
    }

    double minX = rotatedPoints.first.dx;
    double maxX = rotatedPoints.first.dx;
    double minY = rotatedPoints.first.dy;
    double maxY = rotatedPoints.first.dy;
    for (final p in rotatedPoints) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }

    return CutPathData(
      points: rotatedPoints,
      drawFlags: data.drawFlags,
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
    );
  }

  static List<int> applyAngleToBytes({
    required List<int> inputBytes,
    required double angleDegrees,
  }) {
    if (angleDegrees == 0) return inputBytes;

    String text;
    try {
      text = latin1.decode(inputBytes);
    } catch (_) {
      return inputBytes;
    }

    final trimmed = text.trim();
    if (!trimmed.contains('WSJP=')) {
      return inputBytes;
    }

    final normalized =
        trimmed.replaceAll('IN ', '').replaceAll(' @', '').trim();
    final parts = normalized.split(RegExp(r'\s+'));
    if (parts.isEmpty) return inputBytes;

    final header = parts.first;
    if (!header.contains('WSJP=')) return inputBytes;

    final mappingStr = header.replaceAll('WSJP=', '');
    final mapping = _buildMapping(mappingStr);
    if (mapping == null || mapping.length != 10) return inputBytes;

    final tokens = List<String>.from(parts);
    final decodedPoints = <_PointToken>[];

    for (int i = 1; i < tokens.length; i++) {
      final token = tokens[i];
      final split = token.split(',');
      if (split.length != 2) continue;

      final xPart = split[0];
      final yPart = split[1];
      final xPrefix = _prefixOf(xPart);
      final yPrefix = _prefixOf(yPart);
      final xDecoded = _decodeNumber(_stripPrefix(xPart), mapping);
      final yDecoded = _decodeNumber(_stripPrefix(yPart), mapping);
      if (xDecoded == null || yDecoded == null) continue;

      final xVal = int.tryParse(xDecoded);
      final yVal = int.tryParse(yDecoded);
      if (xVal == null || yVal == null) continue;
      if (xVal == 0 && yVal == 0) continue;

      decodedPoints.add(
        _PointToken(
          index: i,
          x: xVal,
          y: yVal,
          xPrefix: xPrefix,
          yPrefix: yPrefix,
        ),
      );
    }

    if (decodedPoints.isEmpty) return inputBytes;

    int minX = decodedPoints.first.x;
    int maxX = decodedPoints.first.x;
    int minY = decodedPoints.first.y;
    int maxY = decodedPoints.first.y;
    for (final p in decodedPoints) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }

    final centerX = minX + ((maxX - minX) / 2.0);
    final centerY = minY + ((maxY - minY) / 2.0);
    final radians = (angleDegrees * 0.5) * pi / 180.0;
    final sinA = sin(radians);
    final cosA = cos(radians);

    for (final p in decodedPoints) {
      final dx = p.x - centerX;
      final dy = p.y - centerY;
      final rx = (dx * cosA) - (dy * sinA) + centerX;
      final ry = (dx * sinA) + (dy * cosA) + centerY;
      p.x = rx.round();
      p.y = ry.round();

      final xEncoded = _encodeNumber(p.x.toString(), mapping);
      final yEncoded = _encodeNumber(p.y.toString(), mapping);
      tokens[p.index] = '${p.xPrefix}$xEncoded,${p.yPrefix}$yEncoded';
    }

    final rebuilt = 'IN ${tokens.join(' ')} @ ';
    return latin1.encode(rebuilt);
  }

  static List<int> applyPhonefilmSpeedPressure({
    required List<int> inputBytes,
    required int speed,
    required int pressure,
  }) {
    if (speed <= 0 && pressure <= 0) return inputBytes;

    String text;
    try {
      text = latin1.decode(inputBytes);
    } catch (_) {
      return inputBytes;
    }

    if (!text.contains('IN')) return inputBytes;

    final cmd = _buildPhonefilmCmd(speed, pressure);
    if (cmd.isEmpty) return inputBytes;

    // Follow PhoneFilm behavior: remove existing IN tokens and re-insert with CMD payload.
    final rebuilt = 'IN $cmd' + text.replaceAll('IN', '');
    return latin1.encode(rebuilt);
  }

  static String _buildPhonefilmCmd(int speed, int pressure) {
    final sb = StringBuffer();
    if (speed >= 1) {
      final s = speed.clamp(1, 4);
      sb.write('CMD:100,11,$s;');
    }
    if (pressure >= 1) {
      final p = pressure.clamp(1, 5);
      sb.write('CMD:100,10,$p;');
    }
    return sb.toString();
  }



  static String _prefixOf(String value) {
    if (value.isEmpty) return '';
    final c = value[0];
    return (c == 'U' || c == 'D') ? c : '';
  }

  static String _stripPrefix(String value) {
    if (value.isEmpty) return value;
    final c = value[0];
    if (c == 'U' || c == 'D') return value.substring(1);
    return value;
  }

  static List<String>? _buildMapping(String value) {
    if (value.length != 10) return null;

    final list = value.split('');
    final missing = <int>[];
    for (int i = 0; i < 10; i++) {
      if (!list.contains(i.toString())) {
        missing.add(i);
      }
    }

    for (int i = 0; i < list.length; i++) {
      final current = list[i];
      if (current == 'x') {
        list[i] = missing.removeAt(0).toString();
        continue;
      }
      for (int j = i + 1; j < list.length; j++) {
        if (list[j] == current) {
          list[j] = 'x';
        }
      }
    }

    for (int i = 0; i < list.length; i++) {
      if (list[i] == 'x') {
        list[i] = missing.removeAt(0).toString();
      }
    }

    final first = <String>[];
    final second = <String>[];
    for (int i = 1; i < list.length; i += 2) {
      first.add(list[i]);
      second.add(list[i - 1]);
    }
    first.addAll(second);
    return first;
  }

  static String? _decodeNumber(String value, List<String> mapping) {
    final buffer = StringBuffer();
    for (final ch in value.split('')) {
      if (ch == '-') {
        buffer.write(ch);
      } else {
        final idx = mapping.indexOf(ch);
        if (idx < 0) return null;
        buffer.write(idx);
      }
    }
    return buffer.toString();
  }

  static String _encodeNumber(String value, List<String> mapping) {
    final buffer = StringBuffer();
    for (final ch in value.split('')) {
      if (ch == '-') {
        buffer.write(ch);
      } else {
        final digit = int.tryParse(ch);
        if (digit == null || digit < 0 || digit > 9) {
          buffer.write(ch);
        } else {
          buffer.write(mapping[digit]);
        }
      }
    }
    return buffer.toString();
  }

}

class _PointToken {
  _PointToken({
    required this.index,
    required this.x,
    required this.y,
    required this.xPrefix,
    required this.yPrefix,
  });

  final int index;
  int x;
  int y;
  final String xPrefix;
  final String yPrefix;
}

class CutPathData {
  CutPathData({
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
