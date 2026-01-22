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
      body: RefreshIndicator(
        color: const Color(0xFF00FF88),
        onRefresh: () async {
          // Update User Info
          await ApiService().getUserInfo().then((_) {
            if (mounted) setState(() {});
          });

          setState(() {
            if (widget.currentCategoryId != null) {
              // Sub-category refreshing: fetch all, find current, show children
              _categoriesFuture = ApiService().getCategories().then((all) {
                final children = _findChildren(all, widget.currentCategoryId!);
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
                child: CircularProgressIndicator(color: Color(0xFF00FF88)),
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

            final categories = snapshot.data!;
            return GridView.builder(
              padding: const EdgeInsets.all(16),
              physics: const AlwaysScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.8,
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
                      border: Border.all(color: const Color(0xFF333333)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Category Image or Icon
                        if (cat.imageUrl.isNotEmpty)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.all(2.0),
                                child: Center(
                                  child: Image.network(
                                    cat.imageUrl,
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Icon(
                                        cat.children.isNotEmpty
                                            ? Icons.folder_open
                                            : Icons.smartphone,
                                        size: 40,
                                        color: Colors.grey,
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          )
                        else
                          Icon(
                            cat.children.isNotEmpty
                                ? Icons.folder_open
                                : Icons.smartphone,
                            size: 50,
                            color: const Color(0xFF00FF88),
                          ),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Text(
                            cat.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
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
    );
  }
}
