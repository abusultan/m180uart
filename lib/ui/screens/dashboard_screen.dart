import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/bluetooth_service.dart';
import '../../data/models/product_models.dart';
import '../../core/app_strings.dart';
import 'product_list_screen.dart';
import 'login_screen.dart';
import 'scan_screen.dart';

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

  @override
  void initState() {
    super.initState();
    if (widget.initialSubCategories != null) {
      _categoriesFuture = Future.value(widget.initialSubCategories);
    } else {
      _categoriesFuture = ApiService().getCategories();
    }
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Search ${widget.title ?? 'Categories'}...",
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
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: const Color(0xFF00FF88),
              onRefresh: () async {
                // Update User Info
                await ApiService().getUserInfo().then((_) {
                  if (mounted) setState(() {});
                });

                setState(() {
                  _searchQuery = ''; // Clear search on refresh
                  if (widget.currentCategoryId != null) {
                    // Sub-category refreshing: fetch all, find current, show children
                    _categoriesFuture = ApiService().getCategories().then((
                      all,
                    ) {
                      final children = _findChildren(
                        all,
                        widget.currentCategoryId!,
                      );
                      return children ?? [];
                    });
                  } else {
                    // Root refreshing
                    _categoriesFuture = ApiService().getCategories();
                  }
                });
                await _categoriesFuture;
              },
              child: FutureBuilder<List<Category>>(
                future: _categoriesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF00FF88),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    // Wrap in centered scrollable to make refresh work even on error
                    return Center(
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Text(
                          "Error: ${snapshot.error}",
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    );
                  }

                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    // Wrap in centered scrollable to make refresh work even on empty
                    return Center(
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            AppStrings.of(context, 'no_categories'),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    );
                  }

                  final allCategories = snapshot.data!;
                  final categories = _searchQuery.isEmpty
                      ? allCategories
                      : allCategories
                            .where(
                              (cat) => cat.name.toLowerCase().contains(
                                _searchQuery.toLowerCase(),
                              ),
                            )
                            .toList();

                  if (categories.isEmpty) {
                    return Center(
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          child: const Text(
                            "No matching categories found",
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    );
                  }

                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    physics: const AlwaysScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 1.0, // More square-like, compact
                        ),
                    itemCount: categories.length,
                    itemBuilder: (context, index) {
                      final cat = categories[index];
                      return GestureDetector(
                        onTap: () => _handleCategoryTap(cat),
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E1E),
                            borderRadius: BorderRadius.circular(16),
                            // Subtle gradient for premium feel
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                const Color(0xFF252525),
                                const Color(0xFF1A1A1A),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                            border: Border.all(
                              color: Colors.white.withOpacity(0.05),
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Category Image or Icon - Smaller & Neater
                              if (cat.imageUrl.isNotEmpty)
                                Container(
                                  height: 70, // Fixed reduced height
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
                                    color: const Color(
                                      0xFF00FF88,
                                    ).withOpacity(0.1),
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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12.0,
                                ),
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
}
