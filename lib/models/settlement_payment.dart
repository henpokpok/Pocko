/// A real-world transfer that a traveler marked as paid ("Mark Settled").
///
/// Payments are applied on top of expense-derived balances, so settling a
/// transfer immediately changes every net balance, ring, banner and chart.
class SettlementPayment {
  final String id;
  final String fromMemberId;
  final String toMemberId;
  final double amount;
  final String currency;
  final DateTime paidAt;

  /// Optional free-text note ("cash at the hotel").
  final String? note;

  /// Compressed JPEG of a transfer slip as base64.
  final String? slipImageBase64;

  /// Uid of the device that recorded this repayment.
  final String? createdByUid;

  const SettlementPayment({
    required this.id,
    required this.fromMemberId,
    required this.toMemberId,
    required this.amount,
    required this.currency,
    required this.paidAt,
    this.note,
    this.slipImageBase64,
    this.createdByUid,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'fromMemberId': fromMemberId,
    'toMemberId': toMemberId,
    'amount': amount,
    'currency': currency,
    'paidAt': paidAt.toIso8601String(),
    if (note != null) 'note': note,
    if (slipImageBase64 != null) 'slipImageBase64': slipImageBase64,
    if (createdByUid != null) 'createdByUid': createdByUid,
  };

  factory SettlementPayment.fromJson(Map<String, dynamic> json) {
    return SettlementPayment(
      id: json['id'] as String? ?? '',
      fromMemberId: json['fromMemberId'] as String? ?? '',
      toMemberId: json['toMemberId'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] as String? ?? 'JPY',
      paidAt:
          DateTime.tryParse(json['paidAt'] as String? ?? '') ?? DateTime.now(),
      note: json['note'] as String?,
      slipImageBase64: json['slipImageBase64'] as String?,
      createdByUid: json['createdByUid'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SettlementPayment && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
