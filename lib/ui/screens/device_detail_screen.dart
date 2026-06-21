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
import '../../core/cut_text_overlay_service.dart';
import '../widgets/text_overlay_interactive_viewer.dart';
import 'cut_text_overlay_sheet.dart';
import '../../core/dq_custom_cut.dart';
import '../../core/dq_cut_service.dart';
import 'dq_custom_cut_screen.dart';
import 'dq_text_on_cut_screen.dart';
import '../../core/sjm_cipher.dart';

class DeviceDetailScreen extends StatefulWidget {
  final ProductItem? productItem;

  const DeviceDetailScreen({super.key, this.productItem});

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  final CutterBluetoothService _bluetooth = CutterBluetoothService();
  late final DqCutService _dqCutService = DqCutService(_bluetooth);
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
  CutTextOverlaySpec? _catalogTextOverlay;
  String _settingsScope = CutSettingsService.scopeGeneric;

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
      _settingsScope = settingsScope;
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
      print('CUT_FILE_URL: $url');

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

  Future<void> _openCatalogTextOverlay() async {
    // For DQ SJM files: use dedicated screen with proper coordinate handling
    if (_cutFile != null && CutFileTransformer.isSjmBytes(await _cutFile!.readAsBytes())) {
      final bytes = await _cutFile!.readAsBytes();
      if (!mounted) return;
      final result = await Navigator.push<DqTextOnCutResult>(
        context,
        MaterialPageRoute(
          builder: (context) => DqTextOnCutScreen(cutFileBytes: bytes),
        ),
      );
      if (result != null && mounted) {
        // Replace cut file with merged version (for cutting)
        await _cutFile!.writeAsBytes(result.mergedBytes);
        // Decode merged file to show shape + text in preview
        final decoded = CutFileTransformer.decodePathData(result.mergedBytes);
        if (decoded != null && mounted) {
          setState(() {
            _previewData = decoded;
          });
        }
      } else if (mounted) {
        // User cancelled - clear any previous text overlay state
        setState(() {
          _catalogTextOverlay = null;
        });
      }
      return;
    }

    final result = await showCutTextOverlaySheet(
      context,
      initialSpec: _catalogTextOverlay,
    );
    if (result == null) return;
    if (result.cleared) {
      setState(() {
        _catalogTextOverlay = null;
      });
      return;
    }
    if (result.spec != null) {
      setState(() {
        _catalogTextOverlay = result.spec;
      });
    }
  }

  Future<void> _openDqCustomCut() async {
    if (_isCutting) return;

    final maxWidth = 190; // Default max width for DQ machines
    if (!mounted) return;

    final spec = await Navigator.push<DqCustomCutResult>(
      context,
      MaterialPageRoute(
        builder: (context) => DqCustomCutScreen(maxWidth: maxWidth),
      ),
    );

    if (!mounted || spec == null) {
      return;
    }

    await _executeDqCustomCut(spec);
  }

  Future<void> _executeDqCustomCut(DqCustomCutResult result) async {
    if (_isCutting) return;
    setState(() {
      _isCutting = true;
      _status = AppStrings.of(context, 'status_verifying_balance');
    });

    try {
      final buildResult = DqCustomCutBuilder.build(result.spec);

      final bytesToSend = buildResult.bytes;

      setState(() => _status = AppStrings.of(context, 'status_sending_data'));

      final cutSpeed = _defaultSpeed;
      final cutPressure = _defaultPressure;
      await _dqCutService.applySpeedAndPressure(speed: cutSpeed, pressure: cutPressure);

      setState(() => _status = AppStrings.of(context, 'status_sync_handshake'));
      final handshakeSuccess = await _dqCutService.performPreCutHandshake();
      if (!handshakeSuccess) {
        throw Exception(AppStrings.of(context, 'error_handshake_failed'));
      }

      await _dqCutService.sendCutData(bytesToSend);

      setState(() => _status = AppStrings.of(context, 'status_cutting'));
      final fsize = await _dqCutService.waitForFsize();
      await _dqCutService.recordCutHistory(
        productId: 'custom_cut',
        productName: 'Custom Cut ${result.spec.widthMm}x${result.spec.heightMm}',
      );
      await _dqCutService.incrementCutCounter();
      // Not recording offline cut to not decrement balance for Custom Cut since product ID is not set
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCutting = false;
          _status = AppStrings.of(context, 'status_idle');
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
        serial.startsWith("MT") ||
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
        serial.startsWith("MT") ||
        _isRockspaceAliasSerial(serial) ||
        _isDqFamilyAgent(agent) ||
        agent == "ROCKSPACE_BLUE";
    return !isException;
  }

  bool get _isMtDqMachine {
    final serial = _bluetooth.serialNumber?.trim().toUpperCase() ?? '';
    return serial.startsWith('MT');
  }

  bool get _isDqMachine {
    return _settingsScope == CutSettingsService.scopeDq;
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
    return agentType == 'DQ' ||
        agentType == 'DX' ||
        agentType == 'LH' ||
        agentType == 'DQ_HANDSHAKE' ||
        agentType == 'MECHANIC_UART' ||
        agentType == 'MECHANIC' ||
        agentType == 'PASS_U32' ||
        agentType == 'DEPASS_U32';
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
      final isSunshineScope = _settingsScope == CutSettingsService.scopeSunshine;
      return Container(
        color: Colors.white,
        child: Stack(
          children: [
            if (isSunshineScope && _catalogTextOverlay != null)
              Positioned.fill(
                child: TextOverlayEditor(
                  baseData: _previewData!,
                  spec: _catalogTextOverlay!,
                  transport: CutTextOverlayTransport.sunshineSjc,
                  flipX: true,
                  onSpecChanged: (newSpec) {
                    setState(() {
                      _catalogTextOverlay = newSpec;
                    });
                  },
                ),
              )
            else
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

      if (_isDqMachine) {
        setState(() => _status = AppStrings.of(context, 'status_sending_data'));
        final preparation = await _prepareCutPayload(allowMaxWidthRequest: true);
        if (preparation == null) throw Exception(fileNotFoundMessage);
        
        final cutSpeed = _defaultSpeed;
        final cutPressure = _defaultPressure;
        await _dqCutService.applySpeedAndPressure(speed: cutSpeed, pressure: cutPressure);
        
        setState(() => _status = AppStrings.of(context, 'status_sync_handshake'));
        final handshakeSuccess = await _dqCutService.performPreCutHandshake();
        if (!handshakeSuccess) throw Exception(handshakeFailedMessage);
        
        await _dqCutService.sendCutData(preparation.bytes);
        
        setState(() => _status = AppStrings.of(context, 'status_verifying_balance'));
        int? cutterIdForDecrement;
        if ((_bluetooth.serialNumber ?? '').isNotEmpty) {
          cutterIdForDecrement = await ApiService().getCutterIdBySerialNumber(_bluetooth.serialNumber!);
        }
        final decrementResult = await ApiService().decrementRemainingPieces(
          productId: productIdForDecrement,
          cutterId: cutterIdForDecrement,
        );
        if (decrementResult['success'] != true) {
          throw Exception(decrementResult['message']?.toString() ?? notEnoughPiecesMessage);
        }
        
        setState(() => _status = AppStrings.of(context, 'status_cutting'));
        final fsize = await _dqCutService.waitForFsize();
        await _dqCutService.recordCutHistory(
          productId: productIdForDecrement.toString(),
          productName: widget.productItem?.nameEn ?? 'Unknown DQ Product',
        );
        await _dqCutService.incrementCutCounter();
        await _dqCutService.recordOfflineCut(
          productId: productIdForDecrement?.toString() ?? '',
          serial: _bluetooth.serialNumber ?? '',
        );
        
        if (mounted) {
          setState(() {
            _isCutting = false;
            _status = AppStrings.of(context, 'status_idle');
          });
        }
        return;
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
      final useOriginalMtDqCutFlow = !isSunshineScope && _isMtDqMachine;
      final shouldPrimeSunshineStandardCutSettings =
          isSunshineScope && activeHandshake == 'STANDARD';
      final shouldSendExplicitStartCommand =
          !isSunshineScope &&
          !(isSunshineScope && activeHandshake == 'STANDARD') &&
          !useOriginalMtDqCutFlow;

      setState(() => _status = AppStrings.of(context, 'status_init_cut'));
      if (!isSunshineScope && !useOriginalMtDqCutFlow) {
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
      var bytesToSend = preparation.bytes;

      if (isSunshineScope && _catalogTextOverlay != null && _previewData != null) {
        final maxWidth = await _resolveMachineMaxWidth();
        try {
          final sunshineSpec = _catalogTextOverlay!.copyWith(
            flipHorizontally: true,
          );
          final overlayResult = CutTextOverlayService.build(
            baseData: _previewData!,
            spec: sunshineSpec,
            transport: CutTextOverlayTransport.sunshineSjc,
            maxWidth: maxWidth,
            preparedBytes: bytesToSend,
            flipX: false,
          );
          bytesToSend = overlayResult.bytes;
          debugPrint("Merged Sunshine SJC text overlay into bytesToSend successfully.");
        } catch (e) {
          debugPrint("Sunshine SJC text overlay merge failed: $e");
        }
      }

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

      // Send the entire file as a single write - exactly like the original
      // Sunshine app's sendNoBackLimit which writes all bytes at once
      await _bluetooth.writeBytes(
        bytesToSend,
        packetDelayMs: 400,
        chunkSize: 2048,
      );

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
                if (widget.productItem != null && (_settingsScope == CutSettingsService.scopeSunshine || _isDqMachine))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: SizedBox(
                      height: isLandscape ? 44 : 50,
                      child: OutlinedButton.icon(
                        onPressed: _openCatalogTextOverlay,
                        icon: Icon(
                          _catalogTextOverlay != null
                              ? Icons.edit
                              : Icons.text_fields,
                        ),
                        label: Text(
                          _catalogTextOverlay != null
                              ? '${AppStrings.of(context, 'text_overlay_title')}: ${_catalogTextOverlay!.text}'
                              : AppStrings.of(context, 'text_overlay_title'),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _catalogTextOverlay != null
                              ? const Color(0xFF00FF88)
                              : Colors.white70,
                          side: BorderSide(
                            color: _catalogTextOverlay != null
                                ? const Color(0xFF00FF88)
                                : Colors.white24,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_isDqMachine && widget.productItem == null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: SizedBox(
                      height: isLandscape ? 44 : 50,
                      child: OutlinedButton.icon(
                        onPressed: _openDqCustomCut,
                        icon: const Icon(Icons.crop_free),
                        label: Text(AppStrings.of(context, 'custom_cut') ?? 'Custom Cut'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white24),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ),
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
