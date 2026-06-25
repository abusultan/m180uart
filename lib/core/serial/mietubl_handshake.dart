import 'dart:async';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_project/core/serial/serial_service.dart';

/// Mietubl 180T specific handshake implementation.
/// Protocol: Binary packets with SHA256 CRC verification.
/// Baud: 38400, Headers: 9CC9 (new) / 5AA5 (old), Footer: 0D0A
class MietublHandshake {
  static const String newHead = '9CC9';
  static const String beforeHead = '5AA5';
  static const String defaultPassword = 'mtbznqmji4368637';

  final CutterSerialService _serial;
  final Function(bool) onHandshakeComplete;
  final Function(String) onStatusUpdate;
  final String _password;

  StreamSubscription? _dataSubscription;
  Timer? _timeoutTimer;

  String _messageBuffer = '';
  int _cmdflag = 2; // Start with new protocol
  bool _finished = false;

  MietublHandshake(
    this._serial, {
    required this.onHandshakeComplete,
    required this.onStatusUpdate,
    String password = defaultPassword,
  }) : _password = password;

  void startHandshake() {
    _resetState();
    _serial.setSuppressAutoHandshake(true);
    _dataSubscription = _serial.receivedDataStream.listen(_handleData);
    onStatusUpdate('Connecting to Mietubl 180T...');
    _queryMachineVersion();
  }

  void _resetState() {
    _cleanup();
    _finished = false;
    _cmdflag = 2;
    _messageBuffer = '';
  }

  /// Send queryMachineVersion command - the initial handshake probe.
  /// Command payload: 00210000 (query version, no parameters)
  void _queryMachineVersion() {
    if (_finished || !_serial.isConnected) {
      debugPrint('MietublHandshake: SKIP - finished=$_finished connected=${_serial.isConnected}');
      return;
    }

    final String basePayload = "00210000";

    String hexCommand;
    if (_cmdflag == 1) {
      // Old protocol (5AA5): simple byte-sum checksum
      final str = "AA$basePayload";
      int sum = 0;
      for (int i = 0; i < str.length; i += 2) {
        sum += int.parse(str.substring(i, i + 2), radix: 16);
      }
      final crc = sum & 0xFF;
      hexCommand = "$beforeHead$str${crc.toRadixString(16).padLeft(2, '0').toUpperCase()}0D0A";
    } else {
      // New protocol (9CC9): for queryMachineVersion, the machine expects a simple byte-sum checksum, not SHA256!
      final str = "55$basePayload";
      int sum = 0;
      for (int i = 0; i < str.length; i += 2) {
        sum += int.parse(str.substring(i, i + 2), radix: 16);
      }
      final crc = sum & 0xFF;
      hexCommand = "$newHead$str${crc.toRadixString(16).padLeft(2, '0').toUpperCase()}0D0A";
    }

    debugPrint('MietublHandshake: sending $hexCommand (cmdflag=$_cmdflag)');
    _safeWriteHex(hexCommand);

    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(milliseconds: 5000), () {
      if (_finished) return;
      if (_cmdflag == 2) {
        debugPrint('MietublHandshake: timeout on new protocol, trying old...');
        _cmdflag = 1;
        _queryMachineVersion();
      } else {
        onStatusUpdate('Connection timeout');
        _finish(false);
      }
    });
  }

  void _handleData(String data) {
    if (_finished) return;
    debugPrint('MietublHandshake RX: ${data.length} chars, codeUnits=${data.codeUnits.take(20).toList()}');
    _messageBuffer += data;
    _processBuffer();
  }

  void _processBuffer() {
    // Check for response headers in hex-encoded format
    final String buf = _messageBuffer.toUpperCase();
    bool foundValidResponse = false;

    if (buf.contains('9CC9') || buf.contains('5AA5')) {
      foundValidResponse = true;
    }

    // Also check raw byte values
    if (!foundValidResponse) {
      final bytes = _messageBuffer.codeUnits;
      for (int i = 0; i < bytes.length - 1; i++) {
        if ((bytes[i] == 0x9C && bytes[i + 1] == 0xC9) ||
            (bytes[i] == 0x5A && bytes[i + 1] == 0xA5)) {
          foundValidResponse = true;
          break;
        }
      }
    }

    if (foundValidResponse) {
      _messageBuffer = '';
      _timeoutTimer?.cancel();
      _markSuccess();
    } else if (_messageBuffer.length > 1000) {
      _messageBuffer = _messageBuffer.substring(500);
    }
  }

  void _safeWriteHex(String hexCommand) {
    final bytes = <int>[];
    for (int i = 0; i < hexCommand.length; i += 2) {
      bytes.add(int.parse(hexCommand.substring(i, i + 2), radix: 16));
    }
    _serial.writeBytes(Uint8List.fromList(bytes)).catchError((_) {});
  }

  void _markSuccess() {
    if (_finished) return;
    onStatusUpdate('✅ Connected to Mietubl 180T!');
    _serial.setSerialNumber('M180T');
    _serial.cacheSuccessfulHandshake(
      '180t_mietubl',
      true,
      markSessionAuthenticated: true,
    );
    _finish(true);
  }

  void _finish(bool success) {
    if (_finished) return;
    _finished = true;
    _cleanup();
    _serial.setSuppressAutoHandshake(false);
    onHandshakeComplete(success);
  }

  void _cleanup() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _dataSubscription?.cancel();
    _dataSubscription = null;
  }

  void dispose() {
    _cleanup();
    _serial.setSuppressAutoHandshake(false);
  }
}
