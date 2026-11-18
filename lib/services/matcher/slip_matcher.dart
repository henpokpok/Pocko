import '../../core/enums/expense_category.dart';
import '../../core/enums/slip_status.dart';
import '../../core/utils/currency_helper.dart';
import '../../models/expense_item.dart';

class SlipMatchResult {
  /// Best candidate, or `null` when nothing is confident enough.
  final ExpenseItem? expense;

  /// 0–100 confidence.
  final int percent;

  const SlipMatchResult({this.expense, required this.percent});
}

/// Correlates an analysed slip with still-unverified expenses using the amount
/// (converted to the base currency), merchant/title similarity and timing.
class SlipMatcher {
  SlipMatcher._();

  static const int minimumConfidence = 45;

  static const Set<String> _stopWords = {
    'the',
    'and',
    'for',
    'card',
    'payment',
    'wise',
    'chase',
    'bank',
    'you',
    'spent',
    'tickets',
    'ticket',
    'tokyo',
    'shop',
    'store',
    'transaction',
    'purchase',
    'visa',
    'mastercard',
    'apple',
    'pay',
  };

  static Set<String> _tokens(String s) =>
      RegExp(r'[a-z0-9]{3,}')
          .allMatches(s.toLowerCase())
          .map((m) => m.group(0)!)
          .where((t) => !_stopWords.contains(t))
          .toSet();

  static SlipMatchResult match({
    required double amount,
    required String currency,
    required String descriptor,
    required DateTime slipTime,
    required List<ExpenseItem> expenses,
    required String baseCurrency,
    Set<String> excludeExpenseIds = const {},
  }) {
    final slipBase = CurrencyHelper.convert(amount, currency, baseCurrency);
    final slipTokens = _tokens(descriptor);
    final slipCategory = ExpenseCategory.fromString(descriptor);

    ExpenseItem? best;
    int bestScore = 0;

    for (final e in expenses) {
      if (e.slipStatus != SlipStatus.waitingForSlip) continue;
      if (excludeExpenseIds.contains(e.id)) continue;

      final expBase = e.amountIn(baseCurrency);
      final diff = (slipBase - expBase).abs() / (expBase <= 0 ? 1 : expBase);
      int amountScore;
      if (diff <= 0.005) {
        amountScore = 60;
      } else if (diff <= 0.03) {
        amountScore = 50; // FX rounding drift
      } else if (diff <= 0.12) {
        amountScore = 30; // card fee / tip
      } else {
        amountScore = 0;
      }

      final titleTokens = _tokens('${e.title} ${e.category.displayName}');
      final overlap = slipTokens.intersection(titleTokens).length;
      var textScore = 0;
      if (overlap > 0) {
        textScore = 15 + (overlap > 1 ? 10 : 0);
      }
      if (slipCategory != ExpenseCategory.MISC && slipCategory == e.category) {
        textScore += 5;
      }
      textScore = textScore.clamp(0, 30);

      final hours = slipTime.difference(e.createdAt).inHours.abs();
      final timeScore = hours <= 3
          ? 10
          : (hours <= 12 ? 7 : (hours <= 48 ? 3 : 0));

      // Without a plausible amount the slip can never be a confident match.
      final total = amountScore == 0
          ? (textScore + timeScore).clamp(0, 40)
          : amountScore + textScore + timeScore;
      if (total > bestScore) {
        bestScore = total;
        best = e;
      }
    }

    final percent = bestScore.clamp(0, 100);
    if (best == null || percent < minimumConfidence) {
      return SlipMatchResult(expense: null, percent: percent);
    }
    return SlipMatchResult(expense: best, percent: percent);
  }
}
