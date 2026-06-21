import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_strings.dart';
import '../../core/cut_file_transformer.dart';
import '../../core/cut_text_overlay_service.dart';
import '../../core/dq_custom_cut.dart';
import '../widgets/text_overlay_interactive_viewer.dart';
import 'cut_text_overlay_sheet.dart';

class DqCustomCutResult {
  const DqCustomCutResult({required this.spec, this.textOverlaySpec});

  final DqCustomCutSpec spec;
  final CutTextOverlaySpec? textOverlaySpec;
}

class DqCustomCutScreen extends StatefulWidget {
  const DqCustomCutScreen({super.key, this.maxWidth});

  final int? maxWidth;

  @override
  State<DqCustomCutScreen> createState() => _DqCustomCutScreenState();
}

class _DqCustomCutScreenState extends State<DqCustomCutScreen> {
  late final TextEditingController _widthController;
  late final TextEditingController _heightController;
  late final TextEditingController _cornerRadiusController;
  late final TextEditingController _openingWidthController;
  late final TextEditingController _openingDepthController;
  late final TextEditingController _openingRadiusController;

  bool _openingEnabled = false;
  DqCustomOpeningSide _openingSide = DqCustomOpeningSide.left;
  CutPathData? _previewData;
  CutPathData? _textOverlayPreviewData;
  String? _errorKey;
  CutTextOverlaySpec? _textOverlaySpec;

  @override
  void initState() {
    super.initState();
    _widthController = TextEditingController(text: '120.0');
    _heightController = TextEditingController(text: '90.0');
    _cornerRadiusController = TextEditingController(text: '0.0');
    _openingWidthController = TextEditingController(text: '20.0');
    _openingDepthController = TextEditingController(text: '10.0');
    _openingRadiusController = TextEditingController(text: '0.0');
    _rebuildPreview();
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    _cornerRadiusController.dispose();
    _openingWidthController.dispose();
    _openingDepthController.dispose();
    _openingRadiusController.dispose();
    super.dispose();
  }

  DqCustomCutSpec? _buildSpec() {
    final width = double.tryParse(_widthController.text.trim());
    final height = double.tryParse(_heightController.text.trim());
    final cornerRadius = double.tryParse(_cornerRadiusController.text.trim());
    if (width == null || height == null || cornerRadius == null) {
      return null;
    }

    DqCustomOpeningSpec? opening;
    if (_openingEnabled) {
      final openingWidth = double.tryParse(_openingWidthController.text.trim());
      final openingDepth = double.tryParse(_openingDepthController.text.trim());
      final openingRadius = double.tryParse(
        _openingRadiusController.text.trim(),
      );
      if (openingWidth == null ||
          openingDepth == null ||
          openingRadius == null) {
        return null;
      }
      opening = DqCustomOpeningSpec(
        side: _openingSide,
        widthMm: openingWidth,
        depthMm: openingDepth,
        radiusMm: openingRadius,
      );
    }

    return DqCustomCutSpec(
      widthMm: width,
      heightMm: height,
      cornerRadiusMm: cornerRadius,
      opening: opening,
    );
  }

  void _rebuildPreview() {
    final spec = _buildSpec();
    if (spec == null) {
      setState(() {
        _errorKey = 'custom_cut_error_invalid_number';
        _previewData = null;
        _textOverlayPreviewData = null;
      });
      return;
    }

    final errorKey = DqCustomCutBuilder.validate(
      spec,
      maxWidth: widget.maxWidth,
    );
    if (errorKey != null) {
      setState(() {
        _errorKey = errorKey;
        _previewData = null;
        _textOverlayPreviewData = null;
      });
      return;
    }

    final result = DqCustomCutBuilder.build(spec, maxWidth: widget.maxWidth);
    CutPathData? overlayPreview;
    if (_textOverlaySpec != null) {
      try {
        final overlayResult = CutTextOverlayService.build(
          baseData: result.previewData,
          spec: _textOverlaySpec!,
          transport: CutTextOverlayTransport.dqSjm,
          maxWidth: widget.maxWidth,
        );
        overlayPreview = overlayResult.overlayPreviewData;
      } catch (_) {
        // Text overlay failed, just show shape without text
      }
    }
    setState(() {
      _errorKey = null;
      _previewData = result.previewData;
      _textOverlayPreviewData = overlayPreview;
    });
  }

  void _submit() {
    final spec = _buildSpec();
    if (spec == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.of(context, 'custom_cut_error_invalid_number'),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final errorKey = DqCustomCutBuilder.validate(
      spec,
      maxWidth: widget.maxWidth,
    );
    if (errorKey != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context, errorKey)),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    Navigator.pop(
      context,
      DqCustomCutResult(spec: spec, textOverlaySpec: _textOverlaySpec),
    );
  }

  Future<void> _openTextOverlaySheet() async {
    final result = await showCutTextOverlaySheet(
      context,
      initialSpec: _textOverlaySpec,
    );
    if (result == null) return;
    if (result.cleared) {
      setState(() {
        _textOverlaySpec = null;
        _textOverlayPreviewData = null;
      });
      _rebuildPreview();
      return;
    }
    if (result.spec != null) {
      setState(() {
        _textOverlaySpec = result.spec;
      });
      _rebuildPreview();
    }
  }

  Widget _buildNumberField({
    required String label,
    required TextEditingController controller,
    required VoidCallback onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      onChanged: (_) => onChanged(),
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        suffixText: 'mm',
        suffixStyle: const TextStyle(color: Colors.white54),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.white24),
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Color(0xFF4DB6FF)),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxWidth = widget.maxWidth;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.of(context, 'custom_cut_title')),
        backgroundColor: Colors.transparent,
      ),
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 280,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: _previewData == null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            AppStrings.of(
                              context,
                              _errorKey ?? 'custom_cut_preview_unavailable',
                            ),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.all(16),
                        child: _textOverlaySpec != null
                            ? TextOverlayEditor(
                                baseData: _previewData!,
                                spec: _textOverlaySpec!,
                                transport: CutTextOverlayTransport.dqSjm,
                                flipX: false,
                                onSpecChanged: (newSpec) {
                                  setState(() {
                                    _textOverlaySpec = newSpec;
                                  });
                                  _rebuildPreview();
                                },
                              )
                            : CustomPaint(
                                painter: _DqCustomPreviewPainter(
                                  _previewData!,
                                ),
                                child: const SizedBox.expand(),
                              ),
                      ),
              ),
              const SizedBox(height: 16),
              if (maxWidth != null && maxWidth > 0)
                Text(
                  AppStrings.of(
                    context,
                    'custom_cut_max_width',
                  ).replaceAll('{value}', maxWidth.toString()),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildNumberField(
                      label: AppStrings.of(context, 'custom_cut_width'),
                      controller: _widthController,
                      onChanged: _rebuildPreview,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildNumberField(
                      label: AppStrings.of(context, 'custom_cut_height'),
                      controller: _heightController,
                      onChanged: _rebuildPreview,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildNumberField(
                label: AppStrings.of(context, 'custom_cut_corner_radius'),
                controller: _cornerRadiusController,
                onChanged: _rebuildPreview,
              ),
              const SizedBox(height: 20),
              SwitchListTile(
                value: _openingEnabled,
                activeColor: const Color(0xFF4DB6FF),
                title: Text(
                  AppStrings.of(context, 'custom_cut_opening_title'),
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  AppStrings.of(context, 'custom_cut_opening_subtitle'),
                  style: const TextStyle(color: Colors.white70),
                ),
                onChanged: (value) {
                  setState(() {
                    _openingEnabled = value;
                  });
                  _rebuildPreview();
                },
              ),
              if (_openingEnabled) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<DqCustomOpeningSide>(
                  value: _openingSide,
                  dropdownColor: const Color(0xFF1F1F1F),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: AppStrings.of(
                      context,
                      'custom_cut_opening_side',
                    ),
                    labelStyle: const TextStyle(color: Colors.white70),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.white24),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFF4DB6FF)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: DqCustomOpeningSide.values
                      .map((side) {
                        final labelKey = switch (side) {
                          DqCustomOpeningSide.left => 'custom_cut_side_left',
                          DqCustomOpeningSide.right => 'custom_cut_side_right',
                          DqCustomOpeningSide.top => 'custom_cut_side_top',
                          DqCustomOpeningSide.bottom =>
                            'custom_cut_side_bottom',
                        };
                        return DropdownMenuItem(
                          value: side,
                          child: Text(AppStrings.of(context, labelKey)),
                        );
                      })
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _openingSide = value;
                    });
                    _rebuildPreview();
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildNumberField(
                        label: AppStrings.of(
                          context,
                          'custom_cut_opening_width',
                        ),
                        controller: _openingWidthController,
                        onChanged: _rebuildPreview,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildNumberField(
                        label: AppStrings.of(
                          context,
                          'custom_cut_opening_depth',
                        ),
                        controller: _openingDepthController,
                        onChanged: _rebuildPreview,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildNumberField(
                  label: AppStrings.of(context, 'custom_cut_opening_radius'),
                  controller: _openingRadiusController,
                  onChanged: _rebuildPreview,
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _openTextOverlaySheet,
                  icon: Icon(
                    _textOverlaySpec != null ? Icons.edit : Icons.text_fields,
                  ),
                  label: Text(
                    _textOverlaySpec != null
                        ? '${AppStrings.of(context, 'text_overlay_title')}: ${_textOverlaySpec!.text}'
                        : AppStrings.of(context, 'text_overlay_title'),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _textOverlaySpec != null
                        ? const Color(0xFF4DB6FF)
                        : Colors.white70,
                    side: BorderSide(
                      color: _textOverlaySpec != null
                          ? const Color(0xFF4DB6FF)
                          : Colors.white24,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4DB6FF),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    AppStrings.of(context, 'custom_cut_apply'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
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

class _DqCustomPreviewPainter extends CustomPainter {
  _DqCustomPreviewPainter(this.data, {this.textOverlayData});

  final CutPathData data;
  final CutPathData? textOverlayData;

  @override
  void paint(Canvas canvas, Size size) {
    final width = (data.maxX - data.minX).abs();
    final height = (data.maxY - data.minY).abs();
    if (width == 0 || height == 0) {
      return;
    }

    final scale = width > 0 && height > 0
        ? (size.width / width < size.height / height
                  ? size.width / width
                  : size.height / height) *
              0.8
        : 1.0;
    final dx = (size.width - width * scale) / 2.0;
    final dy = (size.height - height * scale) / 2.0;

    final path = Path();
    var started = false;
    for (int i = 0; i < data.points.length; i++) {
      final point = data.points[i];
      final x = (point.dx - data.minX) * scale + dx;
      final y = (point.dy - data.minY) * scale + dy;
      if (!started || !data.drawFlags[i]) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Draw text overlay if present
    final overlay = textOverlayData;
    if (overlay != null && overlay.points.isNotEmpty) {
      final textPath = Path();
      var textStarted = false;
      for (int i = 0; i < overlay.points.length; i++) {
        final point = overlay.points[i];
        final x = (point.dx - data.minX) * scale + dx;
        final y = (point.dy - data.minY) * scale + dy;
        if (!textStarted || !overlay.drawFlags[i]) {
          textPath.moveTo(x, y);
          textStarted = true;
        } else {
          textPath.lineTo(x, y);
        }
      }

      canvas.drawPath(
        textPath,
        Paint()
          ..color = const Color(0xFF4DB6FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DqCustomPreviewPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.textOverlayData != textOverlayData;
  }
}
