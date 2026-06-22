import 'package:flutter_project/services/api_service.dart';

import 'package:flutter_project/services/api_service.dart';
import 'package:flutter_project/core/handshake_response_resolver.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_project/core/serial/machine_protocol.dart';

class MachineSystemInfo {
  final String? serialNumber;
  final String? pid;
  final String? model;
  final String? softwareVersion;
  final String? hardwareVersion;
  final String? pgHead;
  final String? faultCode;
  final int? maxWidth;
  final DateTime? lastUpdated;

  const MachineSystemInfo({
    this.serialNumber,
    this.pid,
    this.model,
    this.softwareVersion,
    this.hardwareVersion,
    this.pgHead,
    this.faultCode,
    this.maxWidth,
    this.lastUpdated,
  });
}

class CutterSerialService {
  static const String _lastTypeMachineNameKey = 'last_type_machine_name';
  static const String _legacyMaxWidthKey = 'MaxWidth';
  static const String _maxWidthCachePrefix = 'max_width_';
  static final CutterSerialService _instance =
      CutterSerialService._internal();

  factory CutterSerialService() {
    return _instance;
  }

  CutterSerialService._internal() {
    _ensureEventStream();
  }

  final MethodChannel _channel = const MethodChannel('serial_port');
  final EventChannel _eventChannel = const EventChannel('serial_port/events');

  StreamSubscription? _eventSubscription;
  final _receivedDataController = StreamController<String>();
  final _parsedMessageController = StreamController<String>.broadcast();
  final _serialUpdateController = StreamController<String?>();
  final _typeMachineNameController = StreamController<String>();
  final _systemInfoController = StreamController<MachineSystemInfo>.broadcast();
  late final Stream<String> _receivedDataBroadcast = _receivedDataController
      .stream
      .asBroadcastStream();
  late final Stream<String?> _serialUpdateBroadcast = _serialUpdateController
      .stream
      .asBroadcastStream();
  late final Stream<String> _typeMachineNameBroadcast =
      _typeMachineNameController.stream.asBroadcastStream();
  late final Stream<MachineSystemInfo> _systemInfoBroadcast =
      _systemInfoController.stream.asBroadcastStream();

  String _autoHandshakeBuffer = "";
  bool _suppressAutoHandshake = false;
  MachineSystemInfo _systemInfo = const MachineSystemInfo();
  Future<void> _writeQueue = Future<void>.value();
  int _writeSessionVersion = 0;

  bool _isConnected = false;
  Object? _connectedDevice;

  Stream<String> get receivedDataStream => _receivedDataBroadcast;
  Stream<String> get parsedMessageStream => _parsedMessageController.stream;
  Stream<String?> get serialStream => _serialUpdateBroadcast;
  Stream<String> get typeMachineNameStream => _typeMachineNameBroadcast;
  Stream<MachineSystemInfo> get systemInfoStream => _systemInfoBroadcast;

  Object? get connectedDevice => _connectedDevice;
  String? _serialNumber;
  String? get serialNumber => _serialNumber;
  bool _serialFromPidFallback = false;
  bool get isUsingPidFallback => _serialFromPidFallback;
  MachineSystemInfo get systemInfo => _systemInfo;
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
  bool _sessionHandshakeVerified = false;
  String? _cachedAgentType;
  int _handshakeAttemptIndex = 0;
  int? _lastHandshakeChallenge;
  String? _lastAttemptedAlgo;
  String? _successfulAgentType;

  String _serialCacheKey(String serial) => serial.trim().toUpperCase();

  String? _getCachedHandshakeFromMemory(String? serial) {
    final value = (serial ?? '').trim();
    if (value.isEmpty) return null;
    return _cachedHandshakeBySerial[_serialCacheKey(value)];
  }

  void _rememberCachedHandshake(String serial, String algorithm) {
    final value = serial.trim();
    if (value.isEmpty) return;
    _cachedHandshakeBySerial[_serialCacheKey(value)] = _canonicalizeAgentType(
      algorithm,
    );
  }

  void _emitTypeMachineName(String? value) {
    final normalized = (value ?? '').trim();
    if (normalized.isEmpty) return;
    if (_currentTypeMachineName == normalized) return;
    _currentTypeMachineName = normalized;
    _typeMachineNameController.add(normalized);
  }

  String? _normalizeIdentifier(String? value, {bool allowHyphen = false}) {
    if (value == null) return null;
    final trimmed = value.trim().replaceAll(";", "");
    if (trimmed.isEmpty) return null;
    if (trimmed.toUpperCase() == "UNKNOWN SN") return null;
    if (trimmed.contains("=")) return null;
    if (trimmed.contains(":")) return null;
    if (!allowHyphen && trimmed.contains("-")) return null;
    if (trimmed.toLowerCase() == "null" || trimmed.toUpperCase() == "N/A") {
      return null;
    }
    return trimmed;
  }

  String? _extractEmbeddedMachineSerial(String? raw) {
    if (raw == null) return null;
    final clean = raw
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '')
        .replaceAll(';', '')
        .trim()
        .toUpperCase();
    if (clean.isEmpty) return null;

    final matches = RegExp(
      r'(SS[A-Z0-9]{8,}|DQ[A-Z0-9]{6,}|DX[A-Z0-9]{6,}|LH[A-Z0-9]{6,}|DH[A-Z0-9]{6,}|CUTTER[A-Z0-9]{4,}|SUNSHINE[A-Z0-9]{4,})',
    ).allMatches(clean).toList(growable: false);

    if (matches.isEmpty) return null;
    return matches.last.group(0);
  }

  String? _normalizeSerial(String? serial) {
    final extracted = _extractEmbeddedMachineSerial(serial);
    if (extracted != null) {
      return _normalizeIdentifier(extracted, allowHyphen: false);
    }
    return _normalizeIdentifier(serial, allowHyphen: false);
  }

  String? _normalizePidAsSerial(String? pid) =>
      _normalizeIdentifier(pid, allowHyphen: true);

  String? _normalizeHandshakeIdentifier(String? identifier) {
    final extractedSerial = _extractEmbeddedMachineSerial(identifier);
    if (extractedSerial != null) {
      return _normalizeIdentifier(extractedSerial, allowHyphen: false);
    }
    return _normalizeIdentifier(identifier, allowHyphen: true);
  }

  String _canonicalizeAgentType(String? agentType) {
    final compact = (agentType ?? '')
        .trim()
        .toUpperCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');

    switch (compact) {
      case 'HANDSHAKENEW':
        return 'HANDSHAKE_NEW';
      case 'HANDSHAKE_NEW':
        return 'HANDSHAKE_NEW';
      case 'STANDARD':
        return 'STANDARD';
      case 'GENERICNEW':
      case 'GENERIC_NEW':
        return 'GENERIC_NEW';
      case 'DQ':
        return 'DQ';
      case 'DX':
        return 'DX';
      case 'LH':
        return 'LH';
      case 'SUNSHINE':
        return 'SUNSHINE';
      case 'DEVIA':
        return 'DEVIA';
      case 'SY':
        return 'SY';
      case 'CUTTER':
        return 'CUTTER';
      case 'OLDV1':
      case 'OLD_V1':
        return 'OLD_V1';
      case 'OLDV3':
      case 'OLD_V3':
        return 'OLD_V3';
      case 'ROCKSPACEBLUE':
      case 'ROCKSPACE_BLUE':
        return 'ROCKSPACE_BLUE';
      case 'DQHANDSHAKE':
      case 'DQ_HANDSHAKE':
        return 'DQ_HANDSHAKE';
      case 'MECHANICUART':
      case 'MECHANIC_UART':
        return 'MECHANIC_UART';
      default:
        return compact;
    }
  }

  bool _isDqFamilyAgent(String? agentType) {
    final agent = _canonicalizeAgentType(agentType);
    return agent == 'DQ' ||
        agent == 'DX' ||
        agent == 'LH' ||
        agent == 'DQ_HANDSHAKE' ||
        agent == 'MECHANIC_UART' ||
        agent == 'MECHANIC' ||
        agent == 'PASS_U32' ||
        agent == 'DEPASS_U32';
  }

  bool _isSunshineFamilyAgent(String? agentType) {
    final agent = _canonicalizeAgentType(agentType);
    return agent == 'HANDSHAKE_NEW' ||
        agent == 'STANDARD' ||
        agent == 'GENERIC_NEW' ||
        agent == 'OLD_V1' ||
        agent == 'OLD_V3' ||
        agent == 'SUNSHINE' ||
        agent == 'CUTTER' ||
        agent == 'SY' ||
        agent == 'DEVIA';
  }

  bool _isReusableHandshakeMode(String? mode) {
    final normalized = (mode ?? '').trim().toLowerCase();
    return normalized == 'auto' ||
        normalized == 'manual' ||
        normalized == 'cached' ||
        normalized == 'api';
  }

  String _normalizeHandshakeAlgorithm(String? raw) {
    return _canonicalizeAgentType(raw);
  }

  String _resolveTypeMachineName({String? serial, String? agentType}) {
    final upperSerial = serial?.toUpperCase() ?? '';
    final upperAgent = _canonicalizeAgentType(agentType);

    if (upperAgent == 'ROCKSPACE_BLUE' ||
        upperSerial.startsWith('C180B') ||
        upperSerial.startsWith('ZC2') ||
        upperSerial.startsWith('ZC3')) {
      return 'rock_space';
    }

    if (_isDqFamilyAgent(upperAgent) ||
        upperSerial.startsWith('DQ') ||
        upperSerial.startsWith('DX') ||
        upperSerial.startsWith('LH') ||
        upperSerial.startsWith('DH') ||
        upperSerial.startsWith('MT')) {
      return 'DQ';
    }

    if (_isSunshineFamilyAgent(upperAgent) ||
        upperSerial.startsWith('SUNSHINE') ||
        upperSerial.startsWith('CUTTER') ||
        upperSerial.startsWith('SS')) {
      return 'Sunshine';
    }

    if (_serialFromPidFallback && upperSerial.isNotEmpty) {
      return 'Sunshine';
    }

    return 'DQ';
  }

  bool _hasStrongTypeMachineSignal({String? serial, String? agentType}) {
    final upperSerial = serial?.toUpperCase() ?? '';
    final upperAgent = _canonicalizeAgentType(agentType);

    if (upperAgent.isNotEmpty) return true;
    if (_serialFromPidFallback && upperSerial.isNotEmpty) return true;

    return upperSerial.startsWith('DQ') ||
        upperSerial.startsWith('DX') ||
        upperSerial.startsWith('LH') ||
        upperSerial.startsWith('DH') ||
        upperSerial.startsWith('MT') ||
        upperSerial.startsWith('SUNSHINE') ||
        upperSerial.startsWith('CUTTER') ||
        upperSerial.startsWith('SS') ||
        upperSerial.startsWith('C180B') ||
        upperSerial.startsWith('ZC2') ||
        upperSerial.startsWith('ZC3');
  }

  void setSerialNumber(String? serial, {bool fromPidFallback = false}) {
    final normalized = fromPidFallback
        ? _normalizePidAsSerial(serial)
        : _normalizeSerial(serial);
    if (normalized == null || normalized.isEmpty) return;

    final current = (_serialNumber ?? '').trim();
    if (current == normalized) {
      if (_serialFromPidFallback != fromPidFallback) {
        _serialFromPidFallback = fromPidFallback;
      }
      return;
    }

    if (current.isNotEmpty &&
        normalized.length < current.length &&
        current.startsWith(normalized)) {
      return;
    }

    _serialNumber = normalized;
    _serialFromPidFallback = fromPidFallback;
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

  Future<void> _persistLastConnectedSerial(String serial) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_connected_serial', serial);
    } catch (_) {}
  }

  Future<void> _syncDeviceHandshake(String serial) async {
    final localCached = await getCachedHandshake(serial);
    if (localCached != null && localCached.isNotEmpty) {
      _successfulAgentType = _canonicalizeAgentType(localCached);
      _lastHandshakeMode = 'cached_local';
      return;
    }

    final backendHandshake = await ApiService().getDeviceBySerialNumber(serial);
    if (backendHandshake != null && backendHandshake.isNotEmpty) {
      await cacheSuccessfulHandshake(
        _canonicalizeAgentType(backendHandshake),
        false,
        mode: 'api',
        persist: false,
      );
      return;
    }

    final upper = serial.toUpperCase();
    if (upper.startsWith('DQ') ||
        upper.startsWith('DX') ||
        upper.startsWith('LH') ||
        upper.startsWith('MT')) {
      await cacheSuccessfulHandshake(
        'DQ_HANDSHAKE',
        false,
        mode: 'heuristic',
        persist: false,
      );
    }
  }

  Future<void> _persistLastMachineType(String serial) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final upper = serial.toUpperCase();
      final isPlt =
          upper.startsWith("DQ") ||
          upper.startsWith("DX") ||
          upper.startsWith("LH") ||
          upper.startsWith("MT");
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

  Future<String> getTypeMachineNameForItems() async {
    final hasResolvedMachineContext =
        (_serialNumber?.trim().isNotEmpty ?? false) ||
        (_successfulAgentType?.trim().isNotEmpty ?? false) ||
        _serialFromPidFallback;

    if (!hasResolvedMachineContext) {
      try {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getString(_lastTypeMachineNameKey) ?? 'DQ';
      } catch (_) {
        return 'DQ';
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final persisted = prefs.getString(_lastTypeMachineNameKey);
      if (!_hasStrongTypeMachineSignal(
        serial: _serialNumber,
        agentType: _successfulAgentType,
      )) {
        return persisted ?? 'DQ';
      }

      final resolved = _resolveTypeMachineName(
        serial: _serialNumber,
        agentType: _successfulAgentType,
      );
      if (resolved.isNotEmpty) {
        await _persistTypeMachineName(resolved);
        return resolved;
      }
      return persisted ?? 'DQ';
    } catch (_) {
      return 'DQ';
    }
  }

  void setBypassMode(bool value, {String? agentType, String? simulatedSerial}) {
    _isBypassMode = value;
    _sessionHandshakeVerified = value;
    final canonicalAgent = value ? _canonicalizeAgentType(agentType) : null;
    if (value) {
      _successfulAgentType = canonicalAgent;
      _serialNumber = simulatedSerial;
      _serialFromPidFallback = false;
      ApiService().setRockspaceMode(canonicalAgent == "ROCKSPACE_BLUE");
    } else {
      _successfulAgentType = null;
      _serialNumber = null;
      _serialFromPidFallback = false;
      ApiService().setRockspaceMode(false);
    }
    _serialUpdateController.add(
      value ? (simulatedSerial ?? "BYPASS_MODE") : null,
    );
    if (value) {
      _persistTypeMachineName(
        _resolveTypeMachineName(
          serial: simulatedSerial,
          agentType: canonicalAgent,
        ),
      );
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
  bool get hasVerifiedHandshakeSession =>
      _isBypassMode || (_sessionHandshakeVerified && isConnected);
  String? get cachedAgentType => _cachedAgentType ?? _successfulAgentType;
  String? get successfulHandshakeType => _successfulAgentType;

  Future<void> _persistTypeMachineName(String typeMachineName) async {
    _emitTypeMachineName(typeMachineName);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastTypeMachineNameKey, typeMachineName);
    } catch (_) {}
  }

  String? _resolveBackendMachineType(SharedPreferences prefs, String serial) {
    final upper = serial.trim().toUpperCase();
    if (upper.isEmpty) return null;

    if (upper.startsWith('DQ') || upper.startsWith('MT')) return 'crust';
    if (upper.startsWith('LH')) return 'hebeshi';
    if (upper.startsWith('DX') || upper.startsWith('DH')) return 'AtB';
    if (upper.startsWith('SS') ||
        upper.startsWith('CUTTER') ||
        upper.startsWith('SUNSHINE')) {
      return 'Sunshine';
    }

    final stored = (prefs.getString('machine_type_$upper') ?? '').trim();
    if (stored.isEmpty || stored == 'unknown') return null;
    if (stored == 'ss_like') return 'Sunshine';
    return stored;
  }

  String? _resolveBackendMachineDisplayName(
    SharedPreferences prefs,
    String serial,
    String? handshakeAlgorithm,
  ) {
    final normalizedAlgorithm = _normalizeHandshakeAlgorithm(
      handshakeAlgorithm,
    );
    if (normalizedAlgorithm == HandshakeResponseResolver.algoMechanicUart) {
      return 'Mechanic UART';
    }

    final upper = serial.trim().toUpperCase();
    if (upper.isEmpty) return null;

    if (upper.startsWith('MT')) return 'mietubl uart mini';

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
    if (stored == 'ss_like' || stored.toLowerCase() == 'Sunshine') {
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

  void clearPendingRxBuffer() {
    _autoHandshakeBuffer = "";
  }

  void _invalidateWriteQueue() {
    _writeSessionVersion++;
    _writeQueue = Future<void>.value();
  }

  Future<void> cacheSuccessfulHandshake(
    String agentType,
    bool isNewVersion, {
    String mode = "auto",
    bool persist = true,
    bool markSessionAuthenticated = false,
  }) async {
    final normalizedAgentType = _canonicalizeAgentType(agentType);
    final shouldPreserveVerifiedSession =
        _sessionHandshakeVerified && !markSessionAuthenticated;
    if (!shouldPreserveVerifiedSession) {
      _successfulAgentType = normalizedAgentType;
      _lastHandshakeMode = mode;
    }
    if (markSessionAuthenticated) {
      _sessionHandshakeVerified = true;
    }
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

        for (final identifier in _handshakeCacheIdentifiers(_serialNumber)) {
          final existingMode = prefs.getString('handshake_mode_$identifier');
          final shouldKeepExistingReusableCache =
              !markSessionAuthenticated &&
              _isReusableHandshakeMode(existingMode) &&
              !_isReusableHandshakeMode(mode);
          if (shouldKeepExistingReusableCache) {
            continue;
          }
          await prefs.setString(
            'handshake_algo_$identifier',
            normalizedAgentType,
          );
          await prefs.setString('handshake_mode_$identifier', mode);
        }

        await prefs.setString('last_connected_serial', _serialNumber!);
        if (_lastOpenPortPath != null && _lastOpenPortPath!.isNotEmpty) {
          await prefs.setString(
            'serial_port_$_serialNumber',
            _lastOpenPortPath!,
          );
        }

        unawaited(
          ApiService().addDevice(
            _serialNumber!,
            normalizedAgentType,
            machineType: machineType,
            machineName: machineName,
          ),
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
      for (final identifier in _handshakeCacheIdentifiers(serial)) {
        final value = prefs.getString('handshake_algo_$identifier');
        if (value == null || value.trim().isEmpty) continue;
        final normalized = _canonicalizeAgentType(value);
        _rememberCachedHandshake(identifier, normalized);
        return normalized;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> getCachedHandshakeMode(String serial) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final identifier in _handshakeCacheIdentifiers(serial)) {
        final value = prefs.getString('handshake_mode_$identifier');
        if (value != null && value.trim().isNotEmpty) {
          return value;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> getReusableHandshakeAlgorithm([String? identifier]) async {
    final memoryAgent = _successfulAgentType;
    if (memoryAgent != null &&
        memoryAgent.isNotEmpty &&
        (_sessionHandshakeVerified ||
            _isReusableHandshakeMode(_lastHandshakeMode))) {
      return memoryAgent;
    }

    final preferredIdentifier =
        identifier ??
        _serialNumber ??
        _systemInfo.serialNumber ??
        _systemInfo.pid;
    if (preferredIdentifier == null || preferredIdentifier.isEmpty) {
      return null;
    }

    final cachedMode = await getCachedHandshakeMode(preferredIdentifier);
    if (!_isReusableHandshakeMode(cachedMode)) {
      return null;
    }

    return getCachedHandshake(preferredIdentifier);
  }

  bool get isConnected => _isConnected;

  Future<void> connect({String? portPath, int baud = 115200}) async {
    _ensureEventStream();

    if (_isConnected) {
      await disconnect();
      await Future.delayed(const Duration(milliseconds: 300));
    }

    final candidates = <String>[];
    String? savedPort;
    String? serialPinnedPort;

    if (portPath != null && portPath.isNotEmpty) {
      candidates.add(portPath);
    } else {
      try {
        final prefs = await SharedPreferences.getInstance();
        savedPort = (prefs.getString('last_serial_port_path') ?? '').trim();
        final lastSerial = (prefs.getString('last_connected_serial') ?? '')
            .trim();
        if (lastSerial.isNotEmpty) {
          serialPinnedPort = (prefs.getString('serial_port_$lastSerial') ?? '')
              .trim();
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

      candidates.addAll(['/dev/ttyS0', '/dev/ttyS1']);

      final preferExtended =
          savedPort == '/dev/ttyS2' ||
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
    _invalidateWriteQueue();
    clearPendingRxBuffer();
    _sessionHandshakeVerified = false;
    _systemInfo = const MachineSystemInfo();
    _systemInfoController.add(_systemInfo);
    _serialFromPidFallback = false;
    _serialNumber = null;

    for (final path in candidates) {
      try {
        final ok = await _channel.invokeMethod<bool>('open', {
          'path': path,
          'baud': baud,
        });
        if (ok == true) {
          _lastOpenPortPath = path;
          _isConnected = true;
          _connectedDevice = Object();
          return;
        }
      } catch (e) {
        lastError = e;
      }
    }

    throw Exception(
      'Failed to open serial port${lastError != null ? ': $lastError' : ''}',
    );
  }

  Future<void> disconnect() async {
    _eventSubscription?.cancel();
    _eventSubscription = null;
    try {
      await _channel.invokeMethod('close');
    } catch (_) {}
    _invalidateWriteQueue();
    _isConnected = false;
    _connectedDevice = null;
    _serialNumber = null;
    _serialFromPidFallback = false;
    _successfulAgentType = null;
    _lastHandshakeMode = null;
    _sessionHandshakeVerified = false;
    _systemInfo = const MachineSystemInfo();
    _systemInfoController.add(_systemInfo);
    _autoHandshakeBuffer = "";
    _serialUpdateController.add(null);
  }

  Future<void> write(
    String data, {
    bool forceWithResponse = false,
    int packetDelayMs = 20,
  }) async {
    if (!_isConnected) throw Exception("Not connected");
    await _enqueueWriteOperation((sessionVersion) async {
      _assertWriteSession(expectedSessionVersion: sessionVersion);
      print('UART_TX: $data');
      await _channel.invokeMethod('write', {'data': data});
      if (packetDelayMs > 0) {
        await Future.delayed(Duration(milliseconds: packetDelayMs));
      }
    });
  }

  Future<void> writeBytes(
    List<int> bytes, {
    bool forceWithResponse = false,
    int chunkSize = 2048,
    int packetDelayMs = 10,
  }) async {
    if (!_isConnected) throw Exception("Not connected");
    await _enqueueWriteOperation((sessionVersion) async {
      print('UART_TX_BYTES: ${bytes.length} bytes (first 100: ${String.fromCharCodes(bytes.take(100))})');
      for (int i = 0; i < bytes.length; i += chunkSize) {
        _assertWriteSession(expectedSessionVersion: sessionVersion);
        final end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
        final chunk = bytes.sublist(i, end);
        await _channel.invokeMethod('writeBytes', {
          'bytes': Uint8List.fromList(chunk),
        });
        if (packetDelayMs > 0) {
          await Future.delayed(Duration(milliseconds: packetDelayMs));
        }
      }
    });
  }

  Future<void> _enqueueWriteOperation(
    Future<void> Function(int scheduledSession) operation,
  ) {
    final completer = Completer<void>();
    final scheduledSession = _writeSessionVersion;

    _writeQueue = _writeQueue.catchError((_) {}).then((_) async {
      if (!_isConnected) throw Exception("Not connected");
      if (scheduledSession != _writeSessionVersion) {
        throw StateError("UART write session changed before send");
      }
      await operation(scheduledSession);
    }).then((_) {
      if (!completer.isCompleted) completer.complete();
    }, onError: (Object error, StackTrace stackTrace) {
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    });

    return completer.future;
  }

  void _assertWriteSession({required int expectedSessionVersion}) {
    if (expectedSessionVersion != _writeSessionVersion || !_isConnected) {
      throw StateError("UART write session changed during send");
    }
  }

  List<String> _maxWidthCacheIdentifiers([String? preferred]) {
    final identifiers = <String>{};
    void addIdentifier(String? candidate) {
      final normalized = _normalizeHandshakeIdentifier(candidate);
      if (normalized == null || normalized.isEmpty) return;
      identifiers.add(normalized);
    }
    addIdentifier(preferred);
    addIdentifier(_serialNumber);
    addIdentifier(_systemInfo.serialNumber);
    addIdentifier(_systemInfo.pid);
    return identifiers.toList(growable: false);
  }

  List<String> _handshakeCacheIdentifiers([String? preferred]) {
    return _maxWidthCacheIdentifiers(preferred);
  }

  Future<void> _persistMaxWidth(int width) async {
    if (width <= 0) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_legacyMaxWidthKey, width);
      for (final identifier in _maxWidthCacheIdentifiers()) {
        await prefs.setInt('$_maxWidthCachePrefix$identifier', width);
      }
    } catch (_) {}
  }

  Future<int?> getCachedMaxWidth([String? preferred]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final identifier in _maxWidthCacheIdentifiers(preferred)) {
        final cached = prefs.getInt('$_maxWidthCachePrefix$identifier');
        if (cached != null && cached > 0) return cached;
      }
      final fallback = prefs.getInt(_legacyMaxWidthKey);
      if (fallback != null && fallback > 0) return fallback;
      return null;
    } catch (_) {
      return null;
    }
  }

  int? _extractMaxWidth(String message) {
    final match = RegExp(r'RCMD=100,20,?(\d+)').firstMatch(message);
    if (match == null) return null;
    var width = int.tryParse(match.group(1) ?? "");
    if (width == null) return null;
    if (width > 500) width = width ~/ 40;
    return width;
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
    try {
      _autoHandshakeBuffer += data;
      while (_autoHandshakeBuffer.contains(";")) {
        final endIndex = _autoHandshakeBuffer.indexOf(";");
        String message = _autoHandshakeBuffer.substring(0, endIndex + 1);
        _autoHandshakeBuffer = _autoHandshakeBuffer.substring(endIndex + 1);

        message = message.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
        if (message.isEmpty) continue;

        _captureSystemInfo(message);
        _parsedMessageController.add(message);

        if (message.contains("RCMD=11,")) {
          if (!_suppressAutoHandshake) {
            unawaited(_handleAutoHandshake(message));
          }
        } else if (message.contains("RCMD=12,0")) {
          final winner = _lastAttemptedAlgo;
          _lastAttemptedAlgo = null;
          _handshakeAttemptIndex = 0;
          if (winner != null && winner.isNotEmpty) {
            unawaited(cacheSuccessfulHandshake(winner, false, mode: 'auto', persist: true, markSessionAuthenticated: true));
          }
        } else if (message.contains("RCMD=12,1")) {
          _lastAttemptedAlgo = null;
        }
      }
      final clean = data.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');
      _receivedDataController.add(clean);
    } catch (_) {}
  }

  void _captureSystemInfo(String message) {
    final serial = _extractSerialValue(message);
    final pid = _extractTokenValue(message, const ["PID=", "RPID="]);

    if (serial != null && serial.isNotEmpty && serial != _serialNumber) {
      setSerialNumber(serial);
    } else if ((serial == null || serial.isEmpty) && pid != null && pid.isNotEmpty && _serialNumber == null) {
      setSerialNumber(pid, fromPidFallback: true);
    }

    _mergeSystemInfo(
      serialNumber: serial,
      pid: pid,
      model: _extractTokenValue(message, const ["MODE="]),
      softwareVersion: _extractTokenValue(message, const ["SVER="]),
      hardwareVersion: _extractTokenValue(message, const ["HVER="]),
      pgHead: _extractTokenValue(message, const ["PGHEAD="]),
      faultCode: _extractTokenValue(message, const ["ERR="]),
      maxWidth: _extractMaxWidth(message),
    );
  }

  void _mergeSystemInfo({
    String? serialNumber,
    String? pid,
    String? model,
    String? softwareVersion,
    String? hardwareVersion,
    String? pgHead,
    String? faultCode,
    int? maxWidth,
  }) {
    final nextSerial = _keepOld(_systemInfo.serialNumber, serialNumber);
    final nextPid = _keepOld(_systemInfo.pid, pid);
    final nextModel = _keepOld(_systemInfo.model, model);
    final nextSoftware = _keepOld(_systemInfo.softwareVersion, softwareVersion);
    final nextHardware = _keepOld(_systemInfo.hardwareVersion, hardwareVersion);
    final nextPgHead = _keepOld(_systemInfo.pgHead, pgHead);
    final nextFault = _keepOld(_systemInfo.faultCode, faultCode);
    final nextMaxWidth = maxWidth ?? _systemInfo.maxWidth;

    final hasChanged = nextSerial != _systemInfo.serialNumber ||
        nextPid != _systemInfo.pid ||
        nextModel != _systemInfo.model ||
        nextSoftware != _systemInfo.softwareVersion ||
        nextHardware != _systemInfo.hardwareVersion ||
        nextPgHead != _systemInfo.pgHead ||
        nextFault != _systemInfo.faultCode ||
        nextMaxWidth != _systemInfo.maxWidth;

    if (!hasChanged) return;

    _systemInfo = MachineSystemInfo(
      serialNumber: nextSerial,
      pid: nextPid,
      model: nextModel,
      softwareVersion: nextSoftware,
      hardwareVersion: nextHardware,
      pgHead: nextPgHead,
      faultCode: nextFault,
      maxWidth: nextMaxWidth,
      lastUpdated: DateTime.now(),
    );
    _systemInfoController.add(_systemInfo);
    if (nextMaxWidth != null && nextMaxWidth > 0) unawaited(_persistMaxWidth(nextMaxWidth));
  }

  String? _keepOld(String? oldValue, String? newValue) {
    if (newValue == null || newValue.isEmpty) return oldValue;
    return newValue;
  }

  String? _extractSerialValue(String message) {
    final fromToken = _extractTokenValue(message, const ["RCBM=", "CBM="]);
    if (fromToken != null && fromToken.isNotEmpty) return _normalizeSerial(fromToken);
    final embedded = _extractEmbeddedMachineSerial(message);
    if (embedded == null || embedded.isEmpty) return null;
    return _normalizeSerial(embedded);
  }

  String? _extractTokenValue(String message, List<String> keys) {
    final clean = message.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
    if (clean.isEmpty) return null;
    final upper = clean.toUpperCase();
    for (final key in keys) {
      final idx = upper.lastIndexOf(key.toUpperCase());
      if (idx == -1) continue;
      var value = clean.substring(idx + key.length);
      final end = value.indexOf(";");
      if (end != -1) value = value.substring(0, end);
      value = value.trim();
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  Future<void> _handleAutoHandshake(String data) async {
    try {
      final challenge = _extractChallengeFromMessage(data);
      if (challenge == null) return;
      if (_lastHandshakeChallenge != null && _lastHandshakeChallenge != challenge) _handshakeAttemptIndex++;
      _lastHandshakeChallenge = challenge;

      final cachedAlgo = await getReusableHandshakeAlgorithm();
      String algoToTry;
      if (cachedAlgo != null && cachedAlgo.isNotEmpty) {
        algoToTry = cachedAlgo;
      } else if (_successfulAgentType != null && _successfulAgentType!.isNotEmpty) {
        algoToTry = _successfulAgentType!;
      } else {
        final sequence = HandshakeResponseResolver.supportedAlgorithms;
        algoToTry = sequence[_handshakeAttemptIndex % sequence.length];
      }

      final response = HandshakeResponseResolver.resolveChallengeResponse(algorithm: algoToTry, challenge: challenge);
      _lastAttemptedAlgo = algoToTry;
      await write("BD:12,$response;");
    } catch (_) {}
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


  // ===========================================================================
  // Machine Settings Commands
  // ===========================================================================

  MachineProtocol? _activeMachineProtocol(String operationName) {
    if (_successfulAgentType == null) return null;
    return MachineProtocolResolver.resolve(
      _successfulAgentType!,
      isSunshineFamily: _activeTypeMachineName() == 'Sunshine',
      isLegacySunshine: _isLegacySunshineMachine(),
    );
  }

  String _activeTypeMachineName() {
    return _resolveTypeMachineName(serial: _serialNumber, agentType: _successfulAgentType);
  }

  double? _parseMachineVersion(String? rawVersion) {
    if (rawVersion == null) return null;
    final compact = rawVersion.trim().toUpperCase().replaceAll('V', '').replaceAll('F', '');
    if (compact.isEmpty) return null;
    return double.tryParse(compact);
  }

  bool _isLegacySunshineMachine() {
    if (_activeTypeMachineName() != 'Sunshine') return false;
    final version = _parseMachineVersion(_systemInfo.hardwareVersion) ?? _parseMachineVersion(_systemInfo.softwareVersion);
    return (version != null && version < 9.0);
  }

  Future<void> _sendProtocolCommands(List<String> commands) async {
    for (final command in commands) {
      if (command.trim().isNotEmpty) await write(command.trim());
    }
  }

  Future<void> sendMachineSpeed(int speedLevel) async {
    final protocol = _activeMachineProtocol('set speed');
    if (protocol != null) await _sendProtocolCommands(protocol.speedCommands(speedLevel));
  }

  void setMachineSpeed(int speedLevel) => unawaited(sendMachineSpeed(speedLevel));

  Future<void> sendMachinePressure(int pressureForce) async {
    final protocol = _activeMachineProtocol('set pressure');
    if (protocol != null) await _sendProtocolCommands(protocol.pressureCommands(pressureForce));
  }

  void setMachinePressure(int pressureForce) => unawaited(sendMachinePressure(pressureForce));

  void toggleInduction(bool isOn) {
    final protocol = _activeMachineProtocol('toggle induction');
    if (protocol != null) unawaited(_sendProtocolCommands(protocol.inductionCommands(isOn)));
  }

  void setMachineLEDBrightness(int level) {
    final protocol = _activeMachineProtocol('set LED');
    if (protocol != null) unawaited(_sendProtocolCommands(protocol.ledCommands(level)));
  }

  void sendTestCut() {
    final protocol = _activeMachineProtocol('execute test cut');
    if (protocol != null) unawaited(_sendProtocolCommands(protocol.testCutCommands()));
  }

  void requestMachineInfo() { if (isConnected) write(";RINFO;"); }

  Future<void> requestMaxWidth() async { if (isConnected) await write("BD:100,20,0;"); }
}
