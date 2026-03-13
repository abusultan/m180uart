import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/bluetooth_service.dart';
import 'svg_renderer_widget.dart';

class ProductThumbnail extends StatelessWidget {
  final int productId;
  final String primaryImageUrl;
  final String fallbackImageUrl;
  final BoxFit fit;
  final IconData fallbackIcon;

  const ProductThumbnail({
    super.key,
    required this.productId,
    required this.primaryImageUrl,
    this.fallbackImageUrl = '',
    this.fit = BoxFit.contain,
    this.fallbackIcon = Icons.smartphone,
  });

  static final Map<String, Future<_ResolvedProductThumbnail>> _cache = {};

  Future<_ResolvedProductThumbnail> _resolvePreview() async {
    final api = ApiService();
    final bluetooth = CutterBluetoothService();
    final primary = api.normalizeUrl(primaryImageUrl);
    final fallback = api.normalizeUrl(fallbackImageUrl);
    final defaultUrl = primary.isNotEmpty ? primary : fallback;

    final serial = bluetooth.serialNumber?.trim().toUpperCase() ?? '';
    final isDqLike = serial.startsWith('DQ') ||
        serial.startsWith('DX') ||
        serial.startsWith('LH') ||
        (serial.isEmpty && (await bluetooth.getLastMachineIsDQ() ?? false));

    if (!isDqLike || productId <= 0) {
      return _ResolvedProductThumbnail(
        url: defaultUrl,
        isSvg: _looksLikeSvgUrl(defaultUrl),
        isCutLine: false,
      );
    }

    try {
      final typeMachineName = await bluetooth.getTypeMachineNameForItems();
      final items = await api.getProductItems(
        productId,
        typeMachineName: typeMachineName,
      );
      for (final item in items) {
        final candidate = item.preferredPreviewUrl.trim();
        if (candidate.isEmpty) continue;
        final normalized = api.normalizeUrl(candidate);
        if (normalized.isEmpty) continue;
        return _ResolvedProductThumbnail(
          url: normalized,
          isSvg: _looksLikeSvgUrl(normalized),
          isCutLine: _looksLikeSvgUrl(normalized),
        );
      }
    } catch (_) {}

    return _ResolvedProductThumbnail(
      url: defaultUrl,
      isSvg: _looksLikeSvgUrl(defaultUrl),
      isCutLine: _looksLikeSvgUrl(defaultUrl),
    );
  }

  Future<_ResolvedProductThumbnail> _cachedFuture() {
    final bluetooth = CutterBluetoothService();
    final key =
        '${bluetooth.serialNumber}|${bluetooth.cachedAgentType}|$productId|$primaryImageUrl|$fallbackImageUrl';
    return _cache.putIfAbsent(key, _resolvePreview);
  }

  @override
  Widget build(BuildContext context) {
    final api = ApiService();
    final defaultUrl = api.normalizeUrl(
      primaryImageUrl.isNotEmpty ? primaryImageUrl : fallbackImageUrl,
    );
    final defaultResolved = _ResolvedProductThumbnail(
      url: defaultUrl,
      isSvg: _looksLikeSvgUrl(defaultUrl),
      isCutLine: false,
    );

    return FutureBuilder<_ResolvedProductThumbnail>(
      future: _cachedFuture(),
      builder: (context, snapshot) {
        final resolved = snapshot.data ?? defaultResolved;
        if (resolved.url.isEmpty) {
          return Icon(fallbackIcon, color: Colors.grey);
        }

        if (resolved.isSvg) {
          return SvgRenderer(
            url: resolved.url,
            isCutLine: resolved.isCutLine,
            fit: fit,
          );
        }

        return Image.network(
          resolved.url,
          fit: fit,
          errorBuilder: (context, error, stackTrace) =>
              Icon(fallbackIcon, color: Colors.grey),
        );
      },
    );
  }
}

class _ResolvedProductThumbnail {
  final String url;
  final bool isSvg;
  final bool isCutLine;

  const _ResolvedProductThumbnail({
    required this.url,
    required this.isSvg,
    required this.isCutLine,
  });
}

bool _looksLikeSvgUrl(String value) {
  final lower = value.trim().toLowerCase();
  return lower.contains('.svg') ||
      lower.contains('image/svg') ||
      lower.contains('/svg');
}
