import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../../core/cut_file_transformer.dart';
import '../../core/machine_handshake.dart';
import '../../data/models/product_models.dart';
import '../../services/api_service.dart';
import '../../services/bluetooth_service.dart';
import '../../services/cut_settings_service.dart';
import 'cut_settings_screen.dart' as cut_settings_ui;
import 'scan_screen.dart';
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
  String? _previewVisualUrl;
  bool _previewVisualIsSvg = false;
  bool _isCutting = false;
  final bool _isDownloading = false;
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

  String _normalizeHandshakeLabel(String? raw) {
    return (raw ?? '')
        .trim()
        .toUpperCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
  }

  Future<String> _resolveCutSettingsScope() async {
    final typeMachineName = _bluetooth.isConnected
        ? await _bluetooth.getTypeMachineNameForItems()
        : null;
    return CutSettingsService.resolveScopeForMachine(
      typeMachineName: typeMachineName,
      serialNumber: _bluetooth.serialNumber,
      agentType: _bluetooth.cachedAgentType,
    );
  }

  Future<void> _loadCutSettings() async {
    final settingsScope = await _resolveCutSettingsScope();
    final speed = await _cutSettings.getSpeed(scope: settingsScope);
    final pressure = await _cutSettings.getPressure(scope: settingsScope);
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
        _previewVisualUrl = null;
        _previewVisualIsSvg = false;
      });
    }

    try {
      String url = _resolveCutFileUrl();
      url = ApiService().normalizeUrl(url);

      if (url.isEmpty ||
          url.endsWith('/storage') ||
          url.endsWith('/storage/')) {
        if (mounted) {
          setState(() {
            _previewLoading = false;
          });
        }
        return;
      }

      final file = await ApiService().downloadFile(url);
      if (file == null) {
        if (mounted) {
          setState(() {
            _previewLoading = false;
            _previewFailed = true;
          });
        }
        return;
      }

      _cutFile = file;
      final rawBytes = await file.readAsBytes();
      if (_looksLikeSvgUrl(url) || _looksLikeSvgBytes(rawBytes)) {
        if (!mounted) return;
        setState(() {
          _previewVisualUrl = url;
          _previewVisualIsSvg = true;
          _previewLoading = false;
        });
        return;
      }

      final preparation = await _prepareCutPayload(
        allowMaxWidthRequest: _bluetooth.isConnected,
      );
      final data = preparation?.previewData;

      if (!mounted) return;

      if (data == null) {
        setState(() {
          _previewLoading = false;
        });
        return;
      }

      final rotated = (_angleEnabled &&
              _angleValue != 0 &&
              !(preparation?.appliedAngle ?? false))
          ? CutFileTransformer.rotatePathData(data, -_angleValue)
          : data;

      setState(() {
        _previewVisualUrl = null;
        _previewVisualIsSvg = false;
        _previewData = rotated;
        _previewLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _previewLoading = false;
          _previewFailed = true;
        });
      }
    }
  }

  String _resolveCutFileUrl() {
    final item = widget.productItem;
    if (item == null) return '';
    return item.resolveCutFileUrl(prefersPltFormat: _usesPltFormat());
  }

  bool _usesPltFormat() {
    final serial = _bluetooth.serialNumber?.toUpperCase() ?? '';
    final agent = _normalizedAgentType();
    return serial.startsWith("DQ") ||
        serial.startsWith("DX") ||
        serial.startsWith("LH") ||
        _isRockspaceAliasSerial(serial) ||
        _isDqFamilyAgent(agent) ||
        agent == "ROCKSPACE_BLUE";
  }

  bool get _isMirroredMachine {
    final serial = _bluetooth.serialNumber?.toUpperCase() ?? '';
    final agent = _normalizedAgentType();
    final isException = serial.startsWith("DQ") ||
        serial.startsWith("DX") ||
        serial.startsWith("LH") ||
        serial.startsWith("DH") ||
        _isRockspaceAliasSerial(serial) ||
        _isDqFamilyAgent(agent) ||
        agent == "ROCKSPACE_BLUE";
    return !isException;
  }

  String _normalizedAgentType() {
    return _normalizeAgentTypeValue(_bluetooth.cachedAgentType);
  }

  String _normalizeAgentTypeValue(String? value) {
    return (value ?? '')
        .trim()
        .toUpperCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
  }

  bool _isDqFamilyAgent(String agentType) {
    return agentType == 'DQ' || agentType == 'DX' || agentType == 'LH';
  }

  bool _isRockspaceAliasSerial(String serial) {
    return serial.startsWith("C180B") ||
        serial.startsWith("ZC2") ||
        serial.startsWith("ZC3");
  }

  bool _shouldAutoMirrorBytes(List<int> bytes) {
    if (CutFileTransformer.isSjcBytes(bytes)) {
      return false;
    }
    return _isMirroredMachine;
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
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.diagonal3Values(-1.0, 1.0, 1.0),
                child: CustomPaint(
                  painter: StaticCutPainter(_previewData!, color: Colors.black),
                ),
              ),
            ),
            _buildAngleBadge(),
          ],
        ),
      );
    }

    String imageUrl =
        _previewVisualUrl ?? widget.productItem?.preferredPreviewUrl ?? '';

    if (imageUrl.isNotEmpty) {
      final isSvg = _previewVisualIsSvg || _looksLikeSvgUrl(imageUrl);
      final normalizedUrl = ApiService().normalizeUrl(imageUrl);
      return Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: Colors.white)),
          Positioned.fill(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: isSvg
                  ? SvgRenderer(url: normalizedUrl, isCutLine: true)
                  : Image.network(
                      normalizedUrl,
                      fit: BoxFit.contain,
                      matchTextDirection: false,
                      errorBuilder: (_, __, ___) => const Center(
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

    if (_previewFailed) {
      return const Center(
        child: Icon(Icons.broken_image, color: Colors.grey, size: 50),
      );
    }

    return const Center(
      child: Icon(Icons.image_not_supported, color: Colors.grey, size: 50),
    );
  }

  bool _looksLikeSvgUrl(String value) {
    final lower = value.trim().toLowerCase();
    return lower.contains('.svg') ||
        lower.contains('image/svg') ||
        lower.contains('/svg');
  }

  bool _looksLikeSvgBytes(List<int> bytes) {
    if (bytes.isEmpty) return false;
    try {
      final sample = String.fromCharCodes(bytes.take(200));
      final lower = sample.toLowerCase();
      return lower.contains('<svg') || lower.contains('<?xml');
    } catch (_) {
      return false;
    }
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
    await _executeCut();
  }

  Future<void> _executeCut() async {
    if (_isCutting) return;

    final handshakeFailedMessage = AppStrings.of(
      context,
      'error_handshake_failed',
    );
    final fileNotFoundMessage = AppStrings.of(context, 'status_file_not_found');
    final notEnoughPiecesMessage = AppStrings.of(
      context,
      'error_not_enough_pieces',
    );

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

    bool restoreAutoHandshake = false;
    try {
      final productIdForDecrement =
          widget.productItem?.productId ?? widget.productItem?.id ?? 0;
      if (productIdForDecrement <= 0) {
        throw Exception('Product ID is missing');
      }

      int? cutterIdForDecrement;
      final settingsScope = await _resolveCutSettingsScope();
      final isSunshineScope = settingsScope == CutSettingsService.scopeSunshine;
      if (isSunshineScope) {
        _bluetooth.setSuppressAutoHandshake(true);
        _bluetooth.clearPendingRxBuffer();
        restoreAutoHandshake = true;
      }

      setState(() => _status = AppStrings.of(context, 'status_sync_handshake'));
      final handshakeSuccess = isSunshineScope
          ? await _performSunshineHandshakeSync()
          : await _performHandshakeSync();
      if (!handshakeSuccess) {
        throw Exception(handshakeFailedMessage);
      }

      final cutSpeed = _defaultSpeed;
      final cutPressure = _defaultPressure;
      final activeHandshake = (_bluetooth.successfulHandshakeType ??
              _bluetooth.cachedAgentType ??
              '')
          .trim()
          .toUpperCase();
      final shouldPrimeSunshineStandardCutSettings =
          isSunshineScope && activeHandshake == 'STANDARD';
      final shouldSendExplicitStartCommand =
          !(isSunshineScope && activeHandshake == 'STANDARD');

      setState(() => _status = AppStrings.of(context, 'status_init_cut'));
      if (!isSunshineScope) {
        await _bluetooth.write(";;;");
        await Future.delayed(const Duration(milliseconds: 500));
        await _bluetooth.write("BD:110,3;");
        await Future.delayed(const Duration(milliseconds: 2000));
      }

      if (settingsScope != CutSettingsService.scopeGeneric &&
          !isSunshineScope) {
        await _bluetooth.sendMachineSpeed(cutSpeed);
        await Future.delayed(const Duration(milliseconds: 120));
        await _bluetooth.sendMachinePressure(cutPressure);
      } else if (shouldPrimeSunshineStandardCutSettings) {
        await _bluetooth.write(
          ';BD:100,10,$cutPressure;BD:101,9;',
          packetDelayMs: 40,
        );
        await Future.delayed(const Duration(milliseconds: 150));
        await _bluetooth.write(
          ';BD:100,11,$cutSpeed;BD:101,9;',
          packetDelayMs: 40,
        );
        await Future.delayed(const Duration(milliseconds: 200));
      } else if (!isSunshineScope) {
        await _bluetooth.write("BD:4,$cutSpeed;");
        await _bluetooth.write("BD:3,$cutPressure;");
      }

      setState(() => _status = AppStrings.of(context, 'status_sending_data'));
      final preparation = await _prepareCutPayload(allowMaxWidthRequest: true);
      if (preparation == null) {
        throw Exception(fileNotFoundMessage);
      }
      final bytesToSend = preparation.bytes;

      debugPrint(
        'UART cut normalization: maxWidth=${preparation.maxWidth} '
        'settingsScope=$settingsScope '
        'usesPlt=${_usesPltFormat()} '
        'isSjc=${preparation.isSjcFile} '
        'autoMirror=${preparation.appliedMirror} '
        'angle=${preparation.appliedAngle} '
        'normalize=${preparation.shouldNormalizeSjc} '
        'rebaseWide=${preparation.rebasedWideSjcToOrigin} '
        'rebasePlt=${preparation.rebasedPltToOrigin} '
        'keepOriginalSjcPrefix=${preparation.keepsOriginalSjcPrefix}',
      );

      await Future.delayed(const Duration(milliseconds: 300));

      const int chunkSize = 2048;
      const int firstChunkSize = 256;
      int offset = 0;
      while (offset < bytesToSend.length) {
        final currentChunkSize = offset == 0 ? firstChunkSize : chunkSize;
        final end = (offset + currentChunkSize > bytesToSend.length)
            ? bytesToSend.length
            : offset + currentChunkSize;
        await _bluetooth.writeBytes(
          bytesToSend.sublist(offset, end),
          forceWithResponse: offset == 0,
          packetDelayMs: offset == 0 ? 40 : 20,
        );
        await Future.delayed(const Duration(milliseconds: 100));
        offset = end;
      }

      Future<Map<String, dynamic>> decrementRemainingPieces() async {
        final serialNumber = _bluetooth.serialNumber ?? '';
        if (serialNumber.isNotEmpty) {
          cutterIdForDecrement = await ApiService().getCutterIdBySerialNumber(
            serialNumber,
          );
        }
        return ApiService().decrementRemainingPieces(
          productId: productIdForDecrement,
          cutterId: cutterIdForDecrement,
        );
      }

      if (!isSunshineScope) {
        setState(
          () => _status = AppStrings.of(context, 'status_verifying_balance'),
        );
        final decrementResult = await decrementRemainingPieces();
        if (decrementResult['success'] != true) {
          final msg =
              decrementResult['message']?.toString() ?? notEnoughPiecesMessage;
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
      }

      await Future.delayed(
        Duration(milliseconds: isSunshineScope ? 150 : 1000),
      );
      setState(() => _status = AppStrings.of(context, 'status_starting_cut'));
      if (isSunshineScope) {
        _bluetooth.clearPendingRxBuffer();
      }
      if (shouldSendExplicitStartCommand) {
        await _bluetooth.write(
          "BD:100,13;",
          packetDelayMs: isSunshineScope ? 40 : 20,
        );
      }

      if (isSunshineScope) {
        unawaited(() async {
          final decrementResult = await decrementRemainingPieces();
          if (decrementResult['success'] != true) {
            debugPrint(
              'Sunshine decrement failed after cut start: ${decrementResult['message']}',
            );
          }
        }());
      }

      final cutCompleted = await _waitForMachineCutCompletion(
        gracePeriod:
            isSunshineScope ? const Duration(seconds: 2) : Duration.zero,
        requireStartAck: isSunshineScope,
      );
      if (cutCompleted) {
        if (!mounted) return;
        setState(() => _status = AppStrings.of(context, 'status_cut_complete'));
        await Future.delayed(const Duration(seconds: 2));
      }

      if (!mounted) return;
      setState(() {
        _status = AppStrings.of(context, 'status_cut_complete');
        _isCutting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم القص بنجاح'),
          backgroundColor: Color(0xFF00FF88),
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = "Error: $e";
          _isCutting = false;
        });
      }
    } finally {
      if (restoreAutoHandshake) {
        _bluetooth.setSuppressAutoHandshake(false);
      }
    }
  }

  Future<bool> _performHandshakeSync() async {
    if (_bluetooth.isBypassMode) {
      return true;
    }

    final reusableAlgorithm = await _bluetooth.getReusableHandshakeAlgorithm();
    final preferredSuccess = await _runHandshakeAttempt(
      forcedAlgorithm: reusableAlgorithm,
      handshakeMode: reusableAlgorithm != null ? "cached" : "auto",
    );
    if (preferredSuccess || reusableAlgorithm == null) {
      return preferredSuccess;
    }

    return _runHandshakeAttempt();
  }

  Future<bool> _performSunshineHandshakeSync() async {
    if (_bluetooth.isBypassMode) {
      return true;
    }

    final serial =
        _bluetooth.serialNumber ?? _bluetooth.systemInfo.serialNumber ?? '';
    String? preferredAlgorithm;

    if (serial.isNotEmpty && !_bluetooth.isUsingPidFallback) {
      final backendHandshake = await ApiService().getDeviceBySerialNumber(
        serial,
      );
      final normalizedBackend = _normalizeHandshakeLabel(backendHandshake);
      if (normalizedBackend.isNotEmpty) {
        preferredAlgorithm = normalizedBackend;
        await _bluetooth.cacheSuccessfulHandshake(
          normalizedBackend,
          false,
          mode: 'api',
          persist: false,
        );
      }
    }

    preferredAlgorithm ??= await _bluetooth.getReusableHandshakeAlgorithm(
      serial.isEmpty ? null : serial,
    );

    if (preferredAlgorithm != null && preferredAlgorithm.isNotEmpty) {
      final preferredSuccess = await _runHandshakeAttempt(
        forcedAlgorithm: preferredAlgorithm,
        handshakeMode: 'manual',
      );
      if (preferredSuccess) {
        return true;
      }
    }

    return _runHandshakeAttempt();
  }

  Future<bool> _runHandshakeAttempt({
    String? forcedAlgorithm,
    String handshakeMode = "auto",
  }) async {
    final completer = Completer<bool>();
    final handshake = MachineHandshake(
      _bluetooth,
      onStatusUpdate: (s) {
        if (!mounted) return;
        setState(() => _status = s);
      },
      onHandshakeComplete: (s) {
        if (!completer.isCompleted) {
          completer.complete(s);
        }
      },
      forcedAlgorithm: forcedAlgorithm,
      handshakeMode: handshakeMode,
    );
    handshake.startHandshake();
    try {
      return await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => false,
      );
    } finally {
      handshake.dispose();
    }
  }

  Future<CutPayloadPreparation?> _prepareCutPayload({
    required bool allowMaxWidthRequest,
  }) async {
    final file = _cutFile;
    if (file == null) {
      return null;
    }

    final rawBytes = await file.readAsBytes();
    final maxWidth = await _resolveMachineMaxWidth(
      allowDeviceRequest: allowMaxWidthRequest,
    );
    final settingsScope = await _resolveCutSettingsScope();
    final isSunshineScope = settingsScope == CutSettingsService.scopeSunshine;

    return CutFileTransformer.prepareForMachine(
      inputBytes: rawBytes,
      maxWidth: maxWidth,
      angleDegrees: _angleEnabled ? _angleValue : 0,
      autoMirror: _shouldAutoMirrorBytes(rawBytes),
      isSunshineMachine: isSunshineScope,
    );
  }

  Future<bool> _waitForMachineCutCompletion({
    Duration gracePeriod = Duration.zero,
    bool requireStartAck = false,
  }) async {
    final completer = Completer<bool>();
    final waitStartedAt = DateTime.now();
    var sawStartAck = !requireStartAck;
    late final StreamSubscription<String> subscription;
    subscription = _bluetooth.parsedMessageStream.listen((message) {
      final normalized = message.trim();
      if (!sawStartAck && normalized.contains('RCMD=13')) {
        sawStartAck = true;
        return;
      }
      if (DateTime.now().difference(waitStartedAt) < gracePeriod) {
        return;
      }
      final isCutDone =
          normalized == 'RCMD=10,0;' || normalized == 'RSTR=10,0;';
      if (isCutDone && !sawStartAck) {
        final waitedLongEnough = DateTime.now().difference(waitStartedAt) >=
            const Duration(seconds: 8);
        if (!waitedLongEnough) {
          return;
        }
      }
      if (isCutDone && !completer.isCompleted) {
        completer.complete(true);
      }
    });

    try {
      return await completer.future.timeout(
        const Duration(seconds: 90),
        onTimeout: () => false,
      );
    } finally {
      await subscription.cancel();
    }
  }

  Future<int?> _resolveMachineMaxWidth({bool allowDeviceRequest = true}) async {
    final currentWidth = _bluetooth.systemInfo.maxWidth;
    if (currentWidth != null && currentWidth > 0) {
      return currentWidth;
    }

    final cachedWidth = await _bluetooth.getCachedMaxWidth();
    if (cachedWidth != null && cachedWidth > 0) {
      return cachedWidth;
    }

    if (!allowDeviceRequest || !_bluetooth.isConnected) {
      return currentWidth ?? cachedWidth;
    }

    final completer = Completer<int?>();
    late final StreamSubscription subscription;
    subscription = _bluetooth.systemInfoStream.listen((info) {
      final width = info.maxWidth;
      if (width != null && width > 0 && !completer.isCompleted) {
        completer.complete(width);
      }
    });

    try {
      await _bluetooth.requestMaxWidth();
      return await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => _bluetooth.systemInfo.maxWidth ?? cachedWidth,
      );
    } finally {
      await subscription.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _bluetooth.isConnected || _bluetooth.isBypassMode;
    final name =
        widget.productItem?.nameEn ?? AppStrings.of(context, 'unknown_product');
    final remaining = ApiService().currentUser?.remainingPieces ?? 0;
    final hasBalance = remaining > 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.of(context, 'cutter_control_title')),
        backgroundColor: Colors.transparent,
      ),
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isLandscape = constraints.maxWidth > constraints.maxHeight;
            final contentPadding = isLandscape ? 14.0 : 24.0;
            final previewCard = Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(isLandscape ? 20 : 24),
                border: Border.all(color: Colors.black12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(isLandscape ? 20 : 24),
                child: _buildPreview(),
              ),
            );

            final actionButton = SizedBox(
              width: double.infinity,
              height: isLandscape ? 52 : 56,
              child: ElevatedButton(
                onPressed:
                    _isCutting || _isDownloading || (!hasBalance && isConnected)
                        ? null
                        : () {
                            if (isConnected) {
                              _startCut();
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const ScanScreen(),
                                ),
                              ).then((_) => _checkConnection());
                            }
                          },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isConnected
                      ? (hasBalance
                          ? const Color(0xFF00FF88)
                          : const Color(0xFF666666))
                      : const Color(0xFF333333),
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
            );

            final details = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isLandscape ? 18 : 20,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: isLandscape ? TextAlign.start : TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: isLandscape ? 8 : 10),
                Text(
                  _status,
                  style: TextStyle(
                    color: isConnected ? const Color(0xFF00FF88) : Colors.grey,
                    fontSize: isLandscape ? 12 : 13,
                  ),
                  textAlign: isLandscape ? TextAlign.start : TextAlign.center,
                  maxLines: isLandscape ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),
                actionButton,
                if (isConnected)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      '${AppStrings.of(context, 'remaining_pieces')}: $remaining',
                      style: TextStyle(
                        color:
                            hasBalance ? const Color(0xFF00FF88) : Colors.red,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            );

            if (isLandscape) {
              return Padding(
                padding: EdgeInsets.all(contentPadding),
                child: Row(
                  children: [
                    Expanded(
                      flex: 6,
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: 1.18,
                          child: previewCard,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(flex: 4, child: details),
                  ],
                ),
              );
            }

            return Padding(
              padding: EdgeInsets.all(contentPadding),
              child: Column(
                children: [
                  Expanded(
                    flex: 7,
                    child: Center(
                      child: AspectRatio(aspectRatio: 1.15, child: previewCard),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(flex: 4, child: details),
                ],
              ),
            );
          },
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
