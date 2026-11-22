import 'package:intl/intl.dart';

class CurrencyHelper {
  static const Map<String, String> currencySymbols = {
    'THB': '฿',
    'JPY': '¥',
    'USD': '\$',
    'EUR': '€',
    'KRW': '₩',
    'GBP': '£',
    'CNY': 'CN¥',
    'SGD': 'S\$',
    'AUD': 'A\$',
    'CAD': 'C\$',
    'CHF': 'CHF ',
    'VND': '₫',
    'TWD': 'NT\$',
    'HKD': 'HK\$',
  };

  static const Map<String, String> currencyNames = {
    'JPY': 'Japanese Yen',
    'THB': 'Thai Baht',
    'USD': 'US Dollar',
    'EUR': 'Euro',
    'KRW': 'Korean Won',
    'GBP': 'British Pound',
    'CNY': 'Chinese Yuan',
    'SGD': 'Singapore Dollar',
    'AUD': 'Australian Dollar',
    'CAD': 'Canadian Dollar',
    'CHF': 'Swiss Franc',
    'VND': 'Vietnamese Dong',
    'TWD': 'New Taiwan Dollar',
    'HKD': 'Hong Kong Dollar',
  };

  /// Currencies that are conventionally displayed without decimals.
  static const Set<String> zeroDecimalCurrencies = {'JPY', 'KRW', 'VND'};

  /// Approximate travel conversion rates relative to USD (1.0 USD)
  static const Map<String, double> ratesToUsd = {
    'USD': 1.0,
    'JPY': 1.0 / 150.0, // 150 JPY ≈ 1 USD (56,700 JPY ≈ $378 USD)
    'EUR': 1.08,
    'THB': 1.0 / 35.5,
    'KRW': 1.0 / 1350.0,
    'GBP': 1.27,
    'CNY': 1.0 / 7.2,
    'SGD': 0.74,
    'AUD': 0.66,
    'CAD': 0.73,
    'CHF': 1.12,
    'VND': 1.0 / 25000.0,
    'TWD': 1.0 / 32.0,
    'HKD': 1.0 / 7.8,
  };

  static String symbol(String currency) {
    return currencySymbols[currency.toUpperCase()] ??
        '${currency.toUpperCase()} ';
  }

  /// Converts [amount] between two currencies using the approximate travel
  /// rate table. Unknown currencies are returned unchanged so that totals never
  /// silently drop an expense.
  static double convert(double amount, String from, String to) {
    final f = from.toUpperCase();
    final t = to.toUpperCase();
    if (f == t) return amount;
    final fromRate = ratesToUsd[f];
    final toRate = ratesToUsd[t];
    if (fromRate == null || toRate == null) return amount;
    return amount * fromRate / toRate;
  }

  static String formatAmount(
    double amount,
    String currency, {
    bool showSign = false,
  }) {
    final code = currency.toUpperCase();
    final sym = symbol(code);
    // "-¥6,800" / "+¥6,800" (the sign leads, never "¥-6,800").
    final signStr = amount < 0 && amount.roundToDouble() != 0
        ? '-'
        : (showSign && amount > 0 ? '+' : '');
    final isWhole = zeroDecimalCurrencies.contains(code) || (amount % 1 == 0);
    final formatter = isWhole
        ? NumberFormat('#,##0', 'en_US')
        : NumberFormat('#,##0.00', 'en_US');
    final value = zeroDecimalCurrencies.contains(code)
        ? amount.roundToDouble()
        : amount;
    return '$signStr$sym${formatter.format(value.abs())}';
  }

  static String? getSecondarySubtitle(
    double amount,
    String currency, {
    String target = 'USD',
  }) {
    final normCurrency = currency.toUpperCase();
    final normTarget = target.toUpperCase();

    if (normCurrency == normTarget) {
      if (normCurrency == 'USD') {
        final jpyRate = ratesToUsd['JPY'] ?? (1.0 / 150.0);
        final inJpy = amount / jpyRate;
        return '~¥${NumberFormat('#,##0', 'en_US').format(inJpy)}';
      }
      return null;
    }

    final currencyRate = ratesToUsd[normCurrency];
    final targetRate = ratesToUsd[normTarget];
    if (currencyRate == null || targetRate == null) return null;

    final inUsd = amount * currencyRate;
    final inTarget = inUsd / targetRate;
    final sym = symbol(normTarget);
    final formatted = NumberFormat('#,##0', 'en_US').format(inTarget);

    if (normTarget == 'USD') {
      return '~$sym$formatted USD';
    }
    return '~$sym$formatted';
  }
}
