import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_strings.dart';
import '../../core/sjm_cipher.dart';
import '../../core/cut_file_transformer.dart';
import '../../core/font_path_service.dart';
import '../../core/text_overlay_fonts.dart';

/// Result returned from DqTextOnCutScreen
class DqTextOnCutResult {
  const DqTextOnCutResult({required this.mergedBytes});
  final List<int> mergedBytes;
}

/// Standalone screen for adding text ON TOP of a DQ SJM cut file.
/// Flow:
/// 1. Decodes the cut file and displays the shape
/// 2. User types text, adjusts size/position
/// 3. On save: encrypts text with same seed, merges into file, returns
class DqTextOnCutScreen extends StatefulWidget {
  const DqTextOnCutScreen({super.key, required this.cutFileBytes});

  final List<int> cutFileBytes;

  @override
  State<DqTextOnCutScreen> createState() => _DqTextOnCutScreenState();
}

class _DqTextOnCutScreenState extends State<DqTextOnCutScreen> {
  final _textController = TextEditingController();
  // Font state
  String _fontFamily = 'AdobeGothic';

  // Decoded cut shape
  List<List<Offset>> _shapePolylines = [];
  double _shapeWidth = 0;
  double _shapeHeight = 0;

  // Text polylines (in real machine coords)
  List<List<Offset>> _textPolylines = [];

  // User controls
  double _textScale = 0.15;
  double _pinchBaseScale = 0.15;
  double _textRotation = 0.0;
  double _pinchBaseRotation = 0.0;
  Offset _textOffset = Offset.zero; // normalized 0-1
  bool _isHorizontal = true;

  // File info
  String? _seed;
  List<String>? _keyMap;
  int _fsizeW = 0; // real decoded width
  int _fsizeH = 0; // real decoded height

  @override
  void initState() {
    super.initState();
    _decodeShape();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  // Font state - not needed, using built-in glyphs

  void _decodeShape() {
    final text = latin1.decode(widget.cutFileBytes).trim();

    // Extract seed
    _seed = SjmCipher.extractSeed(text);
    if (_seed == null) return;

    _keyMap = SjmCipher.generateKeyMap(_seed!);
    if (_keyMap == null) return;

    // Decode FSIZE
    final fsize = SjmCipher.decryptFsize(_keyMap!, text);
    if (fsize != null) {
      _fsizeW = fsize.width;
      _fsizeH = fsize.height;
    }

    // Decode all points
    // File format: IN SJM=... FSIZE...;U{y},{x} D{y},{x}...@
    // First coordinate = Y (height axis), Second = X (width axis)
    final pathData = CutFileTransformer.decodePathData(widget.cutFileBytes);
    if (pathData == null || pathData.points.isEmpty) return;

    // pathData points from _decodeSjmPathData: Offset(first_decoded, second_decoded)
    // Original app mirrors X axis: draws (maxX - x, y)
    // First: collect all points to find maxX for mirroring
    final allPoints = <Offset>[];
    for (int i = 0; i < pathData.points.length; i++) {
      allPoints.add(pathData.points[i]);
    }
    double maxFirstCoord = 0;
    for (final p in allPoints) {
      if (p.dx > maxFirstCoord) maxFirstCoord = p.dx;
    }

    final polylines = <List<Offset>>[];
    var currentPolyline = <Offset>[];

    for (int i = 0; i < pathData.points.length; i++) {
      final p = pathData.points[i];
      // Mirror X axis (same as original app: width - x)
      final screenPoint = Offset(maxFirstCoord - p.dx, p.dy);

      if (!pathData.drawFlags[i] && currentPolyline.isNotEmpty) {
        polylines.add(currentPolyline);
        currentPolyline = [screenPoint];
      } else {
        currentPolyline.add(screenPoint);
      }
    }
    if (currentPolyline.isNotEmpty) polylines.add(currentPolyline);

    _shapePolylines = polylines;
    // Use actual bounding box of decoded points for dimensions
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;
    for (final pl in polylines) {
      for (final p in pl) {
        if (p.dx < minX) minX = p.dx;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dy > maxY) maxY = p.dy;
      }
    }
    _shapeWidth = maxX - minX;
    _shapeHeight = maxY - minY;

    setState(() {});
  }

  Future<void> _rebuildTextPolylines() async {
    final text = _textController.text.trim().toUpperCase();
    if (text.isEmpty || _shapeWidth <= 0) {
      if (_textPolylines.isNotEmpty) setState(() => _textPolylines = []);
      return;
    }

    // Use TextOverlayFonts glyphs
    final glyphs = TextOverlayFonts.registry[_fontFamily]?.glyphs ??
        TextOverlayFonts.registry['AdobeGothic']!.glyphs;

    // Build polylines for each character
    final rawPolylines = <List<Offset>>[];
    double cursorX = 0;
    double cursorY = 0;
    final glyphW = 1.0;
    final glyphH = 1.6;
    final gap = 0.3;

    for (final char in text.split('')) {
      final charGlyphs = glyphs[char];
      if (charGlyphs == null) {
        if (_isHorizontal)
          cursorX += glyphW + gap;
        else
          cursorY += glyphH + gap;
        continue;
      }
      for (final stroke in charGlyphs) {
        final polyline = stroke.map((p) {
          if (_isHorizontal) {
            return Offset(p.dx + cursorX, p.dy);
          } else {
            return Offset(p.dx, p.dy + cursorY);
          }
        }).toList();
        if (polyline.length >= 2) rawPolylines.add(polyline);
      }
      if (_isHorizontal)
        cursorX += glyphW + gap;
      else
        cursorY += glyphH + gap;
    }

    if (rawPolylines.isEmpty) {
      if (mounted) setState(() => _textPolylines = []);
      return;
    }

    // Calculate bounding box
    double tMinX = double.infinity, tMaxX = double.negativeInfinity;
    double tMinY = double.infinity, tMaxY = double.negativeInfinity;
    for (final pl in rawPolylines) {
      for (final p in pl) {
        if (p.dx < tMinX) tMinX = p.dx;
        if (p.dx > tMaxX) tMaxX = p.dx;
        if (p.dy < tMinY) tMinY = p.dy;
        if (p.dy > tMaxY) tMaxY = p.dy;
      }
    }
    final tW = tMaxX - tMinX;
    final tH = tMaxY - tMinY;
    if (tW <= 0 || tH <= 0) {
      if (mounted) setState(() => _textPolylines = []);
      return;
    }

    // Scale to fit shape * _textScale
    final targetW = _shapeWidth * _textScale;
    final targetH = _shapeHeight * _textScale;
    final scale = min(targetW / tW, targetH / tH);

    // Position: center + user drag offset
    final centerX = _shapeWidth / 2.0 + _textOffset.dx * _shapeWidth;
    final centerY = _shapeHeight / 2.0 + _textOffset.dy * _shapeHeight;

    final cosR = cos(_textRotation);
    final sinR = sin(_textRotation);

    final scaledPolylines = rawPolylines.map((pl) {
      return pl.map((p) {
        // Scale and center
        final sx = (p.dx - tMinX - tW / 2) * scale;
        final sy = (p.dy - tMinY - tH / 2) * scale;
        // Rotate around center
        final rx = sx * cosR - sy * sinR;
        final ry = sx * sinR + sy * cosR;
        return Offset(rx + centerX, ry + centerY);
      }).toList();
    }).toList();

    if (mounted) setState(() => _textPolylines = scaledPolylines);
  }

  void _save() {
    if (_textPolylines.isEmpty || _keyMap == null || _seed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No text to add'), backgroundColor: Colors.red),
      );
      return;
    }

    // Convert text polylines from screen (X,Y) back to file format (Y,X)
    // Then encrypt with the same seed and append to the file
    final fileText = latin1.decode(widget.cutFileBytes).trim();

    // Find the @ marker and insert text before it
    String body = fileText;
    if (body.contains('@')) {
      body = body.substring(0, body.lastIndexOf('@')).trimRight();
    }

    // Remove trailing U0,0 if present
    final zero = SjmCipher.encrypt(_keyMap!, '0');
    final endMarker = 'U$zero,$zero';
    if (body.endsWith(endMarker)) {
      body = body.substring(0, body.length - endMarker.length).trimRight();
    }

    // Write text coordinates in same order as original file
    // The text polylines are in SCREEN coordinates (mirrored X for display).
    // To write back to file: reverse the mirror (maxFirstCoord - screenX)
    // Then encrypt and write as (first, second) matching file format.

    // Find maxFirstCoord (same as used during decode for mirroring)
    double maxFirst = 0;
    final pathData = CutFileTransformer.decodePathData(widget.cutFileBytes);
    if (pathData != null) {
      for (final p in pathData.points) {
        if (p.dx > maxFirst) maxFirst = p.dx;
      }
    }

    final buffer = StringBuffer();
    for (final polyline in _textPolylines) {
      for (int i = 0; i < polyline.length; i++) {
        final p = polyline[i];
        // Reverse the mirror: file_x = maxFirst - screen_x
        final firstCoord = (maxFirst - p.dx).round();
        final secondCoord = p.dy.round();
        final encFirst = SjmCipher.encrypt(_keyMap!, firstCoord.toString());
        final encSecond = SjmCipher.encrypt(_keyMap!, secondCoord.toString());
        if (i == 0) {
          buffer.write('U$encFirst,$encSecond D$encFirst,$encSecond ');
        } else {
          buffer.write('D$encFirst,$encSecond ');
        }
      }
    }

    final merged = '$body ${buffer.toString()}U$zero,$zero @ ';
    final mergedBytes = latin1.encode(merged);

    Navigator.pop(context, DqTextOnCutResult(mergedBytes: mergedBytes));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Text to Cut'),
        backgroundColor: Colors.transparent,
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('SAVE',
                style: TextStyle(
                    color: Color(0xFF00E676), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      backgroundColor: const Color(0xFF121212),
      body: Column(
        children: [
          // Preview
          Expanded(
            flex: 3,
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: GestureDetector(
                onScaleStart: (_) {
                  _pinchBaseScale = _textScale;
                  _pinchBaseRotation = _textRotation;
                },
                onScaleUpdate: (details) {
                  if (details.pointerCount >= 2) {
                    // Pinch to resize + rotate
                    setState(() {
                      _textScale =
                          (_pinchBaseScale * details.scale).clamp(0.03, 0.8);
                      _textRotation = _pinchBaseRotation + details.rotation;
                    });
                    _rebuildTextPolylines();
                  } else {
                    // Single finger drag to move
                    setState(() {
                      _textOffset += Offset(
                        details.focalPointDelta.dx / 200,
                        details.focalPointDelta.dy / 200,
                      );
                    });
                    _rebuildTextPolylines();
                  }
                },
                child: CustomPaint(
                  painter: _ShapeWithTextPainter(
                    shapePolylines: _shapePolylines,
                    textPolylines: _textPolylines,
                    shapeWidth: _shapeWidth,
                    shapeHeight: _shapeHeight,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          // Controls
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  // Text input
                  TextField(
                    controller: _textController,
                    textCapitalization: TextCapitalization.characters,
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: _fontFamily == 'AlibabaBlack'
                          ? 'AlibabaPuHuiTi'
                          : _fontFamily,
                    ),
                    onChanged: (val) {
                      _rebuildTextPolylines();
                    },
                    onSubmitted: (_) => _rebuildTextPolylines(),
                    decoration: InputDecoration(
                      labelText: 'Text',
                      labelStyle: const TextStyle(color: Colors.white70),
                      hintText: 'HELLO',
                      hintStyle: const TextStyle(color: Colors.white30),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.check, color: Color(0xFF4DB6FF)),
                        onPressed: () => _rebuildTextPolylines(),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF4DB6FF)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Pinch to resize hint
                  const Text(
                    'Pinch to resize • Drag to move',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  // Direction
                  Row(
                    children: [
                      const Text('Direction:',
                          style: TextStyle(color: Colors.white70)),
                      const SizedBox(width: 12),
                      ChoiceChip(
                        label: const Text('Horizontal'),
                        selected: _isHorizontal,
                        onSelected: (_) {
                          setState(() => _isHorizontal = true);
                          _rebuildTextPolylines();
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Vertical'),
                        selected: !_isHorizontal,
                        onSelected: (_) {
                          setState(() => _isHorizontal = false);
                          _rebuildTextPolylines();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Font Selection
                  Row(
                    children: [
                      const Text('Font:',
                          style: TextStyle(color: Colors.white70)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _fontFamily,
                          dropdownColor: const Color(0xFF252525),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: Colors.white24),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: Color(0xFF4DB6FF)),
                            ),
                          ),
                          items: [
                            DropdownMenuItem(
                                value: 'AdobeGothic',
                                child: Text('Adobe Gothic',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontFamily: 'AdobeGothic'))),
                            DropdownMenuItem(
                                value: 'AlibabaBlack',
                                child: Text('Alibaba Black',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontFamily: 'AlibabaPuHuiTi'))),
                            DropdownMenuItem(
                                value: 'Stencil',
                                child: Text('Stencil',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontFamily: 'Stencil'))),
                            DropdownMenuItem(
                                value: 'Oswald',
                                child: Text('Oswald',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontFamily: 'Oswald'))),
                            DropdownMenuItem(
                                value: 'Righteous',
                                child: Text('Righteous',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontFamily: 'Righteous'))),
                            DropdownMenuItem(
                                value: 'Cinzel',
                                child: Text('Cinzel',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontFamily: 'Cinzel'))),
                          ],
                          onChanged: (val) {
                            if (val == null) return;
                            setState(() => _fontFamily = val);
                            _rebuildTextPolylines();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShapeWithTextPainter extends CustomPainter {
  _ShapeWithTextPainter({
    required this.shapePolylines,
    required this.textPolylines,
    required this.shapeWidth,
    required this.shapeHeight,
  });

  final List<List<Offset>> shapePolylines;
  final List<List<Offset>> textPolylines;
  final double shapeWidth;
  final double shapeHeight;

  @override
  void paint(Canvas canvas, Size size) {
    if (shapeWidth <= 0 || shapeHeight <= 0) return;

    final scale =
        min(size.width / shapeWidth, size.height / shapeHeight) * 0.85;
    final dx = (size.width - shapeWidth * scale) / 2;
    final dy = (size.height - shapeHeight * scale) / 2;

    // Draw shape
    final shapePaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final pl in shapePolylines) {
      if (pl.length < 2) continue;
      final path = Path()
        ..moveTo(pl.first.dx * scale + dx, pl.first.dy * scale + dy);
      for (int i = 1; i < pl.length; i++) {
        path.lineTo(pl[i].dx * scale + dx, pl[i].dy * scale + dy);
      }
      canvas.drawPath(path, shapePaint);
    }

    // Draw text
    final textPaint = Paint()
      ..color = const Color(0xFF1565C0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final pl in textPolylines) {
      if (pl.length < 2) continue;
      final path = Path()
        ..moveTo(pl.first.dx * scale + dx, pl.first.dy * scale + dy);
      for (int i = 1; i < pl.length; i++) {
        path.lineTo(pl[i].dx * scale + dx, pl[i].dy * scale + dy);
      }
      canvas.drawPath(path, textPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ShapeWithTextPainter old) => true;
}
