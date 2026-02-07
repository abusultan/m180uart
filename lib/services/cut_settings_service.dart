import 'package:shared_preferences/shared_preferences.dart';

class CutSettingsService {
  static const _keySpeed = 'cut_speed';
  static const _keyPressure = 'cut_pressure';
  static const _keyAutoFeed = 'cut_auto_feed';
  static const _keyAngleEnabled = 'cut_angle_enabled';
  static const _keyAngleValue = 'cut_angle_value';
  static const _keySettingsVersion = 'cut_settings_version';
  static const int _resetVersion = 2;

  static const int defaultSpeed = 1;
  static const int defaultPressure = 3;
  static const bool defaultAutoFeed = true;
  static const bool defaultAngleEnabled = false;
  static const double defaultAngleValue = 0;

  Future<int> getSpeed() async {
    final prefs = await SharedPreferences.getInstance();
    await _ensureResetApplied(prefs);
    return prefs.getInt(_keySpeed) ?? defaultSpeed;
  }

  Future<int> getPressure() async {
    final prefs = await SharedPreferences.getInstance();
    await _ensureResetApplied(prefs);
    return prefs.getInt(_keyPressure) ?? defaultPressure;
  }

  Future<bool> getAutoFeed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAutoFeed) ?? defaultAutoFeed;
  }

  Future<bool> getAngleEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAngleEnabled) ?? defaultAngleEnabled;
  }

  Future<double> getAngleValue() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyAngleValue) ?? defaultAngleValue;
  }

  Future<void> _ensureResetApplied(SharedPreferences prefs) async {
    final version = prefs.getInt(_keySettingsVersion) ?? 0;
    if (version < _resetVersion) {
      await prefs.remove(_keySpeed);
      await prefs.remove(_keyPressure);
      await prefs.setInt(_keySettingsVersion, _resetVersion);
    }
  }


  Future<void> setSpeed(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySpeed, value);
  }

  Future<void> setPressure(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyPressure, value);
  }

  Future<void> setAutoFeed(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoFeed, value);
  }

  Future<void> setAngleEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAngleEnabled, value);
  }

  Future<void> setAngleValue(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyAngleValue, value);
  }

}
