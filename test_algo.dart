// Brute force test to find which algorithm matches the log
// Seed: 1385627655
// Expected Password: 1459896585

void main() {
  int seed = 1385627655;
  int expected = 1459896585;

  print("Testing Seed: $seed Expecting: $expected");

  test("New Default", getHandshakeNew(seed), expected);
  test("DQ", getDQHandshake(seed), expected);
  test("Old V1", getHandshakeOldV1(seed), expected);
  test("Old V3", getHandshakeOldV3(seed), expected);

  test(
    "Sunshine Password (DEVIA)",
    getSunshinePassword(seed, "DEVIA"),
    expected,
  );
  test("Sunshine Password (SY)", getSunshinePassword(seed, "SY"), expected);
  test(
    "Sunshine Password (SUNSHINE)",
    getSunshinePassword(seed, "SUNSHINE"),
    expected,
  );
  test(
    "Sunshine Password (CUTTER)",
    getSunshinePassword(seed, "CUTTER"),
    expected,
  );
  test("Sunshine Password (Empty)", getSunshinePassword(seed, ""), expected);
}

void test(String name, int actual, int expected) {
  if (actual == expected) {
    print("MATCH FOUND: $name");
  } else {
    print("Fail: $name -> $actual");
  }
}

// 32-bit mask for emulating Java's int behavior
const int MASK_32 = 0xFFFFFFFF;

/// The "New" Handshake (Sunshine)
int getHandshakeNew(int serverValue) {
  int result = serverValue & MASK_32;

  result = (result ^ 410665463) & MASK_32;
  result = (result + 859313513) & MASK_32;
  result = (result ^ 1368461889) & MASK_32;
  result = (result + 1789835113) & MASK_32;

  return result;
}

/// DQ Machine Handshake
int getDQHandshake(int seed) {
  int val = (seed ^ 89428503) & MASK_32;
  val = (val + 36213271) & MASK_32;
  val = (val ^ 109659922) & MASK_32;
  val = (val - 18096792) & MASK_32;
  return val & MASK_32;
}

/// Old V1
int getHandshakeOldV1(int serverValue) {
  int result =
      (serverValue < 279999 ? serverValue + 279999 : serverValue - 279999) &
      MASK_32;
  result = (result ^ 64755557) & MASK_32;
  result = result & 268435455;
  return result;
}

/// Old V3
int getHandshakeOldV3(int serverValue) {
  int result = serverValue & MASK_32;
  result = (result ^ -2088463848) & MASK_32;
  result = (result + 1377142310) & MASK_32;
  result = (result ^ 1145538881) & MASK_32;
  result = (result - 303323001) & MASK_32;
  return result;
}

/// Brand-specific
int getSunshinePassword(int challenge, String agentClassName) {
  List<String> machines = ["DEVIA", "SY", "SUNSHINE", "CUTTER"];

  if (agentClassName.isEmpty) {
    int result = challenge;
    result = (result + 310858017) & MASK_32;
    result = (result ^ 589842024) & MASK_32;
    result = (result - 287642402) & MASK_32;
    result = (result ^ 1645561111) & MASK_32;
    return result;
  }

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

  int result = challenge;
  result = (result + 310858017) & MASK_32;
  result = (result ^ 589842024) & MASK_32;
  result = (result - 287642402) & MASK_32;
  result = (result ^ 1645561111) & MASK_32;
  return result;
}
