import 'package:flutter/services.dart';

class AppSettingsService {
  static const MethodChannel _channel = MethodChannel('app_settings');

  Future<bool> openWifiSettings({bool autoReturn = true, int timeoutSeconds = 30}) async {
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
}
