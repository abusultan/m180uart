import 'package:flutter/material.dart';
import 'dart:async';
import '../../core/app_strings.dart';
import 'package:flutter_project/core/serial/mietubl_handshake.dart';
import 'package:flutter_project/core/serial/serial_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_project/features/dashboard/screens/dashboard_screen.dart';
import 'profile_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  bool _autoConnectInProgress = false;
  Timer? _autoConnectRetryTimer;
  StreamSubscription<String?>? _serialSub;

  @override
  void initState() {
    super.initState();
    _serialSub = CutterSerialService().serialStream.listen((_) {
      if (!mounted) return;
      setState(() {});
      if (CutterSerialService().isConnected) {
        _autoConnectRetryTimer?.cancel();
      }
    });
    _scheduleAutoConnect(delay: const Duration(milliseconds: 500));
  }

  void _scheduleAutoConnect({Duration delay = const Duration(seconds: 12)}) {
    _autoConnectRetryTimer?.cancel();
    _autoConnectRetryTimer = Timer(delay, () async {
      if (!mounted) return;
      final connected = await _tryAutoConnect();
      if (!mounted) return;
      if (!connected && !CutterSerialService().isConnected) {
        _scheduleAutoConnect();
      }
    });
  }

  Future<bool> _tryAutoConnect() async {
    if (_autoConnectInProgress) return CutterSerialService().isConnected;
    final cutter = CutterSerialService();
    if (cutter.isConnected) return true;

    _autoConnectInProgress = true;
    bool success = false;

    try {
      final prefs = await SharedPreferences.getInstance();

      // Build port candidates - M180T uses ttyS1 primarily
      final ports = <String>[];
      final saved = (prefs.getString('last_serial_port_path') ?? '').trim();
      if (saved.isNotEmpty) ports.add(saved);
      ports.addAll(['/dev/ttyS1', '/dev/ttyHS2', '/dev/ttyS3', '/dev/ttyS0']);
      final seen = <String>{};
      ports.removeWhere((p) => p.isEmpty || !seen.add(p));

      for (final port in ports) {
        debugPrint('AutoConnect: trying $port');
        try {
          await cutter.connect(portPath: port);

          // Run Mietubl 180T handshake
          final completer = Completer<bool>();
          final handshake = MietublHandshake(
            cutter,
            onStatusUpdate: (s) => debugPrint('Handshake: $s'),
            onHandshakeComplete: (ok) {
              if (!completer.isCompleted) completer.complete(ok);
            },
          );

          handshake.startHandshake();
          final ok = await completer.future.timeout(
            const Duration(seconds: 12),
            onTimeout: () => false,
          );
          handshake.dispose();

          if (ok) {
            await prefs.setString('last_serial_port_path', port);
            debugPrint('AutoConnect: SUCCESS on $port');
            success = true;
            break;
          } else {
            await cutter.disconnect();
            await Future.delayed(const Duration(milliseconds: 200));
          }
        } catch (e) {
          debugPrint('AutoConnect: error on $port: $e');
        }
      }
    } finally {
      _autoConnectInProgress = false;
      if (!success) {
        try { CutterSerialService().disconnect(); } catch (_) {}
      }
    }
    return success;
  }

  List<Widget> _getPages() => [
        const DashboardScreen(),
        const ProfileScreen(),
      ];

  bool _useWideLayout(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.shortestSide >= 600 || (size.width > size.height && size.width >= 720);
  }

  @override
  void dispose() {
    _autoConnectRetryTimer?.cancel();
    _serialSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final useWideLayout = _useWideLayout(context);
    final pages = _getPages();

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: useWideLayout
          ? SafeArea(
              child: Row(
                children: [
                  NavigationRail(
                    backgroundColor: const Color(0xFF1E1E1E),
                    selectedIndex: _currentIndex,
                    onDestinationSelected: (i) => setState(() => _currentIndex = i),
                    selectedIconTheme: const IconThemeData(color: Color(0xFF00FF88)),
                    selectedLabelTextStyle: const TextStyle(color: Color(0xFF00FF88)),
                    unselectedIconTheme: const IconThemeData(color: Colors.grey),
                    unselectedLabelTextStyle: const TextStyle(color: Colors.grey),
                    labelType: NavigationRailLabelType.all,
                    destinations: [
                      NavigationRailDestination(
                        icon: const Icon(Icons.home),
                        label: Text(AppStrings.of(context, 'home')),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.person),
                        label: Text(AppStrings.of(context, 'profile')),
                      ),
                    ],
                  ),
                  const VerticalDivider(width: 1, color: Color(0xFF2A2A2A)),
                  Expanded(child: pages[_currentIndex]),
                ],
              ),
            )
          : pages[_currentIndex],
      bottomNavigationBar: useWideLayout
          ? null
          : BottomNavigationBar(
              backgroundColor: const Color(0xFF1E1E1E),
              selectedItemColor: const Color(0xFF00FF88),
              unselectedItemColor: Colors.grey,
              type: BottomNavigationBarType.fixed,
              currentIndex: _currentIndex,
              onTap: (i) => setState(() => _currentIndex = i),
              items: [
                BottomNavigationBarItem(
                  icon: const Icon(Icons.home),
                  label: AppStrings.of(context, 'home'),
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
