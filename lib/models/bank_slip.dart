import 'dart:typed_data';

import '../core/enums/inference_source.dart';

/// How well a slip lines up with an expense.
enum SlipMatchTier {
  exact('Exact match', 'Amount & date line up'),
  potential('Potential match', 'Amount matches, date unconfirmed'),
  manual('Manual verification required', 'No confident match found');

  final String label;
  final String hint;
  const SlipMatchTier(this.label, this.hint);
}

/// Where the slip came from.
enum SlipOrigin { seeded, sample, upload }

class SlipLineItem {
  final String name;
  final double amount;

  const SlipLineItem({required this.name, required this.amount});

  Map<String, dynamic> toJson() => {'name': name, 'amount': amount};

  factory SlipLineItem.fromJson(Map<String, dynamic> json) => SlipLineItem(
    name: json['name']?.toString() ?? 'Item',
    amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
  );
}

/// A bank notification or paper receipt that was analysed on this device.
///
/// Slips never leave the device: only the matched/unmatched status of the
/// linked expense is synced to the group.
class BankSlip {
  final String id;
  final String bankName;
  final String maskedAccount;
  final double amount;
  final String currency;
  final String time;
  final String merchant;
  final String? targetExpenseId;
  final int matchPercentage;
  final bool isConfirmed;
  final SlipOrigin origin;
  final InferenceSource inferenceSource;
  final int? latencyMs;
  final String? modelInfo;
  final bool isSimulated;
  final String? maskedText;
  final int maskedFieldCount;
  final List<SlipLineItem> lineItems;
  final DateTime createdAt;

  /// Local-only thumbnail of an uploaded photo (never synced).
  final Uint8List? previewBytes;

  const BankSlip({
    required this.id,
    required this.bankName,
    required this.maskedAccount,
    required this.amount,
    this.currency = 'JPY',
    required this.time,
    this.merchant = '',
    this.targetExpenseId,
    required this.matchPercentage,
    this.isConfirmed = false,
    this.origin = SlipOrigin.seeded,
    this.inferenceSource = InferenceSource.onDevice,
    this.latencyMs,
    this.modelInfo,
    this.isSimulated = false,
    this.maskedText,
    this.maskedFieldCount = 0,
    this.lineItems = const [],
    required this.createdAt,
    this.previewBytes,
  });

  SlipMatchTier get tier {
    if (targetExpenseId == null || matchPercentage < 60) {
      return SlipMatchTier.manual;
    }
    if (matchPercentage >= 90) return SlipMatchTier.exact;
    return SlipMatchTier.potential;
  }

  bool get isItemized => lineItems.length >= 2;

  BankSlip copyWith({
    String? targetExpenseId,
    bool clearTarget = false,
    int? matchPercentage,
    bool? isConfirmed,
  }) {
    return BankSlip(
      id: id,
      bankName: bankName,
      maskedAccount: maskedAccount,
      amount: amount,
      currency: currency,
      time: time,
      merchant: merchant,
      targetExpenseId: clearTarget
          ? null
          : (targetExpenseId ?? this.targetExpenseId),
      matchPercentage: matchPercentage ?? this.matchPercentage,
      isConfirmed: isConfirmed ?? this.isConfirmed,
      origin: origin,
      inferenceSource: inferenceSource,
      latencyMs: latencyMs,
      modelInfo: modelInfo,
      isSimulated: isSimulated,
      maskedText: maskedText,
      maskedFieldCount: maskedFieldCount,
      lineItems: lineItems,
      createdAt: createdAt,
      previewBytes: previewBytes,
    );
  }
}
