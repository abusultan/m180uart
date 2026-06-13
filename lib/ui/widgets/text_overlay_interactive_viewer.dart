import 'package:flutter/material.dart';
import '../../../core/cut_file_transformer.dart';
import '../../../core/cut_text_overlay_service.dart';

class TextOverlayEditor extends StatefulWidget {
  const TextOverlayEditor({
    super.key,
    required this.baseData,
    required this.spec,
    required this.transport,
    required this.flipX,
    required this.onSpecChanged,
  });

  final CutPathData baseData;
  final CutTextOverlaySpec spec;
  final CutTextOverlayTransport transport;
  final bool flipX;
  final ValueChanged<CutTextOverlaySpec> onSpecChanged;

  @override
  State<TextOverlayEditor> createState() => _TextOverlayEditorState();
}

class _TextOverlayEditorState extends State<TextOverlayEditor> {
  late CutTextOverlaySpec _currentSpec;

  double _baseScale = 1.0;
  double _baseRotation = 0.0;

  CutPathData? _previewData;

  @override
  void initState() {
    super.initState();
    _currentSpec = widget.spec;
    _updatePreview();
  }

  @override
  void didUpdateWidget(covariant TextOverlayEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spec != widget.spec ||
        oldWidget.baseData != widget.baseData ||
        oldWidget.transport != widget.transport) {
      _currentSpec = widget.spec;
      _updatePreview();
    }
  }

  void _updatePreview() {
    try {
      _previewData = CutTextOverlayService.generatePreviewData(
        baseData: widget.baseData,
        spec: _currentSpec,
        transport: widget.transport,
        flipX: widget.flipX,
      );
    } catch (_) {
      _previewData = null;
    }
  }

  double _calculateMachineScale(Size size) {
    final width = widget.baseData.maxX - widget.baseData.minX;
    final height = widget.baseData.maxY - widget.baseData.minY;
    if (width == 0 || height == 0) return 1.0;
    const padding = 16.0;
    final scaleX = (size.width - padding * 2) / width;
    final scaleY = (size.height - padding * 2) / height;
    return scaleX < scaleY ? scaleX : scaleY;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenScale = _calculateMachineScale(constraints.biggest);

        return GestureDetector(
          onScaleStart: (details) {
            _baseScale = _currentSpec.scale;
            _baseRotation = _currentSpec.rotation;
          },
          onScaleUpdate: (details) {
            setState(() {
              if (details.pointerCount == 1) {
                // 1-finger: Only Translation
                final dxDelta = details.focalPointDelta.dx / screenScale;
                final dyDelta = details.focalPointDelta.dy / screenScale;
                
                final adjustedDxDelta = widget.flipX ? -dxDelta : dxDelta;

                _currentSpec = _currentSpec.copyWith(
                  dx: _currentSpec.dx + adjustedDxDelta,
                  dy: _currentSpec.dy + dyDelta,
                );
              } else if (details.pointerCount >= 2) {
                // 2-fingers: Only Scale & Rotation (prevent jumpy translation)
                final adjustedRotation = widget.flipX ? -details.rotation : details.rotation;

                _currentSpec = _currentSpec.copyWith(
                  scale: (_baseScale * details.scale).clamp(0.01, 1000.0),
                  rotation: _baseRotation + adjustedRotation,
                );
              }
              _updatePreview();
            });
          },
          onScaleEnd: (details) {
            widget.onSpecChanged(_currentSpec);
          },
          child: Container(
            color: Colors.transparent, // to catch touches
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: CutPreviewPainter(
                      widget.baseData,
                      flipX: widget.flipX,
                    ),
                  ),
                ),
                if (_previewData != null)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: CutPreviewPainter(
                        _previewData!,
                        flipX: widget.flipX,
                        refBounds: widget.baseData,
                        color: const Color(0xFF00FF88),
                      ),
                    ),
                  ),
                if (_previewData != null)
                  Positioned(
                    bottom: 16,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Text Size: ${((_previewData!.maxX - _previewData!.minX) / 40.0).toStringAsFixed(1)} x ${((_previewData!.maxY - _previewData!.minY) / 40.0).toStringAsFixed(1)} mm',
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class CutPreviewPainter extends CustomPainter {
  CutPreviewPainter(this.data, {this.flipX = false, this.refBounds, this.color});

  final CutPathData data;
  final bool flipX;
  final CutPathData? refBounds;
  final Color? color;

  @override
  void paint(Canvas canvas, Size size) {
    final ref = refBounds ?? data;
    final width = ref.maxX - ref.minX;
    final height = ref.maxY - ref.minY;
    if (width == 0 || height == 0) return;

    const padding = 16.0;
    final scaleX = (size.width - padding * 2) / width;
    final scaleY = (size.height - padding * 2) / height;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    final drawWidth = width * scale;
    final drawHeight = height * scale;
    final offsetX = (size.width - drawWidth) / 2;
    final offsetY = (size.height - drawHeight) / 2;

    final path = Path();
    bool started = false;
    for (int i = 0; i < data.points.length; i++) {
      final p = data.points[i];
      final x = flipX
          ? (ref.maxX - p.dx) * scale + offsetX
          : (p.dx - ref.minX) * scale + offsetX;
      final y = (p.dy - ref.minY) * scale + offsetY;
      if (!started || !data.drawFlags[i]) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..color = color ?? Colors.black87
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CutPreviewPainter oldDelegate) {
    return oldDelegate.data != data || oldDelegate.flipX != flipX ||
        oldDelegate.refBounds != refBounds || oldDelegate.color != color;
  }
}
