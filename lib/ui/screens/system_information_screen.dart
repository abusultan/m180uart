import 'package:flutter/material.dart';
import '../../core/app_strings.dart';
import 'package:flutter_project/core/serial/serial_service.dart';

class SystemInformationScreen extends StatefulWidget {
  const SystemInformationScreen({super.key});

  @override
  State<SystemInformationScreen> createState() => _SystemInformationScreenState();
}

class _SystemInformationScreenState extends State<SystemInformationScreen> {
  final CutterSerialService _bluetooth = CutterSerialService();

  bool _loading = true;
  String _typeName = '-';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final typeName = await _bluetooth.getTypeMachineNameForItems();
      if (!mounted) return;
      setState(() {
        _typeName = typeName;
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final serial = _bluetooth.serialNumber ?? '-';
    final connected = _bluetooth.isConnected;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: Text(AppStrings.of(context, 'system_information')),
        backgroundColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00FF88)),
            )
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _row('Connected', connected ? 'Yes' : 'No'),
                  const SizedBox(height: 12),
                  _row('Serial', serial),
                  const SizedBox(height: 12),
                  _row('Machine Type', _typeName),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: connected
                        ? () async {
                            _bluetooth.requestMachineInfo();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  AppStrings.of(
                                    context,
                                    'requested_machine_info',
                                  ),
                                ),
                                backgroundColor: const Color(0xFF00FF88),
                              ),
                            );
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00FF88),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(AppStrings.of(context, 'request_machine_info')),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _row(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
