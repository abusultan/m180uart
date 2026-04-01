abstract class MachineProtocol {
  const MachineProtocol();

  String get key;

  List<String> speedCommands(int speedLevel);
  List<String> pressureCommands(int pressureForce);
  List<String> inductionCommands(bool isOn);
  List<String> ledCommands(int level);
  List<String> testCutCommands();
}

int _normalizeSunshineLevel(int value) {
  if (value < 1) return 1;
  if (value > 4) return 4;
  return value;
}

int _normalizeDqSpeedLevel(int value) {
  if (value < 1) return 1;
  if (value > 4) return 4;
  return value;
}

int _normalizeDqPressureLevel(int value) {
  if (value < 1) return 1;
  if (value > 5) return 5;
  return value;
}

class GenericMachineProtocol extends MachineProtocol {
  const GenericMachineProtocol();

  @override
  String get key => 'GENERIC';

  @override
  List<String> speedCommands(int speedLevel) => [';BD:100,11,$speedLevel;'];

  @override
  List<String> pressureCommands(int pressureForce) => [
    ';BD:100,12,$pressureForce;',
  ];

  @override
  List<String> inductionCommands(bool isOn) => [
    isOn ? ';BD:34,1;BD:34;' : ';BD:34,0;BD:34;',
  ];

  @override
  List<String> ledCommands(int level) {
    if (level == 0) return [';LED0,0,0;'];
    if (level == 1) return [';LED100,100,100;'];
    if (level == 2) return [';LED180,180,180;'];
    return [';LED255,255,255;'];
  }

  @override
  List<String> testCutCommands() => [';BD:100,100;'];
}

class DqMachineProtocol extends MachineProtocol {
  const DqMachineProtocol();

  @override
  String get key => 'DQ';

  @override
  List<String> speedCommands(int speedLevel) => [
    ';BD:100,11,${_normalizeDqSpeedLevel(speedLevel)};BD:101,9;',
  ];

  @override
  List<String> pressureCommands(int pressureForce) => [
    ';BD:100,10,${_normalizeDqPressureLevel(pressureForce)};BD:101,9;',
  ];

  @override
  List<String> inductionCommands(bool isOn) => [
    isOn ? ';BD:34,1;BD:34;' : ';BD:34,0;BD:34;',
  ];

  @override
  List<String> ledCommands(int level) {
    if (level == -1) return [';BD:101,9;'];
    if (level == 0) return [';LED0,0,0;BD:101,9;'];
    if (level == 1) return [';LED100,100,100;BD:101,9;'];
    if (level == 2) return [';LED180,180,180;BD:101,9;'];
    return [';LED255,255,255;BD:101,9;'];
  }

  @override
  List<String> testCutCommands() => [';BD:100,100;'];
}

class SunshineMachineProtocol extends MachineProtocol {
  const SunshineMachineProtocol({required this.isLegacy});

  final bool isLegacy;

  @override
  String get key => isLegacy ? 'SUNSHINE_LEGACY' : 'SUNSHINE';

  @override
  List<String> speedCommands(int speedLevel) {
    final level = _normalizeSunshineLevel(speedLevel);
    if (isLegacy) {
      return [';BD:100,11,$level;'];
    }
    return [';BD:100,11,$level;BD:101,9;'];
  }

  @override
  List<String> pressureCommands(int pressureLevel) {
    final level = _normalizeSunshineLevel(pressureLevel);
    if (isLegacy) {
      final legacyForce = ((level - 1) * 15) + 30;
      return [';BD:100,12,$legacyForce;'];
    }
    return [';BD:100,10,$level;BD:101,9;'];
  }

  @override
  List<String> inductionCommands(bool isOn) => [
    isOn ? ';BD:34,1;BD:34;' : ';BD:34,0;BD:34;',
  ];

  @override
  List<String> ledCommands(int level) {
    if (level == 0) return [';LED0,0,0;'];
    if (level == 1) return [';LED100,100,100;'];
    if (level == 2) return [';LED180,180,180;'];
    return [';LED255,255,255;'];
  }

  @override
  List<String> testCutCommands() => [';BD:100,100;'];
}

class MachineProtocolResolver {
  const MachineProtocolResolver._();

  static const MachineProtocol _generic = GenericMachineProtocol();
  static const MachineProtocol _dq = DqMachineProtocol();
  static const MachineProtocol _sunshine = SunshineMachineProtocol(
    isLegacy: false,
  );
  static const MachineProtocol _sunshineLegacy = SunshineMachineProtocol(
    isLegacy: true,
  );

  static MachineProtocol resolve(
    String? agentType, {
    bool isSunshineFamily = false,
    bool isLegacySunshine = false,
  }) {
    if (isSunshineFamily) {
      return isLegacySunshine ? _sunshineLegacy : _sunshine;
    }
    final algo = (agentType ?? '').trim().toUpperCase();
    if (algo == 'DQ' || algo == 'DX' || algo == 'LH') {
      return _dq;
    }
    return _generic;
  }
}
