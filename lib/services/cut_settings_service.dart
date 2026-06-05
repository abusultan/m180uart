import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'app_settings_service.dart';

class CutSettingsService {
  static const _keySpeed = 'cut_speed';
  static const _keyPressure = 'cut_pressure';
  static const _keyDqSpeed = 'cut_speed_dq';
  static const _keyDqPressure = 'cut_pressure_dq';
  static const _keySunshineSpeed = 'cut_speed_sunshine';
  static const _keySunshinePressure = 'cut_pressure_sunshine';
  static const _keyAutoFeed = 'cut_auto_feed';
  static const _keyAutoUpdateEnabled = 'cut_auto_update_enabled';
  static const _keyAngleEnabled = 'cut_angle_enabled';
  static const _keyAngleValue = 'cut_angle_value';
  static const _keyForceLandscape = 'force_landscape';
  static const _keySettingsVersion = 'cut_settings_version';
  static const int _resetVersion = 2;

  static const String scopeGeneric = 'generic';
  static const String scopeDq = 'dq';
  static const String scopeSunshine = 'sunshine';

  static const int defaultSpeed = 1;
  static const int defaultPressure = 3;
  static const int defaultDqSpeed = 1;
  static const int defaultDqPressure = 1;
  static const int defaultSunshineSpeed = 1;
  static const int defaultSunshinePressure = 1;
  static const bool defaultAutoFeed = true;
  static const bool defaultAngleEnabled = false;
  static const double defaultAngleValue = 0;

  static String normalizeScope(String? scope) {
    switch ((scope ?? '').trim().toLowerCase()) {
      case scopeSunshine:
        return scopeSunshine;
      case scopeDq:
        return scopeDq;
      default:
        return scopeGeneric;
    }
  }

  static String normalizeAgentType(String? agentType) {
    return (agentType ?? '')
        .trim()
        .toUpperCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
  }

  static bool _isRockspaceAliasSerial(String serial) {
    return serial.startsWith('C180B') ||
        serial.startsWith('ZC2') ||
        serial.startsWith('ZC3');
  }

  static String resolveScopeForMachine({
    String? typeMachineName,
    String? serialNumber,
    String? agentType,
  }) {
    final normalizedType = (typeMachineName ?? '').trim().toLowerCase();
    final normalizedSerial = (serialNumber ?? '').trim().toUpperCase();
    final normalizedAgent = normalizeAgentType(agentType);

    if (normalizedType == scopeSunshine) {
      return scopeSunshine;
    }

    final isRockspace =
        normalizedType == 'rock_space' ||
        normalizedAgent == 'ROCKSPACE_BLUE' ||
        _isRockspaceAliasSerial(normalizedSerial);

    final isDqFamily =
        normalizedType == 'dq' ||
        normalizedAgent == 'DQ' ||
        normalizedAgent == 'DX' ||
        normalizedAgent == 'LH' ||
        normalizedAgent == 'DQ_HANDSHAKE' ||
        normalizedAgent == 'MECHANIC_UART' ||
        normalizedAgent == 'MECHANIC' ||
        normalizedAgent == 'PASS_U32' ||
        normalizedAgent == 'DEPASS_U32' ||
        normalizedSerial.startsWith('DQ') ||
        normalizedSerial.startsWith('DX') ||
        normalizedSerial.startsWith('LH') ||
        normalizedSerial.startsWith('MT');

    if (!isRockspace && isDqFamily) {
      return scopeDq;
    }

    return scopeGeneric;
  }

  static int minSpeedForScope(String scope) => 1;

  static int maxSpeedForScope(String scope) {
    switch (normalizeScope(scope)) {
      case scopeSunshine:
      case scopeDq:
        return 4;
      default:
        return 30;
    }
  }

  static int minPressureForScope(String scope) => 1;

  static int maxPressureForScope(String scope) {
    switch (normalizeScope(scope)) {
      case scopeSunshine:
        return 4;
      case scopeDq:
        return 5;
      default:
        return 30;
    }
  }

  static int defaultSpeedForScope(String scope) {
    switch (normalizeScope(scope)) {
      case scopeSunshine:
        return defaultSunshineSpeed;
      case scopeDq:
        return defaultDqSpeed;
      default:
        return defaultSpeed;
    }
  }

  static int defaultPressureForScope(String scope) {
    switch (normalizeScope(scope)) {
      case scopeSunshine:
        return defaultSunshinePressure;
      case scopeDq:
        return defaultDqPressure;
      default:
        return defaultPressure;
    }
  }

  static int clampSpeed(int value, {String scope = scopeGeneric}) {
    final normalizedScope = normalizeScope(scope);
    final min = minSpeedForScope(normalizedScope);
    final max = maxSpeedForScope(normalizedScope);
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  static int clampPressure(int value, {String scope = scopeGeneric}) {
    final normalizedScope = normalizeScope(scope);
    final min = minPressureForScope(normalizedScope);
    final max = maxPressureForScope(normalizedScope);
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  String _speedKeyForScope(String scope) {
    switch (normalizeScope(scope)) {
      case scopeSunshine:
        return _keySunshineSpeed;
      case scopeDq:
        return _keyDqSpeed;
      default:
        return _keySpeed;
    }
  }

  String _pressureKeyForScope(String scope) {
    switch (normalizeScope(scope)) {
      case scopeSunshine:
        return _keySunshinePressure;
      case scopeDq:
        return _keyDqPressure;
      default:
        return _keyPressure;
    }
  }

  Future<int> getSpeed({String scope = scopeGeneric}) async {
    final prefs = await SharedPreferences.getInstance();
    await _ensureResetApplied(prefs);
    final normalizedScope = normalizeScope(scope);
    final stored = prefs.getInt(_speedKeyForScope(normalizedScope));
    if (stored == null) {
      return defaultSpeedForScope(normalizedScope);
    }
    return clampSpeed(stored, scope: normalizedScope);
  }

  Future<int> getPressure({String scope = scopeGeneric}) async {
    final prefs = await SharedPreferences.getInstance();
    await _ensureResetApplied(prefs);
    final normalizedScope = normalizeScope(scope);
    final stored = prefs.getInt(_pressureKeyForScope(normalizedScope));
    if (stored == null) {
      return defaultPressureForScope(normalizedScope);
    }
    return clampPressure(stored, scope: normalizedScope);
  }

  Future<bool> getAutoFeed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAutoFeed) ?? defaultAutoFeed;
  }

  Future<bool> getAutoUpdateEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAutoUpdateEnabled) ?? false;
  }

  Future<bool> getAngleEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAngleEnabled) ?? defaultAngleEnabled;
  }

  Future<double> getAngleValue() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyAngleValue) ?? defaultAngleValue;
  }

  Future<bool> getForceLandscape() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyForceLandscape) ?? false;
  }

  Future<void> _ensureResetApplied(SharedPreferences prefs) async {
    final version = prefs.getInt(_keySettingsVersion) ?? 0;
    if (version < _resetVersion) {
      await prefs.remove(_keySpeed);
      await prefs.remove(_keyPressure);
      await prefs.setInt(_keySettingsVersion, _resetVersion);
    }
  }


  Future<void> setSpeed(int value, {String scope = scopeGeneric}) async {
    final prefs = await SharedPreferences.getInstance();
    final normalizedScope = normalizeScope(scope);
    await prefs.setInt(
      _speedKeyForScope(normalizedScope),
      clampSpeed(value, scope: normalizedScope),
    );
  }

  Future<void> setPressure(int value, {String scope = scopeGeneric}) async {
    final prefs = await SharedPreferences.getInstance();
    final normalizedScope = normalizeScope(scope);
    await prefs.setInt(
      _pressureKeyForScope(normalizedScope),
      clampPressure(value, scope: normalizedScope),
    );
  }

  Future<void> setAutoFeed(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoFeed, value);
  }

  Future<void> setAutoUpdateEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoUpdateEnabled, value);
  }

  Future<void> setAngleEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAngleEnabled, value);
  }

  Future<void> setAngleValue(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyAngleValue, value);
  }

  Future<void> setForceLandscape(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyForceLandscape, value);
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
    await AppSettingsService().applyOrientationMode(forceLandscape: value);
  }
}
