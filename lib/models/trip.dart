import 'expense_item.dart';
import 'trip_member.dart';

class Trip {
  final String id;
  final String name;
  final String baseCurrency;

  /// The traveler's home currency: the secondary "≈" amount shown next to totals.
  final String homeCurrency;
  final List<TripMember> members;
  final List<ExpenseItem> expenses;
  final DateTime createdAt;

  /// First day of the trip. Expenses dated before this day (flights, hotels or
  /// insurance booked in advance) are "Pre-Trip" expenses.
  final DateTime startDate;

  /// Uid of the device that created the trip (the host). `null` for legacy
  /// trips, which stay editable by everyone.
  final String? hostUid;

  /// When `true`, guests can still add entries but cannot edit or delete any.
  final bool lockGuestEdits;

  Trip({
    required this.id,
    required this.name,
    this.baseCurrency = 'THB',
    this.homeCurrency = 'USD',
    this.members = const [],
    this.expenses = const [],
    required this.createdAt,
    DateTime? startDate,
    this.hostUid,
    this.lockGuestEdits = false,
  }) : startDate = startDate ?? createdAt;

  Trip copyWith({
    String? id,
    String? name,
    String? baseCurrency,
    String? homeCurrency,
    List<TripMember>? members,
    List<ExpenseItem>? expenses,
    DateTime? createdAt,
    DateTime? startDate,
    String? hostUid,
    bool? lockGuestEdits,
  }) {
    return Trip(
      id: id ?? this.id,
      name: name ?? this.name,
      baseCurrency: baseCurrency ?? this.baseCurrency,
      homeCurrency: homeCurrency ?? this.homeCurrency,
      members: members ?? this.members,
      expenses: expenses ?? this.expenses,
      createdAt: createdAt ?? this.createdAt,
      startDate: startDate ?? this.startDate,
      hostUid: hostUid ?? this.hostUid,
      lockGuestEdits: lockGuestEdits ?? this.lockGuestEdits,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'baseCurrency': baseCurrency,
      'homeCurrency': homeCurrency,
      'members': members.map((m) => m.toJson()).toList(),
      'expenses': expenses.map((e) => e.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'startDate': startDate.toIso8601String(),
      if (hostUid != null) 'hostUid': hostUid,
      'lockGuestEdits': lockGuestEdits,
    };
  }

  factory Trip.fromJson(Map<String, dynamic> json) {
    final created = json['createdAt'] != null
        ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
        : DateTime.now();
    return Trip(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      baseCurrency: json['baseCurrency'] as String? ?? 'THB',
      homeCurrency: json['homeCurrency'] as String? ?? 'USD',
      members:
          (json['members'] as List<dynamic>?)
              ?.map((m) => TripMember.fromJson(m as Map<String, dynamic>))
              .toList() ??
          const [],
      expenses:
          (json['expenses'] as List<dynamic>?)
              ?.map((e) => ExpenseItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      createdAt: created,
      startDate: json['startDate'] != null
          ? DateTime.tryParse(json['startDate'] as String) ?? created
          : created,
      hostUid: json['hostUid'] as String?,
      lockGuestEdits: json['lockGuestEdits'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Trip && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'Trip(id: $id, name: $name, members: ${members.length}, expenses: ${expenses.length})';
}
