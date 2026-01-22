import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/bluetooth_service.dart';
import '../../data/models/product_models.dart';
import '../../core/machine_handshake.dart';
import 'scan_screen.dart';
import '../../utils/digit_mapper.dart';

class DeviceDetailScreen extends StatefulWidget {
  final ProductItem? productItem;

  const DeviceDetailScreen({super.key, this.productItem});

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  final CutterBluetoothService _bluetooth = CutterBluetoothService();

  double _speed = 15;
  double _force = 10;
  bool _isCutting = false;
  bool _isDownloading = false;
  String _status = "Ready";
  File? _cutFile;

  @override
  void initState() {
    super.initState();
    _checkConnection();
  }

  void _checkConnection() {
    setState(() {}); // Refresh UI state based on connection
  }

  Future<void> _setSpeed(double value) async {
    setState(() => _speed = value);
    if (_bluetooth.isConnected) {
      await _bluetooth.write("BD:4,${value.toInt()};");
    }
  }

  Future<void> _setForce(double value) async {
    setState(() => _force = value);
    if (_bluetooth.isConnected) {
      await _bluetooth.write("BD:3,${value.toInt()};");
    }
  }

  Future<void> _downloadFile() async {
    if (widget.productItem == null) return;

    setState(() {
      _isDownloading = true;
      _status = "Downloading file...";
    });

    // Logic: Try PLT for DQ machines, SJC for others.
    String? serial = _bluetooth.serialNumber;
    bool isDQ = serial != null && serial.toUpperCase().startsWith("DQ");

    String url;
    if (isDQ) {
      url = widget.productItem!.pltUrl.isNotEmpty
          ? widget.productItem!.pltUrl
          : widget.productItem!.sjcUrl;
    } else {
      url = widget.productItem!.sjcUrl.isNotEmpty
          ? widget.productItem!.sjcUrl
          : widget.productItem!.pltUrl;
    }

    if (url.isEmpty) {
      setState(() {
        _isDownloading = false;
        _status = "No file available";
      });
      return;
    }

    final file = await ApiService().downloadFile(url);
    if (file != null) {
      _cutFile = file;
      setState(() {
        _isDownloading = false;
        _status = "File Ready";
      });
      _startCut();
    } else {
      setState(() {
        _isDownloading = false;
        _status = "Download Failed";
      });
    }
  }

  Future<void> _startCut() async {
    if (_cutFile == null) {
      // Trigger download first
      _downloadFile();
      return;
    }

    if (_isCutting) return;

    setState(() {
      _isCutting = true;
      _status = "Synchronizing Handshake...";
    });

    try {
      // 0. Perform Handshake Sync (Targeted re-handshake)
      // This ensures we have a valid challenge/password session before starting.
      bool handshakeSuccess = await _performHandshakeSync();
      if (!handshakeSuccess) {
        throw Exception("Handshake synchronization failed.");
      }
      if (!mounted) return;

      setState(() => _status = "Initializing Cut...");
      // 1. Clear Buffer
      // Use ;;; instead of ;RCBM; to avoid resetting the machine/auth state.
      // This ensures we stay authenticated for consecutive cuts.
      await _bluetooth.write(";;;");
      if (!mounted) return;
      setState(() => _status = "Clearing Buffer...");
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;

      // 2. Home
      setState(() => _status = "Homing...");
      await _bluetooth.write("BD:110,3;");
      await Future.delayed(const Duration(milliseconds: 2000));
      if (!mounted) return;

      // 3. Set Params
      await _bluetooth.write("BD:3,${_force.toInt()};");
      await Future.delayed(const Duration(milliseconds: 200));
      await _bluetooth.write("BD:4,${_speed.toInt()};");
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;

      // 4. Send File Data
      setState(() => _status = "Sending Data...");

      // Determine machine type from serial
      String? serial = _bluetooth.serialNumber;
      bool isDQ = serial != null && serial.toUpperCase().startsWith("DQ");

      List<int> bytesToSend;

      if (isDQ) {
        // DQ Machines: Original Java code sends RAW bytes.
        // We suspect previous "Wrong Cutting" was due to Packet Loss (missing digits).
        // We are sending RAW bytes now with improved Bluetooth reliability.
        bytesToSend = await _cutFile!.readAsBytes();
        print(
          "DQ Machine detected ($serial). Sending RAW bytes (Java behavior).",
        );
      } else {
        // Standard Machines: Read bytes directly (User confirmed SRC/SJC file for Sunshine New)
        // Reverted PLT encryption as per user feedback
        bytesToSend = await _cutFile!.readAsBytes();
      }

      int chunkSize = 2048;
      int offset = 0;

      while (offset < bytesToSend.length) {
        if (!mounted) return; // Check cancel
        int end = offset + chunkSize;
        if (end > bytesToSend.length) end = bytesToSend.length;
        List<int> chunk = bytesToSend.sublist(offset, end);

        await _bluetooth.writeBytes(chunk);
        // BluetoothService already has a small delay, but we add a bit more for large file safety tasks
        await Future.delayed(const Duration(milliseconds: 50));
        offset += chunkSize;
      }

      // 5. Start Cut Command
      await Future.delayed(const Duration(milliseconds: 1000));
      if (!mounted) return;

      setState(() => _status = "Starting Cut...");
      await _bluetooth.write("BD:100,13;");

      // Record Use API
      if (widget.productItem != null) {
        // Fire and forget or await, but check mounted if affecting UI
        await ApiService().recordCutterUse(widget.productItem!.id.toString());
      }

      setState(() {
        _status = "Cut Started!";
        _isCutting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Cut Started Successfully!"),
          backgroundColor: Color(0xFF00FF88),
        ),
      );

      // Optionally pop back to list?
      // Navigator.pop(context);
    } catch (e) {
      setState(() {
        _status = "Error: $e";
        _isCutting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isConnected = _bluetooth.isConnected;
    String name =
        widget.productItem?.nameEn ??
        widget.productItem?.nameAr ??
        "Unknown Product";

    return Scaffold(
      appBar: AppBar(
        title: const Text("Cutter Control"),
        backgroundColor: Colors.transparent,
      ),
      backgroundColor: const Color(0xFF121212),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Product Info
            Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            // Status Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isConnected
                      ? [const Color(0xFF00FF88), const Color(0xFF00C853)]
                      : [Colors.grey, Colors.grey.shade700],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Icon(
                    isConnected
                        ? Icons.bluetooth_connected
                        : Icons.bluetooth_disabled,
                    size: 48,
                    color: Colors.black,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isConnected ? "Connected: $_status" : "Disconnected",
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),

            // Connected Controls
            if (isConnected) ...[
              // Speed Control
              const Text(
                "Speed",
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _speed,
                      min: 1,
                      max: 20,
                      activeColor: const Color(0xFF00FF88),
                      onChanged: _setSpeed,
                    ),
                  ),
                  Text(
                    "${_speed.toInt()}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Force Control
              const Text(
                "Force",
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _force,
                      min: 1,
                      max: 30,
                      activeColor: const Color(0xFF00FF88),
                      onChanged: _setForce,
                    ),
                  ),
                  Text(
                    "${_force.toInt()}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ],

            const Spacer(),

            // Action Button
            SizedBox(
              height: 60,
              child: ElevatedButton(
                onPressed: _isCutting || _isDownloading
                    ? null
                    : () {
                        if (isConnected) {
                          _startCut();
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ScanScreen(),
                            ),
                          ).then((_) => _checkConnection());
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isConnected
                      ? const Color(0xFF00FF88)
                      : const Color(0xFF444444),
                  foregroundColor: isConnected ? Colors.black : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 5,
                ),
                child: _isCutting || _isDownloading
                    ? const CircularProgressIndicator(color: Colors.black)
                    : Text(
                        isConnected ? "SEND TO CUTTER" : "CONNECT TO CUTTER",
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _performHandshakeSync() async {
    final completer = Completer<bool>();

    final handshake = MachineHandshake(
      _bluetooth,
      onStatusUpdate: (status) {
        if (mounted) setState(() => _status = status);
      },
      onHandshakeComplete: (success) {
        if (!completer.isCompleted) completer.complete(success);
      },
    );

    handshake.startHandshake();

    // Safety timeout of 15 seconds (should be fast if cached)
    return await completer.future
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            handshake.dispose();
            return false;
          },
        )
        .then((val) {
          handshake.dispose();
          return val;
        });
  }
}
