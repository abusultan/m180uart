import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Mietubl 180T communication protocol.
/// All commands use binary packets with SHA256 CRC (new protocol)
/// or simple byte-sum checksum (old protocol).
class MietublProtocol {
  static const String newHead = '9CC9';
  static const String beforeHead = '5AA5';
  static const String defaultPassword = 'mtbznqmji4368637';

  /// Build a SET command (write to machine)
  static Uint8List makeSetCmd(String payload, {int cmdflag = 2, String pwd = defaultPassword}) {
    String str;
    if (cmdflag == 1) {
      // Old protocol: 5AA5 + BB + payload + bytesum + 0D0A
      str = "BB$payload";
      int sum = 0;
      for (int i = 0; i < str.length; i += 2) {
        sum += int.parse(str.substring(i, i + 2), radix: 16);
      }
      final crc = sum & 0xFF;
      final hexCommand = "$beforeHead$str${crc.toRadixString(16).padLeft(2, '0').toUpperCase()}0D0A";
      return _hexToBytes(hexCommand);
    } else {
      // New protocol: 9CC9 + 66 + payload + SHA256_CRC + 0D0A
      str = "66$payload";
      final cm = _hexToBytesList(str);
      final crcBytes = _calCRC(cm, pwd: pwd);
      final crcStr = crcBytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join('');
      final hexCommand = "$newHead$str${crcStr}0D0A";
      return _hexToBytes(hexCommand);
    }
  }

  /// Build a GET command (read from machine)
  static Uint8List makeGetCmd(String payload, {int cmdflag = 2, String pwd = defaultPassword}) {
    String str;
    if (cmdflag == 1) {
      // Old protocol: 5AA5 + AA + payload + bytesum + 0D0A
      str = "AA$payload";
      int sum = 0;
      for (int i = 0; i < str.length; i += 2) {
        sum += int.parse(str.substring(i, i + 2), radix: 16);
      }
      final crc = sum & 0xFF;
      final hexCommand = "$beforeHead$str${crc.toRadixString(16).padLeft(2, '0').toUpperCase()}0D0A";
      return _hexToBytes(hexCommand);
    } else {
      // New protocol: 9CC9 + 55 + payload + SHA256_CRC + 0D0A
      str = "55$payload";
      final cm = _hexToBytesList(str);
      final crcBytes = _calCRC(cm, pwd: pwd);
      final crcStr = crcBytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join('');
      final hexCommand = "$newHead$str${crcStr}0D0A";
      return _hexToBytes(hexCommand);
    }
  }

  /// SHA256-based CRC: sha256(command_bytes + password_bytes), then
  /// sum first 16 hash bytes → crc[0], sum last 16 hash bytes → crc[1]
  static List<int> _calCRC(List<int> cm, {String pwd = defaultPassword}) {
    final bArr = <int>[...cm];
    if (pwd.isNotEmpty) {
      bArr.addAll(pwd.codeUnits);
    }
    final hash = sha256.convert(bArr).bytes;
    int crc0 = 0, crc1 = 0;
    for (int i = 0; i < 16; i++) {
      crc0 = (crc0 + hash[i]) & 0xFF;
      crc1 = (crc1 + hash[i + 16]) & 0xFF;
    }
    return [crc0, crc1];
  }

  static List<int> _hexToBytesList(String hexStr) {
    final bytes = <int>[];
    for (int i = 0; i < hexStr.length; i += 2) {
      bytes.add(int.parse(hexStr.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }

  static Uint8List _hexToBytes(String hexStr) {
    return Uint8List.fromList(_hexToBytesList(hexStr));
  }

  static String _toLittleEndianHex(int value, int bytes) {
    String result = '';
    for (int i = 0; i < bytes; i++) {
      int b = (value >> (i * 8)) & 0xFF;
      result += b.toRadixString(16).padLeft(2, '0').toUpperCase();
    }
    return result;
  }

  // ===== Machine Commands =====

  /// Test machine (makes it move/beep)
  static Uint8List testMachine({int cmdflag = 2, String pwd = defaultPassword}) {
    return makeSetCmd("00170000", cmdflag: cmdflag, pwd: pwd);
  }

  /// Set knife pressure (0-255)
  static Uint8List setPressure(int pressure, {int cmdflag = 2, String pwd = defaultPassword}) {
    final p = _toLittleEndianHex(pressure.clamp(0, 255), 2);
    return makeSetCmd("00110200$p", cmdflag: cmdflag, pwd: pwd);
  }

  /// Set cut speed (0-255)
  static Uint8List setSpeed(int speed, {int cmdflag = 2, String pwd = defaultPassword}) {
    final s = _toLittleEndianHex(speed.clamp(0, 255), 2);
    return makeSetCmd("00100200$s", cmdflag: cmdflag, pwd: pwd);
  }

  /// Query machine version
  static Uint8List queryVersion({int cmdflag = 2, String pwd = defaultPassword}) {
    return makeGetCmd("00210000", cmdflag: cmdflag, pwd: pwd);
  }

  /// Query machine status
  static Uint8List queryStatus({int cmdflag = 2, String pwd = defaultPassword}) {
    return makeGetCmd("001E0000", cmdflag: cmdflag, pwd: pwd);
  }

  /// Query machine pressure
  static Uint8List queryPressure({int cmdflag = 2, String pwd = defaultPassword}) {
    return makeGetCmd("00110000", cmdflag: cmdflag, pwd: pwd);
  }

  /// Query machine speed
  static Uint8List querySpeed({int cmdflag = 2, String pwd = defaultPassword}) {
    return makeGetCmd("00100000", cmdflag: cmdflag, pwd: pwd);
  }

  /// Query machine code (serial number)
  static Uint8List queryMachineCode({int cmdflag = 2, String pwd = defaultPassword}) {
    return makeGetCmd("00200000", cmdflag: cmdflag, pwd: pwd);
  }

  /// Set auto paper feeder
  static Uint8List setAutoPager(bool enable, {int cmdflag = 2, String pwd = defaultPassword}) {
    final val = enable ? "01" : "00";
    return makeSetCmd("00120100$val", cmdflag: cmdflag, pwd: pwd);
  }

  /// Output paper
  static Uint8List outPaper(bool forward, {int cmdflag = 2, String pwd = defaultPassword}) {
    final val = forward ? "01" : "00";
    return makeSetCmd("00130100$val", cmdflag: cmdflag, pwd: pwd);
  }

  /// Reset knife position
  static Uint8List resetKnife({int cmdflag = 2, String pwd = defaultPassword}) {
    return makeSetCmd("00180000", cmdflag: cmdflag, pwd: pwd);
  }
}
