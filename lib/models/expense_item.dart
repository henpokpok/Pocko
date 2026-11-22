import '../core/enums/expense_category.dart';
import '../core/enums/inference_source.dart';
import '../core/enums/slip_status.dart';
import '../core/utils/currency_helper.dart';

class ExpenseItem {
  final String id;
  final String title;
  final double amount;
  final String currency;
  final ExpenseCategory category;
  final String payerId;
  final List<String> splitWithMemberIds;
  final DateTime createdAt;
  final InferenceSource inferenceSource;
  final String? modelInfo;
  final int? latencyMs;
  final SlipStatus slipStatus;
  final String? note;

  /// Exact per-person shares (member id -> amount in [currency]) when friends
  /// ordered differently priced items on one shared bill. `null` = equal split.
  final Map<String, double>? customSplits;

  /// Compressed JPEG of the receipt / bank slip as base64, so it works offline
  /// and travels inside the synced trip document.
  final String? receiptImageBase64;

  /// Firebase (anonymous) uid of the device that created this expense. Drives
  /// the host / creator edit permissions.
  final String? createdByUid;

  const ExpenseItem({
    required this.id,
    required this.title,
    required this.amount,
    this.currency = 'THB',
    this.category = ExpenseCategory.MISC,
    required this.payerId,
    this.splitWithMemberIds = const [],
    required this.createdAt,
    this.inferenceSource = InferenceSource.manual,
    this.modelInfo,
    this.latencyMs,
    this.slipStatus = SlipStatus.waitingForSlip,
    this.note,
    this.customSplits,
    this.receiptImageBase64,
    this.createdByUid,
  });

  /// Date and time of the purchase (the same value as [createdAt]).
  DateTime get expenseDateTime => createdAt;

  /// Amount converted into [baseCurrency] using the travel rate table.
  double amountIn(String baseCurrency) =>
      CurrencyHelper.convert(amount, currency, baseCurrency);

  /// Whether the bill is split by exact per-person amounts.
  bool get isItemized => customSplits != null && customSplits!.isNotEmpty;

  /// Each participant's share of this expense as a fraction of the total
  /// (the fractions add up to 1). Equal split unless [customSplits] is set;
  /// custom shares are scaled so the ledger always balances to [amount].
  Map<String, double> shareFractions(Iterable<String> memberIds) {
    var ids = splitWithMemberIds.where(memberIds.contains).toList();
    if (ids.isEmpty) ids = memberIds.toList();
    if (ids.isEmpty) return const {};
    if (isItemized) {
      final raw = {for (final id in ids) id: (customSplits![id] ?? 0.0)};
      final sum = raw.values.fold<double>(0, (a, b) => a + b);
      if (sum > 0.001) {
        return {for (final e in raw.entries) e.key: e.value / sum};
      }
    }
    return {for (final id in ids) id: 1 / ids.length};
  }

  ExpenseItem copyWith({
    String? id,
    String? title,
    double? amount,
    String? currency,
    ExpenseCategory? category,
    String? payerId,
    List<String>? splitWithMemberIds,
    DateTime? createdAt,
    InferenceSource? inferenceSource,
    String? modelInfo,
    int? latencyMs,
    SlipStatus? slipStatus,
    String? note,
    Map<String, double>? customSplits,
    bool clearCustomSplits = false,
    String? receiptImageBase64,
    bool clearReceipt = false,
    String? createdByUid,
  }) {
    return ExpenseItem(
      id: id ?? this.id,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      category: category ?? this.category,
      payerId: payerId ?? this.payerId,
      splitWithMemberIds: splitWithMemberIds ?? this.splitWithMemberIds,
      createdAt: createdAt ?? this.createdAt,
      inferenceSource: inferenceSource ?? this.inferenceSource,
      modelInfo: modelInfo ?? this.modelInfo,
      latencyMs: latencyMs ?? this.latencyMs,
      slipStatus: slipStatus ?? this.slipStatus,
      note: note ?? this.note,
      customSplits: clearCustomSplits
          ? null
          : (customSplits ?? this.customSplits),
      receiptImageBase64: clearReceipt
          ? null
          : (receiptImageBase64 ?? this.receiptImageBase64),
      createdByUid: createdByUid ?? this.createdByUid,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'amount': amount,
      'currency': currency,
      'category': category.name,
      'payerId': payerId,
      'splitWithMemberIds': splitWithMemberIds,
      'createdAt': createdAt.toIso8601String(),
      'inferenceSource': inferenceSource.rawValue,
      'modelInfo': modelInfo,
      'latencyMs': latencyMs,
      'slipStatus': slipStatus.rawValue,
      'note': note,
      if (customSplits != null) 'customSplits': customSplits,
      if (receiptImageBase64 != null) 'receiptImageBase64': receiptImageBase64,
      if (createdByUid != null) 'createdByUid': createdByUid,
    };
  }

  factory ExpenseItem.fromJson(Map<String, dynamic> json) {
    return ExpenseItem(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] as String? ?? 'THB',
      category: ExpenseCategory.fromString(json['category'] as String?),
      payerId: json['payerId'] as String? ?? '',
      splitWithMemberIds:
          (json['splitWithMemberIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      inferenceSource: InferenceSource.fromRaw(
        json['inferenceSource'] as String?,
      ),
      modelInfo: json['modelInfo'] as String?,
      latencyMs: json['latencyMs'] as int?,
      slipStatus: SlipStatus.fromRaw(json['slipStatus'] as String?),
      note: json['note'] as String?,
      customSplits: (json['customSplits'] as Map?)?.map(
        (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
      ),
      receiptImageBase64: json['receiptImageBase64'] as String?,
      createdByUid: json['createdByUid'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExpenseItem &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'ExpenseItem(id: $id, title: $title, amount: $currency $amount, category: ${category.name}, payer: $payerId)';
}
