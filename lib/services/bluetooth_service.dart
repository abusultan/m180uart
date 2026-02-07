import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as blue;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/encryption_util.dart';

class CutterBluetoothService {
  static final CutterBluetoothService _instance =
      CutterBluetoothService._internal();

  factory CutterBluetoothService() {
    return _instance;
  }

  CutterBluetoothService._internal();

  blue.BluetoothDevice? _connectedDevice;
  blue.BluetoothCharacteristic? _writeCharacteristic;
  blue.BluetoothCharacteristic? _notifyCharacteristic;

  StreamSubscription? _notifySubscription;
  final _receivedDataController = StreamController<String>.broadcast();
  final _serialUpdateController = StreamController<String?>.broadcast();
  String _autoHandshakeBuffer = "";
  bool _suppressAutoHandshake = false;

  Stream<String> get receivedDataStream => _receivedDataController.stream;
  Stream<String?> get serialStream => _serialUpdateController.stream;
  Stream<blue.BluetoothAdapterState> get adapterState =>
      blue.FlutterBluePlus.adapterState;

  blue.BluetoothDevice? get connectedDevice => _connectedDevice;
  String? _serialNumber;
  String? get serialNumber => _serialNumber;
  String? _lastHandshakeMode;
  String? get lastHandshakeMode => _lastHandshakeMode;

  String? _preferredHandshakeAlgo;
  String? _preferredHandshakeMode;

  void setSerialNumber(String? serial) {
    _serialNumber = serial;
    _serialUpdateController.add(serial);
    // Persist machine type for UI filtering even when not connected
    if (serial != null) {
      _persistLastMachineType(serial);
    }
  }

  Future<void> _persistLastMachineType(String serial) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final upper = serial.toUpperCase();
      final isPlt =
          upper.startsWith("DQ") ||
          upper.startsWith("DX") ||
          upper.startsWith("LH");
      await prefs.setBool('last_machine_is_dq', isPlt);
    } catch (e) {
      print("Error persisting machine type: $e");
    }
  }

  Future<bool?> getLastMachineIsDQ() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('last_machine_is_dq');
    } catch (e) {
      print("Error loading machine type: $e");
      return null;
    }
  }

  void setPreferredHandshakeForNextConnection(
    String mode, {
    String? algorithm,
  }) {
    _preferredHandshakeMode = mode;
    _preferredHandshakeAlgo = algorithm;
  }

  void clearPreferredHandshakeForNextConnection() {
    _preferredHandshakeMode = null;
    _preferredHandshakeAlgo = null;
  }

  String? get preferredHandshakeMode => _preferredHandshakeMode;
  String? get preferredHandshakeAlgorithm => _preferredHandshakeAlgo;

  void setSuppressAutoHandshake(bool suppress) {
    _suppressAutoHandshake = suppress;
    print("Auto-Handshake Suppression: $suppress");
  }

  Future<void> turnOnBluetooth() async {
    try {
      await blue.FlutterBluePlus.turnOn();
    } catch (e) {
      print("Error turning on Bluetooth: $e");
    }
  }

  // Cache for successful handshake algorithm
  String? _successfulAgentType;
  bool? _successfulIsNewVersion;

  Future<void> cacheSuccessfulHandshake(
    String agentType,
    bool isNewVersion, {
    String mode = "auto",
  }) async {
    _successfulAgentType = agentType;
    _successfulIsNewVersion = isNewVersion;
    _lastHandshakeMode = mode;
    print(
      "Cached successful handshake (Memory): Agent=$agentType, IsNew=$isNewVersion",
    );

    if (_serialNumber != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('handshake_algo_$_serialNumber', agentType);
        await prefs.setString('handshake_mode_$_serialNumber', mode);
        // IsNewVersion is implicitly tied to the algorithm names usually, but let's store it to be safe if needed eventually
        // For now, simpler to just store the algo string.
        print("Persisted handshake for $_serialNumber: $agentType");
      } catch (e) {
        print("Error persisting handshake: $e");
      }
    }
  }

  Future<String?> getCachedHandshake(String serial) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('handshake_algo_$serial');
    } catch (e) {
      print("Error loading cached handshake: $e");
      return null;
    }
  }

  Future<String?> getCachedHandshakeMode(String serial) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('handshake_mode_$serial');
    } catch (e) {
      print("Error loading handshake mode: $e");
      return null;
    }
  }

  bool get isConnected =>
      _connectedDevice != null && _connectedDevice!.isConnected;

  String? get successfulHandshakeType => _successfulAgentType;

  Future<void> connect(blue.BluetoothDevice device) async {
    // 1. Disconnect previous if any
    if (_connectedDevice != null) {
      await disconnect();
      // Wait for stack to clear (fix for Android 133 error)
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // 2. Connect
    // 'autoConnect: false' helps with stability on some Android devices
    await device.connect(autoConnect: false, license: blue.License.free);
    _connectedDevice = device;

    // 3. Discover Services
    List<blue.BluetoothService> services = await device.discoverServices();
    print("Discovered ${services.length} services");

    // 4. Find Characteristic
    List<blue.BluetoothCharacteristic> candidates = [];

    for (var service in services) {
      print("Service: ${service.uuid}");
      for (var characteristic in service.characteristics) {
        String props = "";
        if (characteristic.properties.read) props += "R";
        if (characteristic.properties.write) props += "W";
        if (characteristic.properties.writeWithoutResponse) props += "w";
        if (characteristic.properties.notify) props += "N";
        if (characteristic.properties.indicate) props += "I";

        print("  Char: ${characteristic.uuid} [$props]");

        // We look for a characteristic that supports BOTH Write (or WriteWithoutResponse) AND Notify
        if ((characteristic.properties.write ||
                characteristic.properties.writeWithoutResponse) &&
            characteristic.properties.notify) {
          candidates.add(characteristic);
        }
      }
    }

    if (candidates.isNotEmpty) {
      // Logic to pick the best candidate
      // 1. Prefer Custom UUIDs (usually long 128-bit or specific 16-bit like FFE1)
      // 2. Avoid Standard UUIDs (0000xxxx-0000-1000-8000-00805f9b34fb) if possible, especially 2a07 (Tx Power)

      _writeCharacteristic = candidates.first; // Default fallback
      _notifyCharacteristic = candidates.first;

      for (var c in candidates) {
        String uuid = c.uuid.toString().toLowerCase();
        // Check for common UART UUIDs or non-standard ones
        if (uuid.contains("ffe1") ||
            uuid.contains("6e40") ||
            !uuid.contains("0000-1000-8000-00805f9b34fb")) {
          print("Selected Custom/UART Characteristic: $uuid");
          _writeCharacteristic = c;
          _notifyCharacteristic = c;
          break; // Found a good one
        }
      }

      // If we didn't find a "Good" one, check if we have multiple and one of them is NOT 2a07
      if (_writeCharacteristic!.uuid.toString().contains("2a07") &&
          candidates.length > 1) {
        for (var c in candidates) {
          if (!c.uuid.toString().contains("2a07")) {
            print("Avoiding 2a07, selecting: ${c.uuid}");
            _writeCharacteristic = c;
            _notifyCharacteristic = c;
            break;
          }
        }
      }

      print(
        "Final Selection -> Write: ${_writeCharacteristic!.uuid}, Notify: ${_notifyCharacteristic!.uuid}",
      );
    }

    if (_writeCharacteristic == null || _notifyCharacteristic == null) {
      throw Exception("Could not find suitable UART characteristics");
    }

    // 5. Subscribe to notifications
    if (_notifyCharacteristic != null) {
      print("Setting up notification listener...");

      // Listen FIRST to avoid missing data
      _notifySubscription = _notifyCharacteristic!.onValueReceived.listen((
        value,
      ) {
        print("Raw BLE Data Received (${value.length} bytes): $value");
        _onDataReceived(value);
      });

      // Then Enable
      print("Enabling notifications on ${_notifyCharacteristic!.uuid}...");
      try {
        await _notifyCharacteristic!.setNotifyValue(true);
        print("Notifications enabled.");
      } catch (e) {
        print("Warning: Failed to enable notifications (likely Code 10): $e");
        // Proceed anyway, as some devices work without explicit enable or throw false errors
      }
    }
  }

  Future<void> disconnect() async {
    _notifySubscription?.cancel();
    _writeCharacteristic = null;
    _notifyCharacteristic = null;
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
    }
    _connectedDevice = null;
  }

  Future<void> write(String data) async {
    if (_writeCharacteristic == null) throw Exception("Not connected");
    print("[BLE TX] Sending: $data");

    List<int> bytes = data.codeUnits;
    int chunkSize = 20; // Safe BLE default, can be higher if MTU negotiated

    for (int i = 0; i < bytes.length; i += chunkSize) {
      int end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
      List<int> chunk = bytes.sublist(i, end);

      if (_writeCharacteristic!.properties.writeWithoutResponse) {
        await _writeCharacteristic!.write(chunk, withoutResponse: true);
      } else {
        await _writeCharacteristic!.write(chunk);
      }
      // Small delay to prevent flooding
      await Future.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<void> writeBytes(
    List<int> bytes, {
    bool forceWithResponse = false,
    int chunkSize = 20,
    int packetDelayMs = 20,
  }) async {
    if (_writeCharacteristic == null) throw Exception("Not connected");

    for (int i = 0; i < bytes.length; i += chunkSize) {
      int end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
      List<int> chunk = bytes.sublist(i, end);

      if (!forceWithResponse &&
          _writeCharacteristic!.properties.writeWithoutResponse) {
        await _writeCharacteristic!.write(chunk, withoutResponse: true);
      } else {
        await _writeCharacteristic!.write(chunk);
      }
      // Small delay to prevent flooding
      await Future.delayed(Duration(milliseconds: packetDelayMs));
    }
  }

  void _onDataReceived(List<int> bytes) {
    try {
      String data = String.fromCharCodes(bytes);
      print("[BLE RX] $data");

      // Buffering for internal protocol handling
      _autoHandshakeBuffer += data;

      // Process complete messages
      while (_autoHandshakeBuffer.contains(";")) {
        int endIndex = _autoHandshakeBuffer.indexOf(";");
        String message = _autoHandshakeBuffer.substring(0, endIndex + 1);
        _autoHandshakeBuffer = _autoHandshakeBuffer.substring(endIndex + 1);

        // Clean up message
        message = message.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');

        // ALWAYS-ON HANDSHAKE LISTENER
        // Requirement: Respond to RCMD=11 if we have a successful cache OR if not suppressed.
        if (message.contains("RCMD=11,")) {
          if (!_suppressAutoHandshake) {
            print("Auto-Responding to challenge: $message");
            _handleAutoHandshake(message);
          } else {
            print("Auto-Handshake suppressed for message: $message");
          }
        }
      }

      // Clean up the data for UI subscribers
      data = data.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');
      _receivedDataController.add(data);
    } catch (e) {
      print("Error decoding RX data: $e");
    }
  }

  Future<void> _handleAutoHandshake(String data) async {
    try {
      // Extract Challenge
      // Format: ...RCMD=11,123456;...
      int start = data.indexOf("RCMD=11,") + 8;
      int end = data.indexOf(";", start);
      if (end == -1) end = data.length;
      String numStr = data.substring(start, end).trim();
      int challenge = int.parse(numStr);

      int response;

      // 1. Try memory cache first
      String? cachedAlgo = _successfulAgentType;

      // 2. If memory cache failed, try persistent storage if we have serial
      if (cachedAlgo == null && _serialNumber != null) {
        cachedAlgo = await getCachedHandshake(_serialNumber!);
        // If found in storage, assume isNew=true (safest default for stored strings unless it is DQ)
        // Actually, if it's DQ, getSunshinePassword handles it? No, getSunshinePassword handles brands.
        // But the old logic handled DQ via getDQHandshake.
        // However, encryption_util.dart handles DQ separately.
        // We might need to handle DQ specifically here if stored value is "DQ".
        if (cachedAlgo != null) {
          print("Restored cached algo from disk: $cachedAlgo");
        }
      }

      if (cachedAlgo != null) {
        if (cachedAlgo == "DQ") {
          response = EncryptionUtil.getDQHandshake(challenge);
        } else if (cachedAlgo == "OLD_V1") {
          response = EncryptionUtil.getHandshakeOldV1(challenge);
        } else if (cachedAlgo == "OLD_V3") {
          response = EncryptionUtil.getHandshakeOldV3(challenge);
        } else {
          // Default/Brand logic
          response = EncryptionUtil.getSunshinePassword(challenge, cachedAlgo);
        }
      } else {
        // No cache, try default (most common: HandshakeNew)
        print("No cached algorithm, using HandshakeNew as default");
        response = EncryptionUtil.getHandshakeNew(challenge);
      }

      print("Auto-Handshake Challenge: $challenge -> Response: $response");
      write("BD:12,$response;");
    } catch (e) {
      print("Auto-Handshake Error: $e");
    }
  }
}
