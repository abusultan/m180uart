import 'package:flutter/material.dart';

import '../../../core/app_strings.dart';
import '../../../core/font_path_service.dart';
import '../../../core/pen_write_service.dart';

/// Result returned when the user confirms pen writing.
class PenWriteScreenResult {
  const PenWriteScreenResult({
    required this.penWriteResult,
    required this.text,
    required this.fontFamily,
    required this.isHorizontal,
  });

  final PenWriteResult penWriteResult;
  final String text;
  final String fontFamily;
  final bool isHorizontal;
}

/// Screen for entering text to write with pen on the cutting machine.
/// Replicates the UpPrinting app's "Custom Cut Text" feature for DQ/Skycut.
class PenWriteScreen extends StatefulWidget {
  const PenWriteScreen({
    super.key,
    this.maxWidth,
    this.materialWidthMm = 120,
    this.materialHeightMm = 90,
  });

  final int? maxWidth;
  final double materialWidthMm;
  final double materialHeightMm;

  @override
  State<PenWriteScreen> createState() => _PenWriteScreenState();
}

class _PenWriteScreenState extends State<PenWriteScreen> {
  final _textController = TextEditingController(text: 'HELLO');
  String _fontFamily = 'AdobeGothic';
  bool _isHorizontal = true;
  List<List<Offset>>? _previewPolylines;
  String? _error;

  @override
  void initState() {
    super.initState();
    _rebuildPreview();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _rebuildPreview() {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _previewPolylines = null;
        _error = null;
      });
      return;
    }

    try {
      final polylines = FontPathService.instance.textToPolylines(
        text: text.toUpperCase(),
        fontFamily: _fontFamily,
        fontSize: 64,
        isHorizontal: _isHorizontal,
      );

      setState(() {
        _previewPolylines = polylines;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _previewPolylines = null;
        _error = e.toString();
      });
    }
  }

  void _submit() {
    final text = _textController.text.trim().toUpperCase();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter text'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final result = PenWriteService.instance.buildTextPayload(
        text: text,
        fontFamily: _fontFamily,
        isHorizontal: _isHorizontal,
        widthMm: widget.materialWidthMm,
        heightMm: widget.materialHeightMm,
      );

      Navigator.pop(
        context,
        PenWriteScreenResult(
          penWriteResult: result,
          text: text,
          fontFamily: _fontFamily,
          isHorizontal: _isHorizontal,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.of(context, 'pen_write_title')),
        backgroundColor: Colors.transparent,
      ),
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Preview area
              Container(
                height: 220,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: _previewPolylines == null || _previewPolylines!.isEmpty
                    ? Center(
                        child: Text(
                          _error ?? AppStrings.of(context, 'pen_write_preview_hint'),
                          style: const TextStyle(color: Colors.black45),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.all(16),
                        child: CustomPaint(
                          painter: _PenPreviewPainter(_previewPolylines!),
                          child: const SizedBox.expand(),
                        ),
                      ),
              ),
              const SizedBox(height: 20),

              // Text input
              TextField(
                controller: _textController,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                onChanged: (_) => _rebuildPreview(),
                decoration: InputDecoration(
                  labelText: AppStrings.of(context, 'pen_write_text_label'),
                  labelStyle: const TextStyle(color: Colors.white70),
                  hintText: 'HELLO',
                  hintStyle: const TextStyle(color: Colors.white30),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF4DB6FF)),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Font selection
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.of(context, 'pen_write_font_label'),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _fontFamily,
                    dropdownColor: const Color(0xFF252525),
                    style: const TextStyle(color: Colors.white),
                    items: FontPathService.availableFonts.entries
                        .map((e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _fontFamily = value);
                      _rebuildPreview();
                    },
                    decoration: InputDecoration(
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFF4DB6FF)),
                      ),
                    ),
                    iconEnabledColor: Colors.white70,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Direction selection
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.of(context, 'pen_write_direction_label'),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _DirectionButton(
                          label: AppStrings.of(context, 'pen_write_horizontal'),
                          icon: Icons.text_rotation_none,
                          isSelected: _isHorizontal,
                          onTap: () {
                            setState(() => _isHorizontal = true);
                            _rebuildPreview();
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DirectionButton(
                          label: AppStrings.of(context, 'pen_write_vertical'),
                          icon: Icons.text_rotate_vertical,
                          isSelected: !_isHorizontal,
                          onTap: () {
                            setState(() => _isHorizontal = false);
                            _rebuildPreview();
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Material size info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.straighten, color: Colors.white38, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      '${widget.materialWidthMm.toInt()} × ${widget.materialHeightMm.toInt()} mm',
                      style: const TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Submit button
              SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.draw),
                  label: Text(
                    AppStrings.of(context, 'pen_write_start'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4DB6FF),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DirectionButton extends StatelessWidget {
  const _DirectionButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF4DB6FF) : Colors.white24,
            width: isSelected ? 2 : 1,
          ),
          color: isSelected
              ? const Color(0xFF4DB6FF).withOpacity(0.1)
              : Colors.transparent,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? const Color(0xFF4DB6FF) : Colors.white54,
              size: 28,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF4DB6FF) : Colors.white54,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PenPreviewPainter extends CustomPainter {
  _PenPreviewPainter(this.polylines);

  final List<List<Offset>> polylines;

  @override
  void paint(Canvas canvas, Size size) {
    if (polylines.isEmpty) return;

    // Calculate bounds
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;
    for (final polyline in polylines) {
      for (final point in polyline) {
        if (point.dx < minX) minX = point.dx;
        if (point.dx > maxX) maxX = point.dx;
        if (point.dy < minY) minY = point.dy;
        if (point.dy > maxY) maxY = point.dy;
      }
    }

    final dataWidth = maxX - minX;
    final dataHeight = maxY - minY;
    if (dataWidth <= 0 || dataHeight <= 0) return;

    final scale = (size.width / dataWidth < size.height / dataHeight
            ? size.width / dataWidth
            : size.height / dataHeight) *
        0.85;
    final dx = (size.width - dataWidth * scale) / 2.0;
    final dy = (size.height - dataHeight * scale) / 2.0;

    final paint = Paint()
      ..color = const Color(0xFF1565C0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final polyline in polylines) {
      if (polyline.length < 2) continue;
      final path = Path();
      path.moveTo(
        (polyline.first.dx - minX) * scale + dx,
        (polyline.first.dy - minY) * scale + dy,
      );
      for (int i = 1; i < polyline.length; i++) {
        path.lineTo(
          (polyline[i].dx - minX) * scale + dx,
          (polyline[i].dy - minY) * scale + dy,
        );
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PenPreviewPainter oldDelegate) {
    return oldDelegate.polylines != polylines;
  }
}
