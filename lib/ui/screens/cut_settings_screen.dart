import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/cut_settings_service.dart';
import '../../services/bluetooth_service.dart';
import '../../services/app_settings_service.dart';
import '../../core/machine_handshake.dart';

Future<double?> showAngleDialog(
    BuildContext context, double currentValue) async {
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
  static const String _handshakeAlgoKey = 'manual_handshake_algorithm_ui';
  static const String _forceLandscapeKey = 'force_landscape';
  static const String _defaultUpdateUrl = 'https://anti-crash.com/update.apk';
  static const String _sensitivePasswordKey = 'sensitive_settings_password';
  static const String _defaultSensitivePassword = '2580';

  static const List<Map<String, String>> _handshakeAlgorithms = [
    {"label": "Sunshine UART (Try 3 methods)", "value": "SUNSHINE"},
    {"label": "PassWord2 (Primary)", "value": "HANDSHAKE_NEW"},
    {"label": "OldPassWord", "value": "OLD_V1"},
    {"label": "PassWord", "value": "OLD_V3"},
    {"label": "DQ Handshake", "value": "DQ_HANDSHAKE"},
    {"label": "Mechanic UART", "value": "MECHANIC_UART"},
  ];

  final CutSettingsService _settings = CutSettingsService();
  final CutterBluetoothService _bluetooth = CutterBluetoothService();
  final AppSettingsService _appSettings = AppSettingsService();

  bool _loading = true;
  int _speed = CutSettingsService.defaultSpeed;
  int _pressure = CutSettingsService.defaultPressure;
  bool _autoFeed = CutSettingsService.defaultAutoFeed;
  bool _angleEnabled = CutSettingsService.defaultAngleEnabled;
  double _angleValue = CutSettingsService.defaultAngleValue;
  bool _forceLandscape = false;
  String _manualHandshakeAlgorithm = MachineHandshake.algoSunshine;
  bool _isUpdating = false;
  double _downloadProgress = 0;
  String _appVersionLabel = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() => super.dispose();

  Future<void> _load() async {
    final speed = await _settings.getSpeed();
    final pressure = await _settings.getPressure();
    final autoFeed = await _settings.getAutoFeed();
    final angleEnabled = await _settings.getAngleEnabled();
    final angleValue = await _settings.getAngleValue();
    final installedVersionName = await _appSettings.getInstalledVersionName();
    final installedVersionCode = await _appSettings.getInstalledVersionCode();
    final prefs = await SharedPreferences.getInstance();
    final savedAlgo = prefs.getString(_handshakeAlgoKey);
    final forceLandscape = prefs.getBool(_forceLandscapeKey) ?? false;
    final effectiveAlgo =
        _handshakeAlgorithms.any((a) => a['value'] == savedAlgo)
            ? savedAlgo
            : null;
    if (!mounted) return;
    setState(() {
      _speed = speed;
      _pressure = pressure;
      _autoFeed = autoFeed;
      _angleEnabled = angleEnabled;
      _angleValue = angleValue;
      if ((installedVersionName ?? '').isNotEmpty &&
          installedVersionCode != null &&
          installedVersionCode > 0) {
        _appVersionLabel =
            'Installed version: $installedVersionName ($installedVersionCode)';
      } else {
        _appVersionLabel = '';
      }
      _forceLandscape = forceLandscape;
      if (effectiveAlgo != null) {
        _manualHandshakeAlgorithm = effectiveAlgo;
      }
      _loading = false;
    });
  }

  String get _manualHandshakeAlgorithmLabel {
    for (final algo in _handshakeAlgorithms) {
      if (algo['value'] == _manualHandshakeAlgorithm) {
        return algo['label'] ?? _manualHandshakeAlgorithm;
      }
    }
    return _manualHandshakeAlgorithm;
  }

  Future<void> _saveSpeed(int value) async {
    setState(() => _speed = value);
    await _settings.setSpeed(value);
  }

  Future<void> _savePressure(int value) async {
    setState(() => _pressure = value);
    await _settings.setPressure(value);
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
  }

  Future<void> _saveAngleEnabled(bool value) async {
    setState(() => _angleEnabled = value);
    await _settings.setAngleEnabled(value);
  }

  Future<void> _saveAngleValue(double value) async {
    setState(() => _angleValue = value);
    await _settings.setAngleValue(value);
  }

  Future<void> _saveForceLandscape(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_forceLandscapeKey, value);
    if (!mounted) return;
    setState(() => _forceLandscape = value);
    if (value) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  Future<void> _openWifiSettings() async {
    final ok = await _appSettings.openWifiSettings(
        autoReturn: true, timeoutSeconds: 30);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open Wi-Fi settings.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<String> _resolveUpdateUrl() async {
    return _defaultUpdateUrl;
  }

  int? _parsePositiveInt(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed < 0) return null;
    return parsed;
  }

  Map<String, dynamic>? _asStringMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return null;
  }

  int? _extractVersionCodeFromHeaders(Headers headers) {
    const candidates = <String>[
      'x-version-code',
      'x-app-version-code',
      'x-build-number',
      'x-version',
      'version-code',
      'build-number',
    ];

    for (final key in candidates) {
      final values = headers.map[key];
      if (values == null || values.isEmpty) continue;
      final parsed = _parsePositiveInt(values.first);
      if (parsed != null) return parsed;
    }
    return null;
  }

  int? _extractVersionCodeFromPayload(Map<String, dynamic> payload) {
    const keys = <String>[
      'versionCode',
      'version_code',
      'buildNumber',
      'build_number',
      'version',
    ];

    for (final key in keys) {
      final parsed = _parsePositiveInt(payload[key]);
      if (parsed != null) return parsed;
    }

    final nestedCandidates = <dynamic>[
      payload['data'],
      payload['update'],
      payload['app'],
    ];
    for (final nested in nestedCandidates) {
      final nestedMap = _asStringMap(nested);
      if (nestedMap == null) continue;
      for (final key in keys) {
        final parsed = _parsePositiveInt(nestedMap[key]);
        if (parsed != null) return parsed;
      }
    }

    return null;
  }

  List<String> _buildUpdateMetadataUrls(String apkUrl) {
    final apkUri = Uri.tryParse(apkUrl);
    if (apkUri == null || apkUri.scheme.isEmpty || apkUri.host.isEmpty) {
      return const [];
    }
    if (apkUri.pathSegments.isEmpty) return const [];

    final baseSegments = apkUri.pathSegments.length > 1
        ? apkUri.pathSegments.sublist(0, apkUri.pathSegments.length - 1)
        : <String>[];
    const filenames = <String>[
      'update.json',
      'version.json',
      'app-version.json',
    ];

    final urls = <String>[];
    for (final filename in filenames) {
      final uri = apkUri.replace(
        pathSegments: [...baseSegments, filename],
        queryParameters: null,
        query: null,
        fragment: '',
      );
      final normalized = uri.toString();
      if (!urls.contains(normalized)) {
        urls.add(normalized);
      }
    }
    return urls;
  }

  Future<int?> _getInstalledBuildNumber() async {
    return _appSettings.getInstalledVersionCode();
  }

  Future<int?> _fetchServerBuildNumber(String apkUrl) async {
    final dio = Dio();
    final requestOptions = Options(
      followRedirects: true,
      sendTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
      validateStatus: (code) => code != null && code >= 200 && code < 400,
    );

    try {
      final head = await dio.head(apkUrl, options: requestOptions);
      final fromHead = _extractVersionCodeFromHeaders(head.headers);
      if (fromHead != null) return fromHead;
    } catch (_) {
      // Ignore and try metadata URLs.
    }

    final metadataUrls = _buildUpdateMetadataUrls(apkUrl);
    for (final metadataUrl in metadataUrls) {
      try {
        final response = await dio.get(
          metadataUrl,
          options: Options(
            followRedirects: true,
            sendTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(seconds: 20),
            headers: const {'Accept': 'application/json'},
            validateStatus: (code) => code != null && code >= 200 && code < 400,
          ),
        );

        final payload = _asStringMap(response.data);
        if (payload == null) continue;
        final fromPayload = _extractVersionCodeFromPayload(payload);
        if (fromPayload != null) return fromPayload;
      } catch (_) {
        // Try next metadata endpoint.
      }
    }

    return null;
  }

  Future<void> _checkForUpdateAndInstall() async {
    if (_isUpdating) return;

    final url = await _resolveUpdateUrl();
    if (!mounted) return;
    setState(() {
      _isUpdating = true;
      _downloadProgress = 0;
    });

    try {
      final installedBuild = await _getInstalledBuildNumber();
      if (installedBuild == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to read current app version.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final serverBuild = await _fetchServerBuildNumber(url);
      if (serverBuild == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Cannot verify update version from server. Add update.json or X-Version-Code header.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      if (serverBuild <= installedBuild) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('No update found. You already have the latest version.'),
            backgroundColor: Color(0xFF00FF88),
          ),
        );
        return;
      }

      final tmpDir = await getTemporaryDirectory();
      final apkPath =
          '${tmpDir.path}/update_${DateTime.now().millisecondsSinceEpoch}.apk';

      await Dio().download(
        url,
        apkPath,
        options: Options(
          followRedirects: true,
          receiveTimeout: const Duration(minutes: 5),
          sendTimeout: const Duration(minutes: 2),
        ),
        onReceiveProgress: (received, total) {
          if (!mounted || total <= 0) return;
          setState(() {
            _downloadProgress = received / total;
          });
        },
      );

      final isNewer = await _appSettings.isApkNewerThanInstalled(apkPath);
      if (!isNewer) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Server version is $serverBuild but downloaded APK is not newer.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final rootShell = await _appSettings.getRootShellCapability();
      SilentInstallResult silentInstall = const SilentInstallResult(
        success: false,
        deferred: false,
        message: '',
        command: '',
        exitCode: -1,
        output: '',
        sourcePath: '',
        attempts: [],
      );
      var installReason = '';
      var installedSilently = false;
      if (rootShell.available) {
        silentInstall = await _appSettings.installApkSilentlyDetailed(apkPath);
        installReason = silentInstall.message.trim().isNotEmpty
            ? silentInstall.message.trim()
            : (silentInstall.output.trim().isNotEmpty
                ? silentInstall.output.trim()
                : 'Silent install failed.');
        installedSilently = silentInstall.success;
      }
      if (!rootShell.available) {
        installReason = rootShell.reason.trim().isNotEmpty
            ? rootShell.reason.trim()
            : 'This machine does not allow the app to open a root shell.';
      }
      final openedInstaller =
          installedSilently ? false : await _appSettings.installApk(apkPath);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            installedSilently
                ? (silentInstall.deferred
                    ? 'Automatic install started in background. The app should reopen on its own.'
                    : 'Update installed automatically.')
                : openedInstaller
                    ? rootShell.available
                        ? 'Automatic install failed: $installReason. Opened package installer instead.'
                        : 'Opened package installer directly: $installReason'
                    : rootShell.available
                        ? 'Automatic install failed: $installReason'
                        : 'Could not open package installer: $installReason',
          ),
          backgroundColor: installedSilently || openedInstaller
              ? const Color(0xFF00FF88)
              : Colors.red,
        ),
      );
      if (installedSilently && silentInstall.deferred) {
        Future<void>.delayed(const Duration(milliseconds: 900), () async {
          await _appSettings.closeForBackgroundUpdate();
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Update download failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  Future<void> _showAngleDialog() async {
    final result = await showAngleDialog(context, _angleValue);
    if (result != null) {
      await _saveAngleValue(result);
    }
  }

  Future<bool?> _verifySensitivePassword() async {
    final controller = TextEditingController();
    final entered = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Protected Settings',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          obscureText: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Password',
            labelStyle: TextStyle(color: Colors.grey),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Open'),
          ),
        ],
      ),
    );
    if (entered == null) return null;
    final prefs = await SharedPreferences.getInstance();
    final storedPassword =
        prefs.getString(_sensitivePasswordKey) ?? _defaultSensitivePassword;
    return entered == storedPassword;
  }

  Future<void> _changeSensitivePassword() async {
    final newPassController = TextEditingController();
    final confirmController = TextEditingController();
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Change Password',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: newPassController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'New password',
                labelStyle: TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Confirm password',
                labelStyle: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (changed != true) return;

    final newPass = newPassController.text.trim();
    final confirm = confirmController.text.trim();
    if (newPass.length < 4 || newPass != confirm) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password invalid or not matching.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sensitivePasswordKey, newPass);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Password updated.'),
        backgroundColor: Color(0xFF00FF88),
      ),
    );
  }

  Future<void> _openProtectedSettings() async {
    final ok = await _verifySensitivePassword();
    if (ok == null) return;
    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Wrong password.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (!mounted) return;

    String selected = _manualHandshakeAlgorithm;
    bool isTestingConnect = false;
    String? connectResult;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Text(
              'Sensitive Settings',
              style: TextStyle(color: Colors.white),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selected,
                  decoration: const InputDecoration(
                    labelText: 'Default Handshake',
                    labelStyle: TextStyle(color: Colors.grey),
                  ),
                  items: _handshakeAlgorithms
                      .map(
                        (algo) => DropdownMenuItem(
                          value: algo['value'],
                          child: Text(algo['label']!),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    if (val == null) return;
                    setDialogState(() => selected = val);
                  },
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: isTestingConnect
                      ? null
                      : () async {
                          setDialogState(() {
                            isTestingConnect = true;
                            connectResult = null;
                          });

                          final result =
                              await _runHandshakeConnectTest(selected);

                          if (!mounted) return;
                          setDialogState(() {
                            isTestingConnect = false;
                            connectResult = result;
                          });
                        },
                  icon: isTestingConnect
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link),
                  label: Text(
                    isTestingConnect
                        ? 'Connecting...'
                        : 'Connect (Test selected)',
                  ),
                ),
                if (connectResult != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: connectResult!.startsWith('✅')
                          ? Colors.green.withValues(alpha: 0.15)
                          : Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      connectResult!,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: isTestingConnect
                      ? null
                      : () async {
                          Navigator.of(context).pop(false);
                          await _changeSensitivePassword();
                        },
                  icon: const Icon(Icons.password),
                  label: const Text('Change settings password'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isTestingConnect
                    ? null
                    : () => Navigator.of(context).pop(false),
                child:
                    const Text('Close', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: isTestingConnect
                    ? null
                    : () => Navigator.of(context).pop(true),
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );

    if (saved != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_handshakeAlgoKey, selected);
    if (!mounted) return;
    setState(() {
      _manualHandshakeAlgorithm = selected;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sensitive settings saved.'),
        backgroundColor: Color(0xFF00FF88),
      ),
    );
  }

  Future<String> _runHandshakeConnectTest(String algorithm) async {
    final cutter = _bluetooth;
    bool openedByTest = false;
    String lastStatus = 'No response';

    try {
      if (!cutter.isConnected) {
        await cutter.connect();
        openedByTest = true;
      }

      final completer = Completer<bool>();
      final handshake = MachineHandshake(
        cutter,
        forcedAlgorithm: algorithm,
        handshakeMode: "manual",
        persistOnSuccess: false,
        onStatusUpdate: (status) {
          lastStatus = status;
        },
        onHandshakeComplete: (success) {
          if (!completer.isCompleted) {
            completer.complete(success);
          }
        },
      );

      handshake.startHandshake();
      final success = await completer.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () => false,
      );
      handshake.dispose();

      if (success) {
        final serial = (cutter.serialNumber ?? '').trim();
        final serialText = serial.isEmpty ? 'Unknown serial' : serial;
        return '✅ Connected & authenticated ($serialText)';
      }

      if (openedByTest) {
        await cutter.disconnect();
      }
      return '❌ Failed: $lastStatus';
    } catch (e) {
      if (openedByTest) {
        await cutter.disconnect();
      }
      return '❌ Connection error: $e';
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
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00FF88)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildStepper(
                    label: 'Speed',
                    value: _speed,
                    min: 1,
                    max: 30,
                    onChanged: _saveSpeed,
                  ),
                  const SizedBox(height: 20),
                  _buildStepper(
                    label: 'Pressure',
                    value: _pressure,
                    min: 1,
                    max: 30,
                    onChanged: _savePressure,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'وضع أفقي دائم',
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                      Switch(
                        value: _forceLandscape,
                        onChanged: _saveForceLandscape,
                        activeColor: const Color(0xFF00FF88),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
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
                  ElevatedButton.icon(
                    onPressed: _openWifiSettings,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2A2A2A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.wifi),
                    label: const Text(
                      'Wi-Fi Settings',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Card(
                    color: const Color(0xFF1E1E1E),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'App Update (APK)',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (_appVersionLabel.isNotEmpty) ...[
                            Text(
                              _appVersionLabel,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _isUpdating
                                  ? null
                                  : _checkForUpdateAndInstall,
                              icon: const Icon(Icons.system_update_alt),
                              label: Text(
                                _isUpdating
                                    ? 'Checking...'
                                    : 'Check for Update',
                              ),
                            ),
                          ),
                          if (_isUpdating) ...[
                            const SizedBox(height: 10),
                            LinearProgressIndicator(
                              value: _downloadProgress > 0 &&
                                      _downloadProgress <= 1
                                  ? _downloadProgress
                                  : null,
                              color: const Color(0xFF00FF88),
                              backgroundColor: const Color(0xFF2A2A2A),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _downloadProgress > 0
                                  ? 'Progress: ${(_downloadProgress * 100).toStringAsFixed(0)}%'
                                  : 'Starting download...',
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Card(
                    color: const Color(0xFF1E1E1E),
                    child: ListTile(
                      leading: const Icon(Icons.lock, color: Color(0xFF00FF88)),
                      title: const Text(
                        'Protected Handshake Settings',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        'Current default: $_manualHandshakeAlgorithmLabel',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: _openProtectedSettings,
                    ),
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
