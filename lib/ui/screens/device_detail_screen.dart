import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_svg/flutter_svg.dart' as svg;
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/svg_renderer.dart';
import '../../utils/svg_outline.dart';
import '../../services/bluetooth_service.dart';
import '../../data/models/product_models.dart';
import '../../core/machine_handshake.dart';
import 'scan_screen.dart';
import '../../core/app_strings.dart';
import '../../services/cut_settings_service.dart';
import '../../core/cut_file_transformer.dart';
import '../../ui/screens/cut_settings_screen.dart';

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
  bool _autoFeed = true;
  bool _angleEnabled = false;
  double _angleValue = 0;
  CutPathData? _previewData;
  CutPathData? _baseData;
  bool _previewLoading = false;
  bool _previewFailed = false;
  bool _isCutting = false;
  bool _isDownloading = false;
  String _status = "Ready";
  File? _cutFile;

  @override
  void initState() {
    super.initState();
    _checkConnection();
    _loadCutSettings().then((_) => _loadPreview());
  }

  void _checkConnection() {
    setState(() {}); // Refresh UI state based on connection
  }

  Future<void> _loadCutSettings() async {
    final speed = await _cutSettings.getSpeed();
    final pressure = await _cutSettings.getPressure();
    final autoFeed = await _cutSettings.getAutoFeed();
    final angleEnabled = await _cutSettings.getAngleEnabled();
    final angleValue = await _cutSettings.getAngleValue();
    if (!mounted) return;
    setState(() {
      _defaultSpeed = speed;
      _defaultPressure = pressure;
      _autoFeed = autoFeed;
      _angleEnabled = angleEnabled;
      _angleValue = angleValue;
    });
  }

  Future<void> _loadPreview() async {
    if (widget.productItem == null || _previewLoading) return;

    setState(() {
      _previewLoading = true;
      _previewFailed = false;
    });

    final isPltMachine = _usesPltFormat();

    String url;
    if (isPltMachine) {
      url = widget.productItem!.pltUrl.isNotEmpty
          ? widget.productItem!.pltUrl
          : widget.productItem!.sjcUrl;
    } else {
      url = widget.productItem!.sjcUrl.isNotEmpty
          ? widget.productItem!.sjcUrl
          : widget.productItem!.pltUrl;
    }

    if (url.isEmpty) {
      setState(() {
        _previewLoading = false;
        _previewFailed = true;
      });
      return;
    }

    final file = await ApiService().downloadFile(url);
    if (file == null) {
      setState(() {
        _previewLoading = false;
        _previewFailed = true;
      });
      return;
    }

    _cutFile ??= file;
    final bytes = await file.readAsBytes();
    final data = CutFileTransformer.decodePathData(bytes);

    if (!mounted) return;
    if (data == null) {
      setState(() {
        _previewLoading = false;
        _previewFailed = true;
      });
      return;
    }

    final rotated = (_angleEnabled && _angleValue != 0)
        ? CutFileTransformer.rotatePathData(data, -_angleValue)
        : data;

    setState(() {
      _baseData = data;
      _previewData = rotated;
      _previewLoading = false;
      _previewFailed = false;
    });
  }

  bool _usesPltFormat() {
    final serial = _bluetooth.serialNumber?.toUpperCase() ?? '';
    return serial.startsWith("DQ") ||
        serial.startsWith("DX") ||
        serial.startsWith("LH");
  }

  Future<void> _sendSpeedCommand(int level) async {
    await _bluetooth.write("BD:4,$level;");
  }

  Future<void> _sendPressureCommand(int level) async {
    await _bluetooth.write("BD:3,$level;");
  }

  Future<void> _sendAutoFeedCommand(bool enabled) async {
    final cmd = enabled ? ";BD:34,1;BD:34;" : ";BD:34,0;BD:34;";
    await _bluetooth.write(cmd);
  }

  Widget _buildPreview() {
    if (_previewLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF00FF88)),
      );
    }

    if (_previewData != null) {
      return Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: CutPreviewPainter(_previewData!)),
          ),
          _buildAngleBadge(),
        ],
      );
    }

    if (_previewFailed) {
      final imageUrl = _safeUrl(widget.productItem?.imageUrl ?? '');
      if (imageUrl.isNotEmpty) {
        if (imageUrl.toLowerCase().contains('.svg')) {
          return Stack(
            children: [
              Positioned.fill(
                child: Transform.rotate(
                  angle: -_angleValue * 3.141592653589793 / 180.0,
                  alignment: Alignment.center,
                  child: _buildSvgOutline(imageUrl),
                ),
              ),
              _buildAngleBadge(),
            ],
          );
        }
        return Stack(
          children: [
            Positioned.fill(
              child: Transform.rotate(
                angle: -_angleValue * 3.141592653589793 / 180.0,
                alignment: Alignment.center,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (c, e, s) => const Center(
                    child: Icon(
                      Icons.broken_image,
                      color: Colors.grey,
                      size: 50,
                    ),
                  ),
                ),
              ),
            ),
            _buildAngleBadge(),
          ],
        );
      }
      return const Center(
        child: Icon(Icons.broken_image, color: Colors.grey, size: 50),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildSvgOutline(String url) {
    return FutureBuilder<File?>(
      future: ApiService().downloadFile(url),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF00FF88)),
          );
        }
        final file = snapshot.data;
        if (file == null) {
          return svg.SvgPicture.network(
            url,
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            placeholderBuilder: (context) => const Center(
              child: CircularProgressIndicator(color: Color(0xFF00FF88)),
            ),
          );
        }
        if (Platform.isAndroid) {
          return FutureBuilder<Uint8List>(
            future: file.readAsBytes(),
            builder: (context, bytesSnap) {
              if (bytesSnap.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFF00FF88)),
                );
              }
              final bytes = bytesSnap.data;
              if (bytes == null || bytes.isEmpty) {
                return const Center(
                  child: Icon(Icons.broken_image, color: Colors.grey, size: 50),
                );
              }
              return LayoutBuilder(
                builder: (context, constraints) {
                  final dpr = MediaQuery.of(context).devicePixelRatio;
                  final width = constraints.maxWidth.isFinite
                      ? constraints.maxWidth
                      : 260.0;
                  final height = constraints.maxHeight.isFinite
                      ? constraints.maxHeight
                      : 260.0;
                  final widthPx = (width * dpr).clamp(1, 2048).toInt();
                  final heightPx = (height * dpr).clamp(1, 2048).toInt();
                  return FutureBuilder<Uint8List?>(
                    future: SvgRenderer.renderSvgBytesToPng(
                      bytes,
                      width: widthPx,
                      height: heightPx,
                    ),
                    builder: (context, pngSnap) {
                      if (pngSnap.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF00FF88),
                          ),
                        );
                      }
                      final png = pngSnap.data;
                      if (png == null) {
                        return const Center(
                          child: Icon(
                            Icons.broken_image,
                            color: Colors.grey,
                            size: 50,
                          ),
                        );
                      }
                      return Image.memory(
                        png,
                        fit: BoxFit.contain,
                        width: double.infinity,
                        height: double.infinity,
                        gaplessPlayback: true,
                      );
                    },
                  );
                },
              );
            },
          );
        }

        return FutureBuilder<Uint8List>(
          future: file.readAsBytes(),
          builder: (context, svgSnap) {
            if (svgSnap.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFF00FF88)),
              );
            }
            final bytes = svgSnap.data;
            if (bytes == null || bytes.isEmpty) {
              return const Center(
                child: Icon(Icons.broken_image, color: Colors.grey, size: 50),
              );
            }
            final svgText = decodeSvgBytes(bytes);
            if (svgText.isEmpty) {
              return const Center(
                child: Icon(Icons.broken_image, color: Colors.grey, size: 50),
              );
            }
            final outlineSvg = Platform.isIOS
                ? toOutlineSvgHeavy(svgText)
                : _toOutlineSvg(svgText);
            return svg.SvgPicture.string(
              outlineSvg,
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
              allowDrawingOutsideViewBox: true,
              clipBehavior: Clip.none,
              errorBuilder: (context, error, stackTrace) {
                final fallbackSvg = Platform.isIOS
                    ? toOutlineSvgLight(svgText)
                    : _toOutlineSvg(svgText);
                return svg.SvgPicture.string(
                  fallbackSvg,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                  allowDrawingOutsideViewBox: true,
                  clipBehavior: Clip.none,
                  errorBuilder: (c, e, s) => const Center(
                    child: Icon(
                      Icons.broken_image,
                      color: Colors.grey,
                      size: 50,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  String _safeUrl(String url) {
    if (url.isEmpty) return url;
    return ApiService().normalizeUrl(url);
  }

  String _toOutlineSvg(String svg) => toOutlineSvg(svg);

  Positioned _buildAngleBadge() {
    return Positioned(
      left: 16,
      top: 16,
      child: InkWell(
        onTap: () async {
          final newAngle = await showAngleDialog(context, _angleValue);
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _angleValue == 0 ? const Color(0xFF00AEEF) : Colors.red,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'Angle(${_angleValue.toStringAsFixed(1)}°)',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _downloadFile() async {
    if (widget.productItem == null) return;

    setState(() {
      _isDownloading = true;
      _status = AppStrings.of(context, 'status_downloading');
    });

    // Logic: Try PLT for DQ/DX/LH machines, SJC for others.
    final isPltMachine = _usesPltFormat();

    String url;
    if (isPltMachine) {
      url = widget.productItem!.pltUrl.isNotEmpty
          ? widget.productItem!.pltUrl
          : widget.productItem!.sjcUrl;
    } else {
      url = widget.productItem!.sjcUrl.isNotEmpty
          ? widget.productItem!.sjcUrl
          : widget.productItem!.pltUrl;
    }

    if (url.isEmpty) {
      setState(() {
        _isDownloading = false;
        _status = AppStrings.of(context, 'status_no_file');
      });
      return;
    }

    final file = await ApiService().downloadFile(url);
    if (file != null) {
      _cutFile = file;
      setState(() {
        _isDownloading = false;
        _status = AppStrings.of(context, 'status_file_ready');
      });
      _startCut();
    } else {
      setState(() {
        _isDownloading = false;
        _status = AppStrings.of(context, 'status_download_failed');
      });
    }
  }

  Future<void> _startCut() async {
    // 0. Pre-check Remaining Pieces (Local)
    final remaining = ApiService().currentUser?.remainingPieces ?? 0;
    if (remaining <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context, 'error_not_enough_pieces')),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_cutFile == null) {
      // Trigger download first
      _downloadFile();
      return;
    }

    if (_isCutting) return;

    setState(() {
      _isCutting = true;
      _status = AppStrings.of(context, 'status_verifying_balance');
    });

    try {
      // 0.5. Call API to Record Use (Deduct Balance) - Gatekeeper
      // If this fails (e.g. server says no pieces), we stop.
      if (widget.productItem != null) {
        final serial = _bluetooth.serialNumber ?? '';
        await ApiService().recordCutterUse(
          widget.productItem!.id.toString(),
          serial,
        );
        // If we are here, it succeeded. Local balance is updated by ApiService.
        setState(() {}); // Refresh UI for new balance
      }

      setState(() => _status = AppStrings.of(context, 'status_sync_handshake'));

      // 0. Perform Handshake Sync (Targeted re-handshake)
      // This ensures we have a valid challenge/password session before starting.
      bool handshakeSuccess = await _performHandshakeSync();
      if (!handshakeSuccess) {
        throw Exception(AppStrings.of(context, 'error_handshake_failed'));
      }
      if (!mounted) return;

      final isPltMachine = _usesPltFormat();
      final isPhonefilmMode = _bluetooth.lastHandshakeMode == 'phonefilm';

      setState(() => _status = AppStrings.of(context, 'status_init_cut'));
      // 1. Clear Buffer
      // Use ;;; instead of ;RCBM; to avoid resetting the machine/auth state.
      // This ensures we stay authenticated for consecutive cuts.
      await _bluetooth.write(";;;");
      if (!mounted) return;
      setState(
        () => _status = AppStrings.of(context, 'status_clearing_buffer'),
      );
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;

      // 2. Home
      setState(() => _status = AppStrings.of(context, 'status_homing'));
      await _bluetooth.write("BD:110,3;");
      await Future.delayed(const Duration(milliseconds: 2000));
      if (!mounted) return;

      // 3. Set Params (speed/pressure)
      if (!isPhonefilmMode) {
        await _bluetooth.write("BD:4,$_defaultSpeed;");
        await _bluetooth.write("BD:3,$_defaultPressure;");
        await Future.delayed(const Duration(milliseconds: 200));
      }

      // 4. Send File Data
      setState(() => _status = AppStrings.of(context, 'status_sending_data'));

      // Determine machine type from serial
      List<int> bytesToSend;

      if (isPltMachine) {
        // DQ/DX/LH Machines: Original Java code sends RAW bytes.
        // We suspect previous "Wrong Cutting" was due to Packet Loss (missing digits).
        // We are sending RAW bytes now with improved Bluetooth reliability.
        bytesToSend = await _cutFile!.readAsBytes();
        print("PLT machine detected. Sending RAW bytes (Java behavior).");
      } else {
        // Standard Machines: Read bytes directly (User confirmed SRC/SJC file for Sunshine New)
        // Reverted PLT encryption as per user feedback
        bytesToSend = await _cutFile!.readAsBytes();
      }

      if (_angleEnabled && _angleValue != 0) {
        bytesToSend = CutFileTransformer.applyAngleToBytes(
          inputBytes: bytesToSend,
          angleDegrees: _angleValue,
        );
      }

      if (!isPltMachine && isPhonefilmMode) {
        bytesToSend = CutFileTransformer.applyPhonefilmSpeedPressure(
          inputBytes: bytesToSend,
          speed: _defaultSpeed,
          pressure: _defaultPressure,
        );
      }

      if (isPltMachine) {
        // Upprint-style: send the full PLT payload in one write after handshake.
        await _bluetooth.writeBytes(
          bytesToSend,
          chunkSize: bytesToSend.length,
          packetDelayMs: 0,
        );
      } else {
        final blockSize = 2048;
        final delayMs = isPhonefilmMode ? 400 : 50;
        int offset = 0;
        while (offset < bytesToSend.length) {
          if (!mounted) return;
          int end = offset + blockSize;
          if (end > bytesToSend.length) end = bytesToSend.length;
          final chunk = bytesToSend.sublist(offset, end);
          await _bluetooth.writeBytes(
            chunk,
            chunkSize: chunk.length,
            packetDelayMs: 0,
          );
          if (delayMs > 0) {
            await Future.delayed(Duration(milliseconds: delayMs));
          }
          offset = end;
        }
      }

      // 5. Start Cut Command
      await Future.delayed(const Duration(milliseconds: 1000));
      if (!mounted) return;

      setState(() => _status = AppStrings.of(context, 'status_starting_cut'));
      await _bluetooth.write("BD:100,13;");

      setState(() {
        _status = AppStrings.of(context, 'status_cut_started');
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
      String errorMsg = e.toString();
      if (errorMsg.contains("Exception:")) {
        errorMsg = errorMsg.replaceAll("Exception:", "").trim();
      }

      setState(() {
        _status = "Error: $errorMsg";
        _isCutting = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error: $errorMsg"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isConnected = _bluetooth.isConnected;
    String name =
        widget.productItem?.nameEn ?? AppStrings.of(context, 'unknown_product');

    int remaining = ApiService().currentUser?.remainingPieces ?? 0;
    bool hasBalance = remaining > 0;

    final sizeText = _previewData == null
        ? null
        : "W:${(_previewData!.maxX - _previewData!.minX).abs().round()} "
              "L:${(_previewData!.maxY - _previewData!.minY).abs().round()} mm";

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.of(context, 'cutter_control_title')),
        backgroundColor: Colors.transparent,
      ),
      backgroundColor: const Color(0xFF121212),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Preview
                      if (sizeText != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10.0),
                          child: Stack(
                            children: [
                              Center(
                                child: Text(
                                  sizeText,
                                  style: const TextStyle(
                                    color: Colors.black54,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 0,
                                top: -6,
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.favorite_border,
                                    color: Colors.grey,
                                  ),
                                  onPressed: () {},
                                ),
                              ),
                            ],
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: AspectRatio(
                          aspectRatio: 1.4,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(
                                  color: const Color(0xFFDDDDDD),
                                  width: 1,
                                ),
                              ),
                              child: _buildPreview(),
                            ),
                          ),
                        ),
                      ),

                      // Product Info
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),

                      // Status Card
                      /*
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isConnected
                        ? [const Color(0xFF00FF88), const Color(0xFF00C853)]
                        : [Colors.grey, Colors.grey.shade700],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Icon(
                      isConnected
                          ? Icons.bluetooth_connected
                          : Icons.bluetooth_disabled,
                      size: 48,
                      color: Colors.black,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isConnected
                          ? (_status == "Ready" ? "Connected" : _status)
                          : "Disconnected",
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              */
                      const SizedBox(height: 40),

                      // Connected Controls are now in Cut Settings
                      const Spacer(),

                      // Action Button (bottom)
                      SizedBox(
                        height: 56,
                        child: ElevatedButton(
                          onPressed:
                              _isCutting ||
                                  _isDownloading ||
                                  (!hasBalance && isConnected)
                              ? null
                              : () {
                                  if (isConnected) {
                                    _startCut();
                                  } else {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const ScanScreen(),
                                      ),
                                    ).then((_) => _checkConnection());
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: !hasBalance && isConnected
                                ? Colors.red.shade900
                                : (isConnected
                                      ? const Color(0xFF00FF88)
                                      : const Color(0xFF444444)),
                            foregroundColor: isConnected && hasBalance
                                ? Colors.black
                                : Colors.white,
                            disabledBackgroundColor: Colors.grey.shade800,
                            elevation: 5,
                          ),
                          child: _isCutting || _isDownloading
                              ? const CircularProgressIndicator(
                                  color: Colors.black,
                                )
                              : Text(
                                  !hasBalance && isConnected
                                      ? AppStrings.of(
                                          context,
                                          'not_enough_pieces',
                                        )
                                      : (isConnected
                                            ? AppStrings.of(
                                                context,
                                                'send_to_cutter',
                                              )
                                            : AppStrings.of(
                                                context,
                                                'connect_to_cutter',
                                              )),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),

                      if (isConnected)
                        Padding(
                          padding: const EdgeInsets.only(top: 12.0),
                          child: Text(
                            "${AppStrings.of(context, 'remaining')}: $remaining",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: hasBalance
                                  ? const Color(0xFF00FF88)
                                  : Colors.red,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<bool> _performHandshakeSync() async {
    if (_usesPltFormat()) {
      return await _bluetooth.performPrintHandshakeDQ();
    }

    final completer = Completer<bool>();

    final handshake = MachineHandshake(
      _bluetooth,
      onStatusUpdate: (status) {
        if (mounted) setState(() => _status = status);
      },
      onHandshakeComplete: (success) {
        if (!completer.isCompleted) completer.complete(success);
      },
    );

    handshake.startHandshake();

    // Safety timeout of 15 seconds (should be fast if cached)
    return await completer.future
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            handshake.dispose();
            return false;
          },
        )
        .then((val) {
          handshake.dispose();
          return val;
        });
  }
}

class CutPreviewPainter extends CustomPainter {
  CutPreviewPainter(this.data);

  final CutPathData data;

  @override
  void paint(Canvas canvas, Size size) {
    final width = data.maxX - data.minX;
    final height = data.maxY - data.minY;
    if (width == 0 || height == 0) return;

    const padding = 16.0;
    final scaleX = (size.width - padding * 2) / width;
    final scaleY = (size.height - padding * 2) / height;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    final drawWidth = width * scale;
    final drawHeight = height * scale;
    final offsetX = (size.width - drawWidth) / 2;
    final offsetY = (size.height - drawHeight) / 2;

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

    final paint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CutPreviewPainter oldDelegate) {
    return oldDelegate.data != data;
  }
}
