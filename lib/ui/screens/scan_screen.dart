import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/bluetooth_service.dart';
import '../../core/machine_handshake.dart';
import '../../core/app_strings.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _isConnecting = false;
  String _manualAlgorithm = MachineHandshake.algoSunshine;
  static const String _algoPrefKey = 'manual_handshake_algorithm_ui';

  final List<Map<String, String>> _handshakeAlgorithms = const [
    {"label": "Sunshine (Try 3 methods)", "value": "SUNSHINE"},
    {
      "label": "Rockspace Machine Handshake",
      "value": "ROCKSPACE_STR",
    },
    {"label": "PassWord2 (Primary)", "value": "HANDSHAKE_NEW"},
    {"label": "OldPassWord", "value": "OLD_V1"},
    {"label": "PassWord", "value": "OLD_V3"},
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedAlgorithm();
  }

  Future<void> _loadSavedAlgorithm() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_algoPrefKey);
      if (saved == null ||
          !_handshakeAlgorithms.any((a) => a['value'] == saved)) {
        return;
      }
      if (!mounted) return;
      setState(() {
        _manualAlgorithm = saved;
      });
    } catch (_) {}
  }

  String get _manualAlgorithmLabel {
    for (final algo in _handshakeAlgorithms) {
      if (algo['value'] == _manualAlgorithm) {
        return algo['label'] ?? _manualAlgorithm;
      }
    }
    return _manualAlgorithm;
  }

  Future<String> _readAlgorithmForConnect() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_algoPrefKey);
      if (saved != null &&
          _handshakeAlgorithms.any((a) => a['value'] == saved)) {
        if (mounted) {
          setState(() {
            _manualAlgorithm = saved;
          });
        } else {
          _manualAlgorithm = saved;
        }
        return saved;
      }
    } catch (_) {}
    return _manualAlgorithm;
  }

  Future<bool> _askToPinHandshake(String algorithm, String? serial) async {
    final serialText = (serial == null || serial.isEmpty) ? 'Unknown' : serial;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تثبيت الهاند شيك'),
        content: Text(
          'تم اختبار $algorithm بنجاح على الماكينة $serialText.\nهل تريد تثبيته كافتراضي لهذه الماكينة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('لا'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('نعم'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _connectSerial() async {
    if (_isConnecting) return;
    setState(() {
      _isConnecting = true;
    });

    _showLoadingDialog(AppStrings.of(context, 'connecting'));

    try {
      await CutterBluetoothService().connect();
      if (!mounted) return;

      Navigator.pop(context);
      _showLoadingDialog(AppStrings.of(context, 'authenticating'));

      final connectAlgorithm = await _readAlgorithmForConnect();
      final Completer<bool> handshakeCompleter = Completer<bool>();
      final handshake = MachineHandshake(
        CutterBluetoothService(),
        onStatusUpdate: (status) {
          debugPrint("Handshake Status: $status");
        },
        onHandshakeComplete: (success) {
          if (!handshakeCompleter.isCompleted) {
            handshakeCompleter.complete(success);
          }
        },
        forcedAlgorithm: connectAlgorithm,
        handshakeMode: "manual",
        persistOnSuccess: false,
      );

      handshake.startHandshake();
      bool success = await handshakeCompleter.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () => false,
      );
      handshake.dispose();
      if (!mounted) return;

      Navigator.pop(context);

      if (success) {
        final bluetooth = CutterBluetoothService();
        final selectedAlgorithm = connectAlgorithm;
        final serial = bluetooth.serialNumber;
        bool shouldAskToPin = true;
        if (serial != null && serial.isNotEmpty) {
          final cachedAlgo = await bluetooth.getCachedHandshake(serial);
          final cachedMode = await bluetooth.getCachedHandshakeMode(serial);
          shouldAskToPin =
              !(cachedMode == "manual" && cachedAlgo == selectedAlgorithm);
        }

        if (shouldAskToPin) {
          final remember = mounted
              ? await _askToPinHandshake(selectedAlgorithm, serial)
              : false;
          if (remember) {
            await bluetooth.cacheSuccessfulHandshake(
              selectedAlgorithm,
              true,
              mode: "manual",
              persist: true,
            );
          }
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text(AppStrings.of(context, 'connected_authenticated'))),
          );
        }
        if (mounted) Navigator.of(context).pop(true);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppStrings.of(context, 'auth_failed')),
              backgroundColor: Colors.red,
            ),
          );
        }
        await CutterBluetoothService().disconnect();
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("${AppStrings.of(context, 'connection_error')}: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  Future<void> _disconnectSerial() async {
    await CutterBluetoothService().disconnect();
    if (mounted) {
      setState(() {});
    }
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF2A2A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFF00FF88)),
              const SizedBox(height: 16),
              Text(message, style: const TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = CutterBluetoothService().isConnected;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppStrings.of(context, 'select_machine'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth:
                      constraints.maxWidth >= 700 ? 560 : constraints.maxWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      color: const Color(0xFF1E1E1E),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Internal Serial Cutter",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              isConnected ? "Connected" : "Disconnected",
                              style: TextStyle(
                                color: isConnected ? Colors.green : Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      color: const Color(0xFF1E1E1E),
                      child: ListTile(
                        leading: const Icon(
                          Icons.lock,
                          color: Color(0xFF00FF88),
                        ),
                        title: const Text('Handshake Algorithm'),
                        subtitle: Text(
                          'Current: $_manualAlgorithmLabel\nChange from Protected Settings',
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _isConnecting ? null : _connectSerial,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00FF88),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _isConnecting
                            ? AppStrings.of(context, 'connecting')
                            : AppStrings.of(context, 'connect_cutter'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: isConnected ? _disconnectSerial : null,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Disconnect'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
