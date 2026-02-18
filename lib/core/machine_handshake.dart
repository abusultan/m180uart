import 'dart:async';
import 'dart:math';
import '../services/bluetooth_service.dart';
import '../utils/encryption_util.dart';

/// PhoneFilm v3.0.1 handshake flow:
/// 1) getPassWord2
/// 2) getOldPassWord
/// 3) getPassWord
class MachineHandshake {
  static const String algoSunshine = 'SUNSHINE';
  static const String algoPassWord2 = 'HANDSHAKE_NEW';
  static const String algoOldPassWord = 'OLD_V1';
  static const String algoPassWord = 'OLD_V3';
  static const String algoRockspace = 'ROCKSPACE_STR';
  static const String defaultRockspacePid = '12345678901234567890';

  static const List<String> sunshineAlgorithms = [
    algoPassWord2,
    algoOldPassWord,
    algoPassWord,
  ];

  static const List<String> supportedAlgorithms = [
    ...sunshineAlgorithms,
    algoRockspace,
  ];

  final CutterBluetoothService _bluetooth;
  final Function(bool) onHandshakeComplete;
  final Function(String) onStatusUpdate;
  final String _handshakeMode;
  final bool _persistOnSuccess;
  final int _maxRounds;

  StreamSubscription? _dataSubscription;
  Timer? _challengeTimer;
  Timer? _ackTimer;
  final List<Timer> _scheduledTimers = [];

  List<String> _algorithms = List<String>.from(sunshineAlgorithms);
  int _currentAlgoIndex = 0;
  int _currentRound = 1;
  int? _currentChallenge;

  String _messageBuffer = '';
  bool _awaitingAuthAck = false;
  bool _isAuthenticated = false;
  bool _finished = false;
  _RockspaceState _rockspaceState = _RockspaceState.idle;
  String? _detectedPid;
  int _challengeRetryCount = 0;
  static const int _maxChallengeRetriesPerAlgorithm = 3;

  MachineHandshake(
    this._bluetooth, {
    required this.onHandshakeComplete,
    required this.onStatusUpdate,
    String? forcedAlgorithm,
    String? preferredAlgorithm,
    String handshakeMode = 'auto',
    bool persistOnSuccess = true,
    int maxRounds = 1,
  })  : _handshakeMode = handshakeMode,
        _persistOnSuccess = persistOnSuccess,
        _maxRounds = maxRounds < 1 ? 1 : maxRounds {
    final forced = normalizeAlgorithm(forcedAlgorithm);
    if (forced != null) {
      if (forced == algoSunshine) {
        _algorithms = List<String>.from(sunshineAlgorithms);
      } else {
        _algorithms = [forced];
      }
      return;
    }

    final preferred = normalizeAlgorithm(preferredAlgorithm);
    if (preferred != null) {
      if (preferred == algoSunshine) {
        _algorithms = List<String>.from(sunshineAlgorithms);
      } else {
        _algorithms = List<String>.from(sunshineAlgorithms);
        _algorithms.remove(preferred);
        _algorithms.insert(0, preferred);
      }
    }
  }

  static String? normalizeAlgorithm(String? raw) {
    if (raw == null) return null;
    final normalized = raw.trim().toUpperCase();
    if (normalized.isEmpty) return null;

    switch (normalized) {
      case 'SUNSHINE':
      case 'AUTO':
      case 'AUTO_TRY':
        return algoSunshine;
      case 'ROCKSPACE':
      case 'ROCKSPACE_STR':
      case 'ROCKSPACE_SN':
      case 'ROCKSPACE HANDSHAKE SEQUENCE':
        return algoRockspace;
      case 'HANDSHAKE_NEW':
      case 'HANDSHAKENEW':
      case 'STANDARD':
      case 'GENERIC_NEW':
      case 'DQ':
      case 'DEVIA':
      case 'SY':
      case 'CUTTER':
      case 'PASS_U32':
      case 'PASSWORD2':
      case 'PASS_WORD2':
      case 'GETPASSWORD2':
        return algoPassWord2;
      case 'OLD_V1':
      case 'GETOLDPASSWORD':
      case 'OLDPASSWORD':
      case 'PASS_WORD_OLD':
        return algoOldPassWord;
      case 'OLD_V3':
      case 'PASSWORD':
      case 'PASS_WORD':
      case 'GETPASSWORD':
        return algoPassWord;
      default:
        return null;
    }
  }

  bool get isAuthenticated => _isAuthenticated;

  void startHandshake() {
    _resetState();

    _bluetooth.setSuppressAutoHandshake(true);
    _dataSubscription = _bluetooth.receivedDataStream.listen(_handleData);

    onStatusUpdate('Initializing...');

    // Keep the legacy wake-up sequence from the original Android app.
    _safeWrite(';zxcvvbnmasdfghj;');
    _schedule(const Duration(milliseconds: 60), () {
      _safeWrite(';zxcvvbnmasdfgh;');
    });
    final mbRandom = List.generate(10, (_) => Random().nextInt(9) + 1).join();
    _schedule(
      const Duration(milliseconds: 140),
      () => _safeWrite('BD:9,83,$mbRandom;'),
    );
    _safeWrite(';RCBM;');
    _schedule(const Duration(milliseconds: 220), () => _safeWrite(';;;RPID;'));
    _schedule(const Duration(milliseconds: 320), () => _safeWrite(';RMODE;'));
    _schedule(const Duration(milliseconds: 700), _requestChallenge);
  }

  void _resetState() {
    _cleanup();
    _finished = false;
    _isAuthenticated = false;
    _currentAlgoIndex = 0;
    _currentRound = 1;
    _currentChallenge = null;
    _awaitingAuthAck = false;
    _messageBuffer = '';
    _rockspaceState = _RockspaceState.idle;
    _detectedPid = null;
    _challengeRetryCount = 0;
  }

  void _requestChallenge() {
    if (_finished || _isAuthenticated || !_bluetooth.isConnected) return;

    _awaitingAuthAck = false;
    _currentChallenge = null;
    onStatusUpdate('Requesting challenge...');
    _safeWrite('BD:10;');

    _challengeTimer?.cancel();
    _challengeTimer = Timer(const Duration(seconds: 3), () {
      if (_finished || _isAuthenticated) return;
      if (_currentChallenge == null) {
        _challengeRetryCount++;
        if (_challengeRetryCount <= _maxChallengeRetriesPerAlgorithm) {
          _requestChallenge();
        } else {
          _challengeRetryCount = 0;
          _tryNextAlgorithm();
        }
      }
    });
  }

  void _handleData(String data) {
    if (_finished) return;

    _messageBuffer += data;
    while (_messageBuffer.contains(';')) {
      final end = _messageBuffer.indexOf(';');
      var message = _messageBuffer.substring(0, end + 1);
      _messageBuffer = _messageBuffer.substring(end + 1);

      message = message.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
      if (message.isEmpty) continue;

      _processMessage(message);
    }
  }

  void _processMessage(String message) {
    final pid =
        _extractKeyValue(message, 'PID=') ?? _extractKeyValue(message, 'RPID=');
    if (pid != null && pid.isNotEmpty) {
      _detectedPid = pid;
    }

    if (message.contains('RCMD=12,0')) {
      _markSuccess();
      return;
    }

    if (message.contains('RCMD=12,1')) {
      _tryNextAlgorithm();
      return;
    }

    if (_handleRockspaceMessage(message)) {
      return;
    }

    if (!_awaitingAuthAck &&
        (message.contains('RCMD=11,') ||
            message.startsWith('11,') ||
            message.contains(',11,'))) {
      final parsed = _extractChallenge(message);
      if (parsed != null) {
        _currentChallenge = parsed;
        _challengeRetryCount = 0;
        _challengeTimer?.cancel();
        _sendCurrentAlgorithm();
      }
    }
  }

  void _sendCurrentAlgorithm() {
    if (_finished || _isAuthenticated) return;

    if (_currentAlgoIndex >= _algorithms.length) {
      _advanceRoundOrFinish();
      return;
    }

    final algo = _algorithms[_currentAlgoIndex];
    if (algo == algoRockspace) {
      _startRockspaceHandshake();
      return;
    }

    if (_currentChallenge == null) return;

    final challenge = _currentChallenge!;
    final password = _calculatePassword(algo, challenge);

    onStatusUpdate('Testing $algo...');
    _safeWrite('BD:12,$password;');

    _awaitingAuthAck = true;
    _ackTimer?.cancel();
    _ackTimer = Timer(const Duration(seconds: 2), () {
      if (_finished || _isAuthenticated) return;
      if (_awaitingAuthAck) {
        _tryNextAlgorithm();
      }
    });
  }

  int _calculatePassword(String algorithm, int challenge) {
    switch (algorithm) {
      case algoPassWord2:
        return EncryptionUtil.getHandshakeNew(challenge);
      case algoOldPassWord:
        return EncryptionUtil.getHandshakeOldV1(challenge);
      case algoPassWord:
        return EncryptionUtil.getHandshakeOldV3(challenge);
      default:
        return EncryptionUtil.getHandshakeNew(challenge);
    }
  }

  void _markSuccess() {
    if (_finished || _isAuthenticated) return;

    _isAuthenticated = true;
    _awaitingAuthAck = false;
    _ackTimer?.cancel();

    final winAlgo = _algorithms[_currentAlgoIndex];
    onStatusUpdate('✅ Connected!');
    _bluetooth.cacheSuccessfulHandshake(
      winAlgo,
      true,
      mode: _handshakeMode,
      persist: _persistOnSuccess,
    );

    _finish(true);
  }

  void _tryNextAlgorithm() {
    if (_finished || _isAuthenticated) return;

    _awaitingAuthAck = false;
    _ackTimer?.cancel();
    _rockspaceState = _RockspaceState.idle;
    _challengeRetryCount = 0;
    _currentAlgoIndex++;

    if (_currentAlgoIndex < _algorithms.length) {
      if (_algorithms[_currentAlgoIndex] == algoRockspace ||
          _currentChallenge != null) {
        _sendCurrentAlgorithm();
      } else {
        _requestChallenge();
      }
      return;
    }

    _advanceRoundOrFinish();
  }

  void _advanceRoundOrFinish() {
    if (_currentRound < _maxRounds) {
      _currentRound++;
      _currentAlgoIndex = 0;
      _awaitingAuthAck = false;
      _rockspaceState = _RockspaceState.idle;
      _requestChallenge();
      return;
    }
    _finish(false);
  }

  void _startRockspaceHandshake() {
    if (_finished || _isAuthenticated) return;

    _currentChallenge = null;
    _awaitingAuthAck = false;
    _rockspaceState = _RockspaceState.waitingSerial;

    onStatusUpdate('Testing Rockspace Machine Handshake...');
    _safeWrite('STR=10,0;');

    _challengeTimer?.cancel();
    _challengeTimer = Timer(const Duration(seconds: 3), () {
      if (_finished || _isAuthenticated) return;
      if (_rockspaceState == _RockspaceState.waitingSerial) {
        final knownSerial = _extractCandidateSerial(_bluetooth.serialNumber);
        if (knownSerial != null && knownSerial.isNotEmpty) {
          onStatusUpdate('Rockspace using known serial...');
          _sendRockspaceAuth(knownSerial);
          return;
        }
        _tryNextAlgorithm();
      }
    });
  }

  bool _handleRockspaceMessage(String message) {
    if (_currentAlgoIndex >= _algorithms.length) return false;
    if (_algorithms[_currentAlgoIndex] != algoRockspace) return false;
    final upper = message.toUpperCase();

    if (_rockspaceState == _RockspaceState.waitingSerial) {
      final serial = _extractRockspaceSerial(message);
      if (serial == null || serial.isEmpty) return false;

      _sendRockspaceAuth(serial);
      return true;
    }

    if (_rockspaceState == _RockspaceState.waitingAck) {
      if (upper.contains('RSTR=10,0') ||
          upper.contains('STR=10,0') ||
          upper.contains('RSTR=10,OK') ||
          upper.contains('STR=10,OK') ||
          upper.contains('STR=10,SUCCESS')) {
        _markSuccess();
        return true;
      }
      if (upper.contains('RSTR=10,1') ||
          upper.contains('STR=10,1') ||
          upper.contains('RSTR=10,FAIL') ||
          upper.contains('STR=10,FAIL') ||
          upper.contains('RSTR=10,ERROR') ||
          upper.contains('STR=10,ERROR')) {
        _tryNextAlgorithm();
        return true;
      }
    }

    return false;
  }

  void _sendRockspaceAuth(String serialRaw) {
    final serial = _extractCandidateSerial(serialRaw);
    if (serial == null || serial.isEmpty) {
      _tryNextAlgorithm();
      return;
    }

    _challengeTimer?.cancel();
    _bluetooth.setSerialNumber(serial);
    final pid = _resolveRockspacePid();
    final password = EncryptionUtil.getRockspaceSnHandshake(
      pid: pid,
      sn: serial,
    );

    onStatusUpdate('Rockspace auth...');
    _safeWrite('STR=10,$serial#$password;');
    _rockspaceState = _RockspaceState.waitingAck;
    _awaitingAuthAck = true;

    _ackTimer?.cancel();
    _ackTimer = Timer(const Duration(seconds: 4), () {
      if (_finished || _isAuthenticated) return;
      if (_rockspaceState == _RockspaceState.waitingAck) {
        _tryNextAlgorithm();
      }
    });
  }

  String? _extractCandidateSerial(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;

    var text = value;
    final markers = ['CBM=', 'SN=', 'SERIAL=', 'STR=10,', 'RSTR=10,'];
    for (final marker in markers) {
      final idx = text.toUpperCase().lastIndexOf(marker);
      if (idx != -1) {
        text = text.substring(idx + marker.length);
      }
    }

    text = text.replaceAll(';', ' ');
    if (text.contains('#')) {
      text = text.split('#').first;
    }

    final tokens = RegExp(r'[A-Za-z0-9_\-]{4,}')
        .allMatches(text)
        .map((m) => m.group(0) ?? '')
        .where((s) => s.isNotEmpty)
        .toList();

    if (tokens.isEmpty) return null;

    tokens.sort((a, b) => b.length.compareTo(a.length));
    final best = tokens.first;
    final upper = best.toUpperCase();
    if (upper == 'OK' ||
        upper == 'SUCCESS' ||
        upper == 'FAIL' ||
        upper == 'ERROR' ||
        upper == 'CBM' ||
        upper == 'STR' ||
        upper == 'RSTR') {
      return null;
    }
    return best;
  }

  String _resolveRockspacePid() {
    final pid = (_detectedPid ?? '').trim();
    if (pid.isEmpty) return defaultRockspacePid;
    return pid;
  }

  String? _extractRockspaceSerial(String message) {
    final trimmed = message.trim();
    String payload;
    if (trimmed.startsWith('STR=10,')) {
      payload = trimmed.substring(7);
    } else if (trimmed.startsWith('RSTR=10,')) {
      payload = trimmed.substring(8);
    } else {
      return null;
    }

    if (payload.contains('#')) return null;
    final serial = _extractCandidateSerial(payload);
    if (serial == null || serial.isEmpty) return null;

    final upper = serial.toUpperCase();
    if (upper == '0' ||
        upper == '1' ||
        upper == 'OK' ||
        upper == 'SUCCESS' ||
        upper == 'FAIL' ||
        upper == 'ERROR') {
      return null;
    }
    return serial;
  }

  String? _extractKeyValue(String message, String key) {
    try {
      final idx = message.indexOf(key);
      if (idx == -1) return null;
      final start = idx + key.length;
      final end = message.indexOf(';', start);
      final value =
          (end == -1 ? message.substring(start) : message.substring(start, end))
              .trim();
      return value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  int? _extractChallenge(String message) {
    try {
      if (message.contains('RCMD=11,')) {
        final start = message.indexOf('RCMD=11,') + 8;
        var end = message.indexOf(';', start);
        if (end == -1) end = message.length;
        return int.tryParse(message.substring(start, end).trim());
      }

      if (message.startsWith('11,')) {
        final parts = message.replaceAll(';', '').split(',');
        if (parts.length >= 2) return int.tryParse(parts[1].trim());
      }

      final idx = message.indexOf(',11,');
      if (idx != -1) {
        final tail = message.substring(idx + 4).replaceAll(';', '');
        final parts = tail.split(',');
        if (parts.isNotEmpty) return int.tryParse(parts.first.trim());
      }
    } catch (_) {}

    return null;
  }

  void _schedule(Duration delay, void Function() action) {
    final timer = Timer(delay, () {
      if (_finished || !_bluetooth.isConnected) return;
      action();
    });
    _scheduledTimers.add(timer);
  }

  void _safeWrite(String command) {
    _bluetooth.write(command).catchError((_) {});
  }

  void _finish(bool success) {
    if (_finished) return;
    _finished = true;
    _cleanup();
    _bluetooth.setSuppressAutoHandshake(false);
    onHandshakeComplete(success);
  }

  void _cleanup() {
    _challengeTimer?.cancel();
    _challengeTimer = null;

    _ackTimer?.cancel();
    _ackTimer = null;
    _rockspaceState = _RockspaceState.idle;

    for (final timer in _scheduledTimers) {
      timer.cancel();
    }
    _scheduledTimers.clear();

    _dataSubscription?.cancel();
    _dataSubscription = null;
  }

  void dispose() {
    _cleanup();
    _bluetooth.setSuppressAutoHandshake(false);
  }
}

enum _RockspaceState { idle, waitingSerial, waitingAck }
