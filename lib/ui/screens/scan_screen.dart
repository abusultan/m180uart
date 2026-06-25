import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_project/core/serial/serial_service.dart';
import 'package:flutter_project/core/serial/mietubl_handshake.dart';
import '../../core/app_strings.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _isConnecting = false;
  final List<String> _logs = [];

  void _log(String msg) {
    debugPrint('ScanScreen: $msg');
    setState(() {
      _logs.add('[${DateTime.now().toString().substring(11, 19)}] $msg');
      if (_logs.length > 50) _logs.removeAt(0);
    });
  }

  @override
  void initState() {
    super.initState();
  }

  Future<void> _connectSerial() async {
    if (_isConnecting) return;
    setState(() {
      _isConnecting = true;
    });

    _showLoadingDialog(AppStrings.of(context, 'connecting'));

    try {
      // Connect serial at 38400 baud
      _log('Opening serial port (38400 baud)...');
      await CutterSerialService().connect();
      if (!mounted) return;

      _log('Port opened: ${CutterSerialService().lastOpenPortPath ?? "?"}');
      Navigator.pop(context); // close "connecting" dialog
      _showLoadingDialog('Authenticating M180T...');

      // Run Mietubl 180T handshake
      _log('Starting M180T handshake...');
      final Completer<bool> handshakeCompleter = Completer<bool>();
      final handshake = MietublHandshake(
        CutterSerialService(),
        onStatusUpdate: (status) {
          debugPrint("Handshake: $status");
          _log(status);
        },
        onHandshakeComplete: (success) {
          _log('Handshake result: $success');
          if (!handshakeCompleter.isCompleted) {
            handshakeCompleter.complete(success);
          }
        },
      );

      handshake.startHandshake();
      bool success = await handshakeCompleter.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          _log('TIMEOUT - no response from machine');
          return false;
        },
      );
      handshake.dispose();

      if (!mounted) return;
      Navigator.pop(context); // close "authenticating" dialog

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.of(context, 'connected_authenticated')),
            backgroundColor: const Color(0xFF00FF88),
          ),
        );
        Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.of(context, 'auth_failed')),
            backgroundColor: Colors.red,
          ),
        );
        await CutterSerialService().disconnect();
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
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
    await CutterSerialService().disconnect();
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
    final isConnected = CutterSerialService().isConnected;

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
                  maxWidth: constraints.maxWidth >= 700 ? 560 : constraints.maxWidth,
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
                              "Mietubl 180T Cutter",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              isConnected ? "Connected ✅" : "Disconnected",
                              style: TextStyle(
                                color: isConnected ? Colors.green : Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              "Protocol: M180T UART (38400 baud)",
                              style: TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                          ],
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
                    const SizedBox(height: 24),
                    // Debug logs
                    if (_logs.isNotEmpty) ...[
                      const Text(
                        'Connection Log:',
                        style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 200,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListView.builder(
                          itemCount: _logs.length,
                          itemBuilder: (context, index) => Text(
                            _logs[index],
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 10,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ),
                    ],
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
