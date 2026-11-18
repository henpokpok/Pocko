class SettlementTransfer {
  final String fromMemberId;
  final String toMemberId;
  final double amount;
  final String currency;
  final String? fromMemberName;
  final String? toMemberName;

  /// Unique transfer key for settlement tracking
  String get id => '${fromMemberId}_${toMemberId}_${amount.toStringAsFixed(2)}';

  const SettlementTransfer({
    required this.fromMemberId,
    required this.toMemberId,
    required this.amount,
    this.currency = 'THB',
    this.fromMemberName,
    this.toMemberName,
  });

  SettlementTransfer copyWith({
    String? fromMemberId,
    String? toMemberId,
    double? amount,
    String? currency,
    String? fromMemberName,
    String? toMemberName,
  }) {
    return SettlementTransfer(
      fromMemberId: fromMemberId ?? this.fromMemberId,
      toMemberId: toMemberId ?? this.toMemberId,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      fromMemberName: fromMemberName ?? this.fromMemberName,
      toMemberName: toMemberName ?? this.toMemberName,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fromMemberId': fromMemberId,
      'toMemberId': toMemberId,
      'amount': amount,
      'currency': currency,
      'fromMemberName': fromMemberName,
      'toMemberName': toMemberName,
    };
  }

  factory SettlementTransfer.fromJson(Map<String, dynamic> json) {
    return SettlementTransfer(
      fromMemberId: json['fromMemberId'] as String? ?? '',
      toMemberId: json['toMemberId'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] as String? ?? 'THB',
      fromMemberName: json['fromMemberName'] as String?,
      toMemberName: json['toMemberName'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettlementTransfer &&
          runtimeType == other.runtimeType &&
          fromMemberId == other.fromMemberId &&
          toMemberId == other.toMemberId &&
          (amount - other.amount).abs() < 0.001;

  @override
  int get hashCode => Object.hash(fromMemberId, toMemberId, amount);

  @override
  String toString() =>
      'SettlementTransfer($fromMemberName[$fromMemberId] -> $toMemberName[$toMemberId]: $currency $amount)';
}
