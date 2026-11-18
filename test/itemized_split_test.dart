import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/core/enums/expense_category.dart';
import 'package:travmate/core/enums/inference_source.dart';
import 'package:travmate/features/settlement/debt_simplifier.dart';
import 'package:travmate/features/settlement/pair_breakdown.dart';
import 'package:travmate/features/trip/trip_state.dart';
import 'package:travmate/models/expense_item.dart';
import 'package:travmate/models/settlement_payment.dart';
import 'package:travmate/models/trip_member.dart';
import 'package:travmate/services/hybrid_ai/expense_normalizer.dart';
import 'package:travmate/services/hybrid_ai/hybrid_ai_service.dart';
import 'package:travmate/services/hybrid_ai/local_expense_parser.dart';
import 'package:travmate/services/hybrid_ai/parsed_expense_draft.dart';
import 'package:travmate/services/sync/squad_sync_service.dart';

const _sentence =
    'Sushiro dinner, I paid: mine 1200, Maya salmon 1800, Liam udon 950';
const _names = ['You', 'Maya', 'Liam'];

ExpenseItem _bill({
  Map<String, double>? custom,
  double amount = 3950,
  String payer = 'you',
}) => ExpenseItem(
  id: 'b1',
  title: 'Sushiro Dinner',
  amount: amount,
  currency: 'JPY',
  payerId: payer,
  splitWithMemberIds: const ['you', 'maya', 'liam'],
  customSplits: custom,
  createdAt: DateTime(2026, 11, 16, 20),
  inferenceSource: InferenceSource.manual,
);

const _members = [
  TripMember(id: 'you', name: 'You', isCurrentUser: true),
  TripMember(id: 'maya', name: 'Maya'),
  TripMember(id: 'liam', name: 'Liam'),
];

void main() {
  group('Unequal dish split: offline parsing', () {
    test('one shared bill with per-person prices is ONE itemized expense', () {
      final items = LocalExpenseParser.parseExpenses(
        _sentence,
        tripCurrency: 'JPY',
        memberNames: _names,
        defaultPayer: 'You',
      );
      expect(items.length, 1);
      final d = ParsedExpenseDraft.fromMap(items.single);
      expect(d.isItemized, isTrue);
      expect(d.customSplits, {'You': 1200.0, 'Maya': 1800.0, 'Liam': 950.0});
      expect(d.totalFor(3), 3950);
      expect(d.payer, 'You');
      expect(d.category, ExpenseCategory.MEAL);
      expect(d.title, contains('Sushiro'));
    });

    test('the itemized breakdown spells out who owes what', () {
      final d = ParsedExpenseDraft.fromMap(
        LocalExpenseParser.parseExpenses(
          _sentence,
          tripCurrency: 'JPY',
          memberNames: _names,
          defaultPayer: 'You',
        ).single,
      );
      final text = d.breakdown(3)!;
      expect(text, contains('You ¥1,200'));
      expect(text, contains('Maya ¥1,800'));
      expect(text, contains('Liam ¥950'));
    });

    test('a THB lunch with two prices stays one expense', () {
      final items = LocalExpenseParser.parseExpenses(
        'Lunch with Alex, mine 250 baht, Alex 420 baht',
        tripCurrency: 'THB',
        memberNames: const ['You', 'Alex'],
        defaultPayer: 'You',
      );
      expect(items.length, 1);
      expect(items.single['amount'], 670.0);
      expect(items.single['currency'], 'THB');
    });

    test('ordinary sentences are NOT treated as itemized', () {
      for (final text in [
        'Ramen 4800 split 4 ways',
        'Taxi 2000 and coffee 500',
        'Maya paid 6 thousand yen for taxi with everyone',
      ]) {
        final items = LocalExpenseParser.parseExpenses(
          text,
          tripCurrency: 'JPY',
          memberNames: _names,
          defaultPayer: 'You',
        );
        for (final i in items) {
          expect(
            ParsedExpenseDraft.fromMap(i).isItemized,
            isFalse,
            reason: text,
          );
        }
      }
    });

    test('the normalizer collapses a model that split the bill in three', () {
      final fixed = ExpenseNormalizer.normalize(
        [
          {'title': 'Sushi', 'amount': 1200, 'currency': 'JPY'},
          {'title': 'Salmon', 'amount': 1800, 'currency': 'JPY'},
          {'title': 'Udon', 'amount': 950, 'currency': 'JPY'},
        ],
        userInput: _sentence,
        tripCurrency: 'JPY',
        memberNames: _names,
        defaultPayer: 'You',
      );
      expect(fixed.length, 1);
      expect(ParsedExpenseDraft.fromMap(fixed.single).customSplits, {
        'You': 1200.0,
        'Maya': 1800.0,
        'Liam': 950.0,
      });
    });

    test('the normalizer drops exact shares the text never gave', () {
      final fixed = ExpenseNormalizer.normalize(
        [
          {
            'title': 'Taxi',
            'amount': 2000,
            'currency': 'JPY',
            'category': 'TRANSPORT',
            'payer': 'You',
            'splitWith': ['You', 'Maya'],
            'customSplits': {'You': 100, 'Maya': 1900},
          },
        ],
        userInput: 'Taxi 2000 with Maya',
        tripCurrency: 'JPY',
        memberNames: _names,
        defaultPayer: 'You',
      );
      expect(ParsedExpenseDraft.fromMap(fixed.single).customSplits, isNull);
    });

    test('names map to member ids and the amount is the sum', () async {
      final service = HybridAiService(
        isMockEnabled: true,
        simulateLatency: false,
      );
      final result = await service.parseExpenseText(
        text: _sentence,
        mode: InferenceMode.preferOnDevice,
        tripCurrency: 'JPY',
        memberNames: _names,
        defaultPayer: 'You',
      );
      final ids = {'You': 'you', 'Maya': 'maya', 'Liam': 'liam'};
      final expenses = result.toExpenseItems(
        defaultCurrency: 'JPY',
        defaultPayerId: 'you',
        allMemberIds: ids.values.toList(),
        nameToIdMap: ids,
      );
      expect(expenses.length, 1);
      final e = expenses.single;
      expect(e.isItemized, isTrue);
      expect(e.amount, 3950);
      expect(e.customSplits, {'you': 1200.0, 'maya': 1800.0, 'liam': 950.0});
      expect(e.splitWithMemberIds, unorderedEquals(['you', 'maya', 'liam']));
      expect(e.payerId, 'you');
    });
  });

  group('Unequal dish split: settlement math', () {
    test('equal bills keep the classic equal fractions', () {
      final e = _bill();
      final f = e.shareFractions(['you', 'maya', 'liam']);
      expect(f.values.every((v) => (v - 1 / 3).abs() < 1e-9), isTrue);
      expect(e.isItemized, isFalse);
    });

    test('custom shares become fractions that sum to exactly 1', () {
      final e = _bill(custom: {'you': 1200, 'maya': 1800, 'liam': 950});
      final f = e.shareFractions(['you', 'maya', 'liam']);
      expect(f['maya']! * e.amount, closeTo(1800, 1e-6));
      expect(f.values.fold<double>(0, (a, b) => a + b), closeTo(1, 1e-9));
    });

    test('net balances follow each person\'s own dish', () {
      final e = _bill(custom: {'you': 1200, 'maya': 1800, 'liam': 950});
      final net = DebtSimplifier.calculateNetBalances(
        expenses: [e],
        members: _members,
        baseCurrency: 'JPY',
      );
      expect(net['you'], closeTo(3950 - 1200, 0.01)); // paid all, ate 1200
      expect(net['maya'], closeTo(-1800, 0.01));
      expect(net['liam'], closeTo(-950, 0.01));
      expect(net.values.fold<double>(0, (a, b) => a + b), closeTo(0, 0.01));
    });

    test('shares that do not add up to the amount are scaled to balance', () {
      // A guest edited the total after the dishes were entered.
      final e = _bill(
        custom: {'you': 1200, 'maya': 1800, 'liam': 950},
        amount: 4345, // +10 %
      );
      final net = DebtSimplifier.calculateNetBalances(
        expenses: [e],
        members: _members,
        baseCurrency: 'JPY',
      );
      expect(net.values.fold<double>(0, (a, b) => a + b), closeTo(0, 0.01));
      expect(net['maya'], closeTo(-1800 * 1.1, 0.5));
    });

    test('the transfer plan asks Maya and Liam for their own dishes', () {
      final e = _bill(custom: {'you': 1200, 'maya': 1800, 'liam': 950});
      final transfers = DebtSimplifier.simplify(
        expenses: [e],
        members: _members,
        defaultCurrency: 'JPY',
      );
      final byFrom = {for (final t in transfers) t.fromMemberId: t};
      expect(byFrom['maya']!.amount, closeTo(1800, 0.5));
      expect(byFrom['liam']!.amount, closeTo(950, 0.5));
      expect(transfers.every((t) => t.toMemberId == 'you'), isTrue);
    });

    test('the pair breakdown lists the exact dish amount', () {
      final base = TripState.initial();
      final state = base.copyWith(
        trip: base.trip.copyWith(
          members: _members,
          expenses: [
            _bill(custom: {'you': 1200, 'maya': 1800, 'liam': 950}),
          ],
        ),
      );
      final b = computePairBreakdown(state, 'maya', 'you');
      expect(b.net, closeTo(-1800, 0.01));
      expect(b.lines.single.amount.abs(), closeTo(1800, 0.01));
    });

    test('a recorded repayment is deducted from the itemized balance', () {
      final e = _bill(custom: {'you': 1200, 'maya': 1800, 'liam': 950});
      final net = DebtSimplifier.calculateNetBalances(
        expenses: [e],
        members: _members,
        baseCurrency: 'JPY',
        settlements: [
          SettlementPayment(
            id: 'p1',
            fromMemberId: 'maya',
            toMemberId: 'you',
            amount: 1800,
            currency: 'JPY',
            paidAt: DateTime(2026, 11, 17),
          ),
        ],
      );
      expect(net['maya'], closeTo(0, 0.01));
      expect(net['you'], closeTo(950, 0.01));
    });
  });

  group('Photos and the 1 MiB Firestore document limit', () {
    test('small payloads keep their photos', () {
      final out = SquadSyncService.fitImagesToDocument(
        expenses: [
          {'id': 'a', 'receiptImageBase64': 'x' * 1000},
        ],
        settlements: [
          {'id': 's', 'slipImageBase64': 'y' * 1000},
        ],
      );
      expect((out['expenses'] as List).single['receiptImageBase64'], isNotNull);
      expect((out['settlements'] as List).single['slipImageBase64'], isNotNull);
    });

    test(
      'oversized payloads shed the biggest photos from the cloud copy only',
      () {
        final input = [
          {'id': 'big', 'receiptImageBase64': 'x' * 5000},
          {'id': 'small', 'receiptImageBase64': 'x' * 100},
        ];
        final out = SquadSyncService.fitImagesToDocument(
          expenses: input,
          settlements: const [],
          maxBytes: 2000,
        );
        final list = (out['expenses'] as List).cast<Map<String, dynamic>>();
        expect(
          list.firstWhere((e) => e['id'] == 'big')['receiptImageBase64'],
          isNull,
        );
        expect(
          list.firstWhere((e) => e['id'] == 'small')['receiptImageBase64'],
          isNotNull,
        );
        expect(
          input.first['receiptImageBase64'],
          isNotNull,
          reason: 'the caller\'s data is untouched',
        );
      },
    );
  });
}
