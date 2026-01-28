import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
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
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    // Request multiple permissions
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    if (statuses.values.every((status) => status.isGranted)) {
      _startScan();
    } else {
      // Handle denied
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context, 'permissions_required'))),
      );
    }
  }

  Future<void> _startScan() async {
    if (CutterBluetoothService().isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context, 'disconnect_to_scan')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isScanning = true;
      _scanResults = [];
    });

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));

      FlutterBluePlus.scanResults.listen((results) {
        if (mounted) {
          setState(() {
            _scanResults = results
                .where(
                  (r) =>
                      r.device.platformName.toLowerCase().startsWith("cutter"),
                )
                .toList();
          });
        }
      });

      await Future.delayed(const Duration(seconds: 5));
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    } catch (e) {
      print("Scan error: $e");
    }
  }

  Future<void> _openHandshakeTester(BluetoothDevice device) async {
    // Connect first
    try {
      await CutterBluetoothService().connect(device);

      if (!mounted) return;

      // Navigate to tester screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => HandshakeTesterScreen(
            deviceId: device.remoteId.toString(),
            deviceName: device.platformName,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${AppStrings.of(context, 'connection_error')}: $e'),
        ),
      );
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    // Stop scanning first
    await FlutterBluePlus.stopScan();

    _showLoadingDialog(AppStrings.of(context, 'connecting'));

    try {
      // 1. Connect
      await CutterBluetoothService().connect(device);

      Navigator.pop(context); // Pop connecting dialog
      _showLoadingDialog(AppStrings.of(context, 'authenticating'));

      // 2. Handshake
      // Create a completer to await the callback result // verify
      final Completer<bool> handshakeCompleter = Completer<bool>();

      final handshake = MachineHandshake(
        CutterBluetoothService(),
        onStatusUpdate: (status) {
          print("Handshake Status: $status");
        },
        onHandshakeComplete: (success) {
          if (!handshakeCompleter.isCompleted) {
            handshakeCompleter.complete(success);
          }
        },
      );

      handshake.startHandshake();

      // Await the completer result with a safety timeout
      bool success = await handshakeCompleter.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () => false,
      );
      handshake.dispose(); // Clean up internal subscription

      Navigator.pop(context); // Pop auth dialog

      if (success) {
        // Wait up to 2 seconds for serial number to be populated
        // Note: In the new logic, handshake completes when verified, so serial check is less critical here
        // but let's keep it safe.
        int retries = 0;
        while (CutterBluetoothService().serialNumber == null && retries < 4) {
          await Future.delayed(const Duration(milliseconds: 500));
          print("Waiting for serial number... ${retries + 1}");
          retries++;
        }

        // Save serial to Service for global access
        // (Actually, CutterBluetoothService holds it already if populated)
        // verify
        if (CutterBluetoothService().serialNumber == null) {
          CutterBluetoothService().setSerialNumber("Unknown SN");
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.of(context, 'connected_authenticated')),
          ),
        );
        // FORCE UI REFRESH
        if (mounted) setState(() {});

        // Return success to the caller (DeviceDetailScreen)
        Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.of(context, 'auth_failed')),
            backgroundColor: Colors.red,
          ),
        );
        await CutterBluetoothService().disconnect();
      }
    } catch (e) {
      if (mounted) {
        // Schedule the pop to avoid '_debugLocked' errors during build
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context);
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("${AppStrings.of(context, 'connection_error')}: $e"),
          backgroundColor: Colors.red,
        ),
      );
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
    bool isConnected = CutterBluetoothService().isConnected;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppStrings.of(context, 'select_machine'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFF121212),
      body: StreamBuilder<BluetoothAdapterState>(
        stream: CutterBluetoothService().adapterState,
        initialData: BluetoothAdapterState.unknown,
        builder: (context, snapshot) {
          final state = snapshot.data;
          if (state != BluetoothAdapterState.on) {
            return _buildBluetoothOffWidget(state);
          }
          return Column(
            children: [
              // Header Status
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isConnected
                          ? AppStrings.of(context, 'msg_disconnect_to_scan')
                          : _isScanning
                          ? AppStrings.of(context, 'scanning')
                          : "${AppStrings.of(context, 'found_devices')} (${_scanResults.length})",
                      style: TextStyle(color: Colors.grey[400]),
                    ),
                    if (!isConnected)
                      if (!_isScanning)
                        IconButton(
                          icon: const Icon(
                            Icons.refresh,
                            color: Color(0xFF00FF88),
                          ),
                          onPressed: _startScan,
                        )
                      else
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF00FF88),
                          ),
                        ),
                  ],
                ),
              ),

              if (CutterBluetoothService().isConnected &&
                  CutterBluetoothService().connectedDevice != null)
                _buildConnectedDeviceCard(),

              Expanded(
                child: ListView.builder(
                  itemCount: _scanResults.length,
                  itemBuilder: (context, index) {
                    final device = _scanResults[index].device;
                    final name = device.platformName.isNotEmpty
                        ? device.platformName
                        : AppStrings.of(context, 'unknown_device');

                    return Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF333333)),
                      ),
                      child: ListTile(
                        onTap: () => _connectToDevice(device),
                        onLongPress: () => _openHandshakeTester(device),
                        title: Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              device.remoteId.toString(),
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              AppStrings.of(context, 'hold_to_test_handshake'),
                              style: TextStyle(
                                color: const Color(0xFF00FF88).withOpacity(0.7),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildConnectedDeviceCard() {
    final device = CutterBluetoothService().connectedDevice!;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF00FF88),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00FF88).withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 12,
        ),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.bluetooth_connected,
            color: Colors.black,
            size: 28,
          ),
        ),
        title: Text(
          AppStrings.of(context, 'status_connected'),
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          device.platformName.isNotEmpty
              ? device.platformName
              : AppStrings.of(context, 'unknown_device'),
          style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.logout, color: Colors.black87),
          tooltip: "Disconnect",
          onPressed: () async {
            await CutterBluetoothService().disconnect();
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }

  Widget _buildBluetoothOffWidget(BluetoothAdapterState? state) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              state == BluetoothAdapterState.unauthorized
                  ? Icons.lock_outline
                  : Icons.bluetooth_disabled,
              size: 80,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 24),
            Text(
              state == BluetoothAdapterState.unauthorized
                  ? AppStrings.of(context, 'bluetooth_perms_required')
                  : AppStrings.of(context, 'bluetooth_is_off'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              state == BluetoothAdapterState.unauthorized
                  ? AppStrings.of(context, 'grant_bluetooth_permission')
                  : AppStrings.of(context, 'turn_on_bluetooth_msg'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),
            const SizedBox(height: 32),
            if (state != BluetoothAdapterState.unauthorized)
              ElevatedButton.icon(
                onPressed: () => CutterBluetoothService().turnOnBluetooth(),
                icon: const Icon(Icons.bluetooth),
                label: Text(AppStrings.of(context, 'turn_on_bluetooth_btn')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00FF88),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
