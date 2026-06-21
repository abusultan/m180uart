/// SJM Cipher - Dynamic substitution cipher for DQ/Skycut cutting machines.
///
/// This replicates the native JNI `cmd_GetPassWordCutChar` algorithm.
/// The cipher generates a 10-digit substitution map from a 15-character seed
/// (found in the file header as `SJM=<15 digits>`).
///
/// Usage:
/// ```dart
/// final keyMap = SjmCipher.generateKeyMap("515167676782828");
/// final encrypted = SjmCipher.encrypt(keyMap, "U500,600");  // encrypt for machine
/// final decrypted = SjmCipher.decrypt(keyMap, "U611,411");  // decrypt from file
/// ```
class SjmCipher {
  SjmCipher._();

  // Index arrays selected based on the last character of the 15-digit seed
  static const List<int> _numArr1 = [2, 4, 6, 8, 10, 12, 14, 3, 5, 7]; // lastChar == '1'
  static const List<int> _numArr2 = [3, 12, 0, 7, 4, 1, 9, 13, 8, 11]; // lastChar == '2'
  static const List<int> _numArr3 = [3, 5, 6, 8, 4, 1, 9, 13, 7, 11]; // lastChar == '3'
  static const List<int> _numArr4 = [1, 3, 7, 9, 2, 6, 4, 12, 13, 5]; // lastChar == '8'
  static const List<int> _numArr5 = [2, 4, 7, 9, 3, 6, 4, 10, 13, 1]; // lastChar == '9'

  /// Generate the 10-element key map from a 15-character SJM seed.
  /// Returns null if seed is invalid.
  static List<String>? generateKeyMap(String seed) {
    if (seed.length < 15) return null;

    final charArray = seed.split('');
    final lastChar = charArray[14];

    // Select index array based on last digit
    List<int>? numArr;
    switch (lastChar) {
      case '1':
        numArr = _numArr1;
        break;
      case '2':
        numArr = _numArr2;
        break;
      case '3':
        numArr = _numArr3;
        break;
      case '8':
        numArr = _numArr4;
        break;
      case '9':
        numArr = _numArr5;
        break;
      default:
        // Unknown last digit - try numArr4 as fallback (most common)
        numArr = _numArr4;
        break;
    }

    // Step 1: Pick 10 characters from seed using index array
    final keyMap = <String>[];
    for (int i = 0; i < 10; i++) {
      final idx = numArr[i];
      if (idx >= charArray.length) return null;
      keyMap.add(charArray[idx]);
    }

    // Step 2: Find which digits (0-9) are NOT present in keyMap
    final unusedDigits = List<int>.generate(10, (i) => i);
    for (int i = 0; i < 10; i++) {
      final val = unusedDigits[i];
      for (int j = 0; j < keyMap.length; j++) {
        final parsed = int.tryParse(keyMap[j]);
        if (parsed != null && val == parsed) {
          unusedDigits[i] = -1;
          break;
        }
      }
    }

    // Step 3: Mark duplicate entries as 's'
    for (int i = 0; i < keyMap.length; i++) {
      if (keyMap[i] != 's') {
        for (int j = i + 1; j < keyMap.length; j++) {
          if (keyMap[j] == keyMap[i]) {
            keyMap[j] = 's';
          }
        }
      }
    }

    // Step 4: Fill 's' slots with unused digits in order
    int unusedIdx = 0;
    for (int i = 0; i < keyMap.length; i++) {
      if (keyMap[i] == 's') {
        while (unusedIdx < 10 && unusedDigits[unusedIdx] == -1) {
          unusedIdx++;
        }
        if (unusedIdx < 10) {
          keyMap[i] = unusedDigits[unusedIdx].toString();
          unusedDigits[unusedIdx] = -1;
        }
      }
    }

    return keyMap;
  }

  /// Encrypt a coordinate string (for sending new text to machine).
  /// digit d → keyMap[d]
  ///
  /// Example: encrypt(keyMap, "U500,600") → "U611,411"
  static String encrypt(List<String> keyMap, String value) {
    final sb = StringBuffer();
    String cleanVal = value;

    // Preserve U/D prefix
    if (value.isNotEmpty && (value[0] == 'U' || value[0] == 'D')) {
      sb.write(value[0]);
      cleanVal = value.substring(1);
    }

    for (final char in cleanVal.split('')) {
      if (char == '-' || char == ',') {
        sb.write(char);
      } else {
        final digit = int.tryParse(char);
        if (digit != null && digit >= 0 && digit < keyMap.length) {
          sb.write(keyMap[digit]);
        } else {
          sb.write(char);
        }
      }
    }

    return sb.toString();
  }

  /// Decrypt a coordinate string (for reading file data to display).
  /// char c → indexOf(c) in keyMap
  ///
  /// Example: decrypt(keyMap, "U611,411") → "U500,600"
  static String decrypt(List<String> keyMap, String value) {
    final sb = StringBuffer();
    String cleanVal = value;

    // Preserve U/D prefix
    if (value.isNotEmpty && (value[0] == 'U' || value[0] == 'D')) {
      sb.write(value[0]);
      cleanVal = value.substring(1);
    }

    for (final char in cleanVal.split('')) {
      if (char == '-' || char == ',') {
        sb.write(char);
      } else {
        final index = keyMap.indexOf(char);
        if (index >= 0) {
          sb.write(index.toString());
        } else {
          sb.write(char);
        }
      }
    }

    return sb.toString();
  }

  /// Extract the SJM seed from file content.
  /// Returns null if no SJM= found.
  static String? extractSeed(String content) {
    final idx = content.indexOf('SJM=');
    if (idx == -1) return null;
    final start = idx + 4;
    // Seed is 15 digits after SJM=
    if (start + 15 > content.length) return null;
    final seed = content.substring(start, start + 15);
    // Verify it's all digits
    if (!RegExp(r'^\d{15}$').hasMatch(seed)) return null;
    return seed;
  }

  /// Decrypt FSIZE value from file
  /// Example: "FSIZE4260,6954" with seed mapping → real width/height
  static ({int width, int height})? decryptFsize(List<String> keyMap, String content) {
    final fsizeIdx = content.indexOf('FSIZE');
    if (fsizeIdx == -1) return null;
    
    final afterFsize = content.substring(fsizeIdx + 5);
    final semiIdx = afterFsize.indexOf(';');
    final fsizeStr = semiIdx >= 0 ? afterFsize.substring(0, semiIdx) : afterFsize.split(' ').first;
    
    final parts = fsizeStr.split(',');
    if (parts.length != 2) return null;
    
    final decW = decrypt(keyMap, parts[0]);
    final decH = decrypt(keyMap, parts[1]);
    
    final width = int.tryParse(decW);
    final height = int.tryParse(decH);
    
    if (width == null || height == null) return null;
    return (width: width, height: height);
  }
}
