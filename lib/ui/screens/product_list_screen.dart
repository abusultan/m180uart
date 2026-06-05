import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/bluetooth_service.dart';
import '../../data/models/product_models.dart';
import '../../core/app_strings.dart';
import 'device_detail_screen.dart';
import '../widgets/product_thumbnail_widget.dart';

class ProductListScreen extends StatefulWidget {
  final Category category;

  const ProductListScreen({super.key, required this.category});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

enum _CutSideFilter { all, front, back }

class _ProductListScreenState extends State<ProductListScreen> {
  final List<Product> _products = [];
  final Set<int> _loadedProductIds = <int>{};
  bool _isLoading = false;
  int _page = 1;
  bool _hasMore = true;
  final ScrollController _scrollController = ScrollController();

  // Search

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  bool _isOpeningProduct = false;
  StreamSubscription<String>? _typeMachineNameSub;
  String? _lastLoadedTypeMachineName;
  bool _pendingMachineTypeReload = false;
  _CutSideFilter _cutSideFilter = _CutSideFilter.all;

  Future<void> _openProduct(Product product) async {
    if (_isOpeningProduct) return;
    _isOpeningProduct = true;
    try {
      final typeMachineName =
          await CutterBluetoothService().getTypeMachineNameForItems();
      final items = await ApiService().getProductItems(
        product.id,
        typeMachineName: typeMachineName,
      );
      if (!mounted) return;

      if (items.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No items found for this product')),
        );
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DeviceDetailScreen(productItem: items.first),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to open product')));
    } finally {
      _isOpeningProduct = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _typeMachineNameSub = CutterBluetoothService().typeMachineNameStream.listen(
          _handleTypeMachineNameChanged,
        );
    _loadProducts();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    _typeMachineNameSub?.cancel();
    super.dispose();
  }

  void _handleTypeMachineNameChanged(String? typeMachineName) {
    final normalized = (typeMachineName ?? '').trim();
    if (!mounted || normalized.isEmpty) return;
    if (_lastLoadedTypeMachineName == normalized) return;

    if (_isLoading) {
      _pendingMachineTypeReload = true;
      return;
    }

    setState(() {
      _products.clear();
      _loadedProductIds.clear();
      _page = 1;
      _hasMore = true;
      if (!_supportsCutSideFilter(normalized)) {
        _cutSideFilter = _CutSideFilter.all;
      }
    });
    _loadProducts();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoading &&
        _hasMore) {
      _loadProducts();
    }
  }

  void _onScrollNotification(ScrollNotification notification) {
    if (!_hasMore || _isLoading) return;
    if (notification.metrics.pixels >=
        notification.metrics.maxScrollExtent - 220) {
      _loadProducts();
    }
  }

  void _ensureMoreIfViewportNotFilled() {
    if (!_hasMore || _isLoading || !_scrollController.hasClients) return;
    final metrics = _scrollController.position;
    if (metrics.maxScrollExtent <= 0) {
      _loadProducts();
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      setState(() {
        _products.clear();
        _loadedProductIds.clear();
        _page = 1;
        _hasMore = true;
      });
      _loadProducts();
    });
  }

  bool _supportsCutSideFilter(String? typeMachineName) {
    final normalized = (typeMachineName ?? '').trim().toLowerCase();
    return normalized == 'sunshine' ||
        normalized == 'dq' ||
        normalized == 'skycut' ||
        normalized == 'scky_cut' ||
        normalized == 'skycutter';
  }

  bool get _shouldShowCutSideFilter {
    return _supportsCutSideFilter(_lastLoadedTypeMachineName);
  }

  String? get _selectedCutSideParameter {
    return switch (_cutSideFilter) {
      _CutSideFilter.all => null,
      _CutSideFilter.front => 'front',
      _CutSideFilter.back => 'back',
    };
  }

  void _selectCutSideFilter(_CutSideFilter filter) {
    if (_cutSideFilter == filter) return;

    setState(() {
      _cutSideFilter = filter;
      _products.clear();
      _loadedProductIds.clear();
      _page = 1;
      _hasMore = true;
    });

    if (_isLoading) {
      _pendingMachineTypeReload = true;
      return;
    }

    _loadProducts();
  }

  Future<void> _loadProducts() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final query = _searchController.text.trim();
      final typeMachineName =
          await CutterBluetoothService().getTypeMachineNameForItems();
      _lastLoadedTypeMachineName = typeMachineName;
      final selectedCutSide =
          _supportsCutSideFilter(typeMachineName)
              ? _selectedCutSideParameter
              : null;
      List<Product> newProducts;

      if (query.isNotEmpty) {
        // Use Global Search Endpoint (Backend Search)
        // Note: The user requested "http://.../api/products?search=..."
        newProducts = await ApiService().searchProducts(
          query,
          page: _page,
          categoryId: widget.category.id,
          categoryEntityType: widget.category.entityType,
          typeMachineName: typeMachineName,
          cutSide: selectedCutSide,
        );
      } else {
        // Use Category Endpoint (Default view)
        newProducts = await ApiService().getCategoryProducts(
          widget.category.id,
          _page,
          entityType: widget.category.entityType,
          typeMachineName: typeMachineName,
          cutSide: selectedCutSide,
        );
      }

      if (_pendingMachineTypeReload) {
        return;
      }

      if (newProducts.isEmpty) {
        _hasMore = false;
      } else {
        final uniqueProducts =
            newProducts.where((p) => _loadedProductIds.add(p.id)).toList();
        _products.addAll(uniqueProducts);
        _page++;
      }
    } catch (e) {
      print("Error loading products: $e");
    } finally {
      if (mounted) {
        final shouldReload = _pendingMachineTypeReload;
        _pendingMachineTypeReload = false;
        setState(() => _isLoading = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _ensureMoreIfViewportNotFilled();
        });
        if (shouldReload) {
          setState(() {
            _products.clear();
            _loadedProductIds.clear();
            _page = 1;
            _hasMore = true;
          });
          unawaited(_loadProducts());
        }
      }
    }
  }

  String _filterLabel(BuildContext context, _CutSideFilter filter) {
    return switch (filter) {
      _CutSideFilter.all => AppStrings.of(context, 'filter_all'),
      _CutSideFilter.front => AppStrings.of(context, 'filter_front'),
      _CutSideFilter.back => AppStrings.of(context, 'filter_back'),
    };
  }

  Widget _buildCutSideFilterBar() {
    return Material(
      color: Colors.white,
      child: Container(
        height: 58,
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0xFFEDEDED), width: 1),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 9),
        child: Row(
          children: [
            _buildCutSideFilterButton(_CutSideFilter.all),
            _buildCutSideFilterButton(_CutSideFilter.front),
            _buildCutSideFilterButton(_CutSideFilter.back),
          ],
        ),
      ),
    );
  }

  Widget _buildCutSideFilterButton(_CutSideFilter filter) {
    final selected = _cutSideFilter == filter;
    return Expanded(
      child: Center(
        child: InkWell(
          onTap: () => _selectCutSideFilter(filter),
          borderRadius: BorderRadius.circular(22),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            constraints: const BoxConstraints(minWidth: 62, minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF555555) : Colors.transparent,
              borderRadius: BorderRadius.circular(22),
            ),
            alignment: Alignment.center,
            child: Text(
              _filterLabel(context, filter),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFF333333),
                fontSize: 17,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
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
          widget.category.nameEn.isNotEmpty
              ? widget.category.nameEn
              : widget.category.nameAr,
        ),
        backgroundColor: Colors.transparent,
      ),
      backgroundColor: const Color(0xFF121212),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: AppStrings.of(
                  context,
                  'search_in_category',
                ).replaceAll('{category}', widget.category.name),
                hintStyle: const TextStyle(color: Colors.grey),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                          setState(() {});
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onChanged: (value) {
                _onSearchChanged(value);
                setState(() {});
              },
            ),
          ),
          if (_shouldShowCutSideFilter) _buildCutSideFilterBar(),
          Expanded(
            child: _products.isEmpty && _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF00FF88)),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final crossAxisCount = width >= 1300
                          ? 5
                          : width >= 980
                              ? 4
                              : width >= 700
                                  ? 3
                                  : 2;
                      final childAspectRatio = width >= 980
                          ? 1.05
                          : width >= 700
                              ? 1.0
                              : 0.95;

                      return NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          _onScrollNotification(notification);
                          return false;
                        },
                        child: GridView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: _products.length + (_hasMore ? 1 : 0),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: childAspectRatio,
                          ),
                          itemBuilder: (context, index) {
                            if (index == _products.length) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: CircularProgressIndicator(
                                    color: Color(0xFF00FF88),
                                  ),
                                ),
                              );
                            }

                            final product = _products[index];
                            final productImageUrl = product.image;
                            final categoryImageUrl = widget.category.imageUrl;
                            return Card(
                              color: const Color(0xFF1E1E1E),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: InkWell(
                                onTap: () => _openProduct(product),
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: EdgeInsets.all(
                                    width >= 980 ? 8 : 10,
                                  ),
                                  child: Column(
                                    children: [
                                      Expanded(
                                        child: Container(
                                          width: double.infinity,
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          padding: EdgeInsets.all(
                                            width >= 980 ? 6 : 8,
                                          ),
                                          child: ProductThumbnail(
                                            productId: product.id,
                                            primaryImageUrl: productImageUrl,
                                            fallbackImageUrl: categoryImageUrl,
                                            fit: BoxFit.contain,
                                            fallbackIcon: Icons.image,
                                          ),
                                        ),
                                      ),
                                      SizedBox(height: width >= 980 ? 6 : 8),
                                      Text(
                                        product.nameEn.isNotEmpty
                                            ? product.nameEn
                                            : product.nameAr,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: width >= 980 ? 12 : 13,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
