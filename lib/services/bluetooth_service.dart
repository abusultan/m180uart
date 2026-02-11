import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import '../utils/encryption_util.dart';

class CutterBluetoothService {
  static final CutterBluetoothService _instance =
      CutterBluetoothService._internal();

  factory CutterBluetoothService() {
    return _instance;
  }

  CutterBluetoothService._internal() {
    _ensureEventStream();
  }

  final MethodChannel _channel = const MethodChannel('serial_port');
  final EventChannel _eventChannel = const EventChannel('serial_port/events');

  StreamSubscription? _eventSubscription;
  final _receivedDataController = StreamController<String>.broadcast();
  final _serialUpdateController = StreamController<String?>.broadcast();
  String _autoHandshakeBuffer = "";
  bool _suppressAutoHandshake = false;

  bool _isConnected = false;
  Object? _connectedDevice;

  Stream<String> get receivedDataStream => _receivedDataController.stream;
  Stream<String?> get serialStream => _serialUpdateController.stream;

  Object? get connectedDevice => _connectedDevice;
  String? _serialNumber;
  String? get serialNumber => _serialNumber;
  String? _lastHandshakeMode;
  String? get lastHandshakeMode => _lastHandshakeMode;

  String? _preferredHandshakeAlgo;
  String? _preferredHandshakeMode;

  void setSerialNumber(String? serial) {
    _serialNumber = serial;
    _serialUpdateController.add(serial);
    if (serial != null) {
      _persistLastMachineType(serial);
      _syncDeviceHandshake(serial);
    }
  }

  Future<void> _syncDeviceHandshake(String serial) async {
    final backendHandshake = await ApiService().getDeviceBySerialNumber(serial);

    if (backendHandshake != null && backendHandshake.isNotEmpty) {
      await cacheSuccessfulHandshake(backendHandshake, false, mode: "api");
    } else {
      final upper = serial.toUpperCase();
      if (upper.startsWith("DQ") ||
          upper.startsWith("DX") ||
          upper.startsWith("LH")) {
        await cacheSuccessfulHandshake("DQ", false, mode: "heuristic");
      } else {
        _registerDeviceWithBackend(serial);
      }
    }
  }

  Future<void> _registerDeviceWithBackend(String serial) async {
    String? handshake = _successfulAgentType;
    if (handshake == null) {
      handshake = await getCachedHandshake(serial);
    }

    if (handshake != null) {
      ApiService().addDevice(serial, handshake);
    }
  }

  Future<void> _persistLastMachineType(String serial) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final upper = serial.toUpperCase();
      final isPlt =
          upper.startsWith("DQ") || upper.startsWith("DX") || upper.startsWith("LH");
      await prefs.setBool('last_machine_is_dq', isPlt);
    } catch (_) {}
  }

  Future<bool?> getLastMachineIsDQ() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('last_machine_is_dq');
    } catch (_) {
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

    if (_serialNumber != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('handshake_algo_$_serialNumber', agentType);
        await prefs.setString('handshake_mode_$_serialNumber', mode);
        ApiService().addDevice(_serialNumber!, agentType);
      } catch (_) {}
    }
  }

  Future<String?> getCachedHandshake(String serial) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('handshake_algo_$serial');
    } catch (_) {
      return null;
    }
  }

  Future<String?> getCachedHandshakeMode(String serial) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('handshake_mode_$serial');
    } catch (_) {
      return null;
    }
  }

  bool get isConnected => _isConnected;

  String? get successfulHandshakeType => _successfulAgentType;

  Future<void> connect({String? portPath, int baud = 115200}) async {
    _ensureEventStream();
    final candidates = <String>[];
    if (portPath != null && portPath.isNotEmpty) {
      candidates.add(portPath);
    } else {
      candidates.addAll(['/dev/ttyS1', '/dev/ttyS0']);
    }

    Object? lastError;
    for (final path in candidates) {
      try {
        final ok = await _channel.invokeMethod<bool>('open', {
          'path': path,
          'baud': baud,
        });
        if (ok == true) {
          _isConnected = true;
          _connectedDevice = Object();
          return;
        }
      } catch (e) {
        lastError = e;
      }
    }

    throw Exception('Failed to open serial port' + (lastError != null ? ': $lastError' : ''));
  }

  Future<void> disconnect() async {
    _eventSubscription?.cancel();
    _eventSubscription = null;
    try {
      await _channel.invokeMethod('close');
    } catch (_) {}
    _isConnected = false;
    _connectedDevice = null;
    _serialNumber = null;
    _successfulAgentType = null;
    _successfulIsNewVersion = null;
    _lastHandshakeMode = null;
    _autoHandshakeBuffer = "";
    _serialUpdateController.add(null);
  }

  Future<void> write(String data) async {
    if (!_isConnected) throw Exception("Not connected");
    await _channel.invokeMethod('write', {'data': data});
  }

  Future<void> writeBytes(
    List<int> bytes, {
    bool forceWithResponse = false,
    int chunkSize = 20,
    int packetDelayMs = 20,
  }) async {
    if (!_isConnected) throw Exception("Not connected");
    // Chunking is handled in Dart to keep behavior consistent.
    for (int i = 0; i < bytes.length; i += chunkSize) {
      int end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
      List<int> chunk = bytes.sublist(i, end);
      await _channel.invokeMethod('writeBytes', {'bytes': Uint8List.fromList(chunk)});
      if (packetDelayMs > 0) {
        await Future.delayed(Duration(milliseconds: packetDelayMs));
      }
    }
  }

  Future<bool> performPrintHandshakeDQ({
    Duration challengeTimeout = const Duration(seconds: 3),
    Duration ackTimeout = const Duration(seconds: 1),
  }) async {
    if (!_isConnected) return false;
    _ensureEventStream();
    setSuppressAutoHandshake(true);

    final completer = Completer<bool>();
    String buffer = "";
    bool handshakeSent = false;
    Timer? challengeTimer;
    Timer? ackTimer;

    late StreamSubscription sub;
    void finish(bool ok) {
      if (!completer.isCompleted) {
        completer.complete(ok);
      }
    }

    sub = receivedDataStream.listen((data) {
      buffer += data;
      while (buffer.contains(";")) {
        final end = buffer.indexOf(";");
        var msg = buffer.substring(0, end + 1);
        buffer = buffer.substring(end + 1);

        msg = msg.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
        if (msg.isEmpty) continue;

        if (msg.contains("RCMD=10,1")) {
          finish(false);
          return;
        }
        if (msg.contains("RCMD=12,0")) {
          finish(true);
          return;
        }
        if (msg.contains("RCMD=12,1")) {
          finish(false);
          return;
        }

        final challenge = _extractChallengeFromMessage(msg);
        if (challenge != null && !handshakeSent) {
          handshakeSent = true;
          challengeTimer?.cancel();
          final password = EncryptionUtil.getDQHandshake(challenge);
          write("BD:12,$password;");
          ackTimer?.cancel();
          ackTimer = Timer(ackTimeout, () {
            finish(true);
          });
        }
      }
    });

    challengeTimer = Timer(challengeTimeout, () {
      if (!handshakeSent) finish(false);
    });

    bool ok;
    try {
      await write("BD:10;");
      ok = await completer.future.timeout(
        challengeTimeout + ackTimeout + const Duration(seconds: 2),
        onTimeout: () => false,
      );
    } catch (_) {
      ok = false;
    } finally {
      await sub.cancel();
      challengeTimer?.cancel();
      ackTimer?.cancel();
      setSuppressAutoHandshake(false);
    }
    return ok;
  }

  int? _extractChallengeFromMessage(String msg) {
    try {
      if (msg.contains("RCMD=11,")) {
        int start = msg.indexOf("RCMD=11,") + 8;
        int end = msg.indexOf(";", start);
        if (end == -1) end = msg.length;
        return int.tryParse(msg.substring(start, end).trim());
      }
      if (msg.startsWith("11,")) {
        final parts = msg.replaceAll(";", "").split(',');
        if (parts.length >= 2) return int.tryParse(parts[1].trim());
      }
      final idx = msg.indexOf(",11,");
      if (idx != -1) {
        final tail = msg.substring(idx + 4).replaceAll(";", "");
        final parts = tail.split(',');
        if (parts.isNotEmpty) return int.tryParse(parts[0].trim());
      }
    } catch (_) {}
    return null;
  }

  void _ensureEventStream() {
    if (_eventSubscription != null) return;
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen((event) {
      if (event is String) {
        _onDataReceived(event);
      } else if (event is Uint8List) {
        _onDataReceived(String.fromCharCodes(event));
      }
    });
  }

  void _onDataReceived(String data) {
    String clean = data;
    _autoHandshakeBuffer += clean;

    while (_autoHandshakeBuffer.contains(";")) {
      int endIndex = _autoHandshakeBuffer.indexOf(";");
      String message = _autoHandshakeBuffer.substring(0, endIndex + 1);
      _autoHandshakeBuffer = _autoHandshakeBuffer.substring(endIndex + 1);

      message = message.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');

      if (message.contains("RCMD=11,")) {
        if (!_suppressAutoHandshake) {
          _handleAutoHandshake(message);
        }
      }
    }

    clean = clean.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');
    _receivedDataController.add(clean);
  }

  Future<void> _handleAutoHandshake(String data) async {
    try {
      int start = data.indexOf("RCMD=11,") + 8;
      int end = data.indexOf(";", start);
      if (end == -1) end = data.length;
      String numStr = data.substring(start, end).trim();
      int challenge = int.parse(numStr);

      int response;
      String? cachedAlgo = _successfulAgentType;

      if (cachedAlgo == null && _serialNumber != null) {
        cachedAlgo = await getCachedHandshake(_serialNumber!);
      }

      if (cachedAlgo != null) {
        if (cachedAlgo == "DQ") {
          response = EncryptionUtil.getDQHandshake(challenge);
        } else if (cachedAlgo == "OLD_V1") {
          response = EncryptionUtil.getHandshakeOldV1(challenge);
        } else if (cachedAlgo == "OLD_V3") {
          response = EncryptionUtil.getHandshakeOldV3(challenge);
        } else {
          response = EncryptionUtil.getSunshinePassword(challenge, cachedAlgo);
        }
      } else {
        if (_successfulAgentType == null) {
          cacheSuccessfulHandshake("HandshakeNew", true, mode: "default");
        }
        response = EncryptionUtil.getHandshakeNew(challenge);
      }

      write("BD:12,$response;");
    } catch (_) {}
  }

  // Kept for compatibility with older UI calls
  Future<void> turnOnBluetooth() async {
    // No-op for serial connection
  }
}
