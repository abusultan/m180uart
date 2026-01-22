import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../data/models/product_models.dart';
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
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

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

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        _products.clear();
        _page = 1;
        _hasMore = true;
        _loadProducts();
      }
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
        newProducts = await ApiService().searchProducts(query, page: _page);
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
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: "Search products...",
                  hintStyle: TextStyle(color: Colors.grey),
                  border: InputBorder.none,
                ),
                onChanged: _onSearchChanged,
              )
            : Text(widget.category.name),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: _toggleSearch,
          ),
        ],
      ),
      backgroundColor: const Color(0xFF121212),
      body: _products.isEmpty && _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00FF88)),
            )
          : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
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
                        product.image.isNotEmpty
                            ? product.image
                            : widget.category.imageUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          if (product.image.isNotEmpty &&
                              widget.category.imageUrl.isNotEmpty) {
                            return Image.network(
                              widget.category.imageUrl,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(Icons.image, color: Colors.grey),
                            );
                          }
                          return const Icon(Icons.image, color: Colors.grey);
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
    );
  }
}
