import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:typed_data';
import '../../services/api_service.dart';
import '../../data/models/product_models.dart';
import 'device_detail_screen.dart';
import '../../core/cut_file_transformer.dart';
import '../../utils/svg_outline.dart';
import '../../services/svg_renderer.dart';
import 'package:flutter_svg/flutter_svg.dart';

class ProductItemsScreen extends StatefulWidget {
  final Product product;

  const ProductItemsScreen({super.key, required this.product});

  @override
  State<ProductItemsScreen> createState() => _ProductItemsScreenState();
}

class _ProductItemsScreenState extends State<ProductItemsScreen> {
  List<ProductItem> _allItems = [];
  List<ProductItem> _filteredItems = [];
  bool _isLoading = true;
  String _errorMessage = '';
  String _selectedFilter = 'All';
  final Map<int, Future<CutPathData?>> _cutPreviewCache = {};

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() {
      if (_allItems.isEmpty) _isLoading = true;
      _errorMessage = '';
    });
    try {
      final items = await ApiService().getProductItems(widget.product.id);
      if (mounted) {
        setState(() {
          _allItems = items;
          _isLoading = false;
        });
        _applyFilter();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _applyFilter() {
    setState(() {
      if (_selectedFilter == 'All') {
        _filteredItems = List.from(_allItems);
      } else if (_selectedFilter == 'Front') {
        _filteredItems = _allItems.where((item) {
          final name = item.nameEn.toLowerCase();
          return name.contains('front');
        }).toList();
      } else {
        // Back: Contains 'back' or does NOT contain 'front'
        _filteredItems = _allItems.where((item) {
          final name = item.nameEn.toLowerCase();
          return name.contains('back') || !name.contains('front');
        }).toList();
      }
    });
  }

  void _setFilter(String filter) {
    setState(() => _selectedFilter = filter);
    _applyFilter();
  }

  String _safeUrl(String url) {
    if (url.isEmpty) return url;
    return ApiService().normalizeUrl(url);
  }

  Future<CutPathData?> _loadCutPreview(ProductItem item) {
    return _cutPreviewCache.putIfAbsent(item.id, () async {
      final urls = <String>[];
      if (item.pltUrl.isNotEmpty) urls.add(item.pltUrl);
      if (item.sjcUrl.isNotEmpty && item.sjcUrl != item.pltUrl) {
        urls.add(item.sjcUrl);
      }
      for (final url in urls) {
        final file = await ApiService().downloadFile(url);
        if (file == null) continue;
        final bytes = await file.readAsBytes();
        final data = CutFileTransformer.decodePathData(bytes);
        if (data != null) return data;
      }
      return null;
    });
  }

  Widget _buildCutPreviewFallback(ProductItem item) {
    return FutureBuilder<CutPathData?>(
      future: _loadCutPreview(item),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF00FF88)),
          );
        }
        final data = snap.data;
        if (data == null) {
          return const Center(
            child: Icon(Icons.broken_image, color: Colors.grey, size: 40),
          );
        }
        return CustomPaint(painter: CutPreviewPainter(data));
      },
    );
  }

  Widget _buildItemPreview(ProductItem item) {
    if (item.imageUrl.isEmpty) {
      return const Center(
        child: Icon(Icons.image_not_supported, color: Colors.grey, size: 40),
      );
    }

    final url = _safeUrl(item.imageUrl);
    final lowerUrl = url.toLowerCase();
    final isSvg = lowerUrl.contains('.svg');
    if (!isSvg) {
      return Image.network(
        url,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                      loadingProgress.expectedTotalBytes!
                  : null,
              color: const Color(0xFF00FF88),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => const Center(
          child: Icon(Icons.broken_image, color: Colors.grey, size: 40),
        ),
      );
    }

    return FutureBuilder<File?>(
      future: ApiService().downloadFile(url),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF00FF88)),
          );
        }
        final file = snapshot.data;
        if (file == null) {
          return _buildCutPreviewFallback(item);
        }
        if (Platform.isAndroid) {
          return FutureBuilder<Uint8List>(
            future: file.readAsBytes(),
            builder: (context, bytesSnap) {
              if (bytesSnap.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFF00FF88)),
                );
              }
              final bytes = bytesSnap.data;
              if (bytes == null || bytes.isEmpty) {
                return _buildCutPreviewFallback(item);
              }
              return LayoutBuilder(
                builder: (context, constraints) {
                  final dpr = MediaQuery.of(context).devicePixelRatio;
                  final width = constraints.maxWidth.isFinite
                      ? constraints.maxWidth
                      : 180.0;
                  final height = constraints.maxHeight.isFinite
                      ? constraints.maxHeight
                      : 180.0;
                  final widthPx = (width * dpr).clamp(1, 1024).toInt();
                  final heightPx = (height * dpr).clamp(1, 1024).toInt();
                  return FutureBuilder<Uint8List?>(
                    future: SvgRenderer.renderSvgBytesToPng(
                      bytes,
                      width: widthPx,
                      height: heightPx,
                    ),
                    builder: (context, pngSnap) {
                      if (pngSnap.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child:
                              CircularProgressIndicator(color: Color(0xFF00FF88)),
                        );
                      }
                      final png = pngSnap.data;
                      if (png == null) {
                        return _buildCutPreviewFallback(item);
                      }
                      return Image.memory(
                        png,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      );
                    },
                  );
                },
              );
            },
          );
        }

        return FutureBuilder<String>(
          future: file.readAsString(),
          builder: (context, svgSnap) {
            if (svgSnap.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFF00FF88)),
              );
            }
            final svg = svgSnap.data;
            if (svg == null || svg.isEmpty) {
              return const Center(
                child: Icon(Icons.broken_image, color: Colors.grey, size: 40),
              );
            }
            final outlineSvg = toOutlineSvg(svg);
            return SvgPicture.string(
              outlineSvg,
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.contain,
            );
          },
        );
      },
    );
  }


  Widget _buildFilterButton(String title, bool isSelected) {
    return Expanded(
      child: GestureDetector(
        onTap: () => _setFilter(title),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF00FF88)
                : const Color(0xFF333333),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? const Color(0xFF00FF88) : Colors.transparent,
            ),
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.black : Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.product.nameEn.isNotEmpty
              ? widget.product.nameEn
              : widget.product.nameAr,
        ),
        backgroundColor: Colors.transparent,
      ),
      backgroundColor: const Color(0xFF121212),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                _buildFilterButton('All', _selectedFilter == 'All'),
                _buildFilterButton('Back', _selectedFilter == 'Back'),
                _buildFilterButton('Front', _selectedFilter == 'Front'),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF00FF88)),
                  )
                : _errorMessage.isNotEmpty
                ? Center(
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Text(
                        "Error: $_errorMessage",
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  )
                : _filteredItems.isEmpty
                ? Center(
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        child: const Text(
                          "No items found",
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  )
                : RefreshIndicator(
                    color: const Color(0xFF00FF88),
                    onRefresh: _loadItems,
                    child: GridView.builder(
                      padding: const EdgeInsets.all(16),
                      physics: const AlwaysScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            childAspectRatio: 0.8,
                          ),
                      itemCount: _filteredItems.length,
                      itemBuilder: (context, index) {
                        final item = _filteredItems[index];
                        return InkWell(
                          onTap: () {
                            // Navigate to Cut Screen with real Item
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    DeviceDetailScreen(productItem: item),
                              ),
                            );
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1E1E),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFF333333),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(15),
                                    ),
                                    child: Container(
                                      color: Colors.white,
                                      padding: const EdgeInsets.all(12),
                                      child: _buildItemPreview(item),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Column(
                                    children: [
                                      Text(
                                        item.nameEn.isNotEmpty
                                            ? item.nameEn
                                            : item.nameAr,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(
                                            0xFF00FF88,
                                          ).withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: const Color(
                                              0xFF00FF88,
                                            ).withOpacity(0.3),
                                          ),
                                        ),
                                        child: const Text(
                                          "SELECT",
                                          style: TextStyle(
                                            color: Color(0xFF00FF88),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
