import 'package:flutter/material.dart';
import '../../core/app_strings.dart';
import 'dashboard_screen.dart';
import 'profile_screen.dart';
import 'cart_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  List<Widget> _getPages() => [
    const DashboardScreen(),
    const CartScreen(),
    const ProfileScreen(),
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
        type: BottomNavigationBarType
            .fixed, // لضمان ظهور جميع الأيقونات بشكل صحيح
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.home),
            label: AppStrings.of(context, 'home'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.shopping_cart),
            label: AppStrings.of(context, 'cart'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person),
            label: AppStrings.of(context, 'profile'),
          ),
        ],
      ),
    );
  }
}
