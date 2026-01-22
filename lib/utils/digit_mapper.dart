class DigitMapper {
  static const Map<String, String> _digitMap = {
    "0": "2",
    "1": "0",
    "2": "9",
    "3": "7",
    "4": "8",
    "5": "6",
    "6": "4",
    "7": "3",
    "8": "5",
    "9": "1",
  };

  static const Map<String, String> _reverseDigitMap = {
    "2": "0",
    "0": "1",
    "9": "2",
    "7": "3",
    "8": "4",
    "6": "5",
    "4": "6",
    "3": "7",
    "5": "8",
    "1": "9",
  };

  /// Decrypts the PLT file content by reverse mapping the digits in the coordinates.
  /// Used for String content.
  static String decryptPlt(String content) {
    return _transformNumbers(content, _reverseDigitMap);
  }

  /// Encrypts the PLT file content by mapping the digits.
  /// Used for String content.
  static String encryptPlt(String content) {
    return _transformNumbers(content, _digitMap);
  }

  static String _transformNumbers(String content, Map<String, String> map) {
    StringBuffer result = StringBuffer();
    StringBuffer currentNumber = StringBuffer();
    bool isParsingNumber = false;

    for (int i = 0; i < content.length; i++) {
      String char = content[i];
      bool isDigit = int.tryParse(char) != null;

      if (isDigit) {
        currentNumber.write(map[char] ?? char);
        isParsingNumber = true;
      } else {
        if (isParsingNumber) isParsingNumber = false;
        result.write(currentNumber.toString());
        currentNumber.clear();
        result.write(char);
      }
    }
    result.write(currentNumber.toString());
    return result.toString();
  }

  /// Encrypts the PLT file content by mapping the digits at the byte level.
  /// Forward Mapping: 0 -> 2
  static List<int> encryptBytes(List<int> bytes) {
    List<int> result = List<int>.from(bytes);
    Map<int, int> byteMap = {};

    _digitMap.forEach((key, value) {
      if (key.isNotEmpty && value.isNotEmpty) {
        byteMap[key.codeUnitAt(0)] = value.codeUnitAt(0);
      }
    });

    for (int i = 0; i < result.length; i++) {
      int b = result[i];
      if (byteMap.containsKey(b)) {
        result[i] = byteMap[b]!;
      }
    }
    return result;
  }

  /// Decrypts the PLT file content by reverse mapping the digits at the byte level.
  /// Reverse Mapping: 2 -> 0
  static List<int> decryptBytes(List<int> bytes) {
    List<int> result = List<int>.from(bytes);
    Map<int, int> byteMap = {};

    _reverseDigitMap.forEach((key, value) {
      if (key.isNotEmpty && value.isNotEmpty) {
        byteMap[key.codeUnitAt(0)] = value.codeUnitAt(0);
      }
    });

    for (int i = 0; i < result.length; i++) {
      int b = result[i];
      if (byteMap.containsKey(b)) {
        result[i] = byteMap[b]!;
      }
    }
    return result;
  }
}
