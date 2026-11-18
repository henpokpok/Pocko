import '../../core/enums/expense_category.dart';
import '../../core/utils/currency_helper.dart';

/// How [ParsedExpenseDraft.unitAmount] relates to the final total.
enum AmountMode {
  /// The stated amount is the bill (default).
  total,

  /// The stated amount is per person ("500 yen each", "per head"): the total
  /// is the amount times everyone in the split.
  perPerson;

  /// Value used in the AI JSON schema.
  String get wire => this == AmountMode.perPerson ? 'PER_PERSON' : 'TOTAL';

  static AmountMode fromRaw(Object? raw) {
    final v = raw?.toString().toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
    return v == 'PERPERSON' || v == 'PERHEAD' || v == 'EACH'
        ? AmountMode.perPerson
        : AmountMode.total;
  }
}

/// One expense as understood by the AI, *before* the money is computed.
///
/// Neuro-symbolic split: a small on-device model is good at **intent** ("500
/// yen each", "4 coffees at 5 dollars a cup", "plus 10% service") but poor at
/// mental arithmetic. The model therefore reports the numbers as stated
/// ([unitAmount], [quantity], [extraPercent], [amountMode]) and Dart computes
/// the exact total in [totalFor].
class ParsedExpenseDraft {
  final String title;

  /// The number as stated, never multiplied by the model.
  final double unitAmount;
  final AmountMode amountMode;

  /// Item count for "N things at price" phrases (>= 1).
  final int quantity;

  /// Tip / tax / service charge in percent (0 = none).
  final double extraPercent;

  final String currency;
  final ExpenseCategory category;
  final String payer;

  /// Member **names** (as the model / parser reports them).
  final List<String> splitWith;

  /// Exact per-person amounts by member **name** for a shared bill where each
  /// friend ordered differently priced items ("mine 1200, Maya 1800, Liam 950").
  /// `null` for an ordinary equal split. When set it is the whole bill:
  /// [totalFor] is the sum of the shares (plus [extraPercent]).
  final Map<String, double>? customSplits;

  const ParsedExpenseDraft({
    required this.title,
    required this.unitAmount,
    this.amountMode = AmountMode.total,
    this.quantity = 1,
    this.extraPercent = 0,
    this.currency = 'JPY',
    this.category = ExpenseCategory.MISC,
    this.payer = '',
    this.splitWith = const [],
    this.customSplits,
  });

  /// Whether the bill is split by exact per-person amounts.
  bool get isItemized => customSplits != null && customSplits!.isNotEmpty;

  /// Whether any pricing modifier is in play.
  bool get hasModifiers =>
      isItemized ||
      amountMode == AmountMode.perPerson ||
      quantity > 1 ||
      extraPercent != 0;

  /// Exact total for [people] sharing the bill:
  /// `unit x quantity [x people when per person] x (1 + percent / 100)`.
  double totalFor(int people) {
    final n = people < 1 ? 1 : people;
    if (isItemized) {
      final sum = customSplits!.values.fold<double>(0, (a, b) => a + b);
      return ((sum * (1 + extraPercent / 100)) * 100).round() / 100;
    }
    var total = unitAmount * quantity;
    if (amountMode == AmountMode.perPerson) total *= n;
    total *= 1 + extraPercent / 100;
    // Whole-currency-unit noise from percentages (e.g. 11000.000000000002).
    return (total * 100).round() / 100;
  }

  /// Human breakdown for the preview card, e.g. `¥1,500 (¥500 × 3 each)`,
  /// `$20 (4 × $5)` or `¥11,000 (¥10,000 + 10%)`. `null` without modifiers.
  String? breakdown(int people) {
    if (!hasModifiers) return null;
    final n = people < 1 ? 1 : people;
    String money(double v) => CurrencyHelper.formatAmount(v, currency);

    if (isItemized && quantity == 1 && extraPercent == 0) {
      return '${money(totalFor(n))} (${customSplits!.entries.map((e) => '${e.key} ${money(e.value)}').join(' · ')})';
    }

    String calc;
    if (amountMode == AmountMode.perPerson) {
      calc = quantity > 1
          ? '${money(unitAmount)} × $quantity × $n each'
          : '${money(unitAmount)} × $n each';
    } else if (quantity > 1) {
      calc = '$quantity × ${money(unitAmount)}';
    } else {
      calc = money(unitAmount);
    }
    if (extraPercent != 0) {
      final abs = extraPercent.abs();
      final pct = abs % 1 == 0 ? abs.toStringAsFixed(0) : abs.toString();
      calc = extraPercent > 0 ? '$calc + $pct%' : '$calc − $pct%';
    }
    return '${money(totalFor(n))} ($calc)';
  }

  ParsedExpenseDraft copyWith({
    String? title,
    double? unitAmount,
    AmountMode? amountMode,
    int? quantity,
    double? extraPercent,
    String? currency,
    ExpenseCategory? category,
    String? payer,
    List<String>? splitWith,
    Map<String, double>? customSplits,
    bool clearCustomSplits = false,
  }) {
    return ParsedExpenseDraft(
      title: title ?? this.title,
      unitAmount: unitAmount ?? this.unitAmount,
      amountMode: amountMode ?? this.amountMode,
      quantity: quantity ?? this.quantity,
      extraPercent: extraPercent ?? this.extraPercent,
      currency: currency ?? this.currency,
      category: category ?? this.category,
      payer: payer ?? this.payer,
      splitWith: splitWith ?? this.splitWith,
      customSplits: clearCustomSplits
          ? null
          : (customSplits ?? this.customSplits),
    );
  }

  static double? _num(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) {
      return double.tryParse(v.replaceAll(RegExp(r'[^0-9.\-]'), ''));
    }
    return null;
  }

  /// Reads one `items[]` entry of the AI JSON. Accepts the new schema
  /// (`unitAmount`, `amountMode`, `quantity`, `extraPercent`) and the legacy
  /// one (`amount` only, which is then the unit amount).
  factory ParsedExpenseDraft.fromMap(
    Map<String, dynamic> m, {
    String defaultCurrency = 'JPY',
    String defaultPayer = '',
  }) {
    final rawCustom = m['customSplits'];
    Map<String, double>? custom;
    if (rawCustom is Map) {
      custom = {};
      rawCustom.forEach((k, v) {
        final n = _num(v);
        if (n != null && n > 0) custom![k.toString().trim()] = n;
      });
      if (custom.length < 2) custom = null; // one person is not a split
    }
    // An itemized bill's stated amount is the sum of the shares.
    final customSum = custom?.values.fold<double>(0, (a, b) => a + b);
    final unit = customSum ?? _num(m['unitAmount']) ?? _num(m['amount']) ?? 0.0;
    final qty = _num(m['quantity'])?.round() ?? 1;
    final currency = (m['currency']?.toString().trim().isNotEmpty ?? false)
        ? m['currency'].toString().trim().toUpperCase()
        : defaultCurrency;
    return ParsedExpenseDraft(
      title: m['title']?.toString() ?? '',
      unitAmount: unit,
      amountMode: AmountMode.fromRaw(m['amountMode']),
      quantity: qty < 1 ? 1 : qty,
      extraPercent: _num(m['extraPercent']) ?? 0,
      currency: currency,
      category: ExpenseCategory.fromString(m['category']?.toString()),
      payer: m['payer']?.toString().trim().isNotEmpty == true
          ? m['payer'].toString().trim()
          : defaultPayer,
      splitWith: [
        for (final e in (m['splitWith'] as List? ?? const []))
          if (e.toString().trim().isNotEmpty) e.toString().trim(),
      ],
      customSplits: custom,
    );
  }

  /// JSON entry with the computed `amount` (for [people] sharing) next to the
  /// schema fields, so legacy readers keep working.
  Map<String, dynamic> toMap([int? people]) => {
    'title': title,
    'amount': totalFor(people ?? (splitWith.isEmpty ? 1 : splitWith.length)),
    'unitAmount': unitAmount,
    'amountMode': amountMode.wire,
    'quantity': quantity,
    'extraPercent': extraPercent,
    'currency': currency,
    'category': category.name,
    'payer': payer,
    'splitWith': splitWith,
    if (customSplits != null) 'customSplits': customSplits,
  };
}
