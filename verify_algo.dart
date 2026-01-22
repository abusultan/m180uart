void main() {
  int seed = 666649373;
  print("Dart Results for seed: $seed");

  // Case 0: Sunshine
  int res0 = getSunshinePassword(seed, "SUNSHINE");
  print("SUNSHINE (0): $res0");

  // Case 1: Sunshine Masked
  int res1 = res0 & 0xFFFFFFFF;
  print("SUNSHINE Masked (1): $res1");
}

int getSunshinePassword(int challenge, String brand) {
  int result = 0;
  if (brand.contains("SUNSHINE")) {
    // (((challenge + 309809441) ^ 287852129) - 556077345) ^ -2011081661;
    int s = challenge + 309809441;
    s = s ^ 287852129;
    s = s - 556077345;
    result = s ^ -2011081661;
  }
  return result;
}
