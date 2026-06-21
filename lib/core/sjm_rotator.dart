import 'dart:convert';
import 'dart:math';
import 'sjm_cipher.dart';

class SjmRotator {
  static List<int> applyAngleToSjmBytes({
    required List<int> inputBytes,
    required double angleDegrees,
  }) {
    if (angleDegrees == 0 || angleDegrees % 360 == 0) return inputBytes;

    String text;
    try {
      text = latin1.decode(inputBytes);
    } catch (_) {
      return inputBytes;
    }

    final trimmed = text.trim();
    if (!trimmed.contains('IN ') || !trimmed.contains('SJM=')) {
      return inputBytes; // Not an SJM file
    }

    final seed = SjmCipher.extractSeed(trimmed);
    final keyMap = seed != null ? SjmCipher.generateKeyMap(seed) : null;
    if (keyMap == null) return inputBytes;

    // Use a regex to parse the string carefully to preserve separators.
    // The format is: IN SJM=... FSIZE...; U... D... @
    // SJM commands can be separated by spaces or semicolons.
    // We will split by spaces, process, and then rejoin.
    // Wait, let's just use regex to replace all U and D commands.
    
    // First pass: extract all U/D coordinates to find bounding box and apply rotation
    final cmdRegex = RegExp(r'([UD])(\d+),(\d+)');
    final List<_Point> points = [];
    
    for (final match in cmdRegex.allMatches(trimmed)) {
      final cmd = match.group(1)!;
      final xEnc = match.group(2)!;
      final yEnc = match.group(3)!;
      
      final xDec = SjmCipher.decrypt(keyMap, xEnc);
      final yDec = SjmCipher.decrypt(keyMap, yEnc);
      
      final x = int.tryParse(xDec);
      final y = int.tryParse(yDec);
      if (x != null && y != null) {
        points.add(_Point(cmd, x, y, match.start, match.end));
      }
    }
    
    if (points.isEmpty) return inputBytes;
    
    // Determine bounding box
    int minX = points.first.x;
    int maxX = points.first.x;
    int minY = points.first.y;
    int maxY = points.first.y;
    for (final p in points) {
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
    
    // Rotate all points
    for (final p in points) {
      final dx = p.x - centerX;
      final dy = p.y - centerY;
      
      // Standard 2D rotation
      final rx = (dx * cosA) - (dy * sinA) + centerX;
      final ry = (dx * sinA) + (dy * cosA) + centerY;
      
      p.x = rx.round();
      p.y = ry.round();
    }
    
    // Recalculate bounding box to translate back to positive space starting at 0,0
    // Actually, SJM plotters usually don't need translation to exactly 0,0, but let's see.
    // Let's just find new Min and adjust so min=originalMin to keep it within the bounds.
    int newMinX = points.first.x;
    int newMinY = points.first.y;
    for (final p in points) {
      if (p.x < newMinX) newMinX = p.x;
      if (p.y < newMinY) newMinY = p.y;
    }
    
    final dxTrans = minX - newMinX;
    final dyTrans = minY - newMinY;
    
    for (final p in points) {
      p.x += dxTrans;
      p.y += dyTrans;
    }
    
    // Now replace the commands in the string from last to first to preserve indices
    String resultStr = trimmed;
    for (int i = points.length - 1; i >= 0; i--) {
      final p = points[i];
      final xEnc = SjmCipher.encrypt(keyMap, p.x.toString());
      final yEnc = SjmCipher.encrypt(keyMap, p.y.toString());
      
      final replacement = '${p.cmd}$xEnc,$yEnc';
      resultStr = resultStr.replaceRange(p.start, p.end, replacement);
    }
    
    // Handle FSIZE
    final fsizeRegex = RegExp(r'FSIZE(\d+),(\d+)');
    final fsizeMatch = fsizeRegex.firstMatch(resultStr);
    if (fsizeMatch != null) {
      final wEnc = fsizeMatch.group(1)!;
      final hEnc = fsizeMatch.group(2)!;
      
      final wDec = SjmCipher.decrypt(keyMap, wEnc);
      final hDec = SjmCipher.decrypt(keyMap, hEnc);
      
      int? w = int.tryParse(wDec);
      int? h = int.tryParse(hDec);
      
      if (w != null && h != null) {
        // If rotating by 90 or 270, swap width and height
        if ((angleDegrees % 180) != 0) {
          final temp = w;
          w = h;
          h = temp;
        }
        
        final newWEnc = SjmCipher.encrypt(keyMap, w.toString());
        final newHEnc = SjmCipher.encrypt(keyMap, h.toString());
        
        resultStr = resultStr.replaceRange(
          fsizeMatch.start, 
          fsizeMatch.end, 
          'FSIZE$newWEnc,$newHEnc'
        );
      }
    }
    
    return latin1.encode(resultStr);
  }
  static List<int> applyMirrorToSjmBytes({
    required List<int> inputBytes,
  }) {
    String text;
    try {
      text = latin1.decode(inputBytes);
    } catch (_) {
      return inputBytes;
    }

    final trimmed = text.trim();
    if (!trimmed.contains('IN ') || !trimmed.contains('SJM=')) {
      return inputBytes; // Not an SJM file
    }

    final seed = SjmCipher.extractSeed(trimmed);
    final keyMap = seed != null ? SjmCipher.generateKeyMap(seed) : null;
    if (keyMap == null) return inputBytes;

    final cmdRegex = RegExp(r'([UD])(\d+),(\d+)');
    final List<_Point> points = [];
    
    for (final match in cmdRegex.allMatches(trimmed)) {
      final cmd = match.group(1)!;
      final xEnc = match.group(2)!;
      final yEnc = match.group(3)!;
      
      final xDec = SjmCipher.decrypt(keyMap, xEnc);
      final yDec = SjmCipher.decrypt(keyMap, yEnc);
      
      final x = int.tryParse(xDec);
      final y = int.tryParse(yDec);
      if (x != null && y != null) {
        points.add(_Point(cmd, x, y, match.start, match.end));
      }
    }
    
    if (points.isEmpty) return inputBytes;
    
    int minX = points.first.x;
    int maxX = points.first.x;
    for (final p in points) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
    }
    
    final sumX = minX + maxX;
    
    for (final p in points) {
      p.x = sumX - p.x;
    }
    
    final sb = StringBuffer();
    int lastEnd = 0;
    
    for (final p in points) {
      sb.write(trimmed.substring(lastEnd, p.start));
      
      final xDecStr = p.x.toString();
      final yDecStr = p.y.toString();
      
      final xEncStr = SjmCipher.encrypt(keyMap, xDecStr);
      final yEncStr = SjmCipher.encrypt(keyMap, yDecStr);
      
      sb.write('${p.cmd}$xEncStr,$yEncStr');
      lastEnd = p.end;
    }
    
    sb.write(trimmed.substring(lastEnd));
    return latin1.encode(sb.toString());
  }
}

class _Point {
  final String cmd;
  int x;
  int y;
  final int start;
  final int end;
  
  _Point(this.cmd, this.x, this.y, this.start, this.end);
}

