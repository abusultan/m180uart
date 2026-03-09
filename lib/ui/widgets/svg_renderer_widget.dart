import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart' as svg;
import '../../services/api_service.dart';
import '../../utils/svg_outline.dart';

/// A professional SVG renderer that handles multi-color vs single-color cut lines.
class SvgRenderer extends StatelessWidget {
  final String url;
  final bool isCutLine;
  final double? width;
  final double? height;
  final BoxFit fit;

  const SvgRenderer({
    super.key,
    required this.url,
    this.isCutLine = false,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return const SizedBox();

    final downloadUrl = url;

    return FutureBuilder<File?>(
      future: ApiService().downloadFile(downloadUrl),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF00FF88),
            ),
          );
        }

        if (snapshot.hasError || snapshot.data == null) {
          return _buildNetworkFallback(downloadUrl);
        }

        final file = snapshot.data!;
        return FutureBuilder<Uint8List>(
          future: file.readAsBytes(),
          builder: (context, bytesSnap) {
            if (bytesSnap.connectionState == ConnectionState.waiting) {
              return const SizedBox();
            }
            if (!bytesSnap.hasData || bytesSnap.data!.isEmpty) {
              return _buildNetworkFallback(downloadUrl);
            }

            try {
              final svgText = decodeSvgBytes(bytesSnap.data!);
              if (svgText.isEmpty) return _buildNetworkFallback(downloadUrl);

              if (isCutLine) {
                final transformed = toOutlineSvg(svgText);
                return Container(
                  color: Colors.white,
                  child: svg.SvgPicture.string(
                    transformed,
                    width: width,
                    height: height,
                    fit: fit,
                    placeholderBuilder: (_) => const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF00FF88),
                      ),
                    ),
                  ),
                );
              }

              return svg.SvgPicture.string(
                svgText,
                width: width,
                height: height,
                fit: fit,
                errorBuilder: (c, e, s) => _buildNetworkFallback(downloadUrl),
              );
            } catch (e) {
              return _buildNetworkFallback(downloadUrl);
            }
          },
        );
      },
    );
  }

  Widget _buildNetworkFallback(String downloadUrl) {
    final fallbackSvg = svg.SvgPicture.network(
      downloadUrl,
      width: width,
      height: height,
      fit: fit,
      placeholderBuilder: (_) => const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Color(0xFF00FF88),
        ),
      ),
      errorBuilder: (context, error, stackTrace) => const Center(
        child: Icon(Icons.broken_image, color: Colors.grey, size: 24),
      ),
    );

    return Container(
      color: isCutLine ? Colors.white : Colors.transparent,
      child: fallbackSvg,
    );
  }
}
