import 'dart:convert';
import 'dart:ui';

import 'font_path_service.dart';

/// Service that generates DQ/Skycut machine commands for pen writing.
/// Replicates the original UpPrinting app's pen-draw functionality.
///
/// Protocol flow:
/// 1. Send INPG command (page feed for pen mode)
/// 2. Send cut data with U/D coordinates (pen up/down)
///
/// Data format:
/// IN SJM=515167676782828 FSIZE<h>,<w>; U0,0 D0,0 U<y>,<x> D<y>,<x> ... U0,0 @
class PenWriteService {
  PenWriteService._();
  static final PenWriteService instance = PenWriteService._();

  static const String _sjmSeed = '515167676782828';
  static const double _unitsPerMm = 40.0;

  static const Map<String, String> _digitMap = {
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

  /// Build the INPG pre-command for pen mode.
  /// This tells the machine to enter pen/draw mode.
  ///
  /// [offsetMm] - offset in mm (usually the material width)
  List<int> buildInpgCommand({double offsetMm = 0}) {
    final offsetUnits = (offsetMm * _unitsPerMm).toInt();
    final command = 'SJM=$_sjmSeed;U-$offsetUnits,1;INPG;';
    return latin1.encode(command);
  }

  /// Build the full pen-write payload for text.
  ///
  /// [text] - Text to write
  /// [fontFamily] - Font to use ('AdobeGothic' or 'AlibabaPuHuiTi')
  /// [isHorizontal] - true for horizontal, false for vertical
  /// [widthMm] - material/area width in mm
  /// [heightMm] - material/area height in mm
  ///
  /// Returns the encoded bytes ready to send to the machine.
  PenWriteResult buildTextPayload({
    required String text,
    String fontFamily = 'AdobeGothic',
    bool isHorizontal = true,
    required double widthMm,
    required double heightMm,
  }) {
    final pathResult = FontPathService.instance.textToMachinePolylines(
      text: text,
      fontFamily: fontFamily,
      isHorizontal: isHorizontal,
      targetWidthMm: widthMm,
      targetHeightMm: heightMm,
      unitsPerMm: _unitsPerMm,
    );

    if (pathResult.polylines.isEmpty) {
      throw const FormatException('pen_write_error_empty');
    }

    final payload = _buildSjmPayload(
      polylines: pathResult.polylines,
      widthUnits: pathResult.widthUnits,
      heightUnits: pathResult.heightUnits,
    );

    return PenWriteResult(
      inpgBytes: buildInpgCommand(offsetMm: widthMm),
      payloadBytes: latin1.encode(payload),
      payload: payload,
      polylines: pathResult.polylines,
      widthUnits: pathResult.widthUnits,
      heightUnits: pathResult.heightUnits,
    );
  }

  /// Build SJM-encoded payload from polylines.
  /// Format: IN SJM=515167676782828 FSIZE<h>,<w>; U0,0 D0,0 U<y>,<x> D<y>,<x>... U0,0 @
  String _buildSjmPayload({
    required List<List<Offset>> polylines,
    required int widthUnits,
    required int heightUnits,
  }) {
    final encodedWidth = _encodeDigits(widthUnits.toString());
    final encodedHeight = _encodeDigits(heightUnits.toString());
    final encodedZero = _encodeDigits('0');

    final buffer = StringBuffer();
    buffer.write('IN SJM=$_sjmSeed FSIZE$encodedHeight,$encodedWidth;');
    buffer.write('U$encodedZero,$encodedZero ');
    buffer.write('D$encodedZero,$encodedZero ');

    for (final polyline in polylines) {
      if (polyline.isEmpty) continue;

      // First point: Pen Up (move without drawing)
      final firstX = polyline.first.dx.toInt();
      final firstY = polyline.first.dy.toInt();
      final encFirstX = _encodeDigits(firstX.toString());
      final encFirstY = _encodeDigits(firstY.toString());
      buffer.write('U$encFirstY,$encFirstX ');

      // Subsequent points: Pen Down (draw)
      for (int i = 1; i < polyline.length; i++) {
        final x = polyline[i].dx.toInt();
        final y = polyline[i].dy.toInt();
        final encX = _encodeDigits(x.toString());
        final encY = _encodeDigits(y.toString());
        buffer.write('D$encY,$encX ');
      }
    }

    buffer.write('U$encodedZero,$encodedZero @ ');
    return buffer.toString();
  }

  /// Encode digits using the SJM substitution map.
  String _encodeDigits(String value) {
    final buffer = StringBuffer();
    for (final char in value.split('')) {
      if (char == '-') {
        buffer.write('-');
      } else {
        buffer.write(_digitMap[char] ?? char);
      }
    }
    return buffer.toString();
  }
}

class PenWriteResult {
  const PenWriteResult({
    required this.inpgBytes,
    required this.payloadBytes,
    required this.payload,
    required this.polylines,
    required this.widthUnits,
    required this.heightUnits,
  });

  /// INPG command bytes to send first (enters pen mode)
  final List<int> inpgBytes;

  /// Cut data payload bytes (the actual pen paths)
  final List<int> payloadBytes;

  /// Raw payload string (for debugging)
  final String payload;

  /// Polylines for preview rendering
  final List<List<Offset>> polylines;

  /// Width in machine units
  final int widthUnits;

  /// Height in machine units
  final int heightUnits;
}
