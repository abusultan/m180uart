import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_project/core/serial/machine_protocol.dart';
import 'package:flutter_project/services/cut_settings_service.dart';

void main() {
  group('DQ family protocol resolution', () {
    test('maps DQ_HANDSHAKE to DQ protocol commands', () {
      final protocol = MachineProtocolResolver.resolve('DQ_HANDSHAKE');

      expect(protocol.key, 'DQ');
      expect(protocol.pressureCommands(3).join(), contains('BD:100,10,3;'));
      expect(protocol.pressureCommands(3).join(), contains('BD:101,9;'));
    });

    test('maps MECHANIC_UART to DQ protocol commands', () {
      final protocol = MachineProtocolResolver.resolve('MECHANIC_UART');

      expect(protocol.key, 'DQ');
      expect(protocol.speedCommands(2).join(), contains('BD:100,11,2;'));
      expect(protocol.speedCommands(2).join(), contains('BD:101,9;'));
    });
  });

  group('DQ family scope resolution', () {
    test('uses DQ scope for DQ_HANDSHAKE', () {
      final scope = CutSettingsService.resolveScopeForMachine(
        agentType: 'DQ_HANDSHAKE',
      );

      expect(scope, CutSettingsService.scopeDq);
    });

    test('uses DQ scope for MECHANIC_UART', () {
      final scope = CutSettingsService.resolveScopeForMachine(
        agentType: 'MECHANIC_UART',
      );

      expect(scope, CutSettingsService.scopeDq);
    });

    test('uses DQ scope for MT serial machines', () {
      final scope = CutSettingsService.resolveScopeForMachine(
        serialNumber: 'MT123456',
      );

      expect(scope, CutSettingsService.scopeDq);
    });
  });
}
