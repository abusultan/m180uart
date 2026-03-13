import 'dart:async';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/handshake_response_resolver.dart';
import 'api_service.dart';

class CutterBluetoothService {
  static const String _lastTypeMachineNameKey = 'last_type_machine_name';
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
  final _receivedDataController = StreamController<String>();
  final _serialUpdateController = StreamController<String?>();
  final _typeMachineNameController = StreamController<String>();
  late final Stream<String> _receivedDataBroadcast =
      _receivedDataController.stream.asBroadcastStream();
  late final Stream<String?> _serialUpdateBroadcast =
      _serialUpdateController.stream.asBroadcastStream();
  late final Stream<String> _typeMachineNameBroadcast =
      _typeMachineNameController.stream.asBroadcastStream();
  String _autoHandshakeBuffer = "";
  bool _suppressAutoHandshake = false;

  bool _isConnected = false;
  Object? _connectedDevice;

  Stream<String> get receivedDataStream => _receivedDataBroadcast;
  Stream<String?> get serialStream => _serialUpdateBroadcast;
  Stream<String> get typeMachineNameStream => _typeMachineNameBroadcast;

  Object? get connectedDevice => _connectedDevice;
  String? _serialNumber;
  String? get serialNumber => _serialNumber;
  String? _currentTypeMachineName;
  String? get currentTypeMachineName => _currentTypeMachineName;
  String? _lastHandshakeMode;
  String? get lastHandshakeMode => _lastHandshakeMode;
  String? _lastOpenPortPath;
  String? get lastOpenPortPath => _lastOpenPortPath;

  String? _preferredHandshakeAlgo;
  String? _preferredHandshakeMode;
  final Map<String, String> _cachedHandshakeBySerial = {};
  bool _isBypassMode = false;
  String? _cachedAgentType;

  String _serialCacheKey(String serial) => serial.trim().toUpperCase();

  String? _getCachedHandshakeFromMemory(String? serial) {
    final value = (serial ?? '').trim();
    if (value.isEmpty) return null;
    return _cachedHandshakeBySerial[_serialCacheKey(value)];
  }

  void _rememberCachedHandshake(String serial, String algorithm) {
    final value = serial.trim();
    if (value.isEmpty) return;
    _cachedHandshakeBySerial[_serialCacheKey(value)] =
        _normalizeHandshakeAlgorithm(algorithm);
  }

  void _emitTypeMachineName(String? value) {
    final normalized = (value ?? '').trim();
    if (normalized.isEmpty) return;
    if (_currentTypeMachineName == normalized) return;
    _currentTypeMachineName = normalized;
    _typeMachineNameController.add(normalized);
  }

  void setSerialNumber(String? serial) {
    final normalized = _normalizeSerialCandidate(serial);
    if (normalized == null || normalized.isEmpty) return;

    final current = (_serialNumber ?? '').trim();
    if (current == normalized) return;

    // Ignore obvious truncated updates once we already captured a fuller serial.
    if (current.isNotEmpty &&
        normalized.length < current.length &&
        current.startsWith(normalized)) {
      return;
    }

    _serialNumber = normalized;
    _serialUpdateController.add(normalized);
    _persistTypeMachineName(
      _resolveTypeMachineName(
        serial: normalized,
        agentType: _successfulAgentType,
      ),
    );
    _persistLastConnectedSerial(normalized);
    _persistLastMachineType(normalized);
    _syncDeviceHandshake(normalized);
  }

  String? _normalizeSerialCandidate(String? raw) {
    var text = (raw ?? '').trim();
    if (text.isEmpty) return null;

    final upper = text.toUpperCase();
    const markers = ['CBM=', 'SN=', 'SERIAL='];
    for (final marker in markers) {
      final idx = upper.lastIndexOf(marker);
      if (idx != -1) {
        text = text.substring(idx + marker.length).trim();
        break;
      }
    }

    text = text.replaceAll(';', ' ');
    if (text.contains('#')) {
      text = text.split('#').first;
    }

    final tokens = RegExp(r'[A-Za-z0-9_\-]{6,}')
        .allMatches(text)
        .map((m) => m.group(0) ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return null;

    tokens.sort((a, b) => b.length.compareTo(a.length));
    for (final token in tokens) {
      final t = token.toUpperCase();
      if (t == 'SUCCESS' || t == 'FAIL' || t == 'ERROR') continue;
      if (RegExp(r'\d').hasMatch(token)) return token;
    }

    return tokens.first;
  }

  Future<void> _persistLastConnectedSerial(String serial) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_connected_serial', serial);
    } catch (_) {}
  }

  Future<void> _syncDeviceHandshake(String serial) async {
    final localCached = await getCachedHandshake(serial);
    if (localCached != null && localCached.isNotEmpty) {
      _successfulAgentType = _normalizeHandshakeAlgorithm(localCached);
      _lastHandshakeMode = 'cached_local';
      return;
    }

    final backendHandshake = await ApiService().getDeviceBySerialNumber(serial);
    if (backendHandshake != null && backendHandshake.isNotEmpty) {
      await cacheSuccessfulHandshake(
        _normalizeHandshakeAlgorithm(backendHandshake),
        false,
        mode: 'api',
        persist: false,
      );
      return;
    }

    final upper = serial.toUpperCase();
    if (upper.startsWith('DQ') ||
        upper.startsWith('DX') ||
        upper.startsWith('LH')) {
      await cacheSuccessfulHandshake(
        'HANDSHAKE_NEW',
        false,
        mode: 'heuristic',
        persist: false,
      );
    }
    // Do not call add-device here; registration should happen only after
    // a proven successful handshake to avoid duplicate/incorrect backend rows.
  }

  Future<void> _persistLastMachineType(String serial) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final upper = serial.toUpperCase();
      final isPlt = upper.startsWith("DQ") ||
          upper.startsWith("DX") ||
          upper.startsWith("LH");
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
  bool get isBypassMode => _isBypassMode;
  String? get cachedAgentType => _cachedAgentType ?? _successfulAgentType;

  String _normalizeHandshakeAlgorithm(String? raw) {
    return HandshakeResponseResolver.normalizeOrDefault(raw);
  }

  String _resolveTypeMachineName({String? serial, String? agentType}) {
    final upperSerial = (serial ?? '').toUpperCase();
    final upperAgent = (agentType ?? '').toUpperCase();

    if (upperAgent == 'ROCKSPACE_BLUE' ||
        upperSerial.startsWith('C180B') ||
        upperSerial.startsWith('ZC2') ||
        upperSerial.startsWith('ZC3')) {
      return 'rock_space';
    }

    if (upperAgent == 'SUNSHINE' ||
        upperAgent == 'HANDSHAKE_NEW' ||
        upperAgent == 'SUNSHINEDQ' ||
        upperSerial.startsWith('SUNSHINE') ||
        upperSerial.startsWith('SS')) {
      return 'sunshine';
    }

    return 'DQ';
  }

  Future<void> _persistTypeMachineName(String typeMachineName) async {
    _emitTypeMachineName(typeMachineName);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastTypeMachineNameKey, typeMachineName);
    } catch (e) {
      print("Error persisting type_machine_name: $e");
    }
  }

  String? _resolveBackendMachineType(
    SharedPreferences prefs,
    String serial,
  ) {
    final upper = serial.trim().toUpperCase();
    if (upper.isEmpty) return null;

    if (upper.startsWith('DQ')) return 'crust';
    if (upper.startsWith('LH')) return 'hebeshi';
    if (upper.startsWith('DX') || upper.startsWith('DH')) return 'AtB';
    if (upper.startsWith('SS') ||
        upper.startsWith('CUTTER') ||
        upper.startsWith('SUNSHINE')) {
      return 'sunshine';
    }

    final stored = (prefs.getString('machine_type_$upper') ?? '').trim();
    if (stored.isEmpty || stored == 'unknown') return null;
    if (stored == 'ss_like') return 'sunshine';
    return stored;
  }

  String? _resolveBackendMachineDisplayName(
    SharedPreferences prefs,
    String serial,
    String? handshakeAlgorithm,
  ) {
    final normalizedAlgorithm =
        _normalizeHandshakeAlgorithm(handshakeAlgorithm);
    if (normalizedAlgorithm == HandshakeResponseResolver.algoMechanicUart) {
      return 'Mechanic UART';
    }

    final upper = serial.trim().toUpperCase();
    if (upper.isEmpty) return null;

    if (upper.startsWith('SS') ||
        upper.startsWith('CUTTER') ||
        upper.startsWith('SUNSHINE')) {
      return 'Sunshine UART';
    }
    if (upper.startsWith('DQ')) return 'DQ UART';
    if (upper.startsWith('LH')) return 'LH UART';
    if (upper.startsWith('DX') || upper.startsWith('DH')) return 'DX UART';

    final stored = (prefs.getString('machine_type_$upper') ?? '').trim();
    if (stored.isEmpty || stored == 'unknown') return null;
    if (stored == 'ss_like' || stored.toLowerCase() == 'sunshine') {
      return 'Sunshine UART';
    }
    if (stored == 'dq_like' || stored.toLowerCase() == 'crust') {
      return 'DQ UART';
    }
    if (stored.toLowerCase() == 'hebeshi') return 'LH UART';
    if (stored == 'AtB' || stored.toLowerCase() == 'atb') return 'DX UART';
    if (stored.toLowerCase().contains('uart')) return stored;
    return '$stored UART';
  }

  void setSuppressAutoHandshake(bool suppress) {
    _suppressAutoHandshake = suppress;
  }

  // Cache for successful handshake algorithm
  String? _successfulAgentType;

  Future<void> cacheSuccessfulHandshake(
    String agentType,
    bool isNewVersion, {
    String mode = "auto",
    bool persist = true,
  }) async {
    final normalizedAgentType = _normalizeHandshakeAlgorithm(agentType);
    _successfulAgentType = normalizedAgentType;
    _lastHandshakeMode = mode;
    if (_serialNumber != null && _serialNumber!.isNotEmpty) {
      _rememberCachedHandshake(_serialNumber!, normalizedAgentType);
    }

    if (!persist) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'last_successful_handshake_algo',
        normalizedAgentType,
      );
      await prefs.setString('last_successful_handshake_mode', mode);
      await prefs.setBool('auto_connect_enabled', true);
      if (_lastOpenPortPath != null && _lastOpenPortPath!.isNotEmpty) {
        await prefs.setString('last_serial_port_path', _lastOpenPortPath!);
      }

      if (_serialNumber != null && _serialNumber!.isNotEmpty) {
        final machineType = _resolveBackendMachineType(prefs, _serialNumber!);
        final machineName = _resolveBackendMachineDisplayName(
          prefs,
          _serialNumber!,
          normalizedAgentType,
        );
        await prefs.setString(
          'handshake_algo_$_serialNumber',
          normalizedAgentType,
        );
        await prefs.setString('handshake_mode_$_serialNumber', mode);
        await prefs.setString('last_connected_serial', _serialNumber!);
        if (_lastOpenPortPath != null && _lastOpenPortPath!.isNotEmpty) {
          await prefs.setString(
            'serial_port_$_serialNumber',
            _lastOpenPortPath!,
          );
        }
        ApiService().addDevice(
          _serialNumber!,
          normalizedAgentType,
          machineType: machineType,
          machineName: machineName,
        );
      }
    } catch (_) {}
  }

  Future<bool> shouldAutoConnect() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('auto_connect_enabled') ?? false;
      if (!enabled) return false;

      final lastSerial = prefs.getString('last_connected_serial');
      if (lastSerial != null && lastSerial.isNotEmpty) {
        final algo = prefs.getString('handshake_algo_$lastSerial');
        if (algo != null && algo.isNotEmpty) {
          return true;
        }
      }

      for (final key in prefs.getKeys()) {
        if (key.startsWith('handshake_algo_')) {
          final algo = prefs.getString(key);
          if (algo != null && algo.isNotEmpty) {
            return true;
          }
        }
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  Future<String?> getCachedHandshake(String serial) async {
    final memoryValue = _getCachedHandshakeFromMemory(serial);
    if (memoryValue != null && memoryValue.isNotEmpty) {
      return memoryValue;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString('handshake_algo_$serial');
      if (value == null || value.trim().isEmpty) return null;
      final normalized = _normalizeHandshakeAlgorithm(value);
      _rememberCachedHandshake(serial, normalized);
      return normalized;
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
    String? savedPort;
    String? serialPinnedPort;

    if (portPath != null && portPath.isNotEmpty) {
      // Explicit path mode: try only the requested port.
      candidates.add(portPath);
    } else {
      try {
        final prefs = await SharedPreferences.getInstance();
        savedPort = (prefs.getString('last_serial_port_path') ?? '').trim();
        final lastSerial =
            (prefs.getString('last_connected_serial') ?? '').trim();
        if (lastSerial.isNotEmpty) {
          serialPinnedPort =
              (prefs.getString('serial_port_$lastSerial') ?? '').trim();
        }
      } catch (_) {}

      final pinnedPort = serialPinnedPort;
      if (pinnedPort != null && pinnedPort.isNotEmpty) {
        candidates.add(pinnedPort);
      }
      final rememberedPort = savedPort;
      if (rememberedPort != null && rememberedPort.isNotEmpty) {
        candidates.add(rememberedPort);
      }

      // Full scan mode (manual connect screen).
      candidates.addAll(['/dev/ttyS0', '/dev/ttyS1']);

      final preferExtended = savedPort == '/dev/ttyS2' ||
          savedPort == '/dev/ttyS3' ||
          serialPinnedPort == '/dev/ttyS2' ||
          serialPinnedPort == '/dev/ttyS3';
      if (preferExtended) {
        candidates.addAll(['/dev/ttyS2', '/dev/ttyS3']);
      }
    }

    final seen = <String>{};
    candidates.removeWhere((p) => p.isEmpty || !seen.add(p));

    Object? lastError;
    for (final path in candidates) {
      try {
        print("🔌 Serial open attempt: $path @ $baud");
        final ok = await _channel.invokeMethod<bool>('open', {
          'path': path,
          'baud': baud,
        });
        if (ok == true) {
          print("✅ Serial opened on $path");
          _lastOpenPortPath = path;
          _isConnected = true;
          _connectedDevice = Object();
          return;
        }
        print("❌ Serial open returned false on $path");
      } catch (e) {
        print("❌ Serial open error on $path: $e");
        lastError = e;
      }
    }

    throw Exception(
      'Failed to open serial port' + (lastError != null ? ': $lastError' : ''),
    );
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
      await _channel.invokeMethod('writeBytes', {
        'bytes': Uint8List.fromList(chunk),
      });
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
          final password =
              HandshakeResponseResolver.resolvePrintHandshakeResponse(
            challenge,
          );
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
      challengeTimer.cancel();
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
      final cbm = _extractValue(message, "CBM=");
      if (cbm != null && cbm.isNotEmpty) {
        if (_serialNumber == null ||
            _serialNumber!.isEmpty ||
            _serialNumber != cbm) {
          setSerialNumber(cbm);
        }
      }

      if (!message.contains("=")) {
        final bare = message.replaceAll(";", "").trim();
        if (RegExp(
          r'^(SS|DQ|DX|LH)[A-Za-z0-9\-]{4,}$',
          caseSensitive: false,
        ).hasMatch(bare)) {
          if (_serialNumber == null || _serialNumber!.isEmpty) {
            setSerialNumber(bare);
          }
        }
      }

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

      String? cachedAlgo = _successfulAgentType;
      if ((cachedAlgo == null || cachedAlgo.isEmpty) && _serialNumber != null) {
        cachedAlgo = _getCachedHandshakeFromMemory(_serialNumber);
      }

      final normalizedAlgo = _normalizeHandshakeAlgorithm(cachedAlgo);
      final response = HandshakeResponseResolver.resolveChallengeResponse(
        algorithm: normalizedAlgo,
        challenge: challenge,
      );

      if (_successfulAgentType == null || _successfulAgentType!.isEmpty) {
        _successfulAgentType = normalizedAlgo;
      }
      if (_serialNumber != null && _serialNumber!.isNotEmpty) {
        _rememberCachedHandshake(_serialNumber!, normalizedAlgo);
      }

      write("BD:12,$response;");
    } catch (_) {}
  }

  String? _extractValue(String message, String key) {
    try {
      final idx = message.indexOf(key);
      if (idx == -1) return null;
      final start = idx + key.length;
      final end = message.indexOf(";", start);
      final raw =
          (end == -1 ? message.substring(start) : message.substring(start, end))
              .trim();
      return raw.isEmpty ? null : raw;
    } catch (_) {
      return null;
    }
  }

  // Kept for compatibility with older UI calls
  Future<void> turnOnBluetooth() async {
    // No-op for serial connection
  }

  // Compatibility helpers used by the newer UI flow.
  Future<String> getTypeMachineNameForItems() async {
    final resolved = _resolveTypeMachineName(
      serial: _serialNumber,
      agentType: _successfulAgentType,
    );
    if (resolved.isNotEmpty) {
      _emitTypeMachineName(resolved);
      await _persistTypeMachineName(resolved);
      return resolved;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_lastTypeMachineNameKey) ?? 'DQ';
      _emitTypeMachineName(stored);
      return stored;
    } catch (_) {
      _emitTypeMachineName('DQ');
      return 'DQ';
    }
  }

  void setBypassMode(
    bool enabled, {
    String? simulateType,
    String? agentType,
    String? simulatedSerial,
  }) {
    _isBypassMode = enabled;
    final selected = (agentType ?? simulateType ?? '').trim();
    if (selected.isNotEmpty) {
      _cachedAgentType = selected;
      _persistTypeMachineName(
        _resolveTypeMachineName(serial: simulatedSerial, agentType: selected),
      );
    }
    if (simulatedSerial != null && simulatedSerial.trim().isNotEmpty) {
      setSerialNumber(simulatedSerial.trim());
    }
  }
}
