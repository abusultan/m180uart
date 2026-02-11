import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/bluetooth_service.dart';
import '../../core/machine_handshake.dart';
import 'handshake_tester_screen.dart';
import '../../core/app_strings.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _isConnecting = false;
  String _handshakeMode = "auto";
  String _manualAlgorithm = "HANDSHAKE_NEW";

  final List<Map<String, String>> _handshakeAlgorithms = const [
    {"label": "Handshake New", "value": "HANDSHAKE_NEW"},
    {"label": "PASS_U32", "value": "PASS_U32"},
    {"label": "Generic New", "value": "GENERIC_NEW"},
    {"label": "DQ", "value": "DQ"},
    {"label": "SY", "value": "SY"},
    {"label": "Standard", "value": "STANDARD"},
    {"label": "Sunshine", "value": "SUNSHINE"},
    {"label": "Cutter", "value": "CUTTER"},
    {"label": "Old V1", "value": "OLD_V1"},
    {"label": "Old V3", "value": "OLD_V3"},
    {"label": "Devia", "value": "DEVIA"},
  ];

  Future<void> _connectSerial() async {
    if (_isConnecting) return;
    setState(() {
      _isConnecting = true;
    });

    _showLoadingDialog(AppStrings.of(context, 'connecting'));

    try {
      await CutterBluetoothService().connect();

      Navigator.pop(context);
      _showLoadingDialog(AppStrings.of(context, 'authenticating'));

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
        forcedAlgorithm: _handshakeMode == "manual" ? _manualAlgorithm : null,
        handshakeMode: _handshakeMode,
      );

      handshake.startHandshake();
      bool success = await handshakeCompleter.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () => false,
      );
      handshake.dispose();

      Navigator.pop(context);

      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppStrings.of(context, 'connected_authenticated'))),
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
      body: Padding(
        padding: const EdgeInsets.all(16.0),
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
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isConnected ? "Connected" : "Disconnected",
                      style: TextStyle(color: isConnected ? Colors.green : Colors.red),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            DropdownButtonFormField<String>(
              value: _handshakeMode,
              decoration: InputDecoration(
                labelText: 'Handshake Mode',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: const [
                DropdownMenuItem(value: 'auto', child: Text('Auto')),
                DropdownMenuItem(value: 'manual', child: Text('Manual')),
              ],
              onChanged: (val) {
                if (val == null) return;
                setState(() {
                  _handshakeMode = val;
                });
              },
            ),
            const SizedBox(height: 12),
            if (_handshakeMode == 'manual')
              DropdownButtonFormField<String>(
                value: _manualAlgorithm,
                decoration: InputDecoration(
                  labelText: 'Handshake Algorithm',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: _handshakeAlgorithms
                    .map(
                      (algo) => DropdownMenuItem(
                        value: algo['value'],
                        child: Text(algo['label']!),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val == null) return;
                  setState(() {
                    _manualAlgorithm = val;
                  });
                },
              ),
            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: _isConnecting ? null : _connectSerial,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00FF88),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(_isConnecting
                  ? AppStrings.of(context, 'connecting')
                  : AppStrings.of(context, 'connect_cutter')), 
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: isConnected ? _disconnectSerial : null,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Disconnect'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const HandshakeTesterScreen(
                      deviceId: 'serial',
                      deviceName: 'Internal Serial',
                    ),
                  ),
                );
              },
              child: const Text('Handshake Tester'),
            ),
          ],
        ),
      ),
    );
  }
}
