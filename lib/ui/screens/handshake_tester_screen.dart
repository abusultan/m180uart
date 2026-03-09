import 'package:flutter/material.dart';
import 'dart:async';
import '../../core/handshake_response_resolver.dart';
import '../../services/bluetooth_service.dart';

class HandshakeTesterScreen extends StatefulWidget {
  final String deviceId;
  final String deviceName;

  const HandshakeTesterScreen({
    super.key,
    required this.deviceId,
    required this.deviceName,
  });

  @override
  State<HandshakeTesterScreen> createState() => _HandshakeTesterScreenState();
}

class _HandshakeTesterScreenState extends State<HandshakeTesterScreen> {
  final _bluetooth = CutterBluetoothService();

  String? _serialNumber;
  int? _currentChallenge;
  bool _isTesting = false;
  final List<String> _logs = [];
  final ScrollController _scrollController = ScrollController();

  final List<AlgorithmTest> _algorithms = [
    AlgorithmTest(
      name: 'PassWord2 (Primary)',
      algorithm: HandshakeResponseResolver.algoPassWord2,
    ),
    AlgorithmTest(
      name: 'OldPassWord',
      algorithm: HandshakeResponseResolver.algoOldPassWord,
    ),
    AlgorithmTest(
      name: 'PassWord',
      algorithm: HandshakeResponseResolver.algoPassWord,
    ),
    AlgorithmTest(
      name: 'DQ Handshake',
      algorithm: HandshakeResponseResolver.algoDQHandshake,
    ),
    AlgorithmTest(
      name: 'Mechanic UART',
      algorithm: HandshakeResponseResolver.algoMechanicUart,
    ),
  ];

  StreamSubscription? _dataSubscription;
  String _messageBuffer = "";

  @override
  void initState() {
    super.initState();
    _startListening();
    _requestSerialNumber();
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _startListening() {
    _dataSubscription = _bluetooth.receivedDataStream.listen((data) {
      print("🔍 Tester RX: $data");
      _addLog("RX", data);

      _messageBuffer += data;

      while (_messageBuffer.contains(";")) {
        int endIndex = _messageBuffer.indexOf(";");
        String completeMessage = _messageBuffer.substring(0, endIndex + 1);
        _messageBuffer = _messageBuffer.substring(endIndex + 1);

        print("✅ Complete: $completeMessage");
        _processMessage(completeMessage);
      }
    });
  }

  void _addLog(String prefix, String message) {
    if (!mounted) return;
    setState(() {
      _logs.add("[$prefix] $message");
      if (_logs.length > 100) _logs.removeAt(0);
    });

    // Auto-scroll
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _processMessage(String message) {
    print("📨 Processing: $message");

    // Parse Serial Number from CBM/PID/RPID or bare serial
    if (message.contains("CBM=") ||
        message.contains("PID=") ||
        message.contains("RPID=")) {
      try {
        final cleaned = message.replaceAll(";", "");
        final parts = cleaned.split("=");
        if (parts.length >= 2) {
          final serial = parts[1].trim();
          if (serial.isNotEmpty) {
            setState(() {
              _serialNumber = serial;
            });
          }
        }
      } catch (e) {
        print("❌ Error parsing serial: $e");
      }
    } else if ((message.startsWith("SS") ||
            message.startsWith("DQ") ||
            message.startsWith("DX") ||
            message.startsWith("LH")) &&
        !message.contains("=")) {
      final serial = message.replaceAll(";", "").trim();
      if (serial.isNotEmpty) {
        setState(() {
          _serialNumber = serial;
        });
      }
    }

    // Parse Challenge
    if (message.contains("RCMD=11,")) {
      try {
        int start = message.indexOf("RCMD=11,") + 8;
        int end = message.indexOf(";", start);
        String numStr = message.substring(start, end).trim();
        setState(() {
          _currentChallenge = int.parse(numStr);
        });
        print("✅ Challenge: $_currentChallenge");
      } catch (e) {
        print("❌ Error parsing challenge: $e");
      }
    }

    // Check Response
    if (message.contains("RCMD=12,0")) {
      print("✅ Auth SUCCESS!");
      _markCurrentAsSuccess();
    } else if (message.contains("RCMD=12,1")) {
      print("❌ Auth FAILED!");
      _markCurrentAsFailed();
    }
  }

  void _requestSerialNumber() {
    _bluetooth.write(";RCBM;");
    _addLog("TX", ";RCBM;");
    Future.delayed(const Duration(milliseconds: 200), () {
      _bluetooth.write(";;;RPID;");
      _addLog("TX", ";;;RPID;");
    });
  }

  void _markCurrentAsSuccess() {
    if (_isTesting) {
      setState(() {
        for (var algo in _algorithms) {
          if (algo.status == TestStatus.testing) {
            algo.status = TestStatus.success;
            break;
          }
        }
        _isTesting = false;
      });
    }
  }

  void _markCurrentAsFailed() {
    if (_isTesting) {
      setState(() {
        for (var algo in _algorithms) {
          if (algo.status == TestStatus.testing) {
            algo.status = TestStatus.failed;
            break;
          }
        }
        _isTesting = false;
      });
    }
  }

  Future<void> _testAlgorithm(AlgorithmTest algo) async {
    if (_currentChallenge == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد Challenge! أرسل BD:10 أولاً')),
      );
      return;
    }

    setState(() {
      algo.status = TestStatus.testing;
      _isTesting = true;
    });

    final response = _calculateResponse(algo.algorithm, _currentChallenge!);
    print(
      "🧪 Testing ${algo.name}: Challenge=$_currentChallenge Response=$response",
    );

    _bluetooth.write("BD:12,$response;");
    _addLog("TX", "BD:12,$response; (${algo.name})");
  }

  int _calculateResponse(String algorithm, int challenge) {
    return HandshakeResponseResolver.resolveChallengeResponse(
      algorithm: algorithm,
      challenge: challenge,
    );
  }

  void _requestNewChallenge() {
    print('🔄 Requesting new challenge with BD:10;');
    _bluetooth.write('BD:10;');
    _addLog('TX', 'BD:10;');

    setState(() {
      _currentChallenge = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('اختبار Handshake'),
        backgroundColor: const Color(0xFF00FF88),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Machine Info Card
            Card(
              color: Colors.grey[900],
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'الماكينة: ${widget.deviceName}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'السيريال: ${_serialNumber ?? "جاري الحصول..."}',
                      style: TextStyle(color: Colors.grey[400]),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Challenge: ${_currentChallenge ?? "لا يوجد"}',
                      style: TextStyle(
                        color: _currentChallenge != null
                            ? const Color(0xFF00FF88)
                            : Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Request Challenge Button
            ElevatedButton.icon(
              onPressed: _requestNewChallenge,
              icon: const Icon(Icons.refresh),
              label: const Text('طلب Challenge جديد (BD:10)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00FF88),
                foregroundColor: Colors.black,
              ),
            ),
            const SizedBox(height: 16),

            // Algorithms List
            const Text(
              'الخوارزميات المتاحة:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            Expanded(
              flex: 2,
              child: ListView.builder(
                itemCount: _algorithms.length,
                itemBuilder: (context, index) {
                  // ... existing algo card logic
                  final algo = _algorithms[index];
                  return Card(
                    color: _getCardColor(algo.status),
                    child: ListTile(
                      leading: _getStatusIcon(algo.status),
                      title: Text(
                        algo.name,
                        style: const TextStyle(fontSize: 14),
                      ),
                      trailing: algo.status == TestStatus.pending
                          ? ElevatedButton(
                              onPressed:
                                  _currentChallenge != null && !_isTesting
                                      ? () => _testAlgorithm(algo)
                                      : null,
                              child: const Text('اختبر'),
                            )
                          : null,
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 16),

            // Logs (Terminal)
            const Text(
              'التيرمنال (Logs):',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              flex: 3,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[800]!),
                ),
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    final log = _logs[index];
                    final isRX = log.startsWith("[RX]");
                    return Text(
                      log,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: isRX ? const Color(0xFF00FF88) : Colors.amber,
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getCardColor(TestStatus status) {
    switch (status) {
      case TestStatus.pending:
        return Colors.grey[850]!;
      case TestStatus.testing:
        return Colors.blue[900]!;
      case TestStatus.success:
        return Colors.green[900]!;
      case TestStatus.failed:
        return Colors.red[900]!;
    }
  }

  Widget _getStatusIcon(TestStatus status) {
    switch (status) {
      case TestStatus.pending:
        return const Icon(Icons.radio_button_unchecked, color: Colors.grey);
      case TestStatus.testing:
        return const CircularProgressIndicator(color: Colors.blue);
      case TestStatus.success:
        return const Icon(Icons.check_circle, color: Colors.green);
      case TestStatus.failed:
        return const Icon(Icons.cancel, color: Colors.red);
    }
  }
}

class AlgorithmTest {
  final String name;
  final String algorithm;
  TestStatus status;

  AlgorithmTest({
    required this.name,
    required this.algorithm,
    this.status = TestStatus.pending,
  });
}

enum TestStatus { pending, testing, success, failed }
