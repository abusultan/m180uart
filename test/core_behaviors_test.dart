import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_project/core/cut_file_transformer.dart';

void main() {
  group('CutFileTransformer preparation', () {
    test('keeps wide-machine SJC prefix intact during preparation', () {
      final input = latin1.encode(
        'IN WSJP=1029167350 U0,0 D0,0 D0,80 U0,0 D960,0 U6284,467 D6282,489 @',
      );

      final preparation = CutFileTransformer.prepareForMachine(
        inputBytes: input,
        maxWidth: 195,
      );
      final output = latin1.decode(preparation.bytes);

      expect(preparation.isSjcFile, isTrue);
      expect(preparation.shouldNormalizeSjc, isFalse);
      expect(preparation.keepsOriginalSjcPrefix, isTrue);
      expect(preparation.previewData, isNotNull);
      expect(output, contains('D0,80'));
      expect(output, contains('U6284,467'));
      expect(output, contains('D6282,489'));
    });

    test('normalizes narrow-machine SJC payload during preparation', () {
      final input = latin1.encode(
        'IN WSJP=1029167350 U0,0 D0,0 D0,80 U0,0 D960,0 U6284,467 D6282,489 @',
      );

      final preparation = CutFileTransformer.prepareForMachine(
        inputBytes: input,
        maxWidth: 120,
      );
      final output = latin1.decode(preparation.bytes);

      expect(preparation.isSjcFile, isTrue);
      expect(preparation.shouldNormalizeSjc, isTrue);
      expect(preparation.keepsOriginalSjcPrefix, isFalse);
      expect(preparation.previewData, isNotNull);
      expect(output, contains('WSJP=6240092912'));
      expect(output, isNot(contains('D0,80')));
      expect(preparation.previewData!.minX, 0);
      expect(preparation.previewData!.minY, 0);
      expect(preparation.previewData!.points.first.dx, 2);
      expect(preparation.previewData!.points.first.dy, 0);
    });
  });
}
