import 'package:flutter/material.dart';
import 'dart:async';
import '../../core/app_strings.dart';
import '../../core/machine_handshake.dart';
import '../../services/bluetooth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dashboard_screen.dart';
import 'profile_screen.dart';
import 'cart_screen.dart';

class _FirstSerialSetupChoice {
  final String machineType;
  final String handshakeAlgorithm;

  const _FirstSerialSetupChoice({
    required this.machineType,
    required this.handshakeAlgorithm,
  });
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  bool _autoConnectInProgress = false;
  bool _serialSetupDialogOpen = false;
  Timer? _autoConnectRetryTimer;
  static const Duration _autoConnectRetryDelay = Duration(seconds: 12);
  StreamSubscription<String?>? _serialSub;

  @override
  void initState() {
    super.initState();
    _serialSub = CutterBluetoothService().serialStream.listen((_) {
      if (!mounted) return;
      setState(() {});
      if (CutterBluetoothService().isConnected) {
        _autoConnectRetryTimer?.cancel();
      }
    });
    _scheduleAutoConnect(delay: const Duration(milliseconds: 400));
  }

  void _scheduleAutoConnect({Duration delay = _autoConnectRetryDelay}) {
    _autoConnectRetryTimer?.cancel();
    _autoConnectRetryTimer = Timer(delay, () async {
      if (!mounted) return;
      final connected = await _tryAutoConnect();
      if (!mounted) return;
      if (!connected && !CutterBluetoothService().isConnected) {
        _scheduleAutoConnect();
      }
    });
  }

  String? _resolvePreferredAlgorithm(
    SharedPreferences prefs,
    String? currentSerial,
  ) {
    if (currentSerial == null || currentSerial.isEmpty) {
      return null;
    }

    return _readCachedAlgorithmForSerial(prefs, currentSerial);
  }

  String? _readCachedAlgorithmForSerial(
    SharedPreferences prefs,
    String? serial,
  ) {
    if (serial == null || serial.isEmpty) return null;
    final value = (prefs.getString('handshake_algo_$serial') ?? '').trim();
    if (value.isEmpty) return null;
    return MachineHandshake.normalizeAlgorithm(value);
  }

  String _readManualDefaultAlgorithm(SharedPreferences prefs) {
    final manualDefault =
        (prefs.getString('manual_handshake_algorithm_ui') ?? '').trim();
    final normalized = MachineHandshake.normalizeAlgorithm(manualDefault);
    return normalized ?? MachineHandshake.algoSunshine;
  }

  String _serialSetupDoneKey(String serial) =>
      'serial_setup_done_${serial.toUpperCase()}';

  String _machineTypeKey(String serial) =>
      'machine_type_${serial.toUpperCase()}';

  bool _isKnownDqLikeSerial(String serial) {
    final upper = serial.toUpperCase();
    return upper.startsWith('DQ') ||
        upper.startsWith('DX') ||
        upper.startsWith('LH');
  }

  String _defaultMachineTypeFromSerial(String serial) {
    final upper = serial.toUpperCase();
    if (_isKnownDqLikeSerial(upper)) return 'dq_like';
    if (upper.startsWith('SS')) return 'ss_like';
    return 'unknown';
  }

  Future<String?> _waitForDetectedSerial(
    CutterBluetoothService cutter, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final existing = (cutter.serialNumber ?? '').trim();
    if (existing.isNotEmpty) return existing;

    final completer = Completer<String?>();
    late final Timer timer;
    late StreamSubscription<String?> sub;

    void finish(String? value) {
      if (!completer.isCompleted) {
        completer.complete(value);
      }
    }

    sub = cutter.serialStream.listen((serial) {
      final value = (serial ?? '').trim();
      if (value.isNotEmpty) {
        finish(value);
      }
    });

    timer = Timer(timeout, () => finish(null));
    final result = await completer.future;
    timer.cancel();
    await sub.cancel();
    return result;
  }

  Future<String?> _runFirstSerialSetupIfNeeded(
    SharedPreferences prefs,
    String serial,
  ) async {
    final serialValue = serial.trim();
    if (serialValue.isEmpty) return null;

    final doneKey = _serialSetupDoneKey(serialValue);
    if (prefs.getBool(doneKey) == true) return null;

    final existingAlgo = _readCachedAlgorithmForSerial(prefs, serialValue);
    if (existingAlgo != null && existingAlgo.isNotEmpty) {
      await prefs.setBool(doneKey, true);
      return existingAlgo;
    }

    if (!mounted || _serialSetupDialogOpen) return null;
    _serialSetupDialogOpen = true;

    String machineType = _defaultMachineTypeFromSerial(serialValue);
    String handshakeChoice = MachineHandshake.algoSunshine;

    try {
      final choice = await showDialog<_FirstSerialSetupChoice>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              title: const Text(
                'إعداد الماكينة (مرة واحدة)',
                style: TextStyle(color: Colors.white),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'السيريال: $serialValue',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: machineType,
                    dropdownColor: const Color(0xFF1E1E1E),
                    decoration: const InputDecoration(
                      labelText: 'نوع الماكينة',
                      labelStyle: TextStyle(color: Colors.grey),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'unknown',
                        child: Text('غير معروف / خلّيها تجربة'),
                      ),
                      DropdownMenuItem(
                        value: 'dq_like',
                        child: Text('DQ / DX / LH'),
                      ),
                      DropdownMenuItem(
                        value: 'ss_like',
                        child: Text('SS / غيرها'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => machineType = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: handshakeChoice,
                    dropdownColor: const Color(0xFF1E1E1E),
                    decoration: const InputDecoration(
                      labelText: 'نوع الهاند شيك',
                      labelStyle: TextStyle(color: Colors.grey),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'SUNSHINE',
                        child: Text('Sunshine (تجربة 3 طرق)'),
                      ),
                      DropdownMenuItem(
                        value: 'ROCKSPACE_STR',
                        child: Text('Rockspace Machine Handshake'),
                      ),
                      DropdownMenuItem(
                        value: 'HANDSHAKE_NEW',
                        child: Text('PassWord2'),
                      ),
                      DropdownMenuItem(
                        value: 'OLD_V1',
                        child: Text('OldPassWord'),
                      ),
                      DropdownMenuItem(
                        value: 'OLD_V3',
                        child: Text('PassWord'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => handshakeChoice = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'إذا ما بتعرف النوع، خليه Sunshine للتجربة التلقائية.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(
                      const _FirstSerialSetupChoice(
                        machineType: 'unknown',
                        handshakeAlgorithm: 'SUNSHINE',
                      ),
                    );
                  },
                  child: const Text(
                    'جرب Sunshine',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop(
                      _FirstSerialSetupChoice(
                        machineType: machineType,
                        handshakeAlgorithm: handshakeChoice,
                      ),
                    );
                  },
                  child: const Text('حفظ ومتابعة'),
                ),
              ],
            ),
          );
        },
      );

      final resolved = choice ??
          const _FirstSerialSetupChoice(
            machineType: 'unknown',
            handshakeAlgorithm: 'SUNSHINE',
          );

      await prefs.setBool(doneKey, true);
      await prefs.setString(_machineTypeKey(serialValue), resolved.machineType);

      if (resolved.machineType == 'dq_like') {
        await prefs.setBool('last_machine_is_dq', true);
      } else if (resolved.machineType == 'ss_like') {
        await prefs.setBool('last_machine_is_dq', false);
      }

      final normalizedAlgo =
          MachineHandshake.normalizeAlgorithm(resolved.handshakeAlgorithm) ??
              MachineHandshake.algoSunshine;
      if (normalizedAlgo != MachineHandshake.algoSunshine) {
        await prefs.setString('handshake_algo_$serialValue', normalizedAlgo);
        await prefs.setString('handshake_mode_$serialValue', 'user_known');
        await prefs.setBool('auto_connect_enabled', true);
      }

      return normalizedAlgo;
    } finally {
      _serialSetupDialogOpen = false;
    }
  }

  List<Widget> _getPages() => [
        const DashboardScreen(),
        const CartScreen(),
        const ProfileScreen(),
      ];

  bool _useWideLayout(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final shortestSide = size.shortestSide;
    final isLandscape = size.width > size.height;
    // Match PhoneFilm-style breakpoints: sw600dp + landscape-aware layout.
    return shortestSide >= 600 || (isLandscape && size.width >= 720);
  }

  List<String> _buildPortCandidates(SharedPreferences prefs) {
    final result = <String>[];

    final lastSerial = (prefs.getString('last_connected_serial') ?? '').trim();
    if (lastSerial.isNotEmpty) {
      final serialPort =
          (prefs.getString('serial_port_$lastSerial') ?? '').trim();
      if (serialPort.isNotEmpty) {
        result.add(serialPort);
      }
    }

    final saved = (prefs.getString('last_serial_port_path') ?? '').trim();
    if (saved.isNotEmpty) {
      result.add(saved);
    }

    // Prefer ttyS0 first to avoid stalls on boxes where ttyS1 is present
    // but inaccessible or not wired to the cutter.
    result.add('/dev/ttyS0');
    if (saved == '/dev/ttyS1' || lastSerial.isNotEmpty) {
      final serialPort =
          (prefs.getString('serial_port_$lastSerial') ?? '').trim();
      if (serialPort == '/dev/ttyS1' || saved == '/dev/ttyS1') {
        result.add('/dev/ttyS1');
      }
    }

    // Only include extended ports when they were explicitly saved before.
    if (saved == '/dev/ttyS2' || saved == '/dev/ttyS3') {
      result.add('/dev/ttyS2');
      result.add('/dev/ttyS3');
    }

    final seen = <String>{};
    result.removeWhere((p) => p.isEmpty || !seen.add(p));
    return result;
  }

  List<String> _buildDirectHandshakeCandidates({
    required String? cachedBySerial,
    required String manualDefault,
    String? setupSelectedAlgorithm,
  }) {
    final result = <String>[];
    // Sunshine stays first priority, then known/cached choices, then Rockspace fallback.
    result.add(MachineHandshake.algoSunshine);

    void addNormalized(String? value) {
      final normalized = MachineHandshake.normalizeAlgorithm(value);
      if (normalized != null && normalized.isNotEmpty) {
        result.add(normalized);
      }
    }

    addNormalized(setupSelectedAlgorithm);
    addNormalized(cachedBySerial);
    addNormalized(manualDefault);

    // Some machines only answer STR handshake, so keep a fallback path.
    result.add(MachineHandshake.algoRockspace);

    final seen = <String>{};
    result.removeWhere((algo) => !seen.add(algo));
    return result;
  }

  Future<void> _persistSuccessfulPortForSerial(
    SharedPreferences prefs, {
    required String openedPort,
    required String serial,
  }) async {
    await prefs.setString('last_serial_port_path', openedPort);
    await prefs.setString('last_connected_serial', serial);
    await prefs.setString('serial_port_$serial', openedPort);
  }

  Future<bool> _probeMachineResponse(CutterBluetoothService cutter) async {
    final completer = Completer<bool>();
    late StreamSubscription<String> sub;
    Timer? timeout;

    // Probe should not trigger background auto-handshake side effects.
    cutter.setSuppressAutoHandshake(true);

    sub = cutter.receivedDataStream.listen((data) {
      if (data.trim().isNotEmpty && !completer.isCompleted) {
        completer.complete(true);
      }
    });

    timeout = Timer(const Duration(seconds: 3), () {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    });

    try {
      await cutter.write(";RCBM;");
      await Future.delayed(const Duration(milliseconds: 120));
      await cutter.write(";;;RPID;");
      await Future.delayed(const Duration(milliseconds: 120));
      await cutter.write(";RMODE;");
      await Future.delayed(const Duration(milliseconds: 120));
      await cutter.write(";BD:10;");
    } catch (_) {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    } finally {
      cutter.setSuppressAutoHandshake(false);
    }

    final ok = await completer.future;
    timeout.cancel();
    await sub.cancel();
    return ok;
  }

  Future<bool> _runHandshakeAttempt(
    CutterBluetoothService cutter, {
    String? forcedAlgorithm,
    String? preferredAlgorithm,
    required int maxRounds,
    required Duration timeout,
    required bool persistOnSuccess,
    required String mode,
  }) async {
    final completer = Completer<bool>();
    final handshake = MachineHandshake(
      cutter,
      onStatusUpdate: (status) => debugPrint('AutoConnect: $status'),
      onHandshakeComplete: (ok) {
        if (!completer.isCompleted) {
          completer.complete(ok);
        }
      },
      forcedAlgorithm: forcedAlgorithm,
      preferredAlgorithm: preferredAlgorithm,
      handshakeMode: mode,
      persistOnSuccess: persistOnSuccess,
      maxRounds: maxRounds,
    );

    handshake.startHandshake();
    final success = await completer.future.timeout(
      timeout,
      onTimeout: () => false,
    );
    handshake.dispose();
    return success;
  }

  Duration _handshakeScanTimeout({
    required bool hasImmediateRx,
    required int rounds,
  }) {
    // Keep timeout long enough to finish a full algorithm pass.
    final perRoundSeconds = hasImmediateRx ? 75 : 90;
    return Duration(seconds: (perRoundSeconds * rounds) + 20);
  }

  Future<bool> _tryAutoConnect() async {
    if (_autoConnectInProgress) return CutterBluetoothService().isConnected;

    final cutter = CutterBluetoothService();
    if (cutter.isConnected) return true;

    _autoConnectInProgress = true;
    bool success = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final ports = _buildPortCandidates(prefs);

      for (final port in ports) {
        debugPrint('AutoConnect: trying requested port $port');
        var stopPortFallback = false;
        try {
          await cutter.connect(portPath: port);
          final openedPort = (cutter.lastOpenPortPath ?? port).trim();
          debugPrint('AutoConnect: opened $openedPort');

          final hasRx = await _probeMachineResponse(cutter);
          if (hasRx) {
            // If a port is alive, keep trying it on next cycle instead of
            // bouncing to other ports (prevents jumping to blocked ttyS1).
            stopPortFallback = true;
          }
          if (!hasRx) {
            debugPrint(
              'AutoConnect: no immediate machine response on $openedPort; trying handshake anyway',
            );
          }

          String detectedSerial =
              (await _waitForDetectedSerial(cutter))?.trim() ??
                  (cutter.serialNumber ?? '').trim();
          String? setupSelectedAlgorithm;
          if (detectedSerial.isNotEmpty) {
            setupSelectedAlgorithm = await _runFirstSerialSetupIfNeeded(
              prefs,
              detectedSerial,
            );
            detectedSerial = (cutter.serialNumber ?? detectedSerial).trim();
          }
          final cachedBySerial = _readCachedAlgorithmForSerial(
            prefs,
            detectedSerial.isEmpty ? null : detectedSerial,
          );
          final manualDefault = _readManualDefaultAlgorithm(prefs);
          final directAlgorithms = _buildDirectHandshakeCandidates(
            cachedBySerial: cachedBySerial,
            manualDefault: manualDefault,
            setupSelectedAlgorithm: setupSelectedAlgorithm,
          );

          for (final algorithm in directAlgorithms) {
            final mode = (cachedBySerial != null && algorithm == cachedBySerial)
                ? 'auto_cached'
                : (setupSelectedAlgorithm != null &&
                        algorithm == setupSelectedAlgorithm)
                    ? 'first_time_setup'
                    : (algorithm == MachineHandshake.algoRockspace)
                        ? 'fallback_rockspace'
                        : 'manual_default';
            debugPrint('AutoConnect: direct $mode attempt: $algorithm');
            final directOk = await _runHandshakeAttempt(
              cutter,
              forcedAlgorithm: algorithm,
              maxRounds: 1,
              timeout: const Duration(seconds: 30),
              persistOnSuccess: true,
              mode: mode,
            );
            if (directOk) {
              final serialAfterSuccess =
                  (cutter.serialNumber ?? detectedSerial).trim();
              if (serialAfterSuccess.isNotEmpty) {
                await _persistSuccessfulPortForSerial(
                  prefs,
                  openedPort: openedPort,
                  serial: serialAfterSuccess,
                );
              } else {
                await prefs.setString('last_serial_port_path', openedPort);
              }
              debugPrint(
                'AutoConnect: direct success on $openedPort using $algorithm',
              );
              success = true;
              break;
            }
          }
          if (success) break;

          final preferredAlgo = _resolvePreferredAlgorithm(
            prefs,
            detectedSerial.isEmpty ? null : detectedSerial,
          );
          debugPrint(
            'AutoConnect: serial=${detectedSerial.isEmpty ? 'unknown' : detectedSerial} '
            'preferred=${preferredAlgo ?? 'none'}',
          );

          const scanRounds = 1;
          final scanTimeout = _handshakeScanTimeout(
            hasImmediateRx: hasRx,
            rounds: scanRounds,
          );
          debugPrint(
            'AutoConnect: scan rounds=$scanRounds timeout=${scanTimeout.inSeconds}s',
          );

          final roundSuccess = await _runHandshakeAttempt(
            cutter,
            preferredAlgorithm: preferredAlgo,
            maxRounds: scanRounds,
            timeout: scanTimeout,
            persistOnSuccess: true,
            mode: 'auto',
          );

          if (roundSuccess) {
            final serialAfterSuccess =
                (cutter.serialNumber ?? detectedSerial).trim();
            if (serialAfterSuccess.isNotEmpty) {
              await _persistSuccessfulPortForSerial(
                prefs,
                openedPort: openedPort,
                serial: serialAfterSuccess,
              );
            } else {
              await prefs.setString('last_serial_port_path', openedPort);
            }
            debugPrint('AutoConnect: success on $openedPort');
            success = true;
            break;
          }

          await cutter.disconnect();
          if (stopPortFallback) {
            debugPrint(
              'AutoConnect: keeping same active port on next cycle, skip fallback ports',
            );
            break;
          }
        } catch (e) {
          debugPrint('AutoConnect: failed on $port: $e');
          await cutter.disconnect();
        }
      }
    } catch (_) {
      await cutter.disconnect();
    } finally {
      _autoConnectInProgress = false;
      if (mounted) setState(() {});
    }
    return success || cutter.isConnected;
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
                    onDestinationSelected: (index) {
                      setState(() {
                        _currentIndex = index;
                      });
                    },
                    selectedIconTheme: const IconThemeData(
                      color: Color(0xFF00FF88),
                    ),
                    selectedLabelTextStyle: const TextStyle(
                      color: Color(0xFF00FF88),
                    ),
                    unselectedIconTheme: const IconThemeData(
                      color: Colors.grey,
                    ),
                    unselectedLabelTextStyle: const TextStyle(
                      color: Colors.grey,
                    ),
                    labelType: NavigationRailLabelType.all,
                    destinations: [
                      NavigationRailDestination(
                        icon: const Icon(Icons.home),
                        label: Text(AppStrings.of(context, 'home')),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.shopping_cart),
                        label: Text(AppStrings.of(context, 'cart')),
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
