import 'package:flutter_project/core/cut_file_transformer.dart';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';


enum DqCustomOpeningSide { left, right, top, bottom }

class DqCustomOpeningSpec {
  const DqCustomOpeningSpec({
    required this.side,
    required this.widthMm,
    required this.depthMm,
    required this.radiusMm,
  });

  final DqCustomOpeningSide side;
  final double widthMm;
  final double depthMm;
  final double radiusMm;
}

class DqCustomCutSpec {
  const DqCustomCutSpec({
    required this.widthMm,
    required this.heightMm,
    required this.cornerRadiusMm,
    this.opening,
  });

  final double widthMm;
  final double heightMm;
  final double cornerRadiusMm;
  final DqCustomOpeningSpec? opening;
}

class DqCustomCutBuildResult {
  const DqCustomCutBuildResult({
    required this.payload,
    required this.bytes,
    required this.previewData,
    required this.widthUnits,
    required this.heightUnits,
  });

  final String payload;
  final List<int> bytes;
  final CutPathData previewData;
  final int widthUnits;
  final int heightUnits;
}

class DqCustomCutBuilder {
  static const String _mappingSeed = '515167676782828';
  static const double _outerOpeningRadiusMm = 1.5;

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

  static String? validate(DqCustomCutSpec spec, {int? maxWidth}) {
    if (!spec.widthMm.isFinite ||
        !spec.heightMm.isFinite ||
        !spec.cornerRadiusMm.isFinite) {
      return 'custom_cut_error_invalid_number';
    }
    if (spec.widthMm < 4 || spec.heightMm < 4) {
      return 'custom_cut_error_min_size';
    }
    if (spec.cornerRadiusMm < 0 ||
        spec.cornerRadiusMm > min(spec.widthMm, spec.heightMm) / 2.0) {
      return 'custom_cut_error_radius_half';
    }
    if (maxWidth != null && maxWidth > 0 && spec.widthMm > maxWidth - 2) {
      return 'custom_cut_error_max_width';
    }
    if (spec.heightMm > 1000) {
      return 'custom_cut_error_max_height';
    }

    final opening = spec.opening;
    if (opening == null) {
      return null;
    }

    if (!opening.widthMm.isFinite ||
        !opening.depthMm.isFinite ||
        !opening.radiusMm.isFinite) {
      return 'custom_cut_error_invalid_number';
    }

    if (spec.widthMm <= 10 || spec.heightMm <= 10) {
      return 'custom_cut_error_opening_requires_size';
    }

    final isVerticalSide =
        opening.side == DqCustomOpeningSide.left ||
        opening.side == DqCustomOpeningSide.right;

    final minOpeningWidth = 3.0;
    final maxOpeningWidth = isVerticalSide
        ? (spec.heightMm - (spec.cornerRadiusMm * 2.0) - 3.0)
        : (spec.widthMm - (spec.cornerRadiusMm * 2.0) - 3.0);
    final minOpeningDepth = 3.0;
    final maxOpeningDepth = isVerticalSide
        ? (spec.widthMm - 3.0)
        : (spec.heightMm - 3.0);

    if (opening.widthMm < minOpeningWidth ||
        opening.widthMm > maxOpeningWidth) {
      return 'custom_cut_error_opening_width_range';
    }
    if (opening.depthMm < minOpeningDepth ||
        opening.depthMm > maxOpeningDepth) {
      return 'custom_cut_error_opening_depth_range';
    }
    if (opening.radiusMm < 0 ||
        opening.radiusMm > min(opening.widthMm, opening.depthMm) / 2.0) {
      return 'custom_cut_error_opening_radius_range';
    }

    return null;
  }

  static DqCustomCutBuildResult build(DqCustomCutSpec spec, {int? maxWidth}) {
    final validationError = validate(spec, maxWidth: maxWidth);
    if (validationError != null) {
      throw FormatException(validationError);
    }

    final widthUnits = _toMachineUnits(spec.widthMm);
    final heightUnits = _toMachineUnits(spec.heightMm);
    final payloadPoints = _buildPayloadPoints(spec);
    final previewPoints = _buildPreviewPoints(spec);

    return DqCustomCutBuildResult(
      payload: _buildPayload(
        points: payloadPoints,
        widthUnits: widthUnits,
        heightUnits: heightUnits,
      ),
      bytes: latin1.encode(
        _buildPayload(
          points: payloadPoints,
          widthUnits: widthUnits,
          heightUnits: heightUnits,
        ),
      ),
      previewData: _buildPreviewData(previewPoints),
      widthUnits: widthUnits,
      heightUnits: heightUnits,
    );
  }

  static String _buildPayload({
    required List<_DqPoint> points,
    required int widthUnits,
    required int heightUnits,
  }) {
    final encodedWidth = _encodeDigits(widthUnits.toString());
    final encodedHeight = _encodeDigits(heightUnits.toString());
    final encodedZero = _encodeDigits('0');
    final buffer = StringBuffer(
      'IN SJM=$_mappingSeed FSIZE$encodedHeight,$encodedWidth;',
    );
    buffer.write('U$encodedZero,$encodedZero ');
    buffer.write('D$encodedZero,$encodedZero ');

    for (int i = 0; i < points.length; i++) {
      final point = points[i];
      final encodedX = _encodeDigits(point.x.toString());
      final encodedY = _encodeDigits(point.y.toString());
      if (i == 0) {
        buffer.write('U$encodedY,$encodedX ');
      }
      buffer.write('D$encodedY,$encodedX ');
    }

    buffer.write('U$encodedZero,$encodedZero @ ');
    return buffer.toString();
  }

  static List<_DqPoint> _buildPayloadPoints(DqCustomCutSpec spec) {
    final widthUnits = _toMachineUnits(spec.widthMm);
    final heightUnits = _toMachineUnits(spec.heightMm);
    final radiusUnits = _toMachineUnits(spec.cornerRadiusMm);
    final points = <_DqPoint>[
      _DqPoint((widthUnits - radiusUnits) - 40, heightUnits + 40),
      _DqPoint(widthUnits - radiusUnits, heightUnits),
    ];

    if (radiusUnits > 0) {
      points.addAll(
        _buildCornerArc(
          radiusUnits.toDouble(),
          (widthUnits - radiusUnits).toDouble(),
          (heightUnits - radiusUnits).toDouble(),
          360,
        ),
      );
    }

    points.add(_DqPoint(widthUnits, heightUnits - radiusUnits));
    if (spec.opening?.side == DqCustomOpeningSide.right) {
      points.addAll(_buildPayloadOpeningPoints(spec, 40.0, 0, 0));
    }

    points.add(_DqPoint(widthUnits, radiusUnits));
    if (radiusUnits > 0) {
      points.addAll(
        _buildCornerArc(
          radiusUnits.toDouble(),
          (widthUnits - radiusUnits).toDouble(),
          radiusUnits.toDouble(),
          90,
        ),
      );
    }

    points.add(_DqPoint(widthUnits - radiusUnits, 0));
    if (spec.opening?.side == DqCustomOpeningSide.top) {
      points.addAll(_buildPayloadOpeningPoints(spec, 40.0, 0, 0));
    }

    points.add(_DqPoint(radiusUnits, 0));
    if (radiusUnits > 0) {
      points.addAll(
        _buildCornerArc(
          radiusUnits.toDouble(),
          radiusUnits.toDouble(),
          radiusUnits.toDouble(),
          180,
        ),
      );
    }

    points.add(_DqPoint(0, radiusUnits));
    if (spec.opening?.side == DqCustomOpeningSide.left) {
      points.addAll(_buildPayloadOpeningPoints(spec, 40.0, 0, 0));
    }

    points.add(_DqPoint(0, heightUnits - radiusUnits));
    if (radiusUnits > 0) {
      points.addAll(
        _buildCornerArc(
          radiusUnits.toDouble(),
          radiusUnits.toDouble(),
          (heightUnits - radiusUnits).toDouble(),
          270,
        ),
      );
    }

    points.add(_DqPoint(radiusUnits, heightUnits));
    if (spec.opening?.side == DqCustomOpeningSide.bottom) {
      points.addAll(_buildPayloadOpeningPoints(spec, 40.0, 0, 0));
    }

    points.add(_DqPoint(widthUnits - radiusUnits, heightUnits));
    points.add(_DqPoint(widthUnits, heightUnits));
    points.add(_DqPoint(widthUnits + 80, heightUnits));
    return points;
  }

  static List<_DqPoint> _buildPreviewPoints(DqCustomCutSpec spec) {
    final scale = (spec.widthMm > 400 || spec.heightMm > 400) ? 1.0 : 4.0;
    final width = spec.widthMm * scale;
    final height = spec.heightMm * scale;
    final radius = spec.cornerRadiusMm * scale;
    final points = <_DqPoint>[_DqPoint(0, radius.toInt())];

    if (spec.opening?.side == DqCustomOpeningSide.left) {
      points.addAll(_buildPreviewOpeningPoints(spec, scale));
    }

    points.add(_DqPoint(0, (height - radius).toInt()));
    if (radius > 0) {
      points.addAll(_buildCornerArc(radius, radius, height - radius, 270));
    }

    points.add(_DqPoint(radius.toInt(), height.toInt()));
    if (spec.opening?.side == DqCustomOpeningSide.bottom) {
      points.addAll(_buildPreviewOpeningPoints(spec, scale));
    }

    points.add(_DqPoint((width - radius).toInt(), height.toInt()));
    if (radius > 0) {
      points.addAll(
        _buildCornerArc(radius, width - radius, height - radius, 360),
      );
    }

    points.add(_DqPoint(width.toInt(), (height - radius).toInt()));
    if (spec.opening?.side == DqCustomOpeningSide.right) {
      points.addAll(_buildPreviewOpeningPoints(spec, scale));
    }

    points.add(_DqPoint(width.toInt(), radius.toInt()));
    if (radius > 0) {
      points.addAll(_buildCornerArc(radius, width - radius, radius, 90));
    }

    points.add(_DqPoint((width - radius).toInt(), 0));
    if (spec.opening?.side == DqCustomOpeningSide.top) {
      points.addAll(_buildPreviewOpeningPoints(spec, scale));
    }

    points.add(_DqPoint(radius.toInt(), 0));
    if (radius > 0) {
      points.addAll(_buildCornerArc(radius, radius, radius, 180));
    }

    return points;
  }

  static CutPathData _buildPreviewData(List<_DqPoint> points) {
    final offsets = points
        .map((point) => Offset(point.x.toDouble(), point.y.toDouble()))
        .toList(growable: false);
    final drawFlags = List<bool>.generate(
      points.length,
      (index) => index != 0,
      growable: false,
    );

    double minX = offsets.first.dx;
    double maxX = offsets.first.dx;
    double minY = offsets.first.dy;
    double maxY = offsets.first.dy;

    for (final point in offsets) {
      if (point.dx < minX) minX = point.dx;
      if (point.dx > maxX) maxX = point.dx;
      if (point.dy < minY) minY = point.dy;
      if (point.dy > maxY) maxY = point.dy;
    }

    return CutPathData(
      points: offsets,
      drawFlags: drawFlags,
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
    );
  }

  static List<_DqPoint> _buildCornerArc(
    double radius,
    double cx,
    double cy,
    int type,
  ) {
    final points = <_DqPoint>[];
    for (int i = 4; i < 180; i += 4) {
      final angle = ((i * 0.5) * pi) / 180.0;
      final dx = cos(angle) * radius;
      final dy = radius * sin(angle);
      switch (type) {
        case 90:
          points.add(_DqPoint((cx + dx).toInt(), (cy - dy).toInt()));
          break;
        case 180:
          points.add(_DqPoint((cx - dy).toInt(), (cy - dx).toInt()));
          break;
        case 270:
          points.add(_DqPoint((cx - dx).toInt(), (cy + dy).toInt()));
          break;
        case 360:
          points.add(_DqPoint((cx + dy).toInt(), (cy + dx).toInt()));
          break;
      }
    }
    return points;
  }

  static List<_DqPoint> _buildPreviewOpeningPoints(
    DqCustomCutSpec spec,
    double scale,
  ) {
    final opening = spec.opening;
    if (opening == null) {
      return const <_DqPoint>[];
    }

    final width = spec.widthMm;
    final height = spec.heightMm;
    final openingWidth = opening.widthMm;
    final openingDepth = opening.depthMm;
    final openingRadius = opening.radiusMm;
    final outerRadius = _outerOpeningRadiusMm;

    int scaled(double value) => (value * scale).toInt();

    switch (opening.side) {
      case DqCustomOpeningSide.left:
        final points = <_DqPoint>[];
        final entryY = scaled(((width - openingWidth) / 2.0) - outerRadius);
        final outerInset = scaled(outerRadius);
        points.add(_DqPoint(0, entryY));
        points.addAll(
          _buildOpeningArc(
            outerRadius * scale,
            outerInset.toDouble(),
            entryY.toDouble(),
            4,
            1,
          ),
        );
        points.add(_DqPoint(outerInset, scaled((width - openingWidth) / 2.0)));
        final innerStartY = scaled((width - openingWidth) / 2.0);
        final innerDepth = scaled(openingDepth - openingRadius);
        final innerArcStart = innerStartY + scaled(openingRadius);
        points.add(_DqPoint(innerDepth, innerStartY));
        points.addAll(
          _buildOpeningArc(
            openingRadius * scale,
            innerDepth.toDouble(),
            innerArcStart.toDouble(),
            4,
            0,
          ),
        );
        points.add(_DqPoint(scaled(openingDepth), innerArcStart));
        final innerExitArc =
            scaled(((width - openingWidth) / 2.0) + openingWidth) -
            scaled(openingRadius);
        points.add(_DqPoint(scaled(openingDepth), innerExitArc));
        points.addAll(
          _buildOpeningArc(
            openingRadius * scale,
            innerDepth.toDouble(),
            innerExitArc.toDouble(),
            1,
            0,
          ),
        );
        points.add(
          _DqPoint(
            innerDepth,
            scaled(((width - openingWidth) / 2.0) + openingWidth),
          ),
        );
        final outerExitY = scaled(
          ((width - openingWidth) / 2.0) + openingWidth,
        );
        final outerExitArc = scaled(
          ((width - openingWidth) / 2.0) + openingWidth + outerRadius,
        );
        points.add(_DqPoint(outerInset, outerExitY));
        points.addAll(
          _buildOpeningArc(
            outerRadius * scale,
            outerInset.toDouble(),
            outerExitArc.toDouble(),
            3,
            1,
          ),
        );
        points.add(_DqPoint(0, outerExitArc));
        return points;

      case DqCustomOpeningSide.right:
        final points = <_DqPoint>[];
        final entryX = scaled(height);
        final outerY = scaled(
          ((width - openingWidth) / 2.0) + openingWidth + outerRadius,
        );
        final outerInsetX = scaled(height - outerRadius);
        points.add(_DqPoint(entryX, outerY));
        points.addAll(
          _buildOpeningArc(
            outerRadius * scale,
            outerInsetX.toDouble(),
            outerY.toDouble(),
            2,
            1,
          ),
        );
        points.add(
          _DqPoint(
            outerInsetX,
            scaled(((width - openingWidth) / 2.0) + openingWidth),
          ),
        );
        final innerRight = scaled(height - (openingDepth - openingRadius));
        final innerUpperArcY = scaled(
          (((width - openingWidth) / 2.0) + openingWidth) - openingRadius,
        );
        points.add(
          _DqPoint(
            innerRight,
            scaled(((width - openingWidth) / 2.0) + openingWidth),
          ),
        );
        points.addAll(
          _buildOpeningArc(
            openingRadius * scale,
            innerRight.toDouble(),
            innerUpperArcY.toDouble(),
            2,
            0,
          ),
        );
        points.add(_DqPoint(scaled(height - openingDepth), innerUpperArcY));
        final innerLowerArcY = scaled(
          ((width - openingWidth) / 2.0) + openingRadius,
        );
        points.add(_DqPoint(scaled(height - openingDepth), innerLowerArcY));
        points.addAll(
          _buildOpeningArc(
            openingRadius * scale,
            innerRight.toDouble(),
            innerLowerArcY.toDouble(),
            3,
            0,
          ),
        );
        points.add(_DqPoint(innerRight, scaled((width - openingWidth) / 2.0)));
        final topExitY = scaled(((width - openingWidth) / 2.0) - outerRadius);
        points.add(_DqPoint(outerInsetX, scaled((width - openingWidth) / 2.0)));
        points.addAll(
          _buildOpeningArc(
            outerRadius * scale,
            outerInsetX.toDouble(),
            topExitY.toDouble(),
            1,
            1,
          ),
        );
        points.add(_DqPoint(entryX, topExitY));
        return points;

      case DqCustomOpeningSide.top:
        final points = <_DqPoint>[];
        final entryX = scaled(
          ((height - openingWidth) / 2.0) + openingWidth + outerRadius,
        );
        final outerInset = scaled(outerRadius);
        points.add(_DqPoint(entryX, 0));
        points.addAll(
          _buildOpeningArc(
            outerRadius * scale,
            entryX.toDouble(),
            outerInset.toDouble(),
            3,
            1,
          ),
        );
        points.add(
          _DqPoint(
            scaled(((height - openingWidth) / 2.0) + openingWidth),
            outerInset,
          ),
        );
        final notchTop = scaled(openingDepth - openingRadius);
        final rightCenter = scaled(
          (((height - openingWidth) / 2.0) + openingWidth) - openingRadius,
        );
        points.add(
          _DqPoint(
            scaled(((height - openingWidth) / 2.0) + openingWidth),
            notchTop,
          ),
        );
        points.addAll(
          _buildOpeningArc(
            openingRadius * scale,
            rightCenter.toDouble(),
            notchTop.toDouble(),
            1,
            0,
          ),
        );
        points.add(_DqPoint(rightCenter, scaled(openingDepth)));
        final leftCenter = scaled(
          ((height - openingWidth) / 2.0) + openingRadius,
        );
        points.add(_DqPoint(leftCenter, scaled(openingDepth)));
        points.addAll(
          _buildOpeningArc(
            openingRadius * scale,
            leftCenter.toDouble(),
            notchTop.toDouble(),
            2,
            0,
          ),
        );
        points.add(_DqPoint(scaled((height - openingWidth) / 2.0), notchTop));
        final exitOuterX = scaled((height - openingWidth) / 2.0);
        final outerExitX = scaled(
          ((height - openingWidth) / 2.0) - outerRadius,
        );
        points.add(_DqPoint(exitOuterX, outerInset));
        points.addAll(
          _buildOpeningArc(
            outerRadius * scale,
            outerExitX.toDouble(),
            outerInset.toDouble(),
            2,
            1,
          ),
        );
        points.add(_DqPoint(outerExitX, 0));
        return points;

      case DqCustomOpeningSide.bottom:
        final points = <_DqPoint>[];
        final bottomY = scaled(width);
        final entryX = scaled(((height - openingWidth) / 2.0) - outerRadius);
        final outerInsetY = scaled(width - outerRadius);
        points.add(_DqPoint(entryX, bottomY));
        points.addAll(
          _buildOpeningArc(
            outerRadius * scale,
            entryX.toDouble(),
            outerInsetY.toDouble(),
            1,
            1,
          ),
        );
        points.add(
          _DqPoint(scaled((height - openingWidth) / 2.0), outerInsetY),
        );
        final innerLeft = scaled(
          ((height - openingWidth) / 2.0) + openingRadius,
        );
        final innerNotchTop = scaled(width - (openingDepth - openingRadius));
        points.add(
          _DqPoint(scaled((height - openingWidth) / 2.0), innerNotchTop),
        );
        points.addAll(
          _buildOpeningArc(
            openingRadius * scale,
            innerLeft.toDouble(),
            innerNotchTop.toDouble(),
            3,
            0,
          ),
        );
        points.add(_DqPoint(innerLeft, scaled(width - openingDepth)));
        final innerRight = scaled(
          (((height - openingWidth) / 2.0) + openingWidth) - openingRadius,
        );
        points.add(_DqPoint(innerRight, scaled(width - openingDepth)));
        points.addAll(
          _buildOpeningArc(
            openingRadius * scale,
            innerRight.toDouble(),
            innerNotchTop.toDouble(),
            4,
            0,
          ),
        );
        points.add(
          _DqPoint(
            scaled(((height - openingWidth) / 2.0) + openingWidth),
            innerNotchTop,
          ),
        );
        final outerExitX = scaled(
          ((height - openingWidth) / 2.0) + openingWidth,
        );
        final outerExitArcX = scaled(
          ((height - openingWidth) / 2.0) + openingWidth + outerRadius,
        );
        points.add(_DqPoint(outerExitX, outerInsetY));
        points.addAll(
          _buildOpeningArc(
            outerRadius * scale,
            outerExitArcX.toDouble(),
            outerInsetY.toDouble(),
            4,
            1,
          ),
        );
        points.add(_DqPoint(outerExitArcX, bottomY));
        return points;
    }
  }

  static List<_DqPoint> _buildPayloadOpeningPoints(
    DqCustomCutSpec spec,
    double scale,
    int offsetX,
    int offsetY,
  ) {
    final opening = spec.opening;
    if (opening == null) {
      return const <_DqPoint>[];
    }

    final height = spec.heightMm + (offsetX / scale);
    final width = spec.widthMm + (offsetY / scale);
    final openingWidth = opening.widthMm;
    final openingDepth = opening.depthMm;
    final openingRadius = opening.radiusMm;
    final outerRadius = _outerOpeningRadiusMm;
    final outerRadiusUnits = outerRadius * scale;
    final openingRadiusUnits = openingRadius * scale;

    int scaled(double value) => (value * scale).toInt();

    switch (opening.side) {
      case DqCustomOpeningSide.left:
        final points = <_DqPoint>[];
        final entryY =
            scaled(((width - openingWidth) / 2.0) - outerRadius) + offsetY;
        final outerInset = scaled(outerRadius) + offsetX;
        points.add(_DqPoint(offsetX, entryY));
        points.addAll(
          _buildOpeningArc(
            outerRadiusUnits,
            outerInset.toDouble(),
            entryY.toDouble(),
            4,
            1,
          ),
        );
        points.add(
          _DqPoint(outerInset, scaled((width - openingWidth) / 2.0) + offsetY),
        );
        final innerStartY = scaled((width - openingWidth) / 2.0) + offsetY;
        final innerDepth = scaled(openingDepth - openingRadius) + offsetX;
        final innerArcStart = innerStartY + openingRadiusUnits.toInt();
        points.add(_DqPoint(innerDepth, innerStartY));
        points.addAll(
          _buildOpeningArc(
            openingRadiusUnits,
            innerDepth.toDouble(),
            innerArcStart.toDouble(),
            4,
            0,
          ),
        );
        points.add(_DqPoint(scaled(openingDepth) + offsetX, innerArcStart));
        final innerExitArc =
            scaled(((width - openingWidth) / 2.0) + openingWidth) -
            openingRadiusUnits.toInt() +
            offsetY;
        points.add(_DqPoint(scaled(openingDepth) + offsetX, innerExitArc));
        points.addAll(
          _buildOpeningArc(
            openingRadiusUnits,
            innerDepth.toDouble(),
            innerExitArc.toDouble(),
            1,
            0,
          ),
        );
        points.add(
          _DqPoint(
            innerDepth,
            scaled(((width - openingWidth) / 2.0) + openingWidth) + offsetY,
          ),
        );
        final exitOuterX = scaled(outerRadius) + offsetX;
        final outerExitY =
            scaled(
              ((width - openingWidth) / 2.0) + openingWidth + outerRadius,
            ) +
            offsetY;
        points.add(
          _DqPoint(
            exitOuterX,
            scaled(((width - openingWidth) / 2.0) + openingWidth) + offsetY,
          ),
        );
        points.addAll(
          _buildOpeningArc(
            outerRadiusUnits,
            exitOuterX.toDouble(),
            outerExitY.toDouble(),
            3,
            1,
          ),
        );
        points.add(_DqPoint(offsetX, outerExitY));
        return points;

      case DqCustomOpeningSide.right:
        final points = <_DqPoint>[];
        final rightEdge = scaled(height) + offsetX;
        final entryY =
            scaled(
              ((width - openingWidth) / 2.0) + openingWidth + outerRadius,
            ) +
            offsetY;
        final outerInsetX = scaled(height - outerRadius) + offsetX;
        points.add(_DqPoint(rightEdge, entryY));
        points.addAll(
          _buildOpeningArc(
            outerRadiusUnits,
            outerInsetX.toDouble(),
            entryY.toDouble(),
            2,
            1,
          ),
        );
        points.add(
          _DqPoint(
            outerInsetX,
            scaled(((width - openingWidth) / 2.0) + openingWidth) + offsetY,
          ),
        );
        final innerRight =
            scaled(height - (openingDepth - openingRadius)) + offsetX;
        final upperArcY =
            scaled(
              (((width - openingWidth) / 2.0) + openingWidth) - openingRadius,
            ) +
            offsetY;
        points.add(
          _DqPoint(
            innerRight,
            scaled(((width - openingWidth) / 2.0) + openingWidth) + offsetY,
          ),
        );
        points.addAll(
          _buildOpeningArc(
            openingRadiusUnits,
            innerRight.toDouble(),
            upperArcY.toDouble(),
            2,
            0,
          ),
        );
        points.add(
          _DqPoint(scaled(height - openingDepth) + offsetX, upperArcY),
        );
        final lowerArcY =
            scaled(((width - openingWidth) / 2.0) + openingRadius) + offsetY;
        points.add(
          _DqPoint(scaled(height - openingDepth) + offsetX, lowerArcY),
        );
        points.addAll(
          _buildOpeningArc(
            openingRadiusUnits,
            innerRight.toDouble(),
            lowerArcY.toDouble(),
            3,
            0,
          ),
        );
        points.add(
          _DqPoint(innerRight, scaled((width - openingWidth) / 2.0) + offsetY),
        );
        final topExitY =
            scaled(((width - openingWidth) / 2.0) - outerRadius) + offsetY;
        points.add(
          _DqPoint(outerInsetX, scaled((width - openingWidth) / 2.0) + offsetY),
        );
        points.addAll(
          _buildOpeningArc(
            outerRadiusUnits,
            outerInsetX.toDouble(),
            topExitY.toDouble(),
            1,
            1,
          ),
        );
        points.add(_DqPoint(rightEdge, topExitY));
        return points;

      case DqCustomOpeningSide.top:
        final points = <_DqPoint>[];
        final topY = offsetY;
        final entryX =
            scaled(
              ((height - openingWidth) / 2.0) + openingWidth + outerRadius,
            ) +
            offsetX;
        final outerInset = scaled(outerRadius) + offsetY;
        points.add(_DqPoint(entryX, topY));
        points.addAll(
          _buildOpeningArc(
            outerRadiusUnits,
            entryX.toDouble(),
            outerInset.toDouble(),
            3,
            1,
          ),
        );
        points.add(
          _DqPoint(
            scaled(((height - openingWidth) / 2.0) + openingWidth) + offsetX,
            outerInset,
          ),
        );
        final notchTop = scaled(openingDepth - openingRadius) + offsetY;
        final rightCenter =
            scaled(
              (((height - openingWidth) / 2.0) + openingWidth) - openingRadius,
            ) +
            offsetX;
        points.add(
          _DqPoint(
            scaled(((height - openingWidth) / 2.0) + openingWidth) + offsetX,
            notchTop,
          ),
        );
        points.addAll(
          _buildOpeningArc(
            openingRadiusUnits,
            rightCenter.toDouble(),
            notchTop.toDouble(),
            1,
            0,
          ),
        );
        points.add(_DqPoint(rightCenter, scaled(openingDepth) + offsetY));
        final leftCenter =
            scaled(((height - openingWidth) / 2.0) + openingRadius) + offsetX;
        points.add(_DqPoint(leftCenter, scaled(openingDepth) + offsetY));
        points.addAll(
          _buildOpeningArc(
            openingRadiusUnits,
            leftCenter.toDouble(),
            notchTop.toDouble(),
            2,
            0,
          ),
        );
        points.add(
          _DqPoint(scaled((height - openingWidth) / 2.0) + offsetX, notchTop),
        );
        final outerExitX = scaled((height - openingWidth) / 2.0) + offsetX;
        final outerArcExitX =
            scaled(((height - openingWidth) / 2.0) - outerRadius) + offsetX;
        points.add(_DqPoint(outerExitX, outerInset));
        points.addAll(
          _buildOpeningArc(
            outerRadiusUnits,
            outerArcExitX.toDouble(),
            outerInset.toDouble(),
            2,
            1,
          ),
        );
        points.add(_DqPoint(outerArcExitX, topY));
        return points;

      case DqCustomOpeningSide.bottom:
        final points = <_DqPoint>[];
        final bottomY = scaled(width) + offsetY;
        final entryX =
            scaled(((height - openingWidth) / 2.0) - outerRadius) + offsetX;
        final outerInsetY = scaled(width - outerRadius) + offsetY;
        points.add(_DqPoint(entryX, bottomY));
        points.addAll(
          _buildOpeningArc(
            outerRadiusUnits,
            entryX.toDouble(),
            outerInsetY.toDouble(),
            1,
            1,
          ),
        );
        points.add(
          _DqPoint(
            scaled((height - openingWidth) / 2.0) + offsetX,
            outerInsetY,
          ),
        );
        final innerLeft =
            scaled(((height - openingWidth) / 2.0) + openingRadius) + offsetX;
        final innerNotchY =
            scaled(width - (openingDepth - openingRadius)) + offsetY;
        points.add(
          _DqPoint(
            scaled((height - openingWidth) / 2.0) + offsetX,
            innerNotchY,
          ),
        );
        points.addAll(
          _buildOpeningArc(
            openingRadiusUnits,
            innerLeft.toDouble(),
            innerNotchY.toDouble(),
            3,
            0,
          ),
        );
        points.add(_DqPoint(innerLeft, scaled(width - openingDepth) + offsetY));
        final innerRight =
            scaled(
              (((height - openingWidth) / 2.0) + openingWidth) - openingRadius,
            ) +
            offsetX;
        points.add(
          _DqPoint(innerRight, scaled(width - openingDepth) + offsetY),
        );
        points.addAll(
          _buildOpeningArc(
            openingRadiusUnits,
            innerRight.toDouble(),
            innerNotchY.toDouble(),
            4,
            0,
          ),
        );
        points.add(
          _DqPoint(
            scaled(((height - openingWidth) / 2.0) + openingWidth) + offsetX,
            innerNotchY,
          ),
        );
        final outerExitX =
            scaled(((height - openingWidth) / 2.0) + openingWidth) + offsetX;
        final outerArcExitX =
            scaled(
              ((height - openingWidth) / 2.0) + openingWidth + outerRadius,
            ) +
            offsetX;
        points.add(_DqPoint(outerExitX, outerInsetY));
        points.addAll(
          _buildOpeningArc(
            outerRadiusUnits,
            outerArcExitX.toDouble(),
            outerInsetY.toDouble(),
            4,
            1,
          ),
        );
        points.add(_DqPoint(outerArcExitX, bottomY));
        return points;
    }
  }

  static List<_DqPoint> _buildOpeningArc(
    double radius,
    double cx,
    double cy,
    int quadrant,
    int mode,
  ) {
    final points = <_DqPoint>[];
    for (int i = 1; i < 180; i += 4) {
      final angle = ((i * 0.5) * pi) / 180.0;
      final dx = (cos(angle) * radius).toInt();
      final dy = (sin(angle) * radius).toInt();
      if (mode == 1) {
        switch (quadrant) {
          case 1:
            points.add(_DqPoint((dy + cx).toInt(), (dx + cy).toInt()));
            break;
          case 2:
            points.add(_DqPoint((dx + cx).toInt(), (cy - dy).toInt()));
            break;
          case 3:
            points.add(_DqPoint((cx - dy).toInt(), (cy - dx).toInt()));
            break;
          case 4:
            points.add(_DqPoint((cx - dx).toInt(), (dy + cy).toInt()));
            break;
        }
      } else {
        switch (quadrant) {
          case 1:
            points.add(_DqPoint((dx + cx).toInt(), (dy + cy).toInt()));
            break;
          case 2:
            points.add(_DqPoint((cx - dy).toInt(), (dx + cy).toInt()));
            break;
          case 3:
            points.add(_DqPoint((cx - dx).toInt(), (cy - dy).toInt()));
            break;
          case 4:
            points.add(_DqPoint((dy + cx).toInt(), (cy - dx).toInt()));
            break;
        }
      }
    }
    return points;
  }

  static int _toMachineUnits(double mm) => (mm * 40.0).toInt();

  static String _encodeDigits(String value) {
    final buffer = StringBuffer();
    for (final char in value.split('')) {
      buffer.write(_digitMap[char] ?? char);
    }
    return buffer.toString();
  }
}

class _DqPoint {
  const _DqPoint(this.x, this.y);

  final int x;
  final int y;
}
