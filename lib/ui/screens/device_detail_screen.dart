import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/bluetooth_service.dart';
import '../../data/models/product_models.dart';
import '../../core/machine_handshake.dart';
import 'scan_screen.dart';
import '../../core/app_strings.dart';
import '../../services/cut_settings_service.dart';
import '../../core/cut_file_transformer.dart';
import 'cut_settings_screen.dart' as cut_settings_ui;
import '../widgets/svg_renderer_widget.dart';

class DeviceDetailScreen extends StatefulWidget {
  final ProductItem? productItem;

  const DeviceDetailScreen({super.key, this.productItem});

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  final CutterBluetoothService _bluetooth = CutterBluetoothService();
  final CutSettingsService _cutSettings = CutSettingsService();

  int _defaultSpeed = 15;
  int _defaultPressure = 10;
  bool _angleEnabled = false;
  double _angleValue = 0;
  CutPathData? _previewData;
  bool _previewLoading = false;
  bool _previewFailed = false;
  bool _isCutting = false;
  bool _isDownloading = false;
  String _status = "";
  File? _cutFile;
  bool _didInitLocalizedStatus = false;

  @override
  void initState() {
    super.initState();
    _checkConnection();
    _loadCutSettings().then((_) => _loadPreview());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitLocalizedStatus) return;
    _status = AppStrings.of(context, 'status_ready');
    _didInitLocalizedStatus = true;
  }

  void _checkConnection() {
    if (mounted) setState(() {});
  }

  Future<void> _loadCutSettings() async {
    final speed = await _cutSettings.getSpeed();
    final pressure = await _cutSettings.getPressure();
    final angleEnabled = await _cutSettings.getAngleEnabled();
    final angleValue = await _cutSettings.getAngleValue();
    if (!mounted) return;
    setState(() {
      _defaultSpeed = speed;
      _defaultPressure = pressure;
      _angleEnabled = angleEnabled;
      _angleValue = angleValue;
    });
  }

  Future<void> _loadPreview() async {
    if (widget.productItem == null || _previewLoading) return;

    if (mounted) {
      setState(() {
        _previewLoading = true;
        _previewFailed = false;
        _previewData = null;
      });
    }

    try {
      final isPltMachine = _usesPltFormat();

      String url = '';
      if (isPltMachine) {
        url = widget.productItem!.pltUrl.isNotEmpty
            ? widget.productItem!.pltUrl
            : widget.productItem!.sjcUrl;
      } else {
        url = widget.productItem!.sjcUrl.isNotEmpty
            ? widget.productItem!.sjcUrl
            : widget.productItem!.pltUrl;
      }

      url = ApiService().normalizeUrl(url);

      if (url.isEmpty ||
          url.endsWith('/storage') ||
          url.endsWith('/storage/')) {
        if (mounted)
          setState(() {
            _previewLoading = false;
          });
        return;
      }

      final file = await ApiService().downloadFile(url);
      if (file == null) {
        if (mounted)
          setState(() {
            _previewLoading = false;
            _previewFailed = true;
          });
        return;
      }

      _cutFile = file;
      final bytes = await file.readAsBytes();
      final data = CutFileTransformer.decodePathData(bytes);

      if (!mounted) return;

      if (data == null) {
        setState(() {
          _previewLoading = false;
        });
        return;
      }

      final rotated = (_angleEnabled && _angleValue != 0)
          ? CutFileTransformer.rotatePathData(data, -_angleValue)
          : data;

      final processed = _isMirroredMachine
          ? CutFileTransformer.mirrorPathData(rotated)
          : rotated;

      setState(() {
        _previewData = processed;
        _previewLoading = false;
      });
    } catch (e) {
      if (mounted)
        setState(() {
          _previewLoading = false;
          _previewFailed = true;
        });
    }
  }

  bool _usesPltFormat() {
    final serial = _bluetooth.serialNumber?.toUpperCase() ?? '';
    final agent = _bluetooth.cachedAgentType?.toUpperCase() ?? '';
    return serial.startsWith("DQ") ||
        serial.startsWith("DX") ||
        serial.startsWith("LH") ||
        agent == "ROCKSPACE_BLUE";
  }

  bool get _isMirroredMachine {
    final serial = _bluetooth.serialNumber?.toUpperCase() ?? '';
    final agent = _bluetooth.cachedAgentType?.toUpperCase() ?? '';
    bool isException =
        serial.startsWith("DQ") ||
        serial.startsWith("DX") ||
        serial.startsWith("LH") ||
        serial.startsWith("DH") ||
        agent == "ROCKSPACE_BLUE";
    return !isException;
  }

  Widget _buildPreview() {
    if (_previewLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF00FF88)),
      );
    }

    if (_previewData != null) {
      return Container(
        color: Colors.white,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: StaticCutPainter(_previewData!, color: Colors.black),
              ),
            ),
            _buildAngleBadge(),
          ],
        ),
      );
    }

    String imageUrl = widget.productItem?.imageUrl ?? '';

    if (imageUrl.isNotEmpty) {
      final isCutLine = imageUrl.toLowerCase().contains('.svg');
      final normalizedUrl = ApiService().normalizeUrl(imageUrl);
      return Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: Colors.white)),
          Positioned.fill(
            child: isCutLine
                ? SvgRenderer(url: imageUrl, isCutLine: true)
                : Image.network(
                    normalizedUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(
                        Icons.broken_image,
                        color: Colors.grey,
                        size: 50,
                      ),
                    ),
                  ),
          ),
          _buildAngleBadge(),
        ],
      );
    }

    if (_previewFailed) {
      return const Center(
        child: Icon(Icons.broken_image, color: Colors.grey, size: 50),
      );
    }

    return const Center(
      child: Icon(Icons.image_not_supported, color: Colors.grey, size: 50),
    );
  }

  Positioned _buildAngleBadge() {
    return Positioned(
      left: 16,
      top: 10,
      child: InkWell(
        onTap: () async {
          final newAngle = await cut_settings_ui.showAngleDialog(
            context,
            _angleValue,
          );
          if (newAngle == null) return;
          await _cutSettings.setAngleValue(newAngle);
          await _cutSettings.setAngleEnabled(true);
          if (!mounted) return;
          setState(() {
            _angleValue = newAngle;
            _angleEnabled = true;
          });
          await _loadPreview();
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _angleValue == 0 ? const Color(0xFF333333) : Colors.red,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white24),
          ),
          child: Text(
            AppStrings.of(
              context,
              'angle_display',
            ).replaceAll('{value}', _angleValue.toStringAsFixed(0)),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _startCut() async {
    final remaining = ApiService().currentUser?.remainingPieces ?? 0;
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context, 'error_not_enough_pieces')),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    _executeCut();
  }

  Future<void> _executeCut() async {
    if (_isCutting) return;

    if (_cutFile == null) {
      setState(
        () => _status = AppStrings.of(context, 'status_loading_cut_file'),
      );
      await _loadPreview();
      if (_cutFile == null) {
        setState(
          () => _status = AppStrings.of(context, 'status_file_not_found'),
        );
        return;
      }
    }

    setState(() {
      _isCutting = true;
      _status = AppStrings.of(context, 'status_verifying_balance');
    });

    try {
      final productIdForDecrement =
          widget.productItem?.productId ?? widget.productItem?.id ?? 0;
      if (productIdForDecrement <= 0) {
        throw Exception('Product ID is missing');
      }

      int? cutterIdForDecrement;
      final serialNumber = _bluetooth.serialNumber ?? '';
      if (serialNumber.isNotEmpty) {
        cutterIdForDecrement = await ApiService().getCutterIdBySerialNumber(
          serialNumber,
        );
      }

      final decrementResult = await ApiService().decrementRemainingPieces(
        productId: productIdForDecrement,
        cutterId: cutterIdForDecrement,
      );
      if (decrementResult['success'] != true) {
        final msg =
            decrementResult['message']?.toString() ??
            AppStrings.of(context, 'error_not_enough_pieces');
        if (mounted) {
          setState(() {
            _status = msg;
            _isCutting = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: Colors.red),
          );
        }
        return;
      }

      setState(() => _status = AppStrings.of(context, 'status_sync_handshake'));
      bool handshakeSuccess = await _performHandshakeSync();
      if (!handshakeSuccess)
        throw Exception(AppStrings.of(context, 'error_handshake_failed'));

      setState(() => _status = AppStrings.of(context, 'status_init_cut'));
      await _bluetooth.write(";;;");
      await Future.delayed(const Duration(milliseconds: 500));
      await _bluetooth.write("BD:110,3;");
      await Future.delayed(const Duration(milliseconds: 2000));
      await _bluetooth.write("BD:4,$_defaultSpeed;");
      await _bluetooth.write("BD:3,$_defaultPressure;");

      setState(() => _status = AppStrings.of(context, 'status_sending_data'));
      List<int> bytesToSend = await _cutFile!.readAsBytes();
      if (_angleEnabled && _angleValue != 0)
        bytesToSend = CutFileTransformer.applyAngleToBytes(
          inputBytes: bytesToSend,
          angleDegrees: _angleValue,
        );
      if (_isMirroredMachine)
        bytesToSend = CutFileTransformer.applyMirrorToBytes(
          inputBytes: bytesToSend,
        );

      if (_usesPltFormat()) {
        const int blockSize = 1024;
        int offset = 0;
        while (offset < bytesToSend.length) {
          int end = (offset + blockSize > bytesToSend.length)
              ? bytesToSend.length
              : offset + blockSize;
          await _bluetooth.writeBytes(
            bytesToSend.sublist(offset, end),
            forceWithResponse: true,
            chunkSize: 20,
            packetDelayMs: 60,
          );
          await Future.delayed(const Duration(milliseconds: 200));
          offset = end;
        }
      } else {
        await _bluetooth.writeBytes(bytesToSend);
      }

      await Future.delayed(const Duration(milliseconds: 1000));
      setState(() => _status = AppStrings.of(context, 'status_starting_cut'));
      await _bluetooth.write("BD:100,13;");
      setState(() {
        _status = AppStrings.of(context, 'status_cut_complete');
        _isCutting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context, 'msg_cut_success')),
          backgroundColor: Color(0xFF00FF88),
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted)
        setState(() {
          _status = "Error: $e";
          _isCutting = false;
        });
    }
  }

  Future<bool> _performHandshakeSync() async {
    final completer = Completer<bool>();
    final handshake = MachineHandshake(
      _bluetooth,
      onStatusUpdate: (s) => setState(() => _status = s),
      onHandshakeComplete: (s) => completer.complete(s),
    );
    handshake.startHandshake();
    return await completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isConnected = _bluetooth.isConnected || _bluetooth.isBypassMode;
    String name =
        widget.productItem?.nameEn ?? AppStrings.of(context, 'unknown_product');
    int remaining = ApiService().currentUser?.remainingPieces ?? 0;
    bool hasBalance = remaining > 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.of(context, 'cutter_control_title')),
        backgroundColor: Colors.transparent,
      ),
      backgroundColor: const Color(0xFF121212),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 1.2,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.black12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: _buildPreview(),
                ),
              ),
            ),
            const SizedBox(height: 30),
            Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              _status,
              style: TextStyle(
                color: isConnected ? Color(0xFF00FF88) : Colors.grey,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 60),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed:
                    _isCutting || _isDownloading || (!hasBalance && isConnected)
                    ? null
                    : () {
                        if (isConnected)
                          _startCut();
                        else
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ScanScreen(),
                            ),
                          ).then((_) => _checkConnection());
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isConnected
                      ? (hasBalance ? Color(0xFF00FF88) : const Color(0xFF666666))
                      : Color(0xFF333333),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _isCutting || _isDownloading
                    ? const CircularProgressIndicator(color: Colors.black)
                    : Text(
                        isConnected
                            ? (hasBalance
                                  ? AppStrings.of(context, 'send_to_cutter')
                                  : 'الرصيد صفر - لازم تشحن')
                            : AppStrings.of(context, 'connect_to_cutter'),
                        style: TextStyle(
                          color: isConnected && hasBalance
                              ? Colors.black
                              : Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            if (isConnected)
              Padding(
                padding: const EdgeInsets.only(top: 15),
                child: Text(
                  '${AppStrings.of(context, 'remaining_pieces')}: $remaining',
                  style: TextStyle(
                    color: hasBalance ? Color(0xFF00FF88) : Colors.red,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class StaticCutPainter extends CustomPainter {
  final CutPathData data;
  final Color color;
  StaticCutPainter(this.data, {required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final width = (data.maxX - data.minX).abs();
    final height = (data.maxY - data.minY).abs();
    if (width == 0 || height == 0) return;
    final scale = min(size.width / width, size.height / height) * 0.8;
    final offsetX = (size.width - width * scale) / 2;
    final offsetY = (size.height - height * scale) / 2;
    final path = Path();
    bool started = false;
    for (int i = 0; i < data.points.length; i++) {
      final p = data.points[i];
      final x = (p.dx - data.minX) * scale + offsetX;
      final y = (p.dy - data.minY) * scale + offsetY;
      if (!started || !data.drawFlags[i]) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant StaticCutPainter old) =>
      old.data != data || old.color != color;
}

