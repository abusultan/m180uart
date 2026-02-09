import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/app_strings.dart';
import 'rep_orders_screen.dart';
import 'rep_notifications_screen.dart';
import 'rep_invoices_screen.dart';

class RepMainScreen extends StatefulWidget {
  const RepMainScreen({super.key});

  @override
  State<RepMainScreen> createState() => _RepMainScreenState();
}

class _RepMainScreenState extends State<RepMainScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _requestLocationAlways();
  }

  Future<void> _requestLocationAlways() async {
    final status = await Permission.locationAlways.request();
    if (status.isDenied || status.isPermanentlyDenied) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context, 'location_required')),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  List<Widget> _getPages() => const [
        RepOrdersScreen(),
        RepNotificationsScreen(),
        RepInvoicesScreen(),
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: _getPages()[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF1E1E1E),
        selectedItemColor: const Color(0xFF00FF88),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.list_alt),
            label: AppStrings.of(context, 'customer_orders'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.notifications_active),
            label: AppStrings.of(context, 'customer_notifications'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.receipt_long),
            label: AppStrings.of(context, 'invoices'),
          ),
        ],
      ),
    );
  }
}
