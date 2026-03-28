import 'dart:convert';
import 'dart:math';
import 'dart:ui';

class CutFileTransformer {
  static const String _legacyNarrowOutputMapping = '6240092912';
  static const Map<String, String> _legacyNarrowDigitMap = {
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
  };

  static bool isSjcBytes(List<int> inputBytes) {
    try {
      return latin1.decode(inputBytes).contains('WSJP=');
    } catch (_) {
      return false;
    }
  }

  static bool isPltBytes(List<int> inputBytes) {
    try {
      final text = latin1.decode(inputBytes);
      return text.contains('PU') || text.contains('PD') || text.contains('PA');
    } catch (_) {
      return false;
    }
  }

  /// Ensures the cut file starts with a pen-up move to origin (0,0).
  /// This prevents an unwanted line when the cutter head is not at 0,0
  /// before cutting starts.
  static List<int> ensureStartsWithPenUp(List<int> inputBytes) {
    String text;
    try {
      text = latin1.decode(inputBytes);
    } catch (_) {
      return inputBytes;
    }

    final trimmed = text.trim();

    if (trimmed.contains('WSJP=')) {
      // SJC format: inject U0,0 right after the WSJP=... header token
      // Original: "IN WSJP=XXXXXXXXXX FSIZE...; U0,0 D0,0 ..."
      // We ensure U0,0 is the VERY first coordinate token
      final inIdx = trimmed.indexOf('IN ');
      if (inIdx == -1) return inputBytes;

      // Find the end of the header (WSJP=...) — next space after WSJP=
      final wsjpIdx = trimmed.indexOf('WSJP=');
      if (wsjpIdx == -1) return inputBytes;

      // Find where the first coordinate token starts (after header)
      // Header ends at first space after WSJP value
      int headerEnd = trimmed.indexOf(' ', wsjpIdx + 5);
      if (headerEnd == -1) return inputBytes;

      // Check the token at headerEnd — if it starts with FSIZE, skip it too
      final rest = trimmed.substring(headerEnd).trimLeft();
      int insertAt = headerEnd + 1;
      if (rest.startsWith('FSIZE')) {
        // skip the FSIZE token
        final fsizeEnd = trimmed.indexOf(' ', headerEnd + 1);
        if (fsizeEnd != -1) {
          insertAt = fsizeEnd + 1;
        }
      }

      // Check if U0,0 is already the first coordinate token
      final afterInsert = trimmed.substring(insertAt).trimLeft();
      if (afterInsert.startsWith('U0,0')) {
        // Already starts correctly
        return inputBytes;
      }

      // Inject U0,0 before the rest of the tokens
      final modified =
          '${trimmed.substring(0, insertAt)}U0,0 ${trimmed.substring(insertAt)}';
      return latin1.encode(modified);
    } else if (trimmed.contains('PU') ||
        trimmed.contains('PD') ||
        trimmed.contains('PA')) {
      // PLT/HPGL format: prepend PU0,0; to lift blade and go to origin
      if (!trimmed.startsWith('PU0,0;') && !trimmed.startsWith('IN;PU0,0;')) {
        final modified = 'PU0,0;\n$trimmed';
        return latin1.encode(modified);
      }
    }

    return inputBytes;
  }

  /// Removes the leading calibration/registration marks that some SJC files
  /// place before the real design path.
  ///
  /// Example prefix:
  /// `U0,0 D0,0 D0,80 U0,0 D960,0 ...`
  ///
  /// The legacy Android app effectively skips each `0,0` marker and the next
  /// non-zero point that follows it before the real `U...` segment begins.
  static List<int> filterOriginCalibrationMarks(List<int> inputBytes) {
    String text;
    try {
      text = latin1.decode(inputBytes);
    } catch (_) {
      return inputBytes;
    }

    final trimmed = text.trim();
    if (!trimmed.contains('WSJP=')) return inputBytes;

    final tokens = trimmed
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return inputBytes;

    final headerIndex = tokens.indexWhere((token) => token.contains('WSJP='));
    if (headerIndex == -1) return inputBytes;

    final mapping = _buildMapping(tokens[headerIndex].replaceAll('WSJP=', ''));
    if (mapping == null || mapping.length != 10) return inputBytes;

    int firstCoordinateIndex = -1;
    for (int i = headerIndex + 1; i < tokens.length; i++) {
      if (tokens[i] == '@') break;
      if (tokens[i].contains(',')) {
        firstCoordinateIndex = i;
        break;
      }
    }
    if (firstCoordinateIndex == -1) return inputBytes;

    int removeUntil = firstCoordinateIndex;
    bool sawOriginMarker = false;

    for (int i = firstCoordinateIndex; i < tokens.length; i++) {
      final token = tokens[i];
      if (token == '@' || !token.contains(',')) {
        break;
      }

      final split = token.split(',');
      if (split.length != 2) break;

      final xDecoded = _decodeNumber(_stripPrefix(split[0]), mapping);
      final yDecoded = _decodeNumber(_stripPrefix(split[1]), mapping);
      if (xDecoded == null || yDecoded == null) break;

      final xVal = int.tryParse(xDecoded);
      final yVal = int.tryParse(yDecoded);
      if (xVal == null || yVal == null) break;

      if (xVal == 0 && yVal == 0) {
        sawOriginMarker = true;
        removeUntil = i + 1;
        continue;
      }

      if (sawOriginMarker) {
        sawOriginMarker = false;
        removeUntil = i + 1;
        continue;
      }

      break;
    }

    if (removeUntil == firstCoordinateIndex) {
      return inputBytes;
    }

    final rebuiltTokens = <String>[
      ...tokens.take(firstCoordinateIndex),
      ...tokens.skip(removeUntil),
    ];
    return latin1.encode('${rebuiltTokens.join(' ')} ');
  }

  static CutPathData? decodePathData(List<int> inputBytes) {
    String text;
    try {
      text = latin1.decode(inputBytes);
    } catch (_) {
      return null;
    }

    final trimmed = text.trim();
    if (trimmed.contains('WSJP=')) {
      return _decodeSjcPathData(trimmed);
    } else if (trimmed.contains('PU') ||
        trimmed.contains('PD') ||
        trimmed.contains('PA')) {
      return _decodePltPathData(trimmed);
    }
    return null;
  }

  static CutPathData? _decodeSjcPathData(String text) {
    final normalized = text.replaceAll('IN ', '').replaceAll(' @', '').trim();
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

    return _calculateBounds(points, drawFlags);
  }

  static CutPathData? _decodePltPathData(String text) {
    final points = <Offset>[];
    final drawFlags = <bool>[];
    bool isDown = false;

    // Basic HPGL parser: PU, PD, PA commands
    final commands = text.split(';');
    for (var cmd in commands) {
      final trimmed = cmd.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('PU')) {
        isDown = false;
        final coords = trimmed.substring(2).trim();
        if (coords.isNotEmpty) {
          final p = _parsePltCoords(coords);
          if (p != null) {
            points.add(p);
            drawFlags.add(false);
          }
        }
      } else if (trimmed.startsWith('PD')) {
        isDown = true;
        final coords = trimmed.substring(2).trim();
        if (coords.isNotEmpty) {
          final p = _parsePltCoords(coords);
          if (p != null) {
            points.add(p);
            drawFlags.add(true);
          }
        }
      } else if (trimmed.startsWith('PA')) {
        final coords = trimmed.substring(2).trim();
        if (coords.isNotEmpty) {
          final p = _parsePltCoords(coords);
          if (p != null) {
            points.add(p);
            drawFlags.add(isDown);
          }
        }
      }
    }

    if (points.isEmpty) return null;
    return _calculateBounds(points, drawFlags);
  }

  static Offset? _parsePltCoords(String coords) {
    final parts = coords.split(',');
    if (parts.length < 2) return null;
    final x = double.tryParse(parts[0]);
    final y = double.tryParse(parts[1]);
    if (x == null || y == null) return null;
    return Offset(x, y);
  }

  static CutPathData? _calculateBounds(
    List<Offset> points,
    List<bool> drawFlags,
  ) {
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

  static CutPathData rotatePathData(CutPathData data, double angleDegrees) {
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

  static CutPathData mirrorPathData(CutPathData data) {
    final mirroredPoints = <Offset>[];
    for (final p in data.points) {
      // Mirror horizontally around the center: x' = (maxX + minX) - x
      final rx = (data.maxX + data.minX) - p.dx;
      mirroredPoints.add(Offset(rx, p.dy));
    }

    return CutPathData(
      points: mirroredPoints,
      drawFlags: data.drawFlags,
      minX: data.minX,
      maxX: data.maxX,
      minY: data.minY,
      maxY: data.maxY,
    );
  }

  static List<int> applyMirrorToBytes({required List<int> inputBytes}) {
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

    final normalized = trimmed
        .replaceAll('IN ', '')
        .replaceAll(' @', '')
        .trim();
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
    for (final p in decodedPoints) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
    }

    for (final p in decodedPoints) {
      // Mirror horizontally: x' = (maxX + minX) - x
      p.x = (maxX + minX) - p.x;

      final xEncoded = _encodeNumber(p.x.toString(), mapping);
      final yEncoded = _encodeNumber(p.y.toString(), mapping);
      tokens[p.index] = '${p.xPrefix}$xEncoded,${p.yPrefix}$yEncoded';
    }

    final rebuilt = 'IN ${tokens.join(' ')} @ ';
    return latin1.encode(rebuilt);
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

    final normalized = trimmed
        .replaceAll('IN ', '')
        .replaceAll(' @', '')
        .trim();
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

  /// Rebuilds SJC data for narrow legacy cutters (<160mm max width).
  ///
  /// This matches the legacy Android app behavior:
  /// 1. Decode the original coordinates using the source mapping.
  /// 2. Drop initial origin calibration tokens.
  /// 3. Rebase the design to the minimum X/Y.
  /// 4. Emit the legacy fixed `WSJP=6240092912` mapping.
  /// 5. Start and end with a pen-up move to origin.
  static List<int> rebuildSjcForNarrowLegacyCutter({
    required List<int> inputBytes,
  }) {
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

    final normalized = trimmed
        .replaceAll('IN ', '')
        .replaceAll(' @', '')
        .trim();
    final parts = normalized.split(RegExp(r'\s+'));
    if (parts.isEmpty) return inputBytes;

    final header = parts.first;
    if (!header.contains('WSJP=')) return inputBytes;

    final sourceMappingStr = header.replaceAll('WSJP=', '');
    final mapping = _buildMapping(sourceMappingStr);
    if (mapping == null || mapping.length != 10) return inputBytes;

    final segments = <List<_LegacyCutPoint>>[];
    List<_LegacyCutPoint>? currentSegment;
    int skipCounter = 0;

    int? minX;
    int? maxX;
    int? minY;
    int? maxY;

    for (int i = 1; i < parts.length; i++) {
      final token = parts[i];
      final split = token.split(',');
      if (split.length != 2) continue;

      final prefix = _prefixOf(split[0]);
      if (prefix == 'U' || currentSegment == null) {
        currentSegment = <_LegacyCutPoint>[];
        segments.add(currentSegment);
      }

      final xDecoded = _decodeNumber(_stripPrefix(split[0]), mapping);
      final yDecoded = _decodeNumber(_stripPrefix(split[1]), mapping);
      if (xDecoded == null || yDecoded == null) continue;

      final xVal = int.tryParse(xDecoded);
      final yVal = int.tryParse(yDecoded);
      if (xVal == null || yVal == null) continue;

      if (xVal == 0 && yVal == 0) {
        skipCounter++;
        continue;
      }

      if (skipCounter > 0) {
        skipCounter = 0;
        continue;
      }

      currentSegment.add(_LegacyCutPoint(x: xVal, y: yVal));

      minX = minX == null ? xVal : min(minX, xVal);
      maxX = maxX == null ? xVal : max(maxX, xVal);
      minY = minY == null ? yVal : min(minY, yVal);
      maxY = maxY == null ? yVal : max(maxY, yVal);
    }

    if (minX == null || maxX == null || minY == null || maxY == null) {
      return inputBytes;
    }

    final width = maxX - minX;
    final height = maxY - minY;
    final zero = _encodeLegacyNarrowNumber('0');
    final buffer = StringBuffer(
      'IN WSJP=$_legacyNarrowOutputMapping FSIZE$height,$width; ',
    );

    // Match the legacy Android app by explicitly starting from origin.
    buffer.write('U$zero,$zero ');
    buffer.write('D$zero,$zero ');

    for (final segment in segments) {
      if (segment.isEmpty) continue;
      for (int i = 0; i < segment.length; i++) {
        final point = segment[i];
        final encodedPrimary = _encodeLegacyNarrowNumber(
          (point.y - minY).toString(),
        );
        final encodedSecondary = _encodeLegacyNarrowNumber(
          (point.x - minX).toString(),
        );
        if (i == 0) {
          buffer.write('U$encodedPrimary,$encodedSecondary ');
        }
        buffer.write('D$encodedPrimary,$encodedSecondary ');
      }
    }

    buffer.write('U$zero,$zero @ ');
    return latin1.encode(buffer.toString());
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

  static String _encodeLegacyNarrowNumber(String value) {
    final buffer = StringBuffer();
    for (final ch in value.split('')) {
      if (ch == '-') {
        buffer.write(ch);
      } else {
        buffer.write(_legacyNarrowDigitMap[ch] ?? ch);
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

class _LegacyCutPoint {
  const _LegacyCutPoint({required this.x, required this.y});

  final int x;
  final int y;
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
