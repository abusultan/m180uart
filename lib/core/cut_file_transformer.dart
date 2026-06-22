import 'sjm_rotator.dart';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'sjm_cipher.dart';

class CutPayloadPreparation {
  const CutPayloadPreparation({
    required this.bytes,
    required this.previewData,
    required this.isSjcFile,
    required this.isSjmFile,
    required this.maxWidth,
    required this.shouldNormalizeSjc,
    required this.appliedDqNarrowTransform,
    required this.keepsOriginalSjcPrefix,
    required this.rebasedWideSjcToOrigin,
    required this.rebasedPltToOrigin,
    required this.appliedAngle,
    required this.appliedMirror,
  });

  final List<int> bytes;
  final CutPathData? previewData;
  final bool isSjcFile;
  final bool isSjmFile;
  final int? maxWidth;
  final bool shouldNormalizeSjc;
  final bool appliedDqNarrowTransform;
  final bool keepsOriginalSjcPrefix;
  final bool rebasedWideSjcToOrigin;
  final bool rebasedPltToOrigin;
  final bool appliedAngle;
  final bool appliedMirror;
}

class CutFileTransformer {
  static const String _legacyNarrowOutputMapping = '6240092912';
  static const String _editableDqSjmSeed = '515167676782828';
  static const Map<String, String> _dqSjmDigitMap = {
    '0': '1',
    '1': '0',
    '2': '7',
    '3': '3',
    '4': '5',
    '5': '6',
    '6': '4',
    '7': '8',
    '8': '2',
    '9': '9',
  };
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

  static bool isSjmBytes(List<int> inputBytes) {
    try {
      return latin1.decode(inputBytes).contains('SJM=');
    } catch (_) {
      return false;
    }
  }

  static String? extractSjmSeedFromBytes(List<int> inputBytes) {
    try {
      return extractSjmSeedFromText(latin1.decode(inputBytes));
    } catch (_) {
      return null;
    }
  }

  static String? extractSjmSeedFromText(String text) {
    final match = RegExp(r'SJM=([0-9A-Za-z]+)').firstMatch(text);
    return match?.group(1);
  }

  static List<String>? extractSjcEncodingMap(List<int> inputBytes) {
    try {
      final text = latin1.decode(inputBytes).trim();
      if (!text.contains('WSJP=')) return null;
      final normalized = text.replaceAll('IN ', '').replaceAll(' @', '').trim();
      final parts = normalized.split(RegExp(r'\s+'));
      if (parts.isEmpty) return null;
      final header = parts.first;
      if (!header.contains('WSJP=')) return null;
      return _buildMapping(header.replaceAll('WSJP=', ''));
    } catch (_) {
      return null;
    }
  }

  static String encodeWithDigitMapping(String value, List<String> mapping) {
    return _encodeNumber(value, mapping);
  }

  static bool supportsEditableSjmBytes(List<int> inputBytes) {
    try {
      final text = latin1.decode(inputBytes);
      return _supportsEditableSjmText(text);
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
      // FORCED PEN-UP: Sunshine Vertical machines MANDATE a U0,0 (Pen-Up) at start.
      // If the file doesn't have it, the machine interprets the first move as a DRAG
      // from the last known physical position, causing the vertical offset.
      if (text.contains('U0,0')) {
        return inputBytes;
      }
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

  static CutPayloadPreparation prepareForMachine({
    required List<int> inputBytes,
    int? maxWidth,
    double angleDegrees = 0,
    bool autoMirror = false,
    bool preferOriginAlignedBackCut = false,
    bool isSunshineMachine = false,
    bool isDqMachine = false,
  }) {
    var preparedBytes = List<int>.from(inputBytes);
    final isSjcFile = isSjcBytes(preparedBytes);
    final isSjmFile = !isSjcFile && isSjmBytes(preparedBytes);
    final isPltFile = !isSjcFile && !isSjmFile && isPltBytes(preparedBytes);
    final shouldTransformDqNarrow =
        isDqMachine && !isSjcFile && maxWidth != null && maxWidth > 0 && maxWidth < 160;
    // Sunshine machines: send the file exactly as downloaded from server.
    // No transformation needed — the file's positioning depends on how it was
    // generated server-side (the original server centers files based on maxWidth).
    final shouldNormalizeSjc = !isSunshineMachine &&
        isSjcFile && maxWidth != null && maxWidth > 0 && maxWidth < 160;
    final keepsOriginalSjcPrefix = isSjcFile && !shouldNormalizeSjc;
    bool rebasedWideSjcToOrigin = false;
    bool rebasedPltToOrigin = false;
    bool appliedDqNarrowTransform = false;

    if (!isSunshineMachine && isSjcFile && shouldNormalizeSjc) {
      final rebasedBytes = rebaseWideSjcToOriginIfNeeded(
        inputBytes: preparedBytes,
      );
      rebasedWideSjcToOrigin = !_listsEqual(rebasedBytes, preparedBytes);
      preparedBytes = rebasedBytes;
    }

    if (!isSunshineMachine && preferOriginAlignedBackCut && isPltFile && !isDqMachine) {
      final rebasedBytes = rebasePltToOriginIfNeeded(inputBytes: preparedBytes);
      rebasedPltToOrigin = !_listsEqual(rebasedBytes, preparedBytes);
      preparedBytes = rebasedBytes;
    }

    if (shouldTransformDqNarrow) {
      final transformedBytes = transformDqNarrowPayloadIfNeeded(
        inputBytes: preparedBytes,
      );
      appliedDqNarrowTransform = !_listsEqual(transformedBytes, preparedBytes);
      preparedBytes = transformedBytes;
    }

    final appliedAngle = !isSunshineMachine && (isSjcFile || isSjmFile) && angleDegrees != 0;
    if (appliedAngle) {
      preparedBytes = applyAngleToBytes(
        inputBytes: preparedBytes,
        angleDegrees: angleDegrees,
      );
    }

    final appliedMirror = !isSunshineMachine && autoMirror && (isSjcFile || isSjmFile);
    if (appliedMirror) {
      if (isSjcFile) {
        preparedBytes = applyMirrorToBytes(inputBytes: preparedBytes);
      } else if (isSjmFile) {
        preparedBytes = SjmRotator.applyMirrorToSjmBytes(inputBytes: preparedBytes);
      }
    }

    if (!isSunshineMachine && shouldNormalizeSjc) {
      preparedBytes = rebuildSjcForNarrowLegacyCutter(
        inputBytes: preparedBytes,
      );
    }

    return CutPayloadPreparation(
      bytes: preparedBytes,
      previewData: decodePathData(preparedBytes),
      isSjcFile: isSjcFile,
      isSjmFile: isSjmFile,
      maxWidth: maxWidth,
      shouldNormalizeSjc: shouldNormalizeSjc,
      appliedDqNarrowTransform: appliedDqNarrowTransform,
      keepsOriginalSjcPrefix: keepsOriginalSjcPrefix,
      rebasedWideSjcToOrigin: rebasedWideSjcToOrigin,
      rebasedPltToOrigin: rebasedPltToOrigin,
      appliedAngle: appliedAngle,
      appliedMirror: appliedMirror,
    );
  }

  static List<int> rebasePltToOriginIfNeeded({required List<int> inputBytes}) {
    String text;
    try {
      text = latin1.decode(inputBytes);
    } catch (_) {
      return inputBytes;
    }

    if (!(text.contains('PU') || text.contains('PD') || text.contains('PA'))) {
      return inputBytes;
    }

    final commands = text.split(';');
    double? minX;
    double? minY;

    Offset? readCoords(String command) {
      final trimmed = command.trim();
      if (trimmed.length < 2) return null;
      final prefix = trimmed.substring(0, 2);
      if (prefix != 'PU' && prefix != 'PD' && prefix != 'PA') {
        return null;
      }
      final coords = trimmed.substring(2).trim();
      if (coords.isEmpty) return null;
      return _parsePltCoords(coords);
    }

    for (final command in commands) {
      final point = readCoords(command);
      if (point == null) continue;
      minX = minX == null ? point.dx : min(minX, point.dx);
      minY = minY == null ? point.dy : min(minY, point.dy);
    }

    if (minX == null || minY == null || (minX == 0 && minY == 0)) {
      return inputBytes;
    }

    final rebuilt = commands
        .map((command) {
          final trimmed = command.trim();
          if (trimmed.length < 2) return command;
          final prefix = trimmed.substring(0, 2);
          if (prefix != 'PU' && prefix != 'PD' && prefix != 'PA') {
            return command;
          }
          final coords = trimmed.substring(2).trim();
          if (coords.isEmpty) return command;
          final point = _parsePltCoords(coords);
          if (point == null) return command;
          final shiftedX = point.dx - minX!;
          final shiftedY = point.dy - minY!;
          return '$prefix${_formatPltNumber(shiftedX)},${_formatPltNumber(shiftedY)}';
        })
        .join(';');

    return latin1.encode(rebuilt);
  }

  static List<int> transformDqNarrowPayloadIfNeeded({
    required List<int> inputBytes,
  }) {
    String text;
    try {
      text = latin1.decode(inputBytes);
    } catch (_) {
      return inputBytes;
    }

    if (!text.contains('FSIZE') &&
        !RegExp(r'([UD])-?\d+,-?\d+').hasMatch(text)) {
      return inputBytes;
    }

    final swappedFsize = text.replaceAllMapped(
      RegExp(r'FSIZE(-?\d+),(-?\d+)'),
      (match) => 'FSIZE${match.group(2)},${match.group(1)}',
    );
    final swappedCoords = swappedFsize.replaceAllMapped(
      RegExp(r'([UD])(-?\d+),(-?\d+)'),
      (match) => '${match.group(1)}${match.group(3)},${match.group(2)}',
    );

    if (swappedCoords == text) {
      return inputBytes;
    }

    return latin1.encode(swappedCoords);
  }

  static String _formatPltNumber(double value) {
    final rounded = value.roundToDouble();
    if ((value - rounded).abs() < 0.0001) {
      return rounded.toInt().toString();
    }
    return value.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  static List<int> rebaseWideSjcToOriginIfNeeded({
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

    if (decodedPoints.isEmpty) {
      return inputBytes;
    }

    int? minX;
    int? minY;
    for (final point in decodedPoints) {
      if (point.x == 0 && point.y == 0) {
        continue;
      }
      minX = minX == null ? point.x : min(minX, point.x);
      minY = minY == null ? point.y : min(minY, point.y);
    }

    if (minX == null || minY == null || (minX == 0 && minY == 0)) {
      return inputBytes;
    }

    for (final point in decodedPoints) {
      if (point.x == 0 && point.y == 0) {
        continue;
      }
      point.x -= minX;
      point.y -= minY;

      // ABSOLUTE PROTECTION: Ensure coordinates never clip negative (this causes vertical shifts on large machines)
      if (point.x < 0) point.x = 0;
      if (point.y < 0) point.y = 0;

      final xEncoded = _encodeNumber(point.x.toString(), mapping);
      final yEncoded = _encodeNumber(point.y.toString(), mapping);
      tokens[point.index] =
          '${point.xPrefix}$xEncoded,${point.yPrefix}$yEncoded';
    }

    final rebuilt = 'IN ${tokens.join(' ')} @ ';
    return latin1.encode(rebuilt);
  }

  static bool _listsEqual(List<int> a, List<int> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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
    } else if (trimmed.contains('SJM=')) {
      return _decodeSjmPathData(trimmed);
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

  static CutPathData? _decodeSjmPathData(String text) {
    // Extract seed and generate dynamic key map
    final seed = extractSjmSeedFromText(text);
    if (seed == null || seed.length < 15) return null;

    final keyMap = _generateSjmKeyMap(seed);
    if (keyMap == null) return null;

    final fsize = SjmCipher.decryptFsize(keyMap, text);

    final cleaned = text
        .replaceAll('IN ', '')
        .replaceAll('@', '')
        .replaceAll(';', ' ')
        .trim();
    if (!cleaned.contains('SJM=')) return null;

    final tokens = cleaned
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    if (tokens.isEmpty) return null;

    final points = <Offset>[];
    final drawFlags = <bool>[];

    for (final token in tokens) {
      if (token == 'IN' ||
          token.contains('SJM=') ||
          token.startsWith('FSIZE')) {
        continue;
      }

      final split = token.split(',');
      if (split.length != 2) continue;

      final xPart = split[0];
      final yPart = split[1];
      final draw = _prefixOf(xPart) == 'D' || _prefixOf(yPart) == 'D';

      final xDecoded = _decryptWithKeyMap(keyMap, _stripPrefix(xPart));
      final yDecoded = _decryptWithKeyMap(keyMap, _stripPrefix(yPart));
      if (xDecoded == null || yDecoded == null) continue;

      final xVal = int.tryParse(xDecoded);
      final yVal = int.tryParse(yDecoded);
      if (xVal == null || yVal == null) continue;
      if (xVal == 0 && yVal == 0) continue;

      points.add(Offset(xVal.toDouble(), yVal.toDouble()));
      drawFlags.add(draw);
    }

    if (points.isEmpty) return null;
    return _calculateBounds(
      points,
      drawFlags,
      fsizeWidth: fsize?.width.toDouble(),
      fsizeHeight: fsize?.height.toDouble(),
    );
  }

  // Index arrays for SJM key generation (from JNI reverse engineering)
  static const List<int> _sjmNumArr1 = [2, 4, 6, 8, 10, 12, 14, 3, 5, 7];
  static const List<int> _sjmNumArr2 = [3, 12, 0, 7, 4, 1, 9, 13, 8, 11];
  static const List<int> _sjmNumArr3 = [3, 5, 6, 8, 4, 1, 9, 13, 7, 11];
  static const List<int> _sjmNumArr4 = [1, 3, 7, 9, 2, 6, 4, 12, 13, 5];
  static const List<int> _sjmNumArr5 = [2, 4, 7, 9, 3, 6, 4, 10, 13, 1];

  /// Generate key map from 15-digit SJM seed (replaces JNI cmd_GetPassWordCutChar)
  static List<String>? _generateSjmKeyMap(String seed) {
    if (seed.length < 15) return null;

    final charArray = seed.split('');
    final lastChar = charArray[14];

    List<int> numArr;
    switch (lastChar) {
      case '1': numArr = _sjmNumArr1; break;
      case '2': numArr = _sjmNumArr2; break;
      case '3': numArr = _sjmNumArr3; break;
      case '8': numArr = _sjmNumArr4; break;
      case '9': numArr = _sjmNumArr5; break;
      default: numArr = _sjmNumArr4; break;
    }

    final keyMap = <String>[];
    for (int i = 0; i < 10; i++) {
      if (numArr[i] >= charArray.length) return null;
      keyMap.add(charArray[numArr[i]]);
    }

    final unusedDigits = List<int>.generate(10, (i) => i);
    for (int i = 0; i < 10; i++) {
      for (int j = 0; j < keyMap.length; j++) {
        final parsed = int.tryParse(keyMap[j]);
        if (parsed != null && unusedDigits[i] == parsed) {
          unusedDigits[i] = -1;
          break;
        }
      }
    }

    for (int i = 0; i < keyMap.length; i++) {
      if (keyMap[i] != 's') {
        for (int j = i + 1; j < keyMap.length; j++) {
          if (keyMap[j] == keyMap[i]) keyMap[j] = 's';
        }
      }
    }

    int unusedIdx = 0;
    for (int i = 0; i < keyMap.length; i++) {
      if (keyMap[i] == 's') {
        while (unusedIdx < 10 && unusedDigits[unusedIdx] == -1) {
          unusedIdx++;
        }
        if (unusedIdx < 10) {
          keyMap[i] = unusedDigits[unusedIdx].toString();
          unusedDigits[unusedIdx] = -1;
        }
      }
    }

    return keyMap;
  }

  /// Decrypt a number string using a dynamic SJM key map
  static String? _decryptWithKeyMap(List<String> keyMap, String value) {
    if (value.isEmpty) return null;
    final buffer = StringBuffer();
    for (final ch in value.split('')) {
      if (ch == '-') {
        buffer.write(ch);
      } else {
        final idx = keyMap.indexOf(ch);
        if (idx < 0) return null;
        buffer.write(idx);
      }
    }
    return buffer.toString();
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
          final pairs = _parsePltCoordinatePairs(coords);
          for (final point in pairs) {
            points.add(point);
            drawFlags.add(false);
          }
        }
      } else if (trimmed.startsWith('PD')) {
        isDown = true;
        final coords = trimmed.substring(2).trim();
        if (coords.isNotEmpty) {
          final pairs = _parsePltCoordinatePairs(coords);
          for (final point in pairs) {
            points.add(point);
            drawFlags.add(true);
          }
        }
      } else if (trimmed.startsWith('PA')) {
        final coords = trimmed.substring(2).trim();
        if (coords.isNotEmpty) {
          final pairs = _parsePltCoordinatePairs(coords);
          for (final point in pairs) {
            points.add(point);
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

  static List<Offset> _parsePltCoordinatePairs(String coords) {
    final values = coords
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (values.length < 2) {
      final single = _parsePltCoords(coords);
      return single == null ? const <Offset>[] : <Offset>[single];
    }

    final pairs = <Offset>[];
    for (int i = 0; i + 1 < values.length; i += 2) {
      final x = double.tryParse(values[i]);
      final y = double.tryParse(values[i + 1]);
      if (x == null || y == null) continue;
      pairs.add(Offset(x, y));
    }
    return pairs;
  }

  static CutPathData? _calculateBounds(
    List<Offset> points,
    List<bool> drawFlags, {
    double? fsizeWidth,
    double? fsizeHeight,
  }) {
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

    if (fsizeWidth != null && fsizeHeight != null) {
      minX = 0;
      minY = 0;
      maxX = fsizeWidth;
      maxY = fsizeHeight;
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
    final radians = angleDegrees * pi / 180.0;
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
    if (trimmed.contains('IN SJM=')) {
      return SjmRotator.applyAngleToSjmBytes(
        inputBytes: inputBytes,
        angleDegrees: angleDegrees,
      );
    }
    
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
    final radians = angleDegrees * pi / 180.0;
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
  /// This matches `DeviceDetailActivity.e(str)` in the original Android app:
  /// decode the original coordinates, skip origin calibration markers inline,
  /// rebase to the minimum X/Y, and emit the fixed legacy mapping.
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
      if (prefix == 'U') {
        currentSegment = <_LegacyCutPoint>[];
        segments.add(currentSegment);
      } else {
        currentSegment ??= <_LegacyCutPoint>[];
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

    buffer.write('U$zero,$zero ');
    buffer.write('D$zero,$zero ');

    for (final segment in segments) {
      if (segment.isEmpty) continue;
      for (int i = 0; i < segment.length; i++) {
        final point = segment[i];
        final encodedX = _encodeLegacyNarrowNumber((point.x - minX).toString());
        final encodedY = _encodeLegacyNarrowNumber((point.y - minY).toString());
        if (i == 0) {
          buffer.write('U$encodedX,$encodedY ');
        }
        buffer.write('D$encodedX,$encodedY ');
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

  static String? _decodeSjmNumber(String value) {
    if (value.isEmpty) return null;
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      if (char == '-') {
        buffer.write(char);
        continue;
      }
      String? decodedDigit;
      for (int i = 0; i <= 9; i++) {
        if (_dqSjmDigitMap[i.toString()] == char) {
          decodedDigit = i.toString();
          break;
        }
      }
      if (decodedDigit == null) return null;
      buffer.write(decodedDigit);
    }
    return buffer.toString();
  }

  static bool _supportsEditableSjmText(String text) {
    final seed = extractSjmSeedFromText(text);
    return seed != null && seed.length == 15;
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
    final rebuilt = 'IN $cmd${text.replaceAll('IN', '')}';
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
