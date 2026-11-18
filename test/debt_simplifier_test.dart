import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/core/enums/expense_category.dart';
import 'package:travmate/core/enums/inference_source.dart';
import 'package:travmate/features/settlement/debt_simplifier.dart';
import 'package:travmate/models/expense_item.dart';
import 'package:travmate/models/settlement_payment.dart';
import 'package:travmate/models/trip_member.dart';

void main() {
  group('DebtSimplifier Tests', () {
    final boss = TripMember(id: 'boss', name: 'Boss', isCurrentUser: true);
    final may = TripMember(id: 'may', name: 'May');
    final kong = TripMember(id: 'kong', name: 'Kong');
    final members = [boss, may, kong];

    test('1. Standard 3-person equal split: Boss pays 1500 for all 3', () {
      final expense = ExpenseItem(
        id: 'exp1',
        title: 'Grilled pork dinner',
        amount: 1500.0,
        category: ExpenseCategory.MEAL,
        payerId: 'boss',
        splitWithMemberIds: ['boss', 'may', 'kong'],
        createdAt: DateTime.now(),
        inferenceSource: InferenceSource.onDevice,
      );

      final netBalances = DebtSimplifier.calculateNetBalances(
        expenses: [expense],
        members: members,
      );

      expect(netBalances['boss'], 1000.0);
      expect(netBalances['may'], -500.0);
      expect(netBalances['kong'], -500.0);

      final transfers = DebtSimplifier.simplify(
        expenses: [expense],
        members: members,
      );

      expect(transfers.length, 2);
      // Both May and Kong should pay Boss 500
      for (final t in transfers) {
        expect(t.toMemberId, 'boss');
        expect(t.amount, 500.0);
      }
    });

    test('2. Transitive debt cancellation: A pays for B, B pays for C', () {
      // Boss pays 300 for May only
      final exp1 = ExpenseItem(
        id: 'exp1',
        title: 'Lunch',
        amount: 300.0,
        category: ExpenseCategory.MEAL,
        payerId: 'boss',
        splitWithMemberIds: ['may'],
        createdAt: DateTime.now(),
      );

      // May pays 300 for Kong only
      final exp2 = ExpenseItem(
        id: 'exp2',
        title: 'Coffee',
        amount: 300.0,
        category: ExpenseCategory.SNACK_CAFE,
        payerId: 'may',
        splitWithMemberIds: ['kong'],
        createdAt: DateTime.now(),
      );

      final netBalances = DebtSimplifier.calculateNetBalances(
        expenses: [exp1, exp2],
        members: members,
      );

      expect(netBalances['boss'], 300.0);
      expect(netBalances['may'], 0.0);
      expect(netBalances['kong'], -300.0);

      final transfers = DebtSimplifier.simplify(
        expenses: [exp1, exp2],
        members: members,
      );

      // Should simplify to 1 transaction directly from Kong to Boss, bypassing May!
      expect(transfers.length, 1);
      expect(transfers.first.fromMemberId, 'kong');
      expect(transfers.first.toMemberId, 'boss');
      expect(transfers.first.amount, 300.0);
    });

    test('3. Subset split: Boss pays 1500 for May & Kong only (not self)', () {
      final expense = ExpenseItem(
        id: 'exp1',
        title: 'Tickets',
        amount: 1500.0,
        category: ExpenseCategory.ATTRACTION,
        payerId: 'boss',
        splitWithMemberIds: ['may', 'kong'],
        createdAt: DateTime.now(),
      );

      final netBalances = DebtSimplifier.calculateNetBalances(
        expenses: [expense],
        members: members,
      );

      expect(netBalances['boss'], 1500.0);
      expect(netBalances['may'], -750.0);
      expect(netBalances['kong'], -750.0);

      final transfers = DebtSimplifier.simplify(
        expenses: [expense],
        members: members,
      );

      expect(transfers.length, 2);
      expect(
        transfers.any((t) => t.fromMemberId == 'may' && t.amount == 750.0),
        isTrue,
      );
      expect(
        transfers.any((t) => t.fromMemberId == 'kong' && t.amount == 750.0),
        isTrue,
      );
    });

    test('4. Solo expense: May pays 320 for herself only', () {
      final expense = ExpenseItem(
        id: 'exp1',
        title: 'Solo Starbucks',
        amount: 320.0,
        category: ExpenseCategory.SNACK_CAFE,
        payerId: 'may',
        splitWithMemberIds: ['may'],
        createdAt: DateTime.now(),
      );

      final netBalances = DebtSimplifier.calculateNetBalances(
        expenses: [expense],
        members: members,
      );

      expect(netBalances['boss'], 0.0);
      expect(netBalances['may'], 0.0);
      expect(netBalances['kong'], 0.0);

      final transfers = DebtSimplifier.simplify(
        expenses: [expense],
        members: members,
      );

      expect(transfers, isEmpty);
    });

    test('5. Rounding edge case: 100 split 3 ways', () {
      final expense = ExpenseItem(
        id: 'exp1',
        title: 'Snack',
        amount: 100.0,
        category: ExpenseCategory.SNACK_CAFE,
        payerId: 'boss',
        splitWithMemberIds: ['boss', 'may', 'kong'],
        createdAt: DateTime.now(),
      );

      final transfers = DebtSimplifier.simplify(
        expenses: [expense],
        members: members,
      );

      expect(transfers.length, 2);
      final totalTransferred = transfers.fold(0.0, (sum, t) => sum + t.amount);
      // Total transferred should equal roughly 66.66 or 66.67
      expect(totalTransferred, closeTo(66.67, 0.05));
    });

    test('6. Empty or zero inputs handle gracefully', () {
      expect(DebtSimplifier.simplify(expenses: [], members: members), isEmpty);
      expect(DebtSimplifier.simplify(expenses: [], members: []), isEmpty);

      final zeroExp = ExpenseItem(
        id: 'exp0',
        title: 'Free sample',
        amount: 0.0,
        payerId: 'boss',
        splitWithMemberIds: ['boss', 'may'],
        createdAt: DateTime.now(),
      );
      expect(
        DebtSimplifier.simplify(expenses: [zeroExp], members: members),
        isEmpty,
      );
    });
    test('7. Mixed currencies are converted into the base currency', () {
      final yen = ExpenseItem(
        id: 'jpy',
        title: 'Ramen',
        amount: 15000,
        currency: 'JPY',
        payerId: 'boss',
        splitWithMemberIds: ['boss', 'may'],
        createdAt: DateTime.now(),
      );
      final usd = ExpenseItem(
        id: 'usd',
        title: 'Museum',
        amount: 100,
        currency: 'USD',
        payerId: 'may',
        splitWithMemberIds: ['boss', 'may'],
        createdAt: DateTime.now(),
      );

      final balances = DebtSimplifier.calculateNetBalances(
        expenses: [yen, usd],
        members: [boss, may],
        baseCurrency: 'JPY',
      );
      // 100 USD = 15,000 JPY at the 150 JPY/USD travel rate → both paid the same amount.
      expect(balances['boss'], closeTo(0, 0.01));
      expect(balances['may'], closeTo(0, 0.01));

      final inUsd = DebtSimplifier.calculateNetBalances(
        expenses: [yen],
        members: [boss, may],
        baseCurrency: 'USD',
      );
      expect(inUsd['boss'], closeTo(50, 0.01));
    });

    test('8. Recorded settlements cancel the matching debt', () {
      final expense = ExpenseItem(
        id: 'dinner',
        title: 'Dinner',
        amount: 900,
        payerId: 'boss',
        splitWithMemberIds: ['boss', 'may', 'kong'],
        createdAt: DateTime.now(),
      );
      final payment = SettlementPayment(
        id: 'p1',
        fromMemberId: 'may',
        toMemberId: 'boss',
        amount: 300,
        currency: 'THB',
        paidAt: DateTime.now(),
      );

      final balances = DebtSimplifier.calculateNetBalances(
        expenses: [expense],
        members: members,
        settlements: [payment],
      );
      expect(balances['may'], 0.0);
      expect(balances['boss'], 300.0);
      expect(balances['kong'], -300.0);

      final transfers = DebtSimplifier.simplify(
        expenses: [expense],
        members: members,
        settlements: [payment],
      );
      expect(transfers.length, 1);
      expect(transfers.single.fromMemberId, 'kong');
      expect(transfers.single.amount, 300.0);
    });

    test('9. Expenses from unknown payers and unknown split members are ignored safely', () {
      final ghostPayer = ExpenseItem(
        id: 'ghost',
        title: 'Ghost',
        amount: 500,
        payerId: 'nobody',
        splitWithMemberIds: ['boss', 'may'],
        createdAt: DateTime.now(),
      );
      final ghostSplit = ExpenseItem(
        id: 'ghost2',
        title: 'Ghost split',
        amount: 200,
        payerId: 'boss',
        splitWithMemberIds: ['may', 'nobody'],
        createdAt: DateTime.now(),
      );
      final balances = DebtSimplifier.calculateNetBalances(
        expenses: [ghostPayer, ghostSplit],
        members: members,
      );
      expect(balances.values.fold(0.0, (a, b) => a + b), closeTo(0, 0.01));
      expect(balances['boss'], 200.0);
      expect(balances['may'], -200.0);
    });
  });
}
