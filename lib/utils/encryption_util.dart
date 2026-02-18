/// Utility class for password encryption and device commands
/// Ported from Android StringChangeUtil.java
///
/// CRITICAL: Dart uses 64-bit integers by default.
/// We MUST use bitwise AND ( & 0xFFFFFFFF) to emulate Java's 32-bit int overflow behavior.
class EncryptionUtil {
  // 32-bit mask for emulating Java's int behavior
  static const int MASK_32 = 0xFFFFFFFF;
  static const int _SIGN_BIT = 0x80000000;

  /// Casts to signed 32-bit int (Java int behavior).
  static int _toInt32(int value) {
    final masked = value & MASK_32;
    if ((masked & _SIGN_BIT) != 0) {
      return masked - 0x100000000;
    }
    return masked;
  }

  /// The "New" Handshake (Sunshine)
  /// Corresponds to User's 'handshakeNew'
  static int getHandshakeNew(int serverValue) {
    int result = serverValue & MASK_32; // input

    // result = (((result ^ 410665463) & 4294967295L) + 859313513) & 4294967295L;
    result = (result ^ 410665463) & MASK_32;
    result = (result + 859313513) & MASK_32;

    // result = (result ^ 1368461889) & 4294967295L;
    result = (result ^ 1368461889) & MASK_32;

    // result = (result - -1789835113) & 4294967295L;
    // - -1789835113 is equivalent to + 1789835113
    result = (result + 1789835113) & MASK_32;

    return result;
  }

  /// DQ Machine Handshake (Skycut)
  /// Specific algorithm for DQ serial number machines
  static int getDQHandshake(int seed) {
    int val = (seed ^ 89428503) & MASK_32;
    val = (val + 36213271) & MASK_32;
    val = (val ^ 109659922) & MASK_32;
    val = (val - 18096792) & MASK_32;
    return val & MASK_32;
  }

  /// PASS_U32 validation (Upprinting)
  /// Corresponds to PrintUtil.Cmd_DePassU32
  static int getPassU32Expected(int seed) {
    int val = seed & MASK_32;
    val = (val + 908153991) & MASK_32;
    val = (val ^ 1092948257) & MASK_32;
    val = (val - 1361593975) & MASK_32;
    val = (val ^ 309809476) & MASK_32;
    return val & MASK_32;
  }

  /// Rockspace SN-based handshake.
  /// Port of:
  /// snCalculate(String pid, String sn)
  /// Returns unsigned 32-bit result.
  static int getRockspaceSnHandshake({
    required String pid,
    required String sn,
  }) {
    final pidCodes = pid.codeUnits;
    final snCodes = sn.codeUnits;
    final pid20 = List<int>.filled(20, 0);

    final copyCount = pidCodes.length < 20 ? pidCodes.length : 20;
    for (int idx = 0; idx < copyCount; idx++) {
      pid20[idx] = pidCodes[idx];
    }

    int i = 0;
    int i2 = 0;
    int i3 = 0;

    for (int idx = 0; idx < 20; idx++) {
      final c = pid20[idx];
      i = _toInt32(i + c);
      i2 = _toInt32(i2 - c);

      final mix = _toInt32(_toInt32(i2 << 16) + i);
      final step = _toInt32(_toInt32(mix + 579428743) ^ -2074003131);
      i3 = _toInt32(i3 + step);
    }

    for (int idx = 0; idx < snCodes.length; idx++) {
      final c = snCodes[idx];
      i = _toInt32(i - c);
      i2 = _toInt32(i2 + c);

      final mix = _toInt32(_toInt32(i2 << 16) + i);
      final step = _toInt32(_toInt32(mix + 421664280) ^ 558379537);
      i3 = _toInt32(i3 + step);
    }

    return i3 & MASK_32;
  }

  /// Rockspace RCMD challenge handshake:
  /// l ^= 421820515; l += 915960850; l ^= 913393031; l += 1418168705;
  static int getRockspaceChallenge(int challenge) {
    int val = challenge & MASK_32;
    val = _toInt32(val ^ 421820515);
    val = _toInt32(val + 915960850);
    val = _toInt32(val ^ 913393031);
    val = _toInt32(val + 1418168705);
    return val & MASK_32;
  }

  /// Old V1
  /// Corresponds to User's 'handshakeOldV1'
  static int getHandshakeOldV1(int serverValue) {
    // The original Java method takes a `long j2` (64-bit) and the first operation
    // `(j2 < 279999 ? j2 + 279999 : j2 - 279999) & MASK_32;`
    // implies the conditional arithmetic happens first, then the result is masked.
    // Dart's `int` is 64-bit, so `serverValue` can be treated directly.
    int result =
        (serverValue < 279999 ? serverValue + 279999 : serverValue - 279999) &
        MASK_32;

    // result = (result ^ 64755557) & 4294967295L;
    result = (result ^ 64755557) & MASK_32;

    // result = (result & 268435455);
    result = result & 268435455;

    return result;
  }

  /// Old V3
  /// Corresponds to User's 'handshakeOldV3'
  static int getHandshakeOldV3(int serverValue) {
    int result = serverValue & MASK_32;

    // result = (((result ^ -2088463848) & 4294967295L) + 1377142310) & 4294967295L;
    result =
        (result ^ -2088463848) &
        MASK_32; // -2088... is valid int in Dart (64bit), cast to 32bit via mask if needed but XOR handles bits.
    result = (result + 1377142310) & MASK_32;

    // result = (result ^ 1145538881) & 4294967295L;
    result = (result ^ 1145538881) & MASK_32;

    // result = (result - 303323001) & 4294967295L;
    result = (result - 303323001) & MASK_32;

    return result;
  }

  /// Brand-specific password encryption (New Version Protocol)
  /// Corresponds to Java's getPassWord2
  /// Supports: DEVIA, SY, SUNSHINE, CUTTER
  static int getSunshinePassword(int challenge, String agentClassName) {
    const List<String> machines = ["DEVIA", "SY", "SUNSHINE", "CUTTER"];

    // Default logic if agent is empty or not found
    if (agentClassName.isEmpty) {
      int result = challenge;
      result = (result + 310858017) & MASK_32;
      result = (result ^ 589842024) & MASK_32;
      result = (result - 287642402) & MASK_32;
      result = (result ^ 1645561111) & MASK_32;
      return result;
    }

    // Check for each machine type
    for (int i = 0; i < machines.length; i++) {
      if (agentClassName.contains(machines[i])) {
        int result = challenge;

        if (i == 0) {
          // DEVIA
          result = (result + 309809441) & MASK_32;
          result = (result ^ 321406568) & MASK_32;
          result = (result - 556077346) & MASK_32;
          result = (result ^ 1645560967) & MASK_32;
          return result;
        } else if (i == 1) {
          // SY
          result = (result + 309809441) & MASK_32;
          result = (result ^ 287852135) & MASK_32;
          result = (result - 287641891) & MASK_32;
          result = (result ^ 404837445) & MASK_32;
          return result;
        } else if (i == 2) {
          // SUNSHINE
          result = (result + 309809441) & MASK_32;
          result = (result ^ 287852129) & MASK_32;
          result = (result - 556077345) & MASK_32;
          result = (result ^ -2011081661) & MASK_32;
          return result;
        } else if (i == 3) {
          // CUTTER
          result = (result + 410472737) & MASK_32;
          result = (result ^ 388515431) & MASK_32;
          result = (result - 589631778) & MASK_32;
          result = (result ^ -2061413305) & MASK_32;
          return result;
        }
      }
    }

    // Fallback default (same as empty agent)
    int result = challenge;
    result = (result + 310858017) & MASK_32;
    result = (result ^ 589842024) & MASK_32;
    result = (result - 287642402) & MASK_32;
    result = (result ^ 1645561111) & MASK_32;
    return result;
  }
}
