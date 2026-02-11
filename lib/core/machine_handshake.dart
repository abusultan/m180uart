import 'dart:async';
import 'dart:math';
import '../services/bluetooth_service.dart';
import '../utils/encryption_util.dart';

/// Handles the machine handshake protocol by trying all available algorithms in a loop.
class MachineHandshake {
  final CutterBluetoothService _bluetooth;
  final Function(bool) onHandshakeComplete;
  final Function(String) onStatusUpdate;
  final String _handshakeMode;

  // State variables
  bool _isAuthenticated = false;
  int _retryCount = 0;
  int _currentAlgoIndex = 0;
  String _messageBuffer = "";
  bool _bd9Sent = false;
  bool _bd10Sent = false;
  bool _dqProtocolTriggered = false;
  String? _detectedSerial;
  bool _manualLockApplied = false;
  bool _awaitingPassU32 = false;
  int? _passU32Seed;
  bool _stateHandshakeAttempted = false;
  bool _usedStateHandshake = false;

  // Systematic Algorithm List
  List<String> _algorithms = [];

  StreamSubscription? _dataSubscription;
  Timer? _watchdogTimer;

  MachineHandshake(
    this._bluetooth, {
    required this.onHandshakeComplete,
    required this.onStatusUpdate,
    String? forcedAlgorithm,
    String handshakeMode = "auto",
  }) : _handshakeMode = handshakeMode {
    _algorithms =
        forcedAlgorithm != null
            ? [forcedAlgorithm]
            : [
              "HANDSHAKE_NEW",
              "PASS_U32",
              "GENERIC_NEW",
              "DQ",
              "SY",
              "STANDARD",
              "SUNSHINE",
              "CUTTER",
              "OLD_V1",
              "OLD_V3",
              "DEVIA",
            ];
    if (forcedAlgorithm != null) _manualLockApplied = true;
  }

  bool _isPltSerial(String? serial) {
    final s = serial?.toUpperCase();
    if (s == null) return false;
    return s.startsWith("DQ") || s.startsWith("DX") || s.startsWith("LH");
  }

  bool _isPrioritySerial(String? serial) {
    final s = serial?.toUpperCase();
    if (s == null) return false;
    return s.startsWith("SS") || _isPltSerial(s);
  }

  bool _isPhonefilmAlgo(String algo) {
    return algo == "HANDSHAKE_NEW" || algo == "OLD_V1" || algo == "OLD_V3";
  }

  bool _shouldAutoTriggerDQ() {
    if (_manualLockApplied) {
      return _algorithms.isNotEmpty && _algorithms.first == "DQ";
    }
    if (_awaitingPassU32) return false;
    if (_algorithms.isNotEmpty && _algorithms[_currentAlgoIndex] == "PASS_U32") {
      return false;
    }
    return true;
  }

  bool get isAuthenticated => _isAuthenticated;

  void startHandshake() {
    print("🚀 Starting MachineHandshake Loop...");
    _dataSubscription?.cancel();

    _isAuthenticated = false;
    _retryCount = 0;
    _currentAlgoIndex = 0;
    _messageBuffer = "";
    _bd9Sent = false;
    _bd10Sent = false;
    _dqProtocolTriggered = false;
    _awaitingPassU32 = false;
    _passU32Seed = null;
    _detectedSerial = null;
    _stateHandshakeAttempted = false;
    _usedStateHandshake = false;
    _manualLockApplied = _algorithms.length == 1;

    _bluetooth.setSuppressAutoHandshake(true);
    _dataSubscription = _bluetooth.receivedDataStream.listen(_handleData);

    onStatusUpdate("Initializing...");

    // 1. PhoneFilm init sequence (motherboard + wake)
    _bluetooth.write(";zxcvvbnmasdfghj;");
    Future.delayed(
      const Duration(milliseconds: 80),
      () => _bluetooth.write(";zxcvvbnmasdfgh;"),
    );
    final mbRandom = List.generate(10, (_) => Random().nextInt(9) + 1).join();
    Future.delayed(
      const Duration(milliseconds: 140),
      () => _bluetooth.write("BD:9,83,$mbRandom;"),
    );

    // 2. Initial commands to wake up the machine and get serial
    _bluetooth.write(";RCBM;");
    Future.delayed(
      const Duration(milliseconds: 200),
      () => _bluetooth.write(";;;RPID;"),
    );
    Future.delayed(
      const Duration(milliseconds: 400),
      () => _bluetooth.write(";RSVER;"),
    );
    Future.delayed(
      const Duration(milliseconds: 600),
      () => _bluetooth.write(";RHVER;"),
    );
    Future.delayed(
      const Duration(milliseconds: 800),
      () => _bluetooth.write(";RMODE;"),
    );
    Future.delayed(
      const Duration(milliseconds: 1000),
      () => _bluetooth.write(";RPGHEAD;"),
    );
    Future.delayed(
      const Duration(milliseconds: 1200),
      () => _bluetooth.write(";BD:20;"),
    );

    // 2. Targeted Jump (User request: Use what worked before)
    _checkCacheAndJump();

    // 3. Systematic trigger
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (!_isAuthenticated && !_bd9Sent && !_bd10Sent && !_awaitingPassU32) {
        _sendInitialChallenge();
      }
    });
  }

  Future<void> _checkCacheAndJump() async {
    String? serial = _bluetooth.serialNumber;
    if (serial == null) return;

    String? cachedAlgo = await _bluetooth.getCachedHandshake(serial);
    if (cachedAlgo != null) {
      String? cachedMode = await _bluetooth.getCachedHandshakeMode(serial);
      if (cachedMode == "manual") {
        _lockToAlgorithm(cachedAlgo);
        return;
      }
      int idx = _algorithms.indexWhere((a) => a == cachedAlgo);
      if (idx != -1) {
        print("🎯 Cache Hit! Jumping to algorithm: $cachedAlgo");
        _currentAlgoIndex = idx;
        // If it was DQ, we should also prepare for the special protocol
        if (cachedAlgo == "DQ") {
          _triggerDQProtocol();
        }
      }
    }
  }

  void _lockToAlgorithm(String algo) {
    if (_manualLockApplied) return;
    _manualLockApplied = true;
    _algorithms = [algo];
    _currentAlgoIndex = 0;
    _retryCount = 0;
    _bd9Sent = false;
    _bd10Sent = false;
    _dqProtocolTriggered = false;
    print("🔒 Manual handshake locked to: $algo");
    if (algo == "DQ") {
      _triggerDQProtocol();
    }
  }

  void _sendBD9() {
    if (_isAuthenticated || _bd10Sent) return;
    _bd9Sent = true;
    _watchdogTimer?.cancel();

    // Watchdog: If no response in 5s, try next algorithm
    _watchdogTimer = Timer(const Duration(seconds: 5), () {
      print("⏰ Watchdog: No response to BD:9 after 5s.");
      final algo = _algorithms[_currentAlgoIndex];
      if (!_stateHandshakeAttempted && _isPhonefilmAlgo(algo)) {
        _sendBD10Challenge();
      } else {
        print("⏰ Moving on...");
        _tryNextAlgorithm();
      }
    });

    // 6 digits is more common and compatible with older/Sunshine machines
    String random = List.generate(6, (_) => Random().nextInt(10)).join();
    print("📤 Sending BD:9,$random; (Attempt ${_retryCount + 1})");
    _bluetooth.write("BD:9,$random;");
  }

  void _sendBD10Challenge() {
    if (_isAuthenticated) return;
    _bd10Sent = true;
    _stateHandshakeAttempted = true;
    _usedStateHandshake = true;
    onStatusUpdate("Testing STATE...");
    _watchdogTimer?.cancel();

    _watchdogTimer = Timer(const Duration(seconds: 5), () {
      print("⏰ Watchdog: No response to BD:10 after 5s. Moving on...");
      _tryNextAlgorithm();
    });

    print("📤 Sending BD:10; (STATE)");
    _bluetooth.write("BD:10;");
  }

  void _sendPassU32() {
    if (_isAuthenticated || _bd10Sent) return;
    _awaitingPassU32 = true;
    _bd9Sent = false;
    onStatusUpdate("Testing PASS_U32...");
    _watchdogTimer?.cancel();

    _watchdogTimer = Timer(const Duration(seconds: 5), () {
      print("⏰ Watchdog: No response to PASS_U32 after 5s. Moving on...");
      _awaitingPassU32 = false;
      _tryNextAlgorithm();
    });

    _passU32Seed = Random().nextInt(1000000000);
    print("📤 Sending BD:9,8,$_passU32Seed; (PASS_U32)");
    _bluetooth.write("BD:9,8,$_passU32Seed;");
  }

  void _sendInitialChallenge() {
    final algo = _algorithms[_currentAlgoIndex];
    if (algo == "PASS_U32") {
      _sendPassU32();
      return;
    }
    if (_isPltSerial(_detectedSerial) && _shouldAutoTriggerDQ()) {
      _triggerDQProtocol();
      return;
    }
    if (_stateHandshakeAttempted && _isPhonefilmAlgo(algo)) {
      _sendBD10Challenge();
    } else {
      _sendBD9();
    }
  }

  void _triggerDQProtocol() {
    if (_isAuthenticated || _dqProtocolTriggered) return;
    print("🤖 DQ Machine Detected! Triggering Special Protocol...");
    _dqProtocolTriggered = true;

    // Jump to DQ algorithm in the loop for immediate results
    int dqIdx = _algorithms.indexOf("DQ");
    if (dqIdx != -1) {
      _currentAlgoIndex = dqIdx;
    }

    _bd10Sent = true;
    _bd9Sent = false; // Reset BD9 flag as we are switching paths
    _watchdogTimer?.cancel();

    // Watchdog: If no response in 5s, try next algorithm
    _watchdogTimer = Timer(const Duration(seconds: 5), () {
      print("⏰ Watchdog: No response to DQ Protocol after 5s. Moving on...");
      _tryNextAlgorithm();
    });

    // Step 1: App Sends Version Checks & BD:10
    _bluetooth.write(";RSVER;");
    Future.delayed(
      const Duration(milliseconds: 100),
      () => _bluetooth.write(";RHVER;"),
    );
    Future.delayed(
      const Duration(milliseconds: 200),
      () => _bluetooth.write(";BD:10;"),
    );
    Future.delayed(
      const Duration(milliseconds: 300),
      () => _bluetooth.write(";RCBM;"),
    );
  }

  void _finishHandshake(bool success) {
    print("🏁 Handshake finishing. Success: $success");
    _bluetooth.setSuppressAutoHandshake(false);
    onHandshakeComplete(success);
  }

  void dispose() {
    _watchdogTimer?.cancel();
    _bluetooth.setSuppressAutoHandshake(false);
    _dataSubscription?.cancel();
  }

  void _handleData(String data) {
    print("📥 RX: $data");
    _messageBuffer += data;

    while (_messageBuffer.contains(";")) {
      int endIndex = _messageBuffer.indexOf(";");
      String msg = _messageBuffer.substring(0, endIndex + 1);
      _messageBuffer = _messageBuffer.substring(endIndex + 1);

      msg = msg.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
      if (msg.isEmpty) continue;

      _processMessage(msg);
    }
  }

  void _processMessage(String message) {
    print("⚙️ Processing: $message");

    // 1. Serial Detection (Improved Priority Logic)
    if (message.contains("CBM=") ||
        message.contains("PID=") ||
        message.contains("RPID=")) {
      String rawSerial = message.split("=")[1].split(";")[0].trim();
      if (rawSerial.isNotEmpty) {
        bool newIsPriority = _isPrioritySerial(rawSerial);
        bool oldIsPriority = _isPrioritySerial(_detectedSerial);

        // Decision logic to update serial:
        // - Always update if we have nothing.
        // - Update if the new one is priority (SS/DQ) and the old one is not.
        // - Update if it's a CBM= command (explicit machine serial) and we don't already have a priority serial from somewhere else.
        bool shouldUpdate = false;
        if (_detectedSerial == null) {
          shouldUpdate = true;
        } else if (newIsPriority && !oldIsPriority) {
          shouldUpdate = true;
        } else if (message.contains("CBM=") &&
            (!oldIsPriority || newIsPriority)) {
          // If it's CBM, we prefer it unless we already have a priority one and this CBM is not priority
          shouldUpdate = true;
        }

        if (shouldUpdate) {
          _detectedSerial = rawSerial;
          _bluetooth.setSerialNumber(rawSerial);
          print(
            "📋 Detected Serial: $rawSerial${message.contains("CBM=") ? " (via CBM)" : ""}",
          );

          if (!_manualLockApplied) {
            _applyManualPreferenceIfAny(rawSerial);
          }

          // Fast-track DQ/DX/LH if identified
          if (_isPltSerial(rawSerial) && _shouldAutoTriggerDQ()) {
            if (!_bd10Sent && !_isAuthenticated) {
              _triggerDQProtocol();
            }
          }
        }
      }
    } else if ((message.startsWith("SS") ||
            message.startsWith("DQ") ||
            message.startsWith("DX") ||
            message.startsWith("LH")) &&
        !message.contains("=")) {
      String rawSerial = message.replaceAll(";", "").trim();
      if (rawSerial.isNotEmpty) {
        bool oldIsPriority = _isPrioritySerial(_detectedSerial);

        // Bare SS/DQ is always considered priority
        if (_detectedSerial == null || !oldIsPriority) {
          _detectedSerial = rawSerial;
          _bluetooth.setSerialNumber(rawSerial);
          print("📋 Detected Bare Serial: $rawSerial");

          if (!_manualLockApplied) {
            _applyManualPreferenceIfAny(rawSerial);
          }

          if (_isPltSerial(rawSerial) && _shouldAutoTriggerDQ()) {
            if (!_bd10Sent && !_isAuthenticated) {
              _triggerDQProtocol();
            }
          }
        }
      }
    }

    // 1.5 PASS_U32 verification (Upprinting)
    if (_awaitingPassU32 && _passU32Seed != null) {
      final actual = _extractPassU32Value(message);
      if (actual != null) {
        final expected = EncryptionUtil.getPassU32Expected(_passU32Seed!);
        if (actual == expected) {
          _watchdogTimer?.cancel();
          _awaitingPassU32 = false;
          _isAuthenticated = true;
          String winAlgo = _algorithms[_currentAlgoIndex];
          print("✅ PASS_U32 SUCCESS! Algorithm: $winAlgo");
          onStatusUpdate("✅ Connected!");
          _bluetooth.cacheSuccessfulHandshake(
            winAlgo,
            true,
            mode: _manualLockApplied ? "manual" : (_usedStateHandshake ? "phonefilm" : _handshakeMode),
          );
          // Optional follow-up used by Upprinting to fetch URL/COMPNO
          _bluetooth.write("BD:9;");
          _finishHandshake(true);
          return;
        } else {
          print("❌ PASS_U32 failed. expected=$expected actual=$actual");
          _awaitingPassU32 = false;
          _tryNextAlgorithm();
          return;
        }
      }
    }

    // 2. Protocol Responses
    if (message.contains("RCMD=9")) {
      onStatusUpdate("Verifying...");
      _bluetooth.write("BD:10;");
    } else if (message.contains("RCMD=11,")) {
      _watchdogTimer?.cancel();
      _handleChallenge(message);
    } else if (message.contains("RCMD=12,0")) {
      _watchdogTimer?.cancel();
      _isAuthenticated = true;
      String winAlgo = _algorithms[_currentAlgoIndex];
      print(
        "✅ SUCCESS! Algorithm: $winAlgo for Serial: ${_detectedSerial ?? 'Unknown'}",
      );
      onStatusUpdate("✅ Connected!");
      _bluetooth.cacheSuccessfulHandshake(
        winAlgo,
        true,
        mode: _manualLockApplied ? "manual" : (_usedStateHandshake ? "phonefilm" : _handshakeMode),
      );
      _finishHandshake(true);
    } else if (message.contains("RCMD=12,1")) {
      if (!_isAuthenticated) {
        print("❌ Auth Failed for ${_algorithms[_currentAlgoIndex]}");
        _tryNextAlgorithm();
      }
    } else if (message.startsWith("11,") || message.contains(",11,")) {
      // Sometimes the machine sends a challenge without RCMD= prefix after certain sequences
      _handleChallenge(message);
    }
  }

  void _handleChallenge(String response) {
    int challenge = _extractChallenge(response);
    String currentAlgo = _algorithms[_currentAlgoIndex];

    print("🧪 Testing Algorithm: $currentAlgo (Retry $_retryCount)");
    onStatusUpdate("Testing $currentAlgo...");

    int password;
    switch (currentAlgo) {
      case "DQ":
        password = EncryptionUtil.getDQHandshake(challenge);
        break;
      case "HANDSHAKE_NEW":
        password = EncryptionUtil.getHandshakeNew(challenge);
        break;
      case "STANDARD":
        // In some contexts STANDARD uses HandshakeNew, in others something else.
        // Let's keep it as is or try to differentiate.
        password = EncryptionUtil.getHandshakeNew(challenge);
        break;
      case "OLD_V1":
        password = EncryptionUtil.getHandshakeOldV1(challenge);
        break;
      case "OLD_V3":
        password = EncryptionUtil.getHandshakeOldV3(challenge);
        break;
      case "GENERIC_NEW":
        password = EncryptionUtil.getSunshinePassword(challenge, "");
        break;
      default:
        password = EncryptionUtil.getSunshinePassword(challenge, currentAlgo);
    }

    print("📤 Sending BD:12,$password;");
    _bluetooth.write("BD:12,$password;");
  }

  void _tryNextAlgorithm() {
    _currentAlgoIndex++;
    _retryCount++;
    _awaitingPassU32 = false;
    _passU32Seed = null;
    _stateHandshakeAttempted = false;
    _usedStateHandshake = false;

    if (_currentAlgoIndex < _algorithms.length) {
      _bd9Sent = false;
      _bd10Sent = false;
      Future.delayed(const Duration(milliseconds: 500), () {
        if (_bluetooth.isConnected) {
          _sendInitialChallenge();
        }
      });
    } else {
      print("🚫 All algorithms exhausted.");
      onStatusUpdate("❌ Failed");
      _finishHandshake(false);
    }
  }

  int? _extractPassU32Value(String message) {
    try {
      var msg = message.replaceAll(";", "").trim();
      if (!msg.contains("=")) return null;
      final parts = msg.split("=");
      if (parts.length < 2) return null;
      final rhs = parts.sublist(1).join("=").trim();
      final items = rhs.split(",");
      if (items.length < 3) return null;
      final value = items[2].trim();
      return int.tryParse(value);
    } catch (_) {
      return null;
    }
  }

  Future<void> _applyManualPreferenceIfAny(String serial) async {
    try {
      final mode = await _bluetooth.getCachedHandshakeMode(serial);
      if (mode == "manual") {
        final algo = await _bluetooth.getCachedHandshake(serial);
        if (algo != null && algo.isNotEmpty) {
          _lockToAlgorithm(algo);
        }
      }
    } catch (e) {
      print("Error applying manual handshake preference: $e");
    }
  }

  int _extractChallenge(String msg) {
    try {
      int start = msg.indexOf("RCMD=11,") + 8;
      int end = msg.indexOf(";", start);
      return int.parse(msg.substring(start, end).trim());
    } catch (e) {
      return 0;
    }
  }
}
