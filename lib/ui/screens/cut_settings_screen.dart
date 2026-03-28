import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/cut_settings_service.dart';
import '../../services/bluetooth_service.dart';
import '../../core/app_strings.dart';
import 'system_information_screen.dart';

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
  final CutSettingsService _settings = CutSettingsService();
  final CutterBluetoothService _bluetooth = CutterBluetoothService();
  StreamSubscription<String>? _machineDataSub;
  String _machineDataBuffer = '';

  bool _loading = true;
  String _settingsScope = CutSettingsService.scopeGeneric;
  int _speed = CutSettingsService.defaultSpeed;
  int _pressure = CutSettingsService.defaultPressure;
  bool _autoFeed = CutSettingsService.defaultAutoFeed;
  bool _angleEnabled = CutSettingsService.defaultAngleEnabled;
  double _angleValue = CutSettingsService.defaultAngleValue;
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
    final settingsScope = await _resolveSettingsScope();
    final speed = await _settings.getSpeed(scope: settingsScope);
    final pressure = await _settings.getPressure(scope: settingsScope);
    final autoFeed = await _settings.getAutoFeed();
    final angleEnabled = await _settings.getAngleEnabled();
    final angleValue = await _settings.getAngleValue();
    if (!mounted) return;
    setState(() {
      _settingsScope = settingsScope;
      _speed = speed;
      _pressure = pressure;
      _autoFeed = autoFeed;
      _angleEnabled = angleEnabled;
      _angleValue = angleValue;
      _speedMax = CutSettingsService.maxSpeedForScope(settingsScope);
      _pressureMax = CutSettingsService.maxPressureForScope(settingsScope);
      _loading = false;
    });

    if (settingsScope == CutSettingsService.scopeDq && _bluetooth.isConnected) {
      unawaited(_requestDqSettingsSnapshot());
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
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const SystemInformationScreen(),
                        ),
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
                ],
              ),
            ),
    );
  }
}
