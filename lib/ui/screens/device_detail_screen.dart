import 'dart:io';
import 'dart:async';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/bluetooth_service.dart';
import '../../data/models/product_models.dart';
import '../../core/machine_handshake.dart';
import 'scan_screen.dart';
import '../../utils/digit_mapper.dart';
import '../../core/app_strings.dart';

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

  /*
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
  */

  Future<void> _downloadFile() async {
    if (widget.productItem == null) return;

    setState(() {
      _isDownloading = true;
      _status = AppStrings.of(context, 'status_downloading');
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
        _status = AppStrings.of(context, 'status_no_file');
      });
      return;
    }

    final file = await ApiService().downloadFile(url);
    if (file != null) {
      _cutFile = file;
      setState(() {
        _isDownloading = false;
        _status = AppStrings.of(context, 'status_file_ready');
      });
      _startCut();
    } else {
      setState(() {
        _isDownloading = false;
        _status = AppStrings.of(context, 'status_download_failed');
      });
    }
  }

  Future<void> _startCut() async {
    // 0. Pre-check Remaining Pieces (Local)
    final remaining = ApiService().currentUser?.remainingPieces ?? 0;
    if (remaining <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context, 'error_not_enough_pieces')),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_cutFile == null) {
      // Trigger download first
      _downloadFile();
      return;
    }

    if (_isCutting) return;

    setState(() {
      _isCutting = true;
      _status = AppStrings.of(context, 'status_verifying_balance');
    });

    try {
      // 0.5. Call API to Record Use (Deduct Balance) - Gatekeeper
      // If this fails (e.g. server says no pieces), we stop.
      if (widget.productItem != null) {
        await ApiService().recordCutterUse(widget.productItem!.id.toString());
        // If we are here, it succeeded. Local balance is updated by ApiService.
        setState(() {}); // Refresh UI for new balance
      }

      setState(() => _status = AppStrings.of(context, 'status_sync_handshake'));

      // 0. Perform Handshake Sync (Targeted re-handshake)
      // This ensures we have a valid challenge/password session before starting.
      bool handshakeSuccess = await _performHandshakeSync();
      if (!handshakeSuccess) {
        throw Exception(AppStrings.of(context, 'error_handshake_failed'));
      }
      if (!mounted) return;

      setState(() => _status = AppStrings.of(context, 'status_init_cut'));
      // 1. Clear Buffer
      // Use ;;; instead of ;RCBM; to avoid resetting the machine/auth state.
      // This ensures we stay authenticated for consecutive cuts.
      await _bluetooth.write(";;;");
      if (!mounted) return;
      setState(
        () => _status = AppStrings.of(context, 'status_clearing_buffer'),
      );
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;

      // 2. Home
      setState(() => _status = AppStrings.of(context, 'status_homing'));
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
      setState(() => _status = AppStrings.of(context, 'status_sending_data'));

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

      setState(() => _status = AppStrings.of(context, 'status_starting_cut'));
      await _bluetooth.write("BD:100,13;");

      setState(() {
        _status = AppStrings.of(context, 'status_cut_started');
        _isCutting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context, 'msg_cut_success')),
          backgroundColor: Color(0xFF00FF88),
        ),
      );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      String errorMsg = e.toString();
      if (errorMsg.contains("Exception:")) {
        errorMsg = errorMsg.replaceAll("Exception:", "").trim();
      }

      setState(() {
        _status = "Error: $errorMsg";
        _isCutting = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error: $errorMsg"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isConnected = _bluetooth.isConnected;
    String name =
        widget.productItem?.nameEn ?? AppStrings.of(context, 'unknown_product');

    int remaining = ApiService().currentUser?.remainingPieces ?? 0;
    bool hasBalance = remaining > 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.of(context, 'cutter_control_title')),
        backgroundColor: Colors.transparent,
      ),
      backgroundColor: const Color(0xFF121212),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Product Image
                      if (widget.productItem?.imageUrl.isNotEmpty ?? false)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 20.0),
                          child: AspectRatio(
                            aspectRatio: 1.4,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child:
                                  widget.productItem!.imageUrl
                                      .toLowerCase()
                                      .endsWith('.svg')
                                  ? SvgPicture.network(
                                      widget.productItem!.imageUrl,
                                      fit: BoxFit.contain,
                                      width: double.infinity,
                                      height: double.infinity,
                                      colorFilter: const ColorFilter.mode(
                                        Colors.white,
                                        BlendMode.srcIn,
                                      ),
                                      placeholderBuilder: (context) =>
                                          const Center(
                                            child: CircularProgressIndicator(
                                              color: Color(0xFF00FF88),
                                            ),
                                          ),
                                    )
                                  : Image.network(
                                      widget.productItem!.imageUrl,
                                      fit: BoxFit.contain,
                                      width: double.infinity,
                                      height: double.infinity,
                                      errorBuilder: (c, e, s) => const Center(
                                        child: Icon(
                                          Icons.broken_image,
                                          color: Colors.grey,
                                          size: 50,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),

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
                      /*
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
                      isConnected
                          ? (_status == "Ready" ? "Connected" : _status)
                          : "Disconnected",
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              */
                      const SizedBox(height: 40),

                      // Connected Controls
                      /*
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
                      */
                      const SizedBox(height: 40),

                      const Spacer(),

                      if (isConnected)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: Text(
                            "${AppStrings.of(context, 'remaining')}: $remaining",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: hasBalance
                                  ? const Color(0xFF00FF88)
                                  : Colors.red,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),

                      // Action Button
                      SizedBox(
                        height: 60,
                        child: ElevatedButton(
                          onPressed:
                              _isCutting ||
                                  _isDownloading ||
                                  (!hasBalance && isConnected)
                              ? null
                              : () {
                                  if (isConnected) {
                                    _startCut();
                                  } else {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const ScanScreen(),
                                      ),
                                    ).then((_) => _checkConnection());
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: !hasBalance && isConnected
                                ? Colors.red.shade900
                                : (isConnected
                                      ? const Color(0xFF00FF88)
                                      : const Color(0xFF444444)),
                            foregroundColor: isConnected && hasBalance
                                ? Colors.black
                                : Colors.white,
                            disabledBackgroundColor: Colors.grey.shade800,
                            elevation: 5,
                          ),
                          child: _isCutting || _isDownloading
                              ? const CircularProgressIndicator(
                                  color: Colors.black,
                                )
                              : Text(
                                  !hasBalance && isConnected
                                      ? AppStrings.of(
                                          context,
                                          'not_enough_pieces',
                                        )
                                      : (isConnected
                                            ? AppStrings.of(
                                                context,
                                                'send_to_cutter',
                                              )
                                            : AppStrings.of(
                                                context,
                                                'connect_to_cutter',
                                              )),
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
              ),
            ),
          );
        },
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
