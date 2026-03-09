import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_project/core/handshake_response_resolver.dart';
import 'package:flutter_project/utils/encryption_util.dart';

void main() {
  group('HandshakeResponseResolver', () {
    test('normalizes known aliases', () {
      expect(
        HandshakeResponseResolver.normalizeAlgorithm('getpassword2'),
        HandshakeResponseResolver.algoPassWord2,
      );
      expect(
        HandshakeResponseResolver.normalizeAlgorithm('oldpassword'),
        HandshakeResponseResolver.algoOldPassWord,
      );
      expect(
        HandshakeResponseResolver.normalizeAlgorithm('removed_handshake'),
        isNull,
      );
    });

    test('builds the sunshine attempt sequence for aggregate mode', () {
      expect(
        HandshakeResponseResolver.resolveAttemptSequence(
          forcedAlgorithm: HandshakeResponseResolver.algoSunshine,
        ),
        HandshakeResponseResolver.sunshineAlgorithms,
      );
    });

    test('ignores removed legacy algorithms in the preferred slot', () {
      expect(
        HandshakeResponseResolver.resolveAttemptSequence(
          preferredAlgorithm: 'REMOVED_HANDSHAKE',
        ),
        HandshakeResponseResolver.sunshineAlgorithms,
      );
    });

    test('maps challenge responses to the low-level crypto implementation', () {
      const challenge = 123456789;

      expect(
        HandshakeResponseResolver.resolveChallengeResponse(
          algorithm: HandshakeResponseResolver.algoPassWord2,
          challenge: challenge,
        ),
        EncryptionUtil.getHandshakeNew(challenge),
      );
      expect(
        HandshakeResponseResolver.resolveChallengeResponse(
          algorithm: HandshakeResponseResolver.algoOldPassWord,
          challenge: challenge,
        ),
        EncryptionUtil.getHandshakeOldV1(challenge),
      );
      expect(
        HandshakeResponseResolver.resolveChallengeResponse(
          algorithm: HandshakeResponseResolver.algoPassWord,
          challenge: challenge,
        ),
        EncryptionUtil.getHandshakeOldV3(challenge),
      );
    });
  });
}
