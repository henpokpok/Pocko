import '../../models/expense_item.dart';
import '../trip/trip_state.dart';

/// One line of the itemized explanation between two travelers.
class BreakdownLine {
  /// The underlying expense, or `null` for a recorded settlement payment.
  final ExpenseItem? expense;
  final String title;
  final DateTime when;

  /// Full expense amount in the base currency (0 for payments).
  final double total;

  /// Signed amount from [PairBreakdown.aId]'s point of view: positive means
  /// *b owes a*, negative means *a owes b*.
  final double amount;
  final bool isPayment;

  const BreakdownLine({
    required this.expense,
    required this.title,
    required this.when,
    required this.total,
    required this.amount,
    this.isPayment = false,
  });
}

/// Exactly which expenses (and payments) make up what [aId] and [bId] owe each
/// other, in the trip's base currency.
class PairBreakdown {
  final String aId;
  final String bId;
  final List<BreakdownLine> lines;

  const PairBreakdown({
    required this.aId,
    required this.bId,
    required this.lines,
  });

  /// Sum of the expenses where *b* shares something *a* paid.
  double get bOwesA => lines
      .where((l) => !l.isPayment && l.amount > 0)
      .fold(0.0, (s, l) => s + l.amount);

  /// Sum of the expenses where *a* shares something *b* paid.
  double get aOwesB => lines
      .where((l) => !l.isPayment && l.amount < 0)
      .fold(0.0, (s, l) => s - l.amount);

  double get paymentsNet =>
      lines.where((l) => l.isPayment).fold(0.0, (s, l) => s + l.amount);

  /// Positive: *b owes a*; negative: *a owes b* (after recorded payments).
  double get net => lines.fold(0.0, (s, l) => s + l.amount);

  int get expenseCount => lines.where((l) => !l.isPayment).length;
}

/// Builds the pair breakdown from [state]'s expenses and settlement payments.
PairBreakdown computePairBreakdown(TripState state, String a, String b) {
  final base = state.trip.baseCurrency;
  final memberIds = state.trip.members.map((m) => m.id).toSet();
  final lines = <BreakdownLine>[];

  for (final e in state.trip.expenses) {
    final total = e.amountIn(base);
    if (total <= 0.001 || !memberIds.contains(e.payerId)) continue;
    final fractions = e.shareFractions(memberIds);
    final split = fractions.keys.toList();

    if (e.payerId == a && split.contains(b) && a != b) {
      lines.add(
        BreakdownLine(
          expense: e,
          title: e.title,
          when: e.expenseDateTime,
          total: total,
          amount: total * (fractions[b] ?? 0),
        ),
      );
    } else if (e.payerId == b && split.contains(a) && a != b) {
      lines.add(
        BreakdownLine(
          expense: e,
          title: e.title,
          when: e.expenseDateTime,
          total: total,
          amount: -total * (fractions[a] ?? 0),
        ),
      );
    }
  }

  for (final p in state.settlements) {
    final value = p.currency.toUpperCase() == base.toUpperCase()
        ? p.amount
        : null;
    final amount = value ?? p.amount;
    if (p.fromMemberId == a && p.toMemberId == b) {
      // a already paid b: b's debt to a grows by that payment (or a's shrinks).
      lines.add(
        BreakdownLine(
          expense: null,
          title: 'Settled payment',
          when: p.paidAt,
          total: 0,
          amount: amount,
          isPayment: true,
        ),
      );
    } else if (p.fromMemberId == b && p.toMemberId == a) {
      lines.add(
        BreakdownLine(
          expense: null,
          title: 'Settled payment',
          when: p.paidAt,
          total: 0,
          amount: -amount,
          isPayment: true,
        ),
      );
    }
  }

  lines.sort((x, y) => y.when.compareTo(x.when));
  return PairBreakdown(aId: a, bId: b, lines: lines);
}
