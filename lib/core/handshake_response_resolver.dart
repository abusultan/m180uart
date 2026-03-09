import '../utils/encryption_util.dart';

class HandshakeResponseResolver {
  static const String algoSunshine = 'SUNSHINE';
  static const String algoPassWord2 = 'HANDSHAKE_NEW';
  static const String algoOldPassWord = 'OLD_V1';
  static const String algoPassWord = 'OLD_V3';

  static const List<String> sunshineAlgorithms = [
    algoPassWord2,
    algoOldPassWord,
    algoPassWord,
  ];

  static const List<String> supportedAlgorithms = [...sunshineAlgorithms];

  static String? normalizeAlgorithm(String? raw) {
    if (raw == null) return null;

    final normalized = raw.trim().toUpperCase();
    if (normalized.isEmpty) return null;

    switch (normalized) {
      case 'SUNSHINE':
      case 'AUTO':
      case 'AUTO_TRY':
        return algoSunshine;
      case 'HANDSHAKE_NEW':
      case 'HANDSHAKENEW':
      case 'STANDARD':
      case 'GENERIC_NEW':
      case 'DQ':
      case 'DEVIA':
      case 'SY':
      case 'CUTTER':
      case 'PASS_U32':
      case 'PASSWORD2':
      case 'PASS_WORD2':
      case 'GETPASSWORD2':
        return algoPassWord2;
      case 'OLD_V1':
      case 'GETOLDPASSWORD':
      case 'OLDPASSWORD':
      case 'PASS_WORD_OLD':
        return algoOldPassWord;
      case 'OLD_V3':
      case 'PASSWORD':
      case 'PASS_WORD':
      case 'GETPASSWORD':
        return algoPassWord;
      default:
        return null;
    }
  }

  static String normalizeOrDefault(
    String? raw, {
    String fallback = algoPassWord2,
  }) {
    return normalizeAlgorithm(raw) ?? fallback;
  }

  static List<String> resolveAttemptSequence({
    String? forcedAlgorithm,
    String? preferredAlgorithm,
  }) {
    final forced = normalizeAlgorithm(forcedAlgorithm);
    if (forced != null) {
      if (forced == algoSunshine) {
        return List<String>.from(sunshineAlgorithms);
      }
      return [forced];
    }

    final preferred = normalizeAlgorithm(preferredAlgorithm);
    if (preferred == null || preferred == algoSunshine) {
      return List<String>.from(sunshineAlgorithms);
    }

    final algorithms = List<String>.from(sunshineAlgorithms);
    algorithms.remove(preferred);
    algorithms.insert(0, preferred);
    return algorithms;
  }

  static int resolveChallengeResponse({
    required String algorithm,
    required int challenge,
  }) {
    final normalized = normalizeOrDefault(algorithm);
    if (normalized == algoOldPassWord) {
      return EncryptionUtil.getHandshakeOldV1(challenge);
    }
    if (normalized == algoPassWord) {
      return EncryptionUtil.getHandshakeOldV3(challenge);
    }
    return EncryptionUtil.getHandshakeNew(challenge);
  }

  static int resolvePrintHandshakeResponse(int challenge) {
    return EncryptionUtil.getDQHandshake(challenge);
  }
}
