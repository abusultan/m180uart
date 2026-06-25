/// Machine protocol resolver - for M180T only.
abstract class MachineProtocol {
  const MachineProtocol();
  String get key;
  List<String> speedCommands(int speedLevel);
  List<String> pressureCommands(int pressureForce);
  List<String> testCutCommands();
}

class MietublMachineProtocol extends MachineProtocol {
  const MietublMachineProtocol();

  @override
  String get key => '180T_MIETUBL';

  @override
  List<String> speedCommands(int speedLevel) => [];

  @override
  List<String> pressureCommands(int pressureForce) => [];

  @override
  List<String> testCutCommands() => [];
}

class MachineProtocolResolver {
  const MachineProtocolResolver._();

  static const MachineProtocol _mietubl = MietublMachineProtocol();

  static MachineProtocol resolve(String? agentType, {
    bool isSunshineFamily = false,
    bool isLegacySunshine = false,
  }) {
    return _mietubl;
  }
}
