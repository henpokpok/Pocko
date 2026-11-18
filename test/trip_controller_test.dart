import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/core/enums/expense_category.dart';
import 'package:travmate/core/enums/inference_source.dart';
import 'package:travmate/core/enums/slip_status.dart';
import 'package:travmate/features/trip/date_filter.dart';
import 'package:travmate/features/trip/trip_controller.dart';
import 'package:travmate/features/trip/trip_state.dart';
import 'package:travmate/models/expense_item.dart';

ExpenseItem _expense(
  String id, {
  double amount = 1000,
  String currency = 'JPY',
  String payer = 'you',
  List<String> split = const ['you', 'alex', 'maya', 'liam'],
  ExpenseCategory category = ExpenseCategory.MEAL,
}) {
  return ExpenseItem(
    id: id,
    title: 'Test $id',
    amount: amount,
    currency: currency,
    category: category,
    payerId: payer,
    splitWithMemberIds: split,
    createdAt: DateTime.now(),
    inferenceSource: InferenceSource.onDevice,
  );
}

void main() {
  late ProviderContainer container;
  late TripController notifier;

  TripState read() => container.read(tripControllerProvider);

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
    notifier = container.read(tripControllerProvider.notifier);
  });

  group('Initial state', () {
    test(
      'Starts with the Tokyo trip, live balances and a private group code',
      () {
        final state = read();
        expect(state.trip.name, 'Tokyo Trip 🇯🇵');
        expect(state.trip.baseCurrency, 'JPY');
        expect(state.trip.members.length, 4);
        expect(state.trip.expenses.length, 7);
        expect(state.totalSpend, 60000.0);
        expect(state.netBalances, isNotEmpty);
        expect(state.simplifiedTransfers.length, 3);
        expect(RegExp(r'^\d{3}-\d{3}$').hasMatch(state.squadCode), isTrue);
        expect(
          state.squadCode,
          isNot('782-901'),
          reason: 'every install must get its own code',
        );
        expect(
          state.dateRange,
          matches(RegExp(r'^\w{3} \d+ – \w{3} \d+ • \d+ Days?$')),
        );
      },
    );

    test('Recent expenses are the newest three, not the oldest', () {
      final recent = read().recentExpenses;
      expect(recent.map((e) => e.id), ['exp_6', 'exp_5', 'exp_4']);
      expect(read().filteredExpenses.first.id, 'exp_6');
    });
  });

  group('Expenses', () {
    test('Adding an expense recalculates totals, balances and transfers', () {
      final before = read();
      notifier.addExpense(_expense('new', amount: 8000, payer: 'maya'));

      final after = read();
      expect(after.totalSpend, before.totalSpend + 8000);
      expect(after.trip.expenses.any((e) => e.id == 'new'), isTrue);
      expect(after.netBalances['maya'], isNot(before.netBalances['maya']));
      expect(
        after.netBalances.values.fold(0.0, (a, b) => a + b),
        closeTo(0, 0.05),
      );
    });

    test(
      'Duplicate ids are made unique and empty splits fall back to the payer',
      () {
        notifier.addExpense(_expense('exp_1', split: const []));
        final added = read().trip.expenses.last;
        expect(added.id, isNot('exp_1'));
        expect(added.splitWithMemberIds, ['you']);
      },
    );

    test('Editing an expense updates every derived value', () {
      final original = read().trip.expenses.firstWhere((e) => e.id == 'exp_6');
      notifier.updateExpense(original.copyWith(amount: 28200, payerId: 'maya'));

      final state = read();
      expect(state.totalSpend, 60000 + 10000);
      expect(state.netBalances['liam'], lessThan(0));
    });

    test('Deleting and restoring an expense round-trips', () {
      final totalBefore = read().totalSpend;
      final removed = notifier.removeExpense('exp_5');
      expect(removed, isNotNull);
      expect(read().totalSpend, totalBefore - 15400);

      notifier.restoreExpense(removed!);
      expect(read().totalSpend, totalBefore);
    });

    test(
      'Removing the last expense of the selected category clears the filter',
      () {
        notifier.setCategoryFilter(ExpenseCategory.SNACK_CAFE);
        expect(read().filteredExpenses.length, 1);

        notifier.removeExpense('exp_3');
        expect(read().selectedFilterCategory, isNull);
        expect(read().filteredExpenses.length, 6);
      },
    );

    test(
      'Deleting an expense turns its slip into a manual-verification slip',
      () {
        notifier.removeExpense('exp_3');
        final slip = read().slips.firstWhere((s) => s.id == 'slip_1');
        expect(slip.targetExpenseId, isNull);
        expect(read().pendingSlips.any((s) => s.id == 'slip_1'), isTrue);
      },
    );

    test('Deleting every expense leaves a consistent empty state', () {
      for (final e in List.of(read().trip.expenses)) {
        notifier.removeExpense(e.id);
      }
      final state = read();
      expect(state.trip.expenses, isEmpty);
      expect(state.totalSpend, 0);
      expect(state.simplifiedTransfers, isEmpty);
      expect(state.recentExpenses, isEmpty);
    });
  });

  group('Currency', () {
    test(
      'Switching base currency converts totals instead of relabelling them',
      () {
        notifier.updateBaseCurrency('USD');
        var state = read();
        expect(state.trip.baseCurrency, 'USD');
        expect(state.totalSpend, closeTo(400, 0.01)); // ¥60,000 at 150 JPY/USD
        expect(
          state.simplifiedTransfers.every((t) => t.currency == 'USD'),
          isTrue,
        );

        notifier.updateBaseCurrency('JPY');
        state = read();
        expect(state.totalSpend, closeTo(60000, 0.01));
      },
    );

    test('A foreign-currency expense is converted into the base currency', () {
      notifier.addExpense(_expense('eur', amount: 100, currency: 'EUR'));
      // 100 EUR = 108 USD = 16,200 JPY
      expect(read().totalSpend, closeTo(60000 + 16200, 0.01));
    });
  });

  group('Settlement', () {
    test(
      'Marking a transfer settled lowers outstanding balances immediately',
      () {
        final before = read();
        final transfer = before.simplifiedTransfers.first;
        final fromBefore = before.netBalances[transfer.fromMemberId]!;
        final toBefore = before.netBalances[transfer.toMemberId]!;

        expect(notifier.markTransferSettled(transfer.id), isTrue);

        final after = read();
        expect(after.settlements.length, 1);
        expect(after.settledTransferIds.length, 1);
        expect(
          after.simplifiedTransfers.length,
          before.simplifiedTransfers.length - 1,
        );
        expect(
          after.netBalances[transfer.fromMemberId],
          closeTo(fromBefore + transfer.amount, 0.01),
        );
        expect(
          after.netBalances[transfer.toMemberId],
          closeTo(toBefore - transfer.amount, 0.01),
        );
        expect(after.outstandingTotal, lessThan(before.outstandingTotal));
      },
    );

    test(
      'Settling every transfer squares the whole group; undo restores the plan',
      () {
        for (final t in List.of(read().simplifiedTransfers)) {
          notifier.markTransferSettled(t.id);
        }
        expect(read().simplifiedTransfers, isEmpty);
        expect(read().netBalances.values.every((v) => v.abs() < 0.5), isTrue);

        notifier.undoSettlement(read().settlements.first.id);
        expect(read().simplifiedTransfers, isNotEmpty);

        notifier.resetSettledTransfers();
        expect(read().settlements, isEmpty);
        expect(read().simplifiedTransfers.length, 3);
      },
    );

    test('Settled payments survive later expense changes', () {
      final t = read().simplifiedTransfers.first;
      notifier.markTransferSettled(t.id);
      notifier.addExpense(_expense('later', amount: 4000, payer: 'liam'));
      expect(read().settlements.length, 1);
      expect(
        read().netBalances.values.fold(0.0, (a, b) => a + b),
        closeTo(0, 0.05),
      );
    });

    test('Unknown transfer ids are ignored', () {
      expect(notifier.markTransferSettled('transfer_1'), isFalse);
      expect(read().settlements, isEmpty);
    });
  });

  group('Slips', () {
    test('Confirming slips verifies the linked expenses', () {
      final count = notifier.confirmSlips(['slip_1', 'slip_2']);
      expect(count, 2);
      final state = read();
      expect(
        state.trip.expenses.firstWhere((e) => e.id == 'exp_3').slipStatus,
        SlipStatus.matched,
      );
      expect(
        state.trip.expenses.firstWhere((e) => e.id == 'exp_4').slipStatus,
        SlipStatus.matched,
      );
      expect(state.pendingSlips.length, 1);
    });

    test('Batch confirming by expense ids flips status to matched', () {
      notifier.batchConfirmSlips(['exp_3', 'exp_4']);
      final state = read();
      expect(
        state.trip.expenses.firstWhere((e) => e.id == 'exp_3').slipStatus,
        SlipStatus.matched,
      );
      expect(state.slips.where((s) => s.isConfirmed).length, 2);
    });

    test('Slips without a target cannot be confirmed until linked', () {
      notifier.removeExpense('exp_3');
      expect(notifier.confirmSlips(['slip_1']), 0);
      notifier.linkSlip('slip_1', 'exp_5');
      expect(notifier.confirmSlips(['slip_1']), 1);
      expect(
        read().trip.expenses.firstWhere((e) => e.id == 'exp_5').slipStatus,
        SlipStatus.matched,
      );
    });
  });

  group('Group', () {
    test('Adding and removing a member works', () {
      expect(notifier.addMember('Nan'), isTrue);
      final nan = read().trip.members.firstWhere((m) => m.name == 'Nan');
      expect(
        notifier.addMember('nan'),
        isFalse,
        reason: 'duplicate names are rejected',
      );

      expect(notifier.removeMember(nan.id), isNull);
      expect(read().trip.members.any((m) => m.name == 'Nan'), isFalse);
    });

    test(
      'A member who paid for expenses cannot be removed; yourself neither',
      () {
        expect(notifier.removeMember('alex'), contains('paid for'));
        expect(notifier.removeMember('you'), isNotNull);
        expect(read().trip.members.length, 4);
      },
    );

    test('Removing a member strips them from every split', () {
      notifier.addMember('Nan');
      final nan = read().trip.members.firstWhere((m) => m.name == 'Nan');
      notifier.addExpense(
        _expense('with_nan', split: ['you', nan.id], amount: 600),
      );
      notifier.removeMember(nan.id);
      final e = read().trip.expenses.firstWhere((e) => e.id == 'with_nan');
      expect(e.splitWithMemberIds, ['you']);
      expect(read().netBalances.containsKey(nan.id), isFalse);
    });

    test('Display names: this device is "You", another device\'s "You" is the Host', () {
      final state = read();
      expect(state.nameOf('you'), 'You');
      final other = state.copyWith(currentMemberId: 'alex');
      expect(other.nameOf('alex'), 'You');
      expect(other.nameOf('you'), 'Host');
    });
  });

  group('Group codes', () {
    test('normalizeSquadCode accepts digits with any separators', () {
      expect(normalizeSquadCode('782901'), '782-901');
      expect(normalizeSquadCode('782 901'), '782-901');
      expect(normalizeSquadCode(' 782-901 '), '782-901');
      expect(normalizeSquadCode('78290'), isNull);
      expect(normalizeSquadCode('abc'), isNull);
    });

    test('generateSquadCode always produces NNN-NNN', () {
      for (var i = 0; i < 50; i++) {
        expect(
          TripController.generateSquadCode(),
          matches(RegExp(r'^\d{3}-\d{3}$')),
        );
      }
    });

    test(
      'Joining without Firebase stores the code locally and reports offline',
      () async {
        final result = await notifier.joinSquad('999001');
        expect(result, JoinSquadResult.offline);
        expect(read().squadCode, '999-001');
        expect(read().syncStatus, SyncStatus.offline);
      },
    );

    test('Invalid codes are rejected without touching state', () async {
      final code = read().squadCode;
      expect(await notifier.joinSquad('12'), JoinSquadResult.invalid);
      expect(read().squadCode, code);
    });
  });
  group('Dates, Pre-Trip and top expenses', () {
    test('The seeded trip has one Pre-Trip expense and trip days from the start date', () {
      final state = read();
      expect(state.preTripExpenses.map((e) => e.id), ['exp_pre1']);
      expect(state.isPreTrip(state.trip.expenses.first), isTrue);
      expect(state.tripDays.first, startOfDay(state.trip.startDate));
      expect(state.tripDays.length, greaterThanOrEqualTo(2));
      expect(state.dateRange, contains('Days'));
    });

    test('Pre-Trip filter shows only expenses dated before the start day, with their total', () {
      notifier.setDateFilter(const DateFilter.preTrip());
      final state = read();
      expect(state.filteredExpenses.map((e) => e.id), ['exp_pre1']);
      expect(state.spendFor(const DateFilter.preTrip()), 3300);
    });

    test(
      'A day filter shows that calendar day only; All Dates shows everything',
      () {
        final lastDay = read().trip.expenses
            .firstWhere((e) => e.id == 'exp_6')
            .expenseDateTime;
        notifier.setDateFilter(DateFilter.day(lastDay));
        var state = read();
        expect(
          state.filteredExpenses.every(
            (e) => startOfDay(e.expenseDateTime) == startOfDay(lastDay),
          ),
          isTrue,
        );
        expect(state.filteredExpenses, isNotEmpty);
        expect(state.filteredExpenses.any((e) => e.id == 'exp_pre1'), isFalse);

        notifier.setDateFilter(const DateFilter.all());
        state = read();
        expect(state.filteredExpenses.length, 7);
        expect(state.spendFor(const DateFilter.all()), state.totalSpend);
      },
    );

    test('Date and category filters combine', () {
      notifier.setDateFilter(const DateFilter.preTrip());
      notifier.setCategoryFilter(ExpenseCategory.MEAL);
      expect(read().filteredExpenses, isEmpty);
      notifier.setCategoryFilter(ExpenseCategory.INSURANCE);
      expect(read().filteredExpenses.length, 1);
    });

    test('Moving the trip start day re-classifies expenses as Pre-Trip', () {
      final newest = read().trip.expenses
          .firstWhere((e) => e.id == 'exp_6')
          .expenseDateTime;
      notifier.updateTripStartDate(newest.add(const Duration(days: 1)));
      expect(read().preTripExpenses.length, 7);
      notifier.updateTripStartDate(newest.subtract(const Duration(days: 2)));
      expect(read().preTripExpenses.length, 1);
    });

    test('Every expense stores date AND time', () {
      final e = read().trip.expenses.firstWhere((e) => e.id == 'exp_6');
      expect(e.expenseDateTime, e.createdAt);
      final moved = e.copyWith(createdAt: DateTime(2026, 11, 3, 18, 45));
      notifier.updateExpense(moved);
      final back = read().trip.expenses.firstWhere((x) => x.id == 'exp_6');
      expect(back.expenseDateTime.hour, 18);
      expect(back.expenseDateTime.minute, 45);
      expect(read().isPreTrip(back), isTrue);
    });

    test(
      'Top three expenses are the highest-value ones in the base currency',
      () {
        expect(read().topExpenses().map((e) => e.id), [
          'exp_6',
          'exp_5',
          'exp_4',
        ]);
        notifier.addExpense(
          _expense('big_eur', amount: 200, currency: 'EUR'),
        ); // 32,400 JPY
        expect(read().topExpenses().first.id, 'big_eur');
        expect(read().topExpenses(2).length, 2);
      },
    );
  });

  group('Slip grading: cash, wrong match, replacement', () {
    test(
      'Paid in cash resolves the expense and detaches its proposed slip',
      () {
        notifier.markExpenseCash('exp_3');
        final state = read();
        expect(
          state.trip.expenses.firstWhere((e) => e.id == 'exp_3').slipStatus,
          SlipStatus.cash,
        );
        final slip = state.slips.firstWhere((s) => s.id == 'slip_1');
        expect(slip.targetExpenseId, isNull);
        expect(
          state.waitingExpenseCount,
          3,
          reason: 'exp_4, exp_5 and exp_6 still wait',
        );
      },
    );

    test('Choosing a different slip links it, verifies the expense and detaches the old slip', () {
      notifier.replaceSlipForExpense('exp_3', 'slip_2');
      final state = read();
      final chosen = state.slips.firstWhere((s) => s.id == 'slip_2');
      final old = state.slips.firstWhere((s) => s.id == 'slip_1');
      expect(chosen.targetExpenseId, 'exp_3');
      expect(chosen.isConfirmed, isTrue);
      expect(old.targetExpenseId, isNull);
      expect(
        state.trip.expenses.firstWhere((e) => e.id == 'exp_3').slipStatus,
        SlipStatus.matched,
      );
    });

    test(
      'Rejecting a match leaves the slip pending for manual verification',
      () {
        notifier.detachSlip('slip_3');
        final slip = read().slips.firstWhere((s) => s.id == 'slip_3');
        expect(slip.targetExpenseId, isNull);
        expect(slip.isConfirmed, isFalse);
        expect(slip.tier.name, 'manual');
      },
    );

    test('Cash expenses are never offered to the slip matcher', () {
      notifier.markExpenseCash('exp_5');
      expect(read().waitingExpenseCount, 3);
      expect(SlipStatus.fromRaw('cash'), SlipStatus.cash);
      expect(SlipStatus.cash.rawValue, 'cash');
    });
  });

  group('Setup wizard (startNewTrip / loadDemoTrip)', () {
    test('startNewTrip creates an empty trip with the chosen currencies and friends', () {
      final c = container;
      final n = notifier;
      final oldCode = c.read(tripControllerProvider).squadCode;
      n.startNewTrip(
        name: '  Seoul Autumn Trip ',
        currency: 'krw',
        homeCurrency: 'gbp',
        friends: ['Jisoo', ' jisoo ', 'Min', '', 'you', 'You'],
      );
      final s = c.read(tripControllerProvider);
      expect(s.trip.name, 'Seoul Autumn Trip');
      expect(s.trip.baseCurrency, 'KRW');
      expect(s.trip.homeCurrency, 'GBP');
      expect(s.trip.expenses, isEmpty);
      expect(s.slips, isEmpty);
      expect(s.settlements, isEmpty);
      expect(s.trip.members.map((m) => m.name), ['You', 'Jisoo', 'Min']);
      expect(s.trip.members.first.isCurrentUser, isTrue);
      expect(s.currentMemberId, 'you');
      expect(s.totalSpend, 0);
      expect(s.squadCode, isNot(oldCode));
      expect(s.trip.startDate.hour, 0);
    });

    test('a blank name falls back to My Trip', () {
      final c = container;
      notifier.startNewTrip(name: '   ', currency: 'EUR');
      expect(c.read(tripControllerProvider).trip.name, 'My Trip');
    });

    test('loadDemoTrip restores the seeded Tokyo trip', () {
      final c = container;
      final n = notifier;
      n.startNewTrip(name: 'Empty', currency: 'USD');
      expect(c.read(tripControllerProvider).trip.expenses, isEmpty);
      n.loadDemoTrip();
      final s = c.read(tripControllerProvider);
      expect(s.trip.baseCurrency, 'JPY');
      expect(s.trip.expenses.length, 7);
      expect(s.trip.members.length, 4);
    });

    test('home currency is stored and can be changed', () {
      final c = container;
      final n = notifier;
      expect(c.read(tripControllerProvider).trip.homeCurrency, 'USD');
      n.updateHomeCurrency('eur');
      expect(c.read(tripControllerProvider).trip.homeCurrency, 'EUR');
    });
  });
}
