import 'dart:async';
import 'package:flutter/material.dart';
import '../screens/screensaver_screen.dart';

class InactivityDetector extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  final Duration timeout;

  const InactivityDetector({
    super.key,
    required this.child,
    required this.navigatorKey,
    this.timeout = const Duration(minutes: 2),
  });

  @override
  State<InactivityDetector> createState() => _InactivityDetectorState();
}

class _InactivityDetectorState extends State<InactivityDetector> {
  Timer? _timer;
  bool _isScreensaverActive = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer(widget.timeout, _showScreensaver);
  }

  void _resetTimer() {
    if (_isScreensaverActive) {
      return;
    }
    _startTimer();
  }

  void _showScreensaver() {
    if (_isScreensaverActive) return;
    final context = widget.navigatorKey.currentContext;
    if (context != null) {
      _isScreensaverActive = true;
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const ScreensaverScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 800),
        ),
      ).then((_) {
        _isScreensaverActive = false;
        _startTimer();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetTimer(),
      onPointerMove: (_) => _resetTimer(),
      onPointerUp: (_) => _resetTimer(),
      child: widget.child,
    );
  }
}
