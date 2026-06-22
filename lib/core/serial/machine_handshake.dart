import 'package:flutter_project/core/handshake_response_resolver.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter_project/core/serial/serial_service.dart';

/// PhoneFilm v3.0.1 handshake flow:
/// 1) getPassWord2
/// 2) getOldPassWord
/// 3) getPassWord
class MachineHandshake {
  static const String algoSunshine = HandshakeResponseResolver.algoSunshine;
  static const String algoPassWord2 = HandshakeResponseResolver.algoPassWord2;
  static const String algoOldPassWord =
      HandshakeResponseResolver.algoOldPassWord;
  static const String algoPassWord = HandshakeResponseResolver.algoPassWord;
  static const String algoDQHandshake =
      HandshakeResponseResolver.algoDQHandshake;
  static const String algoMechanicUart =
      HandshakeResponseResolver.algoMechanicUart;

  static const List<String> sunshineAlgorithms =
      HandshakeResponseResolver.sunshineAlgorithms;

  static const List<String> supportedAlgorithms =
      HandshakeResponseResolver.supportedAlgorithms;

  final CutterSerialService _bluetooth;
  final Function(bool) onHandshakeComplete;
  final Function(String) onStatusUpdate;
  final String _handshakeMode;
  final bool _persistOnSuccess;
  final int _maxRounds;

  StreamSubscription? _dataSubscription;
  Timer? _challengeTimer;
  Timer? _ackTimer;
  final List<Timer> _scheduledTimers = [];

  List<String> _algorithms = HandshakeResponseResolver.resolveAttemptSequence();
  int _currentAlgoIndex = 0;
  int _currentRound = 1;
  int? _currentChallenge;

  String _messageBuffer = '';
  bool _awaitingAuthAck = false;
  bool _isAuthenticated = false;
  bool _finished = false;
  int _challengeRetryCount = 0;
  bool _awaitingMechanicVerification = false;
  bool _mechanicVerificationPassed = false;
  int? _mechanicVerificationSeed;
  static const int _maxChallengeRetriesPerAlgorithm = 2;
  static const Duration _challengeTimeout = Duration(milliseconds: 5000);
  static const Duration _authAckTimeout = Duration(milliseconds: 5000);
  static const Duration _mechanicVerificationTimeout = Duration(
    milliseconds: 1800,
  );

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
    _algorithms = HandshakeResponseResolver.resolveAttemptSequence(
      forcedAlgorithm: forcedAlgorithm,
      preferredAlgorithm: preferredAlgorithm,
    );
  }

  static String? normalizeAlgorithm(String? raw) {
    return HandshakeResponseResolver.normalizeAlgorithm(raw);
  }

  bool get isAuthenticated => _isAuthenticated;

  void startHandshake() {
    _resetState();

    _bluetooth.setSuppressAutoHandshake(true);
    _dataSubscription = _bluetooth.receivedDataStream.listen(_handleData);

    onStatusUpdate('Initializing...');

    // Exact sequence from Sunshine WelcomeActivity.initData():
    // 1. Motherboard check with random 10-digit number
    final mbRandom = List.generate(10, (_) => Random().nextInt(9) + 1).join();
    _safeWrite('BD:9,83,$mbRandom;');

    // 2. Query device info (same order as original)
    _schedule(const Duration(milliseconds: 100), () => _safeWrite(';;;RPID;'));
    _schedule(const Duration(milliseconds: 200), () => _safeWrite(';RSVER;'));
    _schedule(const Duration(milliseconds: 300), () => _safeWrite(';RHVER;'));
    _schedule(const Duration(milliseconds: 400), () => _safeWrite(';RMODE;'));
    _schedule(const Duration(milliseconds: 500), () => _safeWrite(';RPGHEAD;'));
    _schedule(const Duration(milliseconds: 600), () => _safeWrite(';RCBM;'));
    _schedule(const Duration(milliseconds: 700), () => _safeWrite('BD:100,20,0;'));

    // 3. Start handshake challenge after device info queries complete
    _schedule(const Duration(milliseconds: 900), _requestChallenge);
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
    _challengeRetryCount = 0;
    _awaitingMechanicVerification = false;
    _mechanicVerificationPassed = false;
    _mechanicVerificationSeed = null;
  }

  void _requestChallenge() {
    if (_finished || _isAuthenticated || !_bluetooth.isConnected) return;

    if (_currentAlgoIndex < _algorithms.length &&
        _algorithms[_currentAlgoIndex] == algoMechanicUart &&
        !_mechanicVerificationPassed) {
      _requestMechanicVerification();
      return;
    }

    _awaitingAuthAck = false;
    _currentChallenge = null;
    onStatusUpdate('Requesting challenge...');
    _safeWrite('BD:10;');

    _challengeTimer?.cancel();
    _challengeTimer = Timer(_challengeTimeout, () {
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

  void _requestMechanicVerification() {
    if (_finished || _isAuthenticated || !_bluetooth.isConnected) return;

    _awaitingAuthAck = false;
    _currentChallenge = null;
    _awaitingMechanicVerification = true;
    _mechanicVerificationSeed = Random().nextInt(1000000000);

    onStatusUpdate('Verifying Mechanic UART...');
    _safeWrite('BD:9,8,${_mechanicVerificationSeed!};');

    _challengeTimer?.cancel();
    _challengeTimer = Timer(_mechanicVerificationTimeout, () {
      if (_finished || _isAuthenticated) return;
      if (_awaitingMechanicVerification) {
        _awaitingMechanicVerification = false;
        _mechanicVerificationPassed = false;
        _mechanicVerificationSeed = null;
        _tryNextAlgorithm();
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
    if (_awaitingMechanicVerification &&
        _isMechanicVerificationResponse(message)) {
      _handleMechanicVerificationResponse(message);
      return;
    }

    if (message.contains('RCMD=12,0')) {
      _markSuccess();
      return;
    }

    if (message.contains('RCMD=12,1')) {
      if (_currentAlgoIndex >= _algorithms.length) {
        _advanceRoundOrFinish();
        return;
      }
      _tryNextAlgorithm();
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

  bool _isMechanicVerificationResponse(String message) {
    return message.contains('RCMD=9') ||
        message.startsWith('9,') ||
        message.contains(',9,');
  }

  void _handleMechanicVerificationResponse(String message) {
    _challengeTimer?.cancel();

    final expected = _mechanicVerificationSeed == null
        ? null
        : HandshakeResponseResolver.resolveMechanicVerificationExpected(
            _mechanicVerificationSeed!,
          );
    final returned = _extractMechanicVerificationValue(message);
    final isValid = returned == null ||
        expected == null ||
        (returned & 0xFFFFFFFF) == (expected & 0xFFFFFFFF);

    _awaitingMechanicVerification = false;
    _mechanicVerificationSeed = null;

    if (!isValid) {
      _mechanicVerificationPassed = false;
      _tryNextAlgorithm();
      return;
    }

    _mechanicVerificationPassed = true;
    onStatusUpdate('Mechanic UART verified...');
    _requestChallenge();
  }

  void _sendCurrentAlgorithm() {
    if (_finished || _isAuthenticated) return;

    if (_currentAlgoIndex >= _algorithms.length) {
      _advanceRoundOrFinish();
      return;
    }

    final algo = _algorithms[_currentAlgoIndex];
    if (_currentChallenge == null) return;

    final challenge = _currentChallenge!;
    final password = HandshakeResponseResolver.resolveChallengeResponse(
      algorithm: algo,
      challenge: challenge,
    );

    onStatusUpdate('Testing $algo...');
    _safeWrite('BD:12,$password;');

    _awaitingAuthAck = true;
    _ackTimer?.cancel();
    _ackTimer = Timer(_authAckTimeout, () {
      if (_finished || _isAuthenticated) return;
      if (_awaitingAuthAck) {
        _tryNextAlgorithm();
      }
    });
  }

  void _markSuccess() {
    if (_finished || _isAuthenticated) return;

    _isAuthenticated = true;
    _awaitingAuthAck = false;
    _ackTimer?.cancel();

    final winAlgo =
        _currentAlgoIndex >= 0 && _currentAlgoIndex < _algorithms.length
            ? _algorithms[_currentAlgoIndex]
            : (_bluetooth.successfulHandshakeType ??
                _bluetooth.cachedAgentType ??
                HandshakeResponseResolver.algoPassWord2);
    onStatusUpdate('✅ Connected!');
    _bluetooth.cacheSuccessfulHandshake(
      winAlgo,
      true,
      mode: _handshakeMode,
      persist: _persistOnSuccess,
      markSessionAuthenticated: true,
    );

    _finish(true);
  }

  void _tryNextAlgorithm() {
    if (_finished || _isAuthenticated) return;

    _awaitingAuthAck = false;
    _ackTimer?.cancel();
    _challengeRetryCount = 0;
    _awaitingMechanicVerification = false;
    _mechanicVerificationPassed = false;
    _mechanicVerificationSeed = null;
    _currentAlgoIndex++;

    if (_currentAlgoIndex < _algorithms.length) {
      if (_currentChallenge != null) {
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
      _requestChallenge();
      return;
    }
    _finish(false);
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

  int? _extractMechanicVerificationValue(String message) {
    try {
      if (message.contains('RCMD=9,')) {
        final start = message.indexOf('RCMD=9,') + 7;
        var end = message.indexOf(';', start);
        if (end == -1) end = message.length;
        return int.tryParse(message.substring(start, end).trim());
      }

      if (message.startsWith('9,')) {
        final parts = message.replaceAll(';', '').split(',');
        if (parts.length >= 2) return int.tryParse(parts[1].trim());
      }

      final idx = message.indexOf(',9,');
      if (idx != -1) {
        final tail = message.substring(idx + 3).replaceAll(';', '');
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
