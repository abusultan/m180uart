import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/api_service.dart';

class ScreensaverScreen extends StatefulWidget {
  const ScreensaverScreen({super.key});

  @override
  State<ScreensaverScreen> createState() => _ScreensaverScreenState();
}

class _ScreensaverScreenState extends State<ScreensaverScreen> {
  final PageController _pageController = PageController();
  List<String> _images = [];
  bool _isLoading = true;
  Timer? _carouselTimer;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  Future<void> _loadImages() async {
    try {
      final images = await ApiService().fetchScreensavers();
      if (mounted) {
        setState(() {
          _images = images;
          _isLoading = false;
        });
        if (_images.isNotEmpty) {
          _startCarousel();
        }
      }
    } catch (e) {
      debugPrint("Failed to load screensavers: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _startCarousel() {
    _carouselTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_images.isEmpty) return;
      if (_pageController.hasClients) {
        _currentPage++;
        if (_currentPage >= _images.length) {
          _currentPage = 0;
        }
        _pageController.animateToPage(
          _currentPage,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _carouselTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Navigator.pop(context);
        },
        child: Stack(
          children: [
            if (_isLoading)
              const Center(child: CircularProgressIndicator(color: Colors.white))
            else if (_images.isEmpty)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/logo.png',
                      width: 200,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.image, size: 100, color: Colors.white54),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Anti-crash.com',
                      style: TextStyle(color: Colors.white54, fontSize: 24),
                    ),
                  ],
                ),
              )
            else
              PageView.builder(
                controller: _pageController,
                itemCount: _images.length,
                physics: const NeverScrollableScrollPhysics(), // Only auto-scroll
                itemBuilder: (context, index) {
                  return CachedNetworkImage(
                    imageUrl: _images[index],
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    placeholder: (context, url) =>
                        const Center(child: CircularProgressIndicator(color: Colors.white24)),
                    errorWidget: (context, url, error) =>
                        const Center(child: Icon(Icons.error, color: Colors.white24, size: 50)),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
