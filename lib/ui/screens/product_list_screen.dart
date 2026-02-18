import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../data/models/product_models.dart';
import '../../core/app_strings.dart';
import 'product_items_screen.dart';

class ProductListScreen extends StatefulWidget {
  final Category category;

  const ProductListScreen({super.key, required this.category});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  final List<Product> _products = [];
  bool _isLoading = false;
  int _page = 1;
  bool _hasMore = true;
  final ScrollController _scrollController = ScrollController();

  // Search

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  String _safeUrl(String url) => ApiService().normalizeUrl(url);

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoading &&
        _hasMore) {
      _loadProducts();
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      setState(() {
        _products.clear();
        _page = 1;
        _hasMore = true;
      });
      _loadProducts();
    });
  }

  Future<void> _loadProducts() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final query = _searchController.text.trim();
      List<Product> newProducts;

      if (query.isNotEmpty) {
        // Use Global Search Endpoint (Backend Search)
        // Note: The user requested "http://.../api/products?search=..."
        newProducts = await ApiService().searchProducts(
          query,
          page: _page,
          categoryId: widget.category.id,
        );
      } else {
        // Use Category Endpoint (Default view)
        newProducts = await ApiService().getCategoryProducts(
          widget.category.id,
          _page,
        );
      }

      if (newProducts.isEmpty) {
        _hasMore = false;
      } else {
        _products.addAll(newProducts);
        _page++;
      }
    } catch (e) {
      print("Error loading products: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.category.name),
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
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          Expanded(
            child: _products.isEmpty && _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF00FF88)),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: _products.length + (_hasMore ? 1 : 0),
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
                      return Card(
                        color: const Color(0xFF1E1E1E),
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(12),
                          leading: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.all(4),
                            child: Image.network(
                              _safeUrl(
                                product.image.isNotEmpty
                                    ? product.image
                                    : widget.category.imageUrl,
                              ),
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                if (product.image.isNotEmpty &&
                                    widget.category.imageUrl.isNotEmpty) {
                                  return Image.network(
                                    _safeUrl(widget.category.imageUrl),
                                    fit: BoxFit.contain,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            const Icon(
                                      Icons.image,
                                      color: Colors.grey,
                                    ),
                                  );
                                }
                                return const Icon(
                                  Icons.image,
                                  color: Colors.grey,
                                );
                              },
                            ),
                          ),
                          title: Text(
                            product.nameEn.isNotEmpty
                                ? product.nameEn
                                : product.nameAr,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          trailing: const Icon(
                            Icons.arrow_forward_ios,
                            color: Colors.grey,
                            size: 16,
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    ProductItemsScreen(product: product),
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
