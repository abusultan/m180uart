import 'dart:async';
import 'package:flutter_project/core/serial/serial_service.dart';
import 'package:flutter_project/core/serial/mietubl_handshake.dart';

/// Machine handshake dispatcher - for M180T, always uses MietublHandshake.
class MachineHandshake {
  static const String algoSunshine = "SUNSHINE";
  static const String algo180tMietubl = "180t_mietubl";

  static String? normalizeAlgorithm(String? algo) {
    if (algo == null || algo.trim().isEmpty) return null;
    return algo.trim().toUpperCase();
  }

  final CutterSerialService _serial;
  final Function(bool) onHandshakeComplete;
  final Function(String) onStatusUpdate;

  MietublHandshake? _internalHandshake;

  MachineHandshake(
    this._serial, {
    required this.onHandshakeComplete,
    required this.onStatusUpdate,
    String? forcedAlgorithm,
    String? preferredAlgorithm,
    String handshakeMode = 'auto',
    bool persistOnSuccess = true,
    int maxRounds = 1,
  });

  bool get isAuthenticated => _internalHandshake != null;

  void startHandshake() {
    _internalHandshake = MietublHandshake(
      _serial,
      onHandshakeComplete: onHandshakeComplete,
      onStatusUpdate: onStatusUpdate,
    );
    _internalHandshake!.startHandshake();
  }

  void dispose() {
    _internalHandshake?.dispose();
  }
}
