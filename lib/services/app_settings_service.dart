import 'package:flutter/services.dart';

class SilentInstallResult {
  final bool success;
  final bool deferred;
  final String message;
  final String command;
  final int exitCode;
  final String output;
  final String sourcePath;
  final List<Map<String, dynamic>> attempts;

  const SilentInstallResult({
    required this.success,
    required this.deferred,
    required this.message,
    required this.command,
    required this.exitCode,
    required this.output,
    required this.sourcePath,
    required this.attempts,
  });

  factory SilentInstallResult.fromMap(Map<String, dynamic> map) {
    final rawAttempts = map['attempts'];
    final attempts = <Map<String, dynamic>>[];
    if (rawAttempts is List) {
      for (final item in rawAttempts) {
        if (item is Map) {
          attempts.add(
            item.map((key, value) => MapEntry(key.toString(), value)),
          );
        }
      }
    }

    return SilentInstallResult(
      success: map['success'] == true,
      deferred: map['deferred'] == true,
      message: map['message']?.toString() ?? '',
      command: map['command']?.toString() ?? '',
      exitCode: int.tryParse(map['exitCode']?.toString() ?? '') ?? -1,
      output: map['output']?.toString() ?? '',
      sourcePath: map['sourcePath']?.toString() ?? '',
      attempts: attempts,
    );
  }
}

class RootShellCapability {
  final bool available;
  final String path;
  final String reason;

  const RootShellCapability({
    required this.available,
    required this.path,
    required this.reason,
  });

  factory RootShellCapability.fromMap(Map<String, dynamic> map) {
    return RootShellCapability(
      available: map['available'] == true,
      path: map['path']?.toString() ?? '',
      reason: map['reason']?.toString() ?? '',
    );
  }
}

class AppSettingsService {
  static const MethodChannel _channel = MethodChannel('app_settings');

  Future<Map<String, dynamic>?> getInstalledAppVersionInfo() async {
    try {
      final result =
          await _channel.invokeMethod<dynamic>('getInstalledAppVersionInfo');
      if (result is Map) {
        return result.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<int?> getInstalledVersionCode() async {
    final info = await getInstalledAppVersionInfo();
    final raw = info?['versionCode']?.toString().trim() ?? '';
    return int.tryParse(raw);
  }

  Future<String?> getInstalledVersionName() async {
    final info = await getInstalledAppVersionInfo();
    final raw = info?['versionName']?.toString().trim() ?? '';
    return raw.isEmpty ? null : raw;
  }

  Future<bool> openWifiSettings(
      {bool autoReturn = true, int timeoutSeconds = 30}) async {
    try {
      final result = await _channel.invokeMethod<bool>('openWifiSettings', {
        'autoReturn': autoReturn,
        'timeoutSeconds': timeoutSeconds,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> canInstallPackages() async {
    try {
      final result = await _channel.invokeMethod<bool>('canInstallPackages');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<RootShellCapability> getRootShellCapability() async {
    try {
      final result = await _channel.invokeMethod<dynamic>('getRootShellCapability');
      if (result is Map) {
        return RootShellCapability.fromMap(
          result.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    } on PlatformException {
      // Fall through to the default result below.
    }
    return const RootShellCapability(
      available: false,
      path: '',
      reason: 'Root shell capability could not be determined.',
    );
  }

  Future<bool> openInstallUnknownSourcesSettings() async {
    try {
      final result = await _channel
          .invokeMethod<bool>('openInstallUnknownSourcesSettings');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> installApk(String apkPath) async {
    try {
      final result =
          await _channel.invokeMethod<bool>('installApk', {'path': apkPath});
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> installApkSilently(String apkPath) async {
    try {
      final result = await _channel
          .invokeMethod<bool>('installApkSilently', {'path': apkPath});
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<SilentInstallResult> installApkSilentlyDetailed(String apkPath) async {
    try {
      final result = await _channel.invokeMethod<dynamic>(
        'installApkSilentlyDetailed',
        {'path': apkPath},
      );
      if (result is Map) {
        return SilentInstallResult.fromMap(
          result.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
      return const SilentInstallResult(
        success: false,
        deferred: false,
        message: 'Silent install returned an invalid result.',
        command: '',
        exitCode: -1,
        output: '',
        sourcePath: '',
        attempts: [],
      );
    } on PlatformException catch (e) {
      return SilentInstallResult(
        success: false,
        deferred: false,
        message: e.message ?? 'Silent install failed.',
        command: '',
        exitCode: -1,
        output: e.details?.toString() ?? '',
        sourcePath: '',
        attempts: const [],
      );
    }
  }

  Future<bool> isApkNewerThanInstalled(String apkPath) async {
    try {
      final result = await _channel
          .invokeMethod<bool>('isApkNewerThanInstalled', {'path': apkPath});
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<Map<String, dynamic>?> compareApkWithInstalled(String apkPath) async {
    try {
      final result = await _channel.invokeMethod<dynamic>(
          'compareApkWithInstalled', {'path': apkPath});
      if (result is Map) {
        return result.map((key, value) => MapEntry(key.toString(), value));
      }
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<bool> closeForBackgroundUpdate() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('closeForBackgroundUpdate');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> applyOrientationMode({required bool forceLandscape}) async {
    try {
      final result = await _channel.invokeMethod<bool>('applyOrientationMode', {
        'forceLandscape': forceLandscape,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }
}
