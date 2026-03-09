import 'package:flutter/services.dart';

class AppSettingsService {
  static const MethodChannel _channel = MethodChannel('app_settings');

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

  Future<bool> isApkNewerThanInstalled(String apkPath) async {
    try {
      final result = await _channel
          .invokeMethod<bool>('isApkNewerThanInstalled', {'path': apkPath});
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }
}
