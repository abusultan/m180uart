import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../data/models/product_models.dart';
import 'device_detail_screen.dart';

class ProductItemsScreen extends StatefulWidget {
  final Product product;

  const ProductItemsScreen({super.key, required this.product});

  @override
  State<ProductItemsScreen> createState() => _ProductItemsScreenState();
}

class _ProductItemsScreenState extends State<ProductItemsScreen> {
  late Future<List<ProductItem>> _itemsFuture;

  @override
  void initState() {
    super.initState();
    _itemsFuture = ApiService().getProductItems(widget.product.id);
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
      body: FutureBuilder<List<ProductItem>>(
        future: _itemsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF00FF88)),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                "Error: ${snapshot.error}",
                style: const TextStyle(color: Colors.red),
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text(
                "No items found",
                style: TextStyle(color: Colors.white),
              ),
            );
          }

          final items = snapshot.data!;
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (c, i) => const Divider(color: Colors.grey),
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                title: Text(
                  item.nameEn.isNotEmpty ? item.nameEn : item.nameAr,
                  style: const TextStyle(color: Colors.white),
                ),
                trailing: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00FF88),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () {
                    // Navigate to Cut Screen with real Item
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            DeviceDetailScreen(productItem: item),
                      ),
                    );
                  },
                  child: const Text("CUT"),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
