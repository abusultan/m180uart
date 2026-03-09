import 'dart:async';
import 'dart:math';
import '../services/bluetooth_service.dart';
import 'handshake_response_resolver.dart';

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

  static const List<String> sunshineAlgorithms =
      HandshakeResponseResolver.sunshineAlgorithms;

  static const List<String> supportedAlgorithms =
      HandshakeResponseResolver.supportedAlgorithms;

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

  List<String> _algorithms = HandshakeResponseResolver.resolveAttemptSequence();
  int _currentAlgoIndex = 0;
  int _currentRound = 1;
  int? _currentChallenge;

  String _messageBuffer = '';
  bool _awaitingAuthAck = false;
  bool _isAuthenticated = false;
  bool _finished = false;
  int _challengeRetryCount = 0;
  static const int _maxChallengeRetriesPerAlgorithm = 1;
  static const Duration _challengeTimeout = Duration(milliseconds: 1400);
  static const Duration _authAckTimeout = Duration(milliseconds: 900);

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
    _challengeRetryCount = 0;
  }

  void _requestChallenge() {
    if (_finished || _isAuthenticated || !_bluetooth.isConnected) return;

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
    if (message.contains('RCMD=12,0')) {
      _markSuccess();
      return;
    }

    if (message.contains('RCMD=12,1')) {
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
    _challengeRetryCount = 0;
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
