import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/bluetooth_service.dart';
import 'handshake_response_resolver.dart';
import 'cut_file_transformer.dart';

/// Parsed FSIZE response from the DQ machine.
/// Machine sends this after receiving cut data: FSIZE=width,height;PAGE=X;
class DqFsizeInfo {
  final double widthMm;
  final double heightMm;
  final int? pageCount;

  const DqFsizeInfo({
    required this.widthMm,
    required this.heightMm,
    this.pageCount,
  });

  @override
  String toString() => 'FSIZE(${widthMm.toStringAsFixed(0)}x${heightMm.toStringAsFixed(0)}mm, pages=$pageCount)';
}

/// Result of a DQ cut operation.
class DqCutResult {
  final bool success;
  final DqFsizeInfo? fsizeInfo;
  final String? errorMessage;

  const DqCutResult({
    required this.success,
    this.fsizeInfo,
    this.errorMessage,
  });
}

/// Service that handles all DQ machine cutting operations.
///
/// DQ machines (serial starts with DQ, DX, LH, DH, HL, MT, 33) use a specific
/// protocol that differs from Sunshine/Forward machines:
///
/// Cutting flow (matches original Film_Cutter APK):
///   1. BD:10; → query machine status
///   2. RCMD=10,0;X,CHALLENGE → machine sends challenge
///   3. BD:12,response; → app sends computed handshake response
///   4. RCMD=12,0 → handshake accepted, machine ready
///   5. Send cut data (raw SJM/SJC bytes, chunked at 93 bytes)
///   6. Machine responds with FSIZE=W,H;PAGE=X; (dimensions + pages)
///   7. Machine cuts → RCMD=10,1; (busy)
///   8. Segment done → RCMD=12,0; → send next page if multi-page
///   9. All done → RCMD=10,0;X,NEW_CHALLENGE (idle)
///
/// Speed/Pressure: Configured separately via BD:100,10 (pressure 1-5) and
/// BD:100,11 (speed 1-4), NOT prepended to cut data.
class DqCutService {
  final CutterBluetoothService _bluetooth;

  // ─── Offline Cut Queue Keys ─────────────────────────────────────────────
  static const String _offlineCutQueueKey = 'dq_offline_cut_queue';
  static const String _offlineCutMaxKey = 'dq_offline_cut_max';
  static const int _defaultOfflineCutMax = 50;

  DqCutService(this._bluetooth);

  // ─── Machine Detection ──────────────────────────────────────────────────

  /// Returns true if the connected machine is a DQ-family device.
  static bool isDqMachine(String? serial) {
    final s = (serial ?? '').trim().toUpperCase();
    return s.startsWith('DX') ||
        s.startsWith('LH') ||
        s.startsWith('DH') ||
        s.startsWith('HL') ||
        s.startsWith('MT') ||
        s.startsWith('33');
  }

  bool get isConnectedDqMachine => isDqMachine(_bluetooth.serialNumber);

  // ─── Machine Status Check ───────────────────────────────────────────────

  /// Checks if the DQ machine is currently busy (cutting).
  /// Returns true if idle, false if busy.
  Future<bool> isMachineIdle({Duration timeout = const Duration(seconds: 3)}) async {
    if (!_bluetooth.isConnected) return false;

    final completer = Completer<bool>();
    String buffer = '';

    _bluetooth.setSuppressAutoHandshake(true);

    final sub = _bluetooth.receivedDataStream.listen((data) {
      buffer += data.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');
      while (buffer.contains(';')) {
        final end = buffer.indexOf(';');
        final msg = buffer.substring(0, end + 1).trim();
        buffer = buffer.substring(end + 1);

        if (msg.contains('RCMD=10,1')) {
          if (!completer.isCompleted) completer.complete(false);
        } else if (msg.contains('RCMD=10,0')) {
          if (!completer.isCompleted) completer.complete(true);
        }
      }
    });

    try {
      await _bluetooth.write(';BD:10;');
      return await completer.future.timeout(timeout, onTimeout: () => true);
    } finally {
      await sub.cancel();
      _bluetooth.setSuppressAutoHandshake(false);
    }
  }

  // ─── Pre-Cut Handshake ──────────────────────────────────────────────────

  /// Performs the DQ pre-cut handshake cycle.
  /// BD:10; → RCMD=10,0;challenge → BD:12,password → RCMD=12,0
  Future<bool> performPreCutHandshake({
    Duration timeout = const Duration(seconds: 10),
    void Function(String)? onStatus,
  }) async {
    final completer = Completer<bool>();
    String buffer = '';
    bool challengeResponded = false;

    _bluetooth.setSuppressAutoHandshake(true);
    onStatus?.call('Authenticating...');

    final sub = _bluetooth.receivedDataStream.listen((data) {
      buffer += data.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');

      while (buffer.contains(';')) {
        final end = buffer.indexOf(';');
        final msg = buffer.substring(0, end + 1).trim();
        buffer = buffer.substring(end + 1);

        if (msg.isEmpty) continue;
        print('🔧 DQ PreCut RX: $msg');

        if (msg.contains('RCMD=10,1')) {
          if (!completer.isCompleted) completer.complete(true);
          return;
        }
        if (msg.contains('RCMD=12,0')) {
          onStatus?.call('Authenticated');
          if (!completer.isCompleted) completer.complete(true);
          return;
        }
        if (msg.contains('RCMD=12,1')) {
          onStatus?.call('Authentication failed');
          if (!completer.isCompleted) completer.complete(false);
          return;
        }
        if (msg.contains('RCMD=10,0')) {
          continue;
        }

        if (!challengeResponded) {
          final challenge = _extractChallenge(msg);
          if (challenge != null) {
            challengeResponded = true;
            final algo = _bluetooth.successfulHandshakeType ?? 'DQ';
            final response = HandshakeResponseResolver.resolve(challenge, algo);
            _bluetooth.write(';BD:12,$response;');
            print('📤 DQ PreCut: challenge=$challenge → BD:12,$response;');
          }
        }
      }
    });

    try {
      await _bluetooth.write(';BD:10;');
      print('📤 DQ PreCut: Sent ;BD:10;');

      return await completer.future.timeout(
        timeout,
        onTimeout: () {
          print('⏰ DQ pre-cut handshake timeout');
          onStatus?.call('Timeout');
          return false;
        },
      );
    } finally {
      await sub.cancel();
      _bluetooth.setSuppressAutoHandshake(false);
    }
  }

  // ─── Cut Data Sending ───────────────────────────────────────────────────

  /// Sends cut data to a DQ machine (93-byte BLE chunks).
  Future<void> sendCutData(
    List<int> bytes, {
    int chunkSize = 93,
    int packetDelayMs = 20,
    void Function(String)? onStatus,
  }) async {
    if (bytes.isEmpty) throw Exception('Cut data is empty');
    if (!_bluetooth.isConnected) throw Exception('Not connected');

    onStatus?.call('Sending data...');
    print('📤 DQ: Sending ${bytes.length} bytes in $chunkSize-byte chunks');

    await _bluetooth.writeBytes(
      bytes,
      chunkSize: chunkSize,
      packetDelayMs: packetDelayMs,
      forceWithResponse: true,
    );

    print('✅ DQ: Data sent successfully');
  }

  // ─── FSIZE Parsing ──────────────────────────────────────────────────────

  /// Listens for FSIZE response from machine after data is sent.
  /// Format: FSIZE=width,height;PAGE=count; (units are /40 to get mm)
  Future<DqFsizeInfo?> waitForFsize({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final completer = Completer<DqFsizeInfo?>();
    String buffer = '';
    double? width;
    double? height;
    int? pageCount;

    final sub = _bluetooth.receivedDataStream.listen((data) {
      buffer += data.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');

      while (buffer.contains(';')) {
        final end = buffer.indexOf(';');
        final msg = buffer.substring(0, end + 1).trim();
        buffer = buffer.substring(end + 1);

        // Parse FSIZE=width,height;
        if (msg.contains('FSIZE=')) {
          final fsizeStr = msg.replaceAll('FSIZE=', '').replaceAll(';', '');
          final parts = fsizeStr.split(',');
          if (parts.length >= 2) {
            final rawW = int.tryParse(parts[0]);
            final rawH = int.tryParse(parts[1]);
            if (rawW != null && rawH != null) {
              width = rawW / 40.0;
              height = rawH / 40.0;
            }
          }
        }

        // Parse PAGE=count;
        if (msg.contains('PAGE=')) {
          final pageStr = msg.replaceAll('PAGE=', '').replaceAll(';', '').trim();
          pageCount = int.tryParse(pageStr);
        }

        // If we have FSIZE, complete (PAGE is optional)
        if (width != null && height != null && !completer.isCompleted) {
          completer.complete(DqFsizeInfo(
            widthMm: width!,
            heightMm: height!,
            pageCount: pageCount,
          ));
        }
      }
    });

    try {
      return await completer.future.timeout(timeout, onTimeout: () => null);
    } finally {
      await sub.cancel();
    }
  }

  // ─── Multi-Page Cut (RCMD=12,0 Loop) ───────────────────────────────────

  /// Executes a multi-page cut flow matching the original app.
  ///
  /// Original flow:
  /// 1. Send data for current page
  /// 2. Machine cuts → RCMD=10,1 (busy)
  /// 3. Segment done → RCMD=12,0 → app sends next page via S1()
  /// 4. Repeat until all pages sent
  /// 5. Cut fully done → RCMD=10,0 (idle + new challenge)
  ///
  /// For single-page files (most phone films), this just sends data once
  /// and waits for RCMD=10,0 completion.
  Future<DqCutResult> executeMultiPageCut({
    required List<int> cutBytes,
    bool mirror = false,
    int? materialWidthMm,
    int? materialHeightMm,
    void Function(String)? onStatus,
    Duration cutTimeout = const Duration(minutes: 5),
  }) async {
    if (!_bluetooth.isConnected) {
      return const DqCutResult(success: false, errorMessage: 'Not connected');
    }

    // Step 1: Clear buffer
    await _bluetooth.write(';;;');
    await Future.delayed(const Duration(milliseconds: 300));

    // Step 2: Optional mirror (only if user requested)
    if (mirror) {
      await sendMirror();
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // Step 3: Optional material size
    if (materialWidthMm != null && materialHeightMm != null) {
      await setMaterialSize(widthMm: materialWidthMm, heightMm: materialHeightMm);
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // Step 4: Send cut data
    onStatus?.call('Sending data...');
    await sendCutData(cutBytes, onStatus: onStatus);

    // Step 5: Wait for FSIZE response (machine acknowledges data)
    final fsize = await waitForFsize(timeout: const Duration(seconds: 5));
    if (fsize != null) {
      print('📐 DQ FSIZE: ${fsize.widthMm.toStringAsFixed(0)}x${fsize.heightMm.toStringAsFixed(0)}mm, pages=${fsize.pageCount}');
      onStatus?.call('Cutting (${fsize.widthMm.toStringAsFixed(0)}x${fsize.heightMm.toStringAsFixed(0)}mm)...');
    }

    // Step 6: Wait for cut completion
    // The machine sends RCMD=10,1 while busy, then:
    //   - RCMD=12,0 for each completed segment (multi-page loop handled by bluetooth_service)
    //   - RCMD=10,0 when fully idle (all pages done)
    onStatus?.call('Cutting...');
    final completed = await waitForCutCompletion(
      timeout: cutTimeout,
      onStatus: onStatus,
    );

    return DqCutResult(
      success: completed,
      fsizeInfo: fsize,
      errorMessage: completed ? null : 'Cut timeout',
    );
  }

  // ─── Wait for Cut Completion ────────────────────────────────────────────

  /// Waits for RCMD=10,0 (machine idle) after cutting.
  Future<bool> waitForCutCompletion({
    Duration timeout = const Duration(minutes: 5),
    Duration pollInterval = const Duration(seconds: 2),
    void Function(String)? onStatus,
  }) async {
    onStatus?.call('Cutting...');
    final completer = Completer<bool>();

    final sub = _bluetooth.parsedMessageStream.listen((msg) {
      if (msg.contains('RCMD=10,0') || msg.contains('RCMD=10, 0')) {
        print('🏁 DQ cut complete (RCMD=10,0)');
        if (!completer.isCompleted) completer.complete(true);
      }
    });

    final pollTimer = Timer.periodic(pollInterval, (_) {
      _bluetooth.write(';BD:10;');
    });

    try {
      return await completer.future.timeout(
        timeout,
        onTimeout: () {
          onStatus?.call('Timeout');
          return false;
        },
      );
    } finally {
      pollTimer.cancel();
      await sub.cancel();
    }
  }

  // ─── Machine Settings ───────────────────────────────────────────────────

  /// Sets DQ machine speed (1-4). Format: BD:100,11,X;BD:101,9;
  Future<void> setSpeed(int level) async {
    final clamped = level.clamp(1, 4);
    await _bluetooth.write(';BD:100,11,$clamped;BD:101,9;');
    print('⚙️ DQ Speed set to $clamped');
  }

  /// Sets DQ machine blade pressure (1-5). Format: BD:100,10,X;BD:101,9;
  Future<void> setPressure(int level) async {
    final clamped = level.clamp(1, 5);
    await _bluetooth.write(';BD:100,10,$clamped;BD:101,9;');
    print('⚙️ DQ Pressure set to $clamped');
  }

  /// Sends speed AND pressure to DQ machine.
  Future<void> applySpeedAndPressure({required int speed, required int pressure}) async {
    await setPressure(pressure);
    await Future.delayed(const Duration(milliseconds: 100));
    await setSpeed(speed);
  }

  /// Sets material size. Format: BD:33,height,width; (swapped from W*H)
  Future<void> setMaterialSize({required int widthMm, required int heightMm}) async {
    await _bluetooth.write(';BD:33,$heightMm,$widthMm;');
    print('⚙️ DQ Material size: ${heightMm}x${widthMm}mm');
  }

  /// Sends mirror command. Only call when user explicitly enables mirror.
  Future<void> sendMirror() async {
    await _bluetooth.write(';BD:8;');
    print('⚙️ DQ Mirror enabled');
  }

  /// Sends a test cut command.
  Future<void> sendTestCut() async {
    await _bluetooth.write(';BD:100,100;');
    print('🔪 DQ Test cut sent');
  }

  // ─── Full Cut Flow ──────────────────────────────────────────────────────

  /// Executes a complete DQ cut cycle matching the original app exactly:
  /// handshake → settings → send data → FSIZE → wait completion.
  Future<DqCutResult> executeCut({
    required List<int> cutBytes,
    bool mirror = false,
    int? materialWidthMm,
    int? materialHeightMm,
    int? speed,
    int? pressure,
    void Function(String)? onStatus,
  }) async {
    // Step 1: Check if machine is busy
    onStatus?.call('Checking machine...');
    final idle = await isMachineIdle();
    if (!idle) {
      return const DqCutResult(success: false, errorMessage: 'Machine is busy');
    }

    // Step 2: Pre-cut handshake
    onStatus?.call('Authenticating...');
    final handshakeOk = await performPreCutHandshake(onStatus: onStatus);
    if (!handshakeOk) {
      return const DqCutResult(success: false, errorMessage: 'Handshake failed');
    }

    // Step 3: Apply speed/pressure if provided
    if (speed != null && pressure != null) {
      await applySpeedAndPressure(speed: speed, pressure: pressure);
      await Future.delayed(const Duration(milliseconds: 200));
    }

    // Step 4: Execute the multi-page cut flow
    return await executeMultiPageCut(
      cutBytes: cutBytes,
      mirror: mirror,
      materialWidthMm: materialWidthMm,
      materialHeightMm: materialHeightMm,
      onStatus: onStatus,
    );
  }

  // ─── Prepare Cut Data ───────────────────────────────────────────────────

  /// Prepares raw file bytes for DQ machine cutting.
  CutPayloadPreparation prepareFileForCut({
    required List<int> inputBytes,
    int? maxWidth,
    double angleDegrees = 0.0,
    bool autoMirror = false,
  }) {
    return CutFileTransformer.prepareForMachine(
      inputBytes: inputBytes,
      maxWidth: maxWidth,
      angleDegrees: angleDegrees,
      autoMirror: autoMirror,
      isDqMachine: true,
    );
  }

  // ─── Max Width ──────────────────────────────────────────────────────────

  /// Queries machine max width via BD:100,20,0;
  Future<int?> queryMaxWidth({Duration timeout = const Duration(seconds: 3)}) async {
    if (!_bluetooth.isConnected) return null;

    final completer = Completer<int?>();
    String buffer = '';

    final sub = _bluetooth.receivedDataStream.listen((data) {
      buffer += data;
      while (buffer.contains(';')) {
        final end = buffer.indexOf(';');
        final msg = buffer.substring(0, end + 1);
        buffer = buffer.substring(end + 1);

        final match = RegExp(r'RCMD=100,20,?(\d+)').firstMatch(msg);
        if (match != null && !completer.isCompleted) {
          var width = int.tryParse(match.group(1) ?? '');
          if (width != null && width > 500) width = width ~/ 40;
          completer.complete(width);
        }
      }
    });

    try {
      await _bluetooth.write(';BD:100,20,0;');
      return await completer.future.timeout(timeout, onTimeout: () => null);
    } finally {
      await sub.cancel();
    }
  }

  // ─── Offline Cut Queue ──────────────────────────────────────────────────

  /// Records a cut operation locally for offline tracking.
  /// Matches original app's AppendBean mechanism.
  Future<void> recordOfflineCut({
    required String productId,
    required String serial,
    String? cutType,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_offlineCutQueueKey) ?? [];

    final entry = json.encode({
      'productId': productId,
      'serial': serial,
      'cutType': cutType ?? 'Y',
      'timestamp': DateTime.now().toIso8601String(),
    });

    queue.add(entry);
    await prefs.setStringList(_offlineCutQueueKey, queue);
    print('📝 DQ: Recorded offline cut (queue size: ${queue.length})');
  }

  /// Returns the number of pending offline cuts.
  Future<int> getOfflineCutCount() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_offlineCutQueueKey) ?? []).length;
  }

  /// Returns the max allowed offline cuts before requiring network sync.
  Future<int> getOfflineCutMax() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_offlineCutMaxKey) ?? _defaultOfflineCutMax;
  }

  /// Sets the max offline cut limit (from server config).
  Future<void> setOfflineCutMax(int max) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_offlineCutMaxKey, max);
  }

  /// Checks if we've exceeded the offline cut limit.
  Future<bool> isOfflineCutLimitReached() async {
    final count = await getOfflineCutCount();
    final max = await getOfflineCutMax();
    if (max <= 0) return false;
    return count >= max;
  }

  /// Gets all pending offline cuts for sync.
  Future<List<Map<String, dynamic>>> getPendingOfflineCuts() async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_offlineCutQueueKey) ?? [];
    return queue.map((e) {
      try {
        return json.decode(e) as Map<String, dynamic>;
      } catch (_) {
        return <String, dynamic>{};
      }
    }).where((e) => e.isNotEmpty).toList();
  }

  /// Clears the offline cut queue after successful sync.
  Future<void> clearOfflineCutQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_offlineCutQueueKey);
    print('🗑️ DQ: Offline cut queue cleared');
  }

  /// Removes a specific number of entries from the front of the queue.
  Future<void> removeOfflineCuts(int count) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_offlineCutQueueKey) ?? [];
    if (count >= queue.length) {
      await prefs.remove(_offlineCutQueueKey);
    } else {
      await prefs.setStringList(_offlineCutQueueKey, queue.sublist(count));
    }
  }

  // ─── Cut History ────────────────────────────────────────────────────────

  static const String _cutHistoryKey = 'dq_cut_history';
  static const int _maxHistoryEntries = 100;

  /// Records a cut in local history (matches original CutHistory JSON).
  Future<void> recordCutHistory({
    required String productId,
    String? productName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getString(_cutHistoryKey) ?? '[]';

    List<dynamic> history;
    try {
      history = json.decode(historyJson) as List<dynamic>;
    } catch (_) {
      history = [];
    }

    // Check if product already exists
    bool found = false;
    for (final entry in history) {
      if (entry is Map && entry['productId'] == productId) {
        entry['count'] = (entry['count'] ?? 0) + 1;
        entry['lastCut'] = DateTime.now().toIso8601String();
        found = true;
        break;
      }
    }

    if (!found) {
      history.add({
        'productId': productId,
        'productName': productName ?? '',
        'count': 1,
        'lastCut': DateTime.now().toIso8601String(),
      });
    }

    // Trim to max entries
    if (history.length > _maxHistoryEntries) {
      history = history.sublist(history.length - _maxHistoryEntries);
    }

    await prefs.setString(_cutHistoryKey, json.encode(history));
  }

  /// Gets cut history sorted by most recent.
  Future<List<Map<String, dynamic>>> getCutHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getString(_cutHistoryKey) ?? '[]';

    try {
      final history = (json.decode(historyJson) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .toList();
      history.sort((a, b) {
        final aTime = a['lastCut'] ?? '';
        final bTime = b['lastCut'] ?? '';
        return bTime.compareTo(aTime);
      });
      return history;
    } catch (_) {
      return [];
    }
  }

  // ─── Cut Counter ────────────────────────────────────────────────────────

  static const String _cutCounterKey = 'dq_total_cut_count';

  /// Increments and returns the total local cut counter.
  Future<int> incrementCutCounter() async {
    final prefs = await SharedPreferences.getInstance();
    final count = (prefs.getInt(_cutCounterKey) ?? 0) + 1;
    await prefs.setInt(_cutCounterKey, count);
    return count;
  }

  /// Returns the total local cut count.
  Future<int> getCutCounter() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_cutCounterKey) ?? 0;
  }

  // ─── Helpers ────────────────────────────────────────────────────────────

  int? _extractChallenge(String segment) {
    final parts = segment.replaceAll(';', '').split(',');
    for (final part in parts) {
      final val = int.tryParse(part.trim());
      if (val != null && val > 1000) return val;
    }
    return null;
  }
}
