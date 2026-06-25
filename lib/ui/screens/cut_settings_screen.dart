import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import '../../services/cut_settings_service.dart';
import 'package:flutter_project/core/serial/serial_service.dart';
import '../../services/app_settings_service.dart';
import '../../core/app_strings.dart';

Future<double?> showAngleDialog(
  BuildContext context,
  double currentValue,
) async {
  final controller = TextEditingController(
    text: currentValue.toStringAsFixed(1),
  );
  return showDialog<double>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: Text(
        AppStrings.of(context, 'set_angle_title'),
        style: const TextStyle(color: Colors.white),
      ),
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: AppStrings.of(context, 'angle_hint'),
          hintStyle: const TextStyle(color: Colors.grey),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            AppStrings.of(context, 'cancel'),
            style: const TextStyle(color: Colors.grey),
          ),
        ),
        TextButton(
          onPressed: () {
            final value = double.tryParse(controller.text.trim());
            if (value == null || value < -45 || value > 45) {
              Navigator.pop(context);
              return;
            }
            Navigator.pop(context, value);
          },
          child: Text(
            AppStrings.of(context, 'save'),
            style: const TextStyle(color: Color(0xFF00FF88)),
          ),
        ),
      ],
    ),
  );
}

class CutSettingsScreen extends StatefulWidget {
  const CutSettingsScreen({super.key});

  @override
  State<CutSettingsScreen> createState() => _CutSettingsScreenState();
}

class _CutSettingsScreenState extends State<CutSettingsScreen> {
  static const String _updateManifestUrl = 'https://anti-crash.com/m180t_version.json';
  static const String _updateApkUrl = 'https://anti-crash.com/m180update.apk';

  final CutSettingsService _settings = CutSettingsService();
  final CutterSerialService _bluetooth = CutterSerialService();
  final AppSettingsService _appSettings = AppSettingsService();
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(minutes: 5),
      sendTimeout: const Duration(seconds: 20),
    ),
  );
  StreamSubscription<String>? _machineDataSub;
  String _machineDataBuffer = '';

  bool _loading = true;
  bool _autoUpdateEnabled = false;
  bool _updateBusy = false;
  bool _autoUpdateCheckTriggered = false;
  String _settingsScope = CutSettingsService.scopeGeneric;
  int _speed = CutSettingsService.defaultSpeed;
  int _pressure = CutSettingsService.defaultPressure;
  bool _autoFeed = CutSettingsService.defaultAutoFeed;
  bool _angleEnabled = CutSettingsService.defaultAngleEnabled;
  double _angleValue = CutSettingsService.defaultAngleValue;
  bool _forceLandscape = false;
  int _installedVersionCode = 0;
  String _installedVersionName = '';
  String? _updateStatus;
  String? _handshakeAlgo;
  int _speedMax = CutSettingsService.maxSpeedForScope(
    CutSettingsService.scopeGeneric,
  );
  int _pressureMax = CutSettingsService.maxPressureForScope(
    CutSettingsService.scopeGeneric,
  );

  @override
  void initState() {
    super.initState();
    _machineDataSub = _bluetooth.receivedDataStream.listen(_handleMachineData);
    _load();
  }

  @override
  void dispose() {
    _machineDataSub?.cancel();
    super.dispose();
  }

  Future<String> _resolveSettingsScope() async {
    final typeMachineName = _bluetooth.isConnected
        ? await _bluetooth.getTypeMachineNameForItems()
        : null;
    return CutSettingsService.resolveScopeForMachine(
      typeMachineName: typeMachineName,
      serialNumber: _bluetooth.serialNumber,
      agentType: _bluetooth.cachedAgentType,
    );
  }

  Future<void> _requestDqSettingsSnapshot() async {
    if (!_bluetooth.isConnected) return;
    await _bluetooth.write(';BD:101,9;');
  }

  Future<void> _handleMachineData(String data) async {
    if (_settingsScope != CutSettingsService.scopeDq) return;

    _machineDataBuffer += data;
    while (_machineDataBuffer.contains(';')) {
      final endIndex = _machineDataBuffer.indexOf(';');
      final message = _machineDataBuffer.substring(0, endIndex + 1);
      _machineDataBuffer = _machineDataBuffer.substring(endIndex + 1);

      if (!message.startsWith('RCMD=101,')) continue;

      final payload = message.replaceFirst('RCMD=101,', '').replaceAll(';', '');
      final parts = payload.split(',');
      if (parts.length < 2) continue;

      final speed = int.tryParse(parts[0].trim());
      final pressure = int.tryParse(parts[1].trim());
      if (speed == null || pressure == null) continue;

      final normalizedSpeed = CutSettingsService.clampSpeed(
        speed,
        scope: _settingsScope,
      );
      final normalizedPressure = CutSettingsService.clampPressure(
        pressure,
        scope: _settingsScope,
      );

      if (!mounted) return;
      setState(() {
        _speed = normalizedSpeed;
        _pressure = normalizedPressure;
      });

      await _settings.setSpeed(normalizedSpeed, scope: _settingsScope);
      await _settings.setPressure(normalizedPressure, scope: _settingsScope);
    }
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedAlgo = prefs.getString('manual_handshake_algorithm_ui');
    final settingsScope = await _resolveSettingsScope();
    final speed = await _settings.getSpeed(scope: settingsScope);
    final pressure = await _settings.getPressure(scope: settingsScope);
    final autoFeed = await _settings.getAutoFeed();
    final autoUpdateEnabled = await _settings.getAutoUpdateEnabled();
    final angleEnabled = await _settings.getAngleEnabled();
    final angleValue = await _settings.getAngleValue();
    final forceLandscape = await _settings.getForceLandscape();
    final installedVersionCode =
        await _appSettings.getInstalledVersionCode() ?? 0;
    final installedVersionName =
        await _appSettings.getInstalledVersionName() ?? '';
    if (!mounted) return;
    setState(() {
      _settingsScope = settingsScope;
      _speed = speed;
      _pressure = pressure;
      _autoFeed = autoFeed;
      _autoUpdateEnabled = autoUpdateEnabled;
      _angleEnabled = angleEnabled;
      _angleValue = angleValue;
      _forceLandscape = forceLandscape;
      _installedVersionCode = installedVersionCode;
      _installedVersionName = installedVersionName;
      _handshakeAlgo = savedAlgo ?? _bluetooth.cachedAgentType ?? '180t_mietubl';
      _speedMax = CutSettingsService.maxSpeedForScope(settingsScope);
      _pressureMax = CutSettingsService.maxPressureForScope(settingsScope);
      _loading = false;
    });

    if (settingsScope == CutSettingsService.scopeDq && _bluetooth.isConnected) {
      unawaited(_requestDqSettingsSnapshot());
    }
    if (autoUpdateEnabled && !_autoUpdateCheckTriggered) {
      _autoUpdateCheckTriggered = true;
      unawaited(_checkForUpdate(autoTriggered: true));
    }
  }

  Future<void> _saveSpeed(int value) async {
    final normalized = CutSettingsService.clampSpeed(
      value,
      scope: _settingsScope,
    );
    setState(() => _speed = normalized);
    await _settings.setSpeed(normalized, scope: _settingsScope);
    if (_bluetooth.isConnected) {
      await _bluetooth.sendMachineSpeed(normalized);
    }
  }

  Future<void> _savePressure(int value) async {
    final normalized = CutSettingsService.clampPressure(
      value,
      scope: _settingsScope,
    );
    setState(() => _pressure = normalized);
    await _settings.setPressure(normalized, scope: _settingsScope);
    if (_bluetooth.isConnected) {
      await _bluetooth.sendMachinePressure(normalized);
    }
  }

  Widget _buildStepper({
    required String label,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
        Row(
          children: [
            IconButton(
              onPressed: value > min ? () => onChanged(value - 1) : null,
              icon: const Icon(Icons.remove_circle_outline),
              color: const Color(0xFF00FF88),
            ),
            Text(
              value.toString(),
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            IconButton(
              onPressed: value < max ? () => onChanged(value + 1) : null,
              icon: const Icon(Icons.add_circle_outline),
              color: const Color(0xFF00FF88),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _saveAutoFeed(bool value) async {
    setState(() => _autoFeed = value);
    await _settings.setAutoFeed(value);
    if (_bluetooth.isConnected) {
      _bluetooth.toggleInduction(value);
    }
  }

  Future<void> _saveAutoUpdateEnabled(bool value) async {
    setState(() => _autoUpdateEnabled = value);
    await _settings.setAutoUpdateEnabled(value);
    if (value) {
      unawaited(_checkForUpdate(autoTriggered: true));
    }
  }

  int _ledBrightness = 3;

  void _saveLEDBrightness(int value) {
    setState(() => _ledBrightness = value);
    if (_bluetooth.isConnected) {
      _bluetooth.setMachineLEDBrightness(value);
    }
  }

  Future<void> _saveAngleEnabled(bool value) async {
    setState(() => _angleEnabled = value);
    await _settings.setAngleEnabled(value);
  }

  String _formatInstalledVersion() {
    final versionName = _installedVersionName.trim().isEmpty
        ? AppStrings.of(context, 'system_unknown')
        : _installedVersionName.trim();
    if (_installedVersionCode > 0) {
      return '$versionName (${_installedVersionCode.toString()})';
    }
    return versionName;
  }

  void _showUpdateSnack(
    String message, {
    Color backgroundColor = const Color(0xFF00FF88),
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: backgroundColor),
    );
  }

  int? _readServerVersionCode(Map<String, dynamic> data) {
    final candidates = [
      data['versionCode'],
      data['version_code'],
      data['buildNumber'],
      data['build_number'],
      data['version'],
    ];
    for (final value in candidates) {
      final parsed = int.tryParse(value?.toString().trim() ?? '');
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }
    return null;
  }

  String _readServerVersionName(Map<String, dynamic> data) {
    return (data['versionName']?.toString().trim() ?? '');
  }

  Future<void> _refreshInstalledVersionInfo() async {
    final installedVersionCode =
        await _appSettings.getInstalledVersionCode() ?? 0;
    final installedVersionName =
        await _appSettings.getInstalledVersionName() ?? '';
    if (!mounted) return;
    setState(() {
      _installedVersionCode = installedVersionCode;
      _installedVersionName = installedVersionName;
    });
  }

  Future<String> _downloadUpdateApk() async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/m180update.apk');
    if (await file.exists()) {
      await file.delete();
    }
    await _dio.download(_updateApkUrl, file.path);
    return file.path;
  }

  Future<void> _checkForUpdate({bool autoTriggered = false}) async {
    if (_updateBusy) return;

    setState(() {
      _updateBusy = true;
      _updateStatus = AppStrings.of(context, 'update_checking');
    });

    try {
      final response = await _dio.get<dynamic>(_updateManifestUrl);
      final rawData = response.data;
      Map<String, dynamic>? data;
      if (rawData is Map) {
        data = rawData.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      } else if (rawData is String) {
        final decoded = jsonDecode(rawData);
        if (decoded is Map) {
          data = decoded.map(
            (key, value) => MapEntry(key.toString(), value),
          );
        }
      }

      if (data == null) {
        throw Exception(AppStrings.of(context, 'update_invalid_manifest'));
      }
      final serverVersionCode = _readServerVersionCode(data);
      final serverVersionName = _readServerVersionName(data);

      if (serverVersionCode == null) {
        throw Exception(AppStrings.of(context, 'update_invalid_manifest'));
      }

      final installedVersionCode =
          await _appSettings.getInstalledVersionCode() ?? _installedVersionCode;

      if (serverVersionCode <= installedVersionCode) {
        if (mounted) {
          setState(() {
            _installedVersionCode = installedVersionCode;
            _updateStatus = null;
          });
        }
        if (!autoTriggered) {
          _showUpdateSnack(
            AppStrings.of(context, 'update_no_new_version'),
            backgroundColor: Colors.orange,
          );
        }
        return;
      }

      if (mounted) {
        setState(() {
          _updateStatus =
              '${AppStrings.of(context, 'update_downloading')} ${serverVersionName.isEmpty ? '' : serverVersionName}'.trim();
        });
      }

      final apkPath = await _downloadUpdateApk();
      final comparison = await _appSettings.compareApkWithInstalled(apkPath);
      if (comparison == null || comparison['isNewer'] != true) {
        final runningPkg = comparison?['runningPackageName'] ?? 'unknown';
        final archivePkg = comparison?['archivePackageName'] ?? 'unknown';
        final runningVer = comparison?['runningVersionCode'] ?? 'unknown';
        final archiveVer = comparison?['archiveVersionCode'] ?? 'unknown';
        throw Exception(
          '${AppStrings.of(context, 'update_apk_not_newer')}\n(Running: $runningPkg v$runningVer\nUpdate: $archivePkg v$archiveVer)'
        );
      }

      if (mounted) {
        setState(() {
          _updateStatus = AppStrings.of(context, 'update_ready_installing');
        });
      }

      final success = await _appSettings.installApk(apkPath);
      if (!success) {
        throw Exception('Install prompt failed to launch.');
      }
      return;
    } catch (e) {
      final message = AppStrings.of(
        context,
        'update_failed',
      ).replaceAll('{message}', e.toString());
      _showUpdateSnack(message, backgroundColor: Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _updateBusy = false;
          _updateStatus = null;
        });
      }
    }
  }

  Future<void> _saveForceLandscape(bool value) async {
    setState(() => _forceLandscape = value);
    await _settings.setForceLandscape(value);
  }

  Future<void> _saveAngleValue(double value) async {
    setState(() => _angleValue = value);
    await _settings.setAngleValue(value);
  }

  Future<void> _showAngleDialog() async {
    final result = await showAngleDialog(context, _angleValue);
    if (result != null) {
      await _saveAngleValue(result);
    }
  }

  Future<void> _saveHandshakeAlgo(String? value) async {
    if (value == null) return;
    setState(() => _handshakeAlgo = value);
    await _bluetooth.cacheSuccessfulHandshake(value, false, mode: 'manual');
  }

  Future<void> _pinHandshakeAlgo() async {
    if (_handshakeAlgo == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('manual_handshake_algorithm_ui', _handshakeAlgo!);
    
    if (_bluetooth.isConnected && _bluetooth.serialNumber != null) {
      await _bluetooth.cacheSuccessfulHandshake(_handshakeAlgo!, true, mode: 'manual', persist: true);
    }
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم تثبيت الهاند شيك كافتراضي بنجاح!'),
        backgroundColor: Color(0xFF00FF88),
      ),
    );
  }

  Future<void> _unpinHandshakeAlgo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('manual_handshake_algorithm_ui');
    
    if (_bluetooth.isConnected && _bluetooth.serialNumber != null) {
      await prefs.remove('handshake_algo_${_bluetooth.serialNumber!}');
      await prefs.remove('handshake_mode_${_bluetooth.serialNumber!}');
    }
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم إلغاء التثبيت! الماكينة الآن في الوضع التلقائي.'),
        backgroundColor: Colors.blueAccent,
      ),
    );
  }

  Future<void> _runFilmCutterTest() async {
    if (!_bluetooth.isConnected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context, 'error_connect_to_cutter')),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    const commands = [
      'BD:100,100;',
      'BD:100,102;',
      'BD:100,103;',
      'BD:100,104;',
      'BD:100,105;',
      'BD:100,106;',
    ];

    for (final cmd in commands) {
      await _bluetooth.write(cmd);
      await Future.delayed(const Duration(milliseconds: 200));
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppStrings.of(context, 'test_sequence_sent')),
        backgroundColor: const Color(0xFF00FF88),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: Text(AppStrings.of(context, 'cut_settings')),
        backgroundColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00FF88)),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          AppStrings.of(context, 'app_update'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          AppStrings.of(context, 'installed_version')
                              .replaceAll('{version}', _formatInstalledVersion()),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                        if (_updateStatus != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _updateStatus!,
                            style: const TextStyle(
                              color: Color(0xFF00FF88),
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              AppStrings.of(context, 'auto_update'),
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 14,
                              ),
                            ),
                            Switch(
                              value: _autoUpdateEnabled,
                              onChanged: _updateBusy ? null : _saveAutoUpdateEnabled,
                              activeThumbColor: const Color(0xFF00FF88),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _updateBusy
                              ? null
                              : () => _checkForUpdate(autoTriggered: false),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00FF88),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            AppStrings.of(context, 'check_for_update'),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: () {
                      // System information not available for M180T
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('M180T - System info via serial')),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF00FF88),
                      side: const BorderSide(color: Color(0xFF00FF88)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.memory),
                    label: Text(AppStrings.of(context, 'system_information')),
                  ),
                  const SizedBox(height: 20),
                  _buildStepper(
                    label: AppStrings.of(context, 'speed'),
                    value: _speed,
                    min: 1,
                    max: _speedMax,
                    onChanged: _saveSpeed,
                  ),
                  const SizedBox(height: 20),
                  _buildStepper(
                    label: AppStrings.of(context, 'pressure'),
                    value: _pressure,
                    min: 1,
                    max: _pressureMax,
                    onChanged: _savePressure,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        AppStrings.of(context, 'auto_feed'),
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                      Switch(
                        value: _autoFeed,
                        onChanged: _saveAutoFeed,
                        activeThumbColor: const Color(0xFF00FF88),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        AppStrings.of(context, 'set_angle'),
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                      Switch(
                        value: _angleEnabled,
                        onChanged: _saveAngleEnabled,
                        activeThumbColor: const Color(0xFF00FF88),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        AppStrings.of(context, 'force_landscape'),
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                      Switch(
                        value: _forceLandscape,
                        onChanged: _saveForceLandscape,
                        activeThumbColor: const Color(0xFF00FF88),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _showAngleDialog,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF00FF88),
                      side: const BorderSide(color: Color(0xFF00FF88)),
                    ),
                    child: Text(
                      AppStrings.of(
                        context,
                        'angle_display',
                      ).replaceAll('{value}', _angleValue.toStringAsFixed(1)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildStepper(
                    label: AppStrings.of(context, 'led_brightness'),
                    value: _ledBrightness,
                    min: 0,
                    max: 3,
                    onChanged: _saveLEDBrightness,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      if (!_bluetooth.isConnected) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              AppStrings.of(context, 'error_connect_to_cutter'),
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      _bluetooth.sendTestCut();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            AppStrings.of(context, 'sent_test_cut_command'),
                          ),
                          backgroundColor: const Color(0xFF00FF88),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00FF88),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      AppStrings.of(context, 'single_test_cut_label'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _runFilmCutterTest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00AEEF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      AppStrings.of(context, 'cutting_test'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () {
                      if (!_bluetooth.isConnected) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              AppStrings.of(context, 'error_connect_to_cutter'),
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      _bluetooth.requestMachineInfo();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            AppStrings.of(context, 'requested_machine_info'),
                          ),
                          backgroundColor: const Color(0xFF00FF88),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white12,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      AppStrings.of(context, 'request_machine_info'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Divider(color: Colors.white24),
                  const SizedBox(height: 16),
                  const Text(
                    "Handshake Algorithm",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: '180t_mietubl',
                    dropdownColor: const Color(0xFF1E1E1E),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    items: const ['180t_mietubl']
                        .map((algo) => DropdownMenuItem(
                              value: algo,
                              child: Text(algo),
                            ))
                        .toList(),
                    onChanged: _saveHandshakeAlgo,
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: _pinHandshakeAlgo,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00FF88),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'تثبيت كافتراضي (Pin as Default)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: _unpinHandshakeAlgo,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'إلغاء التثبيت للعودة للتلقائي (Return to Auto)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "Warning: Changing this manualy will force the machine to use the selected protocol for decryption.",
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }
}
