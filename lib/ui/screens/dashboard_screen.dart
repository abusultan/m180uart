import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/bluetooth_service.dart';
import '../../data/models/product_models.dart';
import '../../core/app_strings.dart';
import 'product_list_screen.dart';
import 'login_screen.dart';
import 'scan_screen.dart';
import 'product_items_screen.dart';
import 'dart:async';

class DashboardScreen extends StatefulWidget {
  final List<Category>? initialSubCategories;
  final String? title;
  final int? currentCategoryId; // Field to track which category we are viewing

  const DashboardScreen({
    super.key,
    this.initialSubCategories,
    this.title,
    this.currentCategoryId,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<List<Category>> _categoriesFuture;
  String _searchQuery = '';
  List<Product> _productSearchResults = [];
  bool _isSearchingProducts = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (widget.initialSubCategories != null) {
      _categoriesFuture = Future.value(widget.initialSubCategories);
    } else {
      _categoriesFuture = ApiService().getCategories();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
    });

    if (_debounce?.isActive ?? false) _debounce!.cancel();

    if (query.isEmpty) {
      setState(() {
        _productSearchResults = [];
        _isSearchingProducts = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      setState(() {
        _isSearchingProducts = true;
      });

      try {
        final products = await ApiService().searchAllProducts(query);
        if (mounted) {
          setState(() {
            _productSearchResults = products;
            _isSearchingProducts = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isSearchingProducts = false;
            // Optionally handle error
          });
        }
      }
    });
  }

  void _logout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(
          AppStrings.of(context, 'logout_title'),
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          AppStrings.of(context, 'logout_confirm'),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              AppStrings.of(context, 'cancel'),
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              CutterBluetoothService().disconnect();
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false,
              );
            },
            child: Text(
              AppStrings.of(context, 'logout'),
              style: const TextStyle(
                color: Color(0xFF00FF88),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleCategoryTap(Category cat) {
    if (cat.children.isNotEmpty) {
      // Navigate to DashboardScreen again but with subcategories
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DashboardScreen(
            title: cat.name,
            initialSubCategories: cat.children,
            currentCategoryId: cat.id,
          ),
        ),
      );
    } else {
      // Navigate to Product List
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ProductListScreen(category: cat),
        ),
      );
    }
  }

  // Recursive Helper to find a category and return its children
  List<Category>? _findChildren(List<Category> all, int targetId) {
    for (var cat in all) {
      if (cat.id == targetId) {
        return cat.children;
      }
      if (cat.children.isNotEmpty) {
        final found = _findChildren(cat.children, targetId);
        if (found != null) return found;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final serialNumber = CutterBluetoothService().serialNumber;
    final isConnected = CutterBluetoothService().isConnected;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.title ?? AppStrings.of(context, 'categories'),
                  style: const TextStyle(fontSize: 18),
                ),
                Text(
                  "${AppStrings.of(context, 'remaining')}: ${ApiService().currentUser?.remainingPieces ?? 0}",
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF00FF88),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (isConnected)
              Expanded(
                child: Center(
                  child: Text(
                    serialNumber ?? 'N/A',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF00FF88),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        ),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: Icon(
              Icons.bluetooth,
              color: isConnected ? const Color(0xFF00FF88) : Colors.grey,
            ),
            tooltip: AppStrings.of(context, 'connect_cutter'),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ScanScreen()),
              );
              setState(() {}); // Refresh to show connection status
            },
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      backgroundColor: const Color(0xFF121212),
      body: !isConnected
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.bluetooth_disabled,
                      size: 80,
                      color: Colors.white54,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      AppStrings.of(context, 'connect_required_title'),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      AppStrings.of(context, 'connect_required_msg'),
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white70,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ScanScreen(),
                          ),
                        );
                        setState(() {});
                      },
                      icon: const Icon(Icons.bluetooth),
                      label: Text(AppStrings.of(context, 'go_to_connect')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00FF88),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: AppStrings.of(context, 'search_hint'),
                      hintStyle: const TextStyle(color: Colors.grey),
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF1E1E1E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                    ),
                    onChanged: _onSearchChanged,
                  ),
                ),
                Expanded(
                  child: _searchQuery.isNotEmpty
                      ? _buildSearchResults(context)
                      : RefreshIndicator(
                          color: const Color(0xFF00FF88),
                          onRefresh: () async {
                            // Update User Info
                            await ApiService().getUserInfo().then((_) {
                              if (mounted) setState(() {});
                            });

                            setState(() {
                              _searchQuery = ''; // Clear search on refresh
                              if (widget.currentCategoryId != null) {
                                // Sub-category refreshing
                                _categoriesFuture = ApiService()
                                    .getCategories()
                                    .then((all) {
                                      final children = _findChildren(
                                        all,
                                        widget.currentCategoryId!,
                                      );
                                      return children ?? [];
                                    });
                              } else {
                                // Root refreshing
                                _categoriesFuture = ApiService()
                                    .getCategories();
                              }
                            });
                            await _categoriesFuture;
                          },
                          child: FutureBuilder<List<Category>>(
                            future: _categoriesFuture,
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(
                                  child: CircularProgressIndicator(
                                    color: Color(0xFF00FF88),
                                  ),
                                );
                              }

                              if (snapshot.hasError) {
                                return Center(
                                  child: SingleChildScrollView(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    child: Text(
                                      "Error: ${snapshot.error}",
                                      style: const TextStyle(color: Colors.red),
                                    ),
                                  ),
                                );
                              }

                              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                                return Center(
                                  child: SingleChildScrollView(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    child: Container(
                                      padding: const EdgeInsets.all(20),
                                      child: Text(
                                        AppStrings.of(context, 'no_categories'),
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }

                              // Filter categories based on _searchQuery if it's not empty
                              final filteredCategories = snapshot.data!
                                  .where(
                                    (cat) => cat.name.toLowerCase().contains(
                                      _searchQuery.toLowerCase(),
                                    ),
                                  )
                                  .toList();

                              if (filteredCategories.isEmpty &&
                                  _searchQuery.isNotEmpty) {
                                return Center(
                                  child: SingleChildScrollView(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    child: Container(
                                      padding: const EdgeInsets.all(20),
                                      child: Text(
                                        AppStrings.of(
                                          context,
                                          'no_matching_categories',
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }

                              return GridView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  16,
                                ),
                                physics: const AlwaysScrollableScrollPhysics(),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                      childAspectRatio: 1.0,
                                    ),
                                itemCount: filteredCategories.length,
                                itemBuilder: (context, index) {
                                  final cat = filteredCategories[index];
                                  return _buildCategoryCard(cat);
                                },
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildCategoryCard(Category cat) {
    return GestureDetector(
      onTap: () => _handleCategoryTap(cat),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [const Color(0xFF252525), const Color(0xFF1A1A1A)],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (cat.imageUrl.isNotEmpty)
              Container(
                height: 70,
                width: 70,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Image.network(
                  cat.imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(
                      cat.children.isNotEmpty
                          ? Icons.folder_open
                          : Icons.smartphone,
                      size: 30,
                      color: Colors.grey,
                    );
                  },
                ),
              )
            else
              Container(
                height: 70,
                width: 70,
                decoration: BoxDecoration(
                  color: const Color(0xFF00FF88).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  cat.children.isNotEmpty
                      ? Icons.folder_open
                      : Icons.smartphone,
                  size: 32,
                  color: const Color(0xFF00FF88),
                ),
              ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Text(
                cat.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults(BuildContext context) {
    return FutureBuilder<List<Category>>(
      future: _categoriesFuture,
      builder: (context, snapshot) {
        final List<Category> matchingCategories = [];
        if (snapshot.hasData) {
          matchingCategories.addAll(
            snapshot.data!.where(
              (cat) =>
                  cat.name.toLowerCase().contains(_searchQuery.toLowerCase()),
            ),
          );
        }

        return CustomScrollView(
          slivers: [
            if (matchingCategories.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    AppStrings.of(context, 'matching_categories'),
                    style: const TextStyle(
                      color: Color(0xFF00FF88),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.0,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    return _buildCategoryCard(matchingCategories[index]);
                  }, childCount: matchingCategories.length),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  AppStrings.of(context, 'matching_products'),
                  style: const TextStyle(
                    color: Color(0xFF00FF88),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            if (_isSearchingProducts)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFF00FF88)),
                  ),
                ),
              )
            else if (_productSearchResults.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Text(
                    AppStrings.of(context, 'no_products_found'),
                    style: const TextStyle(
                      color: Colors.grey,
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final product = _productSearchResults[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Card(
                      color: const Color(0xFF1E1E1E),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 50,
                          height: 50,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Image.network(
                            product.image,
                            fit: BoxFit.contain,
                            errorBuilder: (c, e, s) => const Icon(
                              Icons.smartphone,
                              color: Colors.grey,
                            ),
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
                        subtitle: Text(
                          AppStrings.of(context, 'product_label'),
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
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
                    ),
                  );
                }, childCount: _productSearchResults.length),
              ),
            // Bottom padding
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        );
      },
    );
  }
}
