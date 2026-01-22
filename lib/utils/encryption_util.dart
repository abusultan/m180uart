/// Utility class for password encryption and device commands
/// Ported from Android StringChangeUtil.java
///
/// CRITICAL: Dart uses 64-bit integers by default.
/// We MUST use bitwise AND ( & 0xFFFFFFFF) to emulate Java's 32-bit int overflow behavior.
class EncryptionUtil {
  // 32-bit mask for emulating Java's int behavior
  static const int MASK_32 = 0xFFFFFFFF;

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
