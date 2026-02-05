import 'package:flutter/material.dart';
import '../../services/cut_settings_service.dart';
import '../../services/bluetooth_service.dart';

Future<double?> showAngleDialog(BuildContext context, double currentValue) async {
  final controller = TextEditingController(
    text: currentValue.toStringAsFixed(1),
  );
  return showDialog<double>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: const Text(
        'Set angle',
        style: TextStyle(color: Colors.white),
      ),
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          hintText: '-45 to 45',
          hintStyle: TextStyle(color: Colors.grey),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
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
          child: const Text(
            'Save',
            style: TextStyle(color: Color(0xFF00FF88)),
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

  bool _loading = true;
  bool _autoFeed = CutSettingsService.defaultAutoFeed;
  bool _angleEnabled = CutSettingsService.defaultAngleEnabled;
  double _angleValue = CutSettingsService.defaultAngleValue;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final autoFeed = await _settings.getAutoFeed();
    final angleEnabled = await _settings.getAngleEnabled();
    final angleValue = await _settings.getAngleValue();
    if (!mounted) return;
    setState(() {
      _autoFeed = autoFeed;
      _angleEnabled = angleEnabled;
      _angleValue = angleValue;
      _loading = false;
    });
  }

  Future<void> _saveAutoFeed(bool value) async {
    setState(() => _autoFeed = value);
    await _settings.setAutoFeed(value);
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
        const SnackBar(
          content: Text('Please connect to the cutter first.'),
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
      const SnackBar(
        content: Text('Test sequence sent.'),
        backgroundColor: Color(0xFF00FF88),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Cut Settings'),
        backgroundColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00FF88)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Automatic paper feed',
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                      Switch(
                        value: _autoFeed,
                        onChanged: _saveAutoFeed,
                        activeColor: const Color(0xFF00FF88),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Set angle',
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                      Switch(
                        value: _angleEnabled,
                        onChanged: _saveAngleEnabled,
                        activeColor: const Color(0xFF00FF88),
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
                    child: Text('Angle: ${_angleValue.toStringAsFixed(1)}°'),
                  ),
                  const SizedBox(height: 20),
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
                    child: const Text(
                      'Cutting Test',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
