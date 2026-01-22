import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/bluetooth_service.dart';
import '../../data/models/product_models.dart';
import 'product_list_screen.dart';
import 'login_screen.dart';
import 'scan_screen.dart';

class DashboardScreen extends StatefulWidget {
  final List<Category>? initialSubCategories;
  final String? title;

  const DashboardScreen({super.key, this.initialSubCategories, this.title});

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
    CutterBluetoothService().disconnect();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
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

  @override
  Widget build(BuildContext context) {
    final connectedDevice = CutterBluetoothService().connectedDevice;
    final serialNumber = CutterBluetoothService().serialNumber;
    final isConnected = CutterBluetoothService().isConnected;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(widget.title ?? "Categories"),
            if (isConnected)
              Text(
                "${connectedDevice?.platformName ?? 'Unknown'} - SN: ${serialNumber ?? 'N/A'}",
                style: const TextStyle(fontSize: 12, color: Color(0xFF00FF88)),
              ),
            if (isConnected &&
                CutterBluetoothService().successfulHandshakeType != null)
              Text(
                "Handshake: ${CutterBluetoothService().successfulHandshakeType}",
                style: const TextStyle(fontSize: 10, color: Color(0xFF00FF88)),
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
            tooltip: "Connect Cutter",
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
      body: FutureBuilder<List<Category>>(
        future: _categoriesFuture,
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
                "No Categories Found",
                style: TextStyle(color: Colors.white),
              ),
            );
          }

          final categories = snapshot.data!;
          return GridView.builder(
            padding: const EdgeInsets.all(16),
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
                      // Placeholder icon logic (improved)
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
    );
  }
}
