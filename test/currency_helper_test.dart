import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/core/utils/currency_helper.dart';

void main() {
  group('CurrencyHelper Tests', () {
    test('Formats currency amounts correctly with symbols', () {
      expect(CurrencyHelper.formatAmount(4800, 'JPY'), '¥4,800');
      expect(CurrencyHelper.formatAmount(1500, 'THB'), '฿1,500');
      expect(CurrencyHelper.formatAmount(50.5, 'USD'), '\$50.50');
      expect(
        CurrencyHelper.formatAmount(2400, 'JPY', showSign: true),
        '+¥2,400',
      );
    });

    test('Computes approximate secondary currency subtitles', () {
      // 56700 JPY -> ~$378 USD
      final subUsd = CurrencyHelper.getSecondarySubtitle(
        56700,
        'JPY',
        target: 'USD',
      );
      expect(subUsd, '~\$378 USD');

      // 4800 JPY -> ~$32 USD
      final sub4800 = CurrencyHelper.getSecondarySubtitle(
        4800,
        'JPY',
        target: 'USD',
      );
      expect(sub4800, '~\$32 USD');

      // 4800 JPY -> THB (~฿1,136)
      final subJpy = CurrencyHelper.getSecondarySubtitle(
        4800,
        'JPY',
        target: 'THB',
      );
      expect(subJpy, isNotNull);
      expect(subJpy, contains('฿'));

      // USD -> JPY
      final subFromUsd = CurrencyHelper.getSecondarySubtitle(100, 'USD');
      expect(subFromUsd, isNotNull);
      expect(subFromUsd, contains('¥'));
    });
  });
}
