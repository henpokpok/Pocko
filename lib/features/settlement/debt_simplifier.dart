import 'dart:math';

import '../../core/utils/currency_helper.dart';
import '../../models/expense_item.dart';
import '../../models/settlement_payment.dart';
import '../../models/settlement_transfer.dart';
import '../../models/trip_member.dart';

class DebtSimplifier {
  /// Calculates the net balance of each member in the trip.
  /// Positive value means the member is owed money (creditor).
  /// Negative value means the member owes money (debtor).
  ///
  /// * [baseCurrency] — when provided, every expense is converted into this
  ///   currency first, so mixed-currency trips (¥ + € + $) net out correctly.
  /// * [settlements] — transfers already paid in real life. A payer's balance
  ///   rises by the paid amount and the receiver's falls, so paid transfers
  ///   disappear from the outstanding plan.
  static Map<String, double> calculateNetBalances({
    required List<ExpenseItem> expenses,
    required List<TripMember> members,
    String? baseCurrency,
    List<SettlementPayment> settlements = const [],
  }) {
    final Map<String, double> balances = {for (final m in members) m.id: 0.0};
    final memberIds = balances.keys.toSet();

    for (final exp in expenses) {
      final total = baseCurrency != null
          ? exp.amountIn(baseCurrency)
          : exp.amount;
      if (total <= 0.001) continue;
      // An expense paid by someone who is no longer in the group cannot be netted.
      if (!memberIds.contains(exp.payerId)) continue;

      // Only current members participate; an empty split means "everyone".
      // Equal split, or exact per-person shares for itemized bills.
      final fractions = exp.shareFractions(memberIds);
      if (fractions.isEmpty) continue;

      // Payer is credited the full amount
      balances[exp.payerId] = balances[exp.payerId]! + total;

      // Each participating member is debited their share
      fractions.forEach((id, f) {
        balances[id] = balances[id]! - total * f;
      });
    }

    for (final payment in settlements) {
      final value = baseCurrency != null
          ? CurrencyHelper.convert(
              payment.amount,
              payment.currency,
              baseCurrency,
            )
          : payment.amount;
      if (balances.containsKey(payment.fromMemberId) &&
          balances.containsKey(payment.toMemberId)) {
        balances[payment.fromMemberId] =
            balances[payment.fromMemberId]! + value;
        balances[payment.toMemberId] = balances[payment.toMemberId]! - value;
      }
    }

    // Clean up rounding noise to 2 decimal places
    final Map<String, double> rounded = {};
    balances.forEach((id, val) {
      final r = (val * 100).round() / 100.0;
      rounded[id] = r == 0 ? 0.0 : r; // avoid negative zero
    });

    return rounded;
  }

  /// Simplifies multi-party debts into the minimal list of transactions
  /// using a greedy net-balance matching algorithm.
  static List<SettlementTransfer> simplify({
    required List<ExpenseItem> expenses,
    required List<TripMember> members,
    String defaultCurrency = 'THB',
    bool convertToDefaultCurrency = false,
    List<SettlementPayment> settlements = const [],
  }) {
    if (members.isEmpty || (expenses.isEmpty && settlements.isEmpty)) {
      return const [];
    }

    final memberMap = {for (final m in members) m.id: m};
    final netBalances = calculateNetBalances(
      expenses: expenses,
      members: members,
      baseCurrency: convertToDefaultCurrency ? defaultCurrency : null,
      settlements: settlements,
    );

    // Group into debtors (owe money) and creditors (owed money)
    final List<MapEntry<String, double>> debtors = [];
    final List<MapEntry<String, double>> creditors = [];

    netBalances.forEach((id, balance) {
      if (balance < -0.01) {
        debtors.add(MapEntry(id, -balance)); // Positive debt magnitude
      } else if (balance > 0.01) {
        creditors.add(MapEntry(id, balance));
      }
    });

    // Sort descending by amount to settle largest debts first
    debtors.sort((a, b) => b.value.compareTo(a.value));
    creditors.sort((a, b) => b.value.compareTo(a.value));

    final List<SettlementTransfer> transfers = [];
    int dIndex = 0;
    int cIndex = 0;

    while (dIndex < debtors.length && cIndex < creditors.length) {
      final debtor = debtors[dIndex];
      final creditor = creditors[cIndex];

      final settleAmount = min(debtor.value, creditor.value);
      final roundedAmount = (settleAmount * 100).round() / 100.0;

      if (roundedAmount > 0.01) {
        final fromMember = memberMap[debtor.key];
        final toMember = memberMap[creditor.key];

        transfers.add(
          SettlementTransfer(
            fromMemberId: debtor.key,
            toMemberId: creditor.key,
            amount: roundedAmount,
            currency: defaultCurrency,
            fromMemberName: fromMember?.name ?? debtor.key,
            toMemberName: toMember?.name ?? creditor.key,
          ),
        );
      }

      debtors[dIndex] = MapEntry(debtor.key, debtor.value - settleAmount);
      creditors[cIndex] = MapEntry(creditor.key, creditor.value - settleAmount);

      if (debtors[dIndex].value < 0.01) {
        dIndex++;
      }
      if (creditors[cIndex].value < 0.01) {
        cIndex++;
      }
    }

    return transfers;
  }
}
