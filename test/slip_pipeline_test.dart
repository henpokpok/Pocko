import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/core/enums/expense_category.dart';
import 'package:travmate/core/enums/inference_source.dart';
import 'package:travmate/core/enums/slip_status.dart';
import 'package:travmate/features/trip/trip_state.dart';
import 'package:travmate/models/bank_slip.dart';
import 'package:travmate/models/expense_item.dart';
import 'package:travmate/services/hybrid_ai/hybrid_ai_service.dart';
import 'package:travmate/services/matcher/pii_masker.dart';
import 'package:travmate/services/matcher/slip_analyzer.dart';
import 'package:travmate/services/matcher/slip_matcher.dart';
import 'package:travmate/services/matcher/slip_samples.dart';

SlipAnalyzer _analyzer() =>
    SlipAnalyzer(HybridAiService(isMockEnabled: true, simulateLatency: false));

void main() {
  group('PiiMasker', () {
    test('Masks card numbers, e-mails, phone numbers and holder names', () {
      final masked = PiiMasker.mask('''Chase alert
Card: 4929 1823 7701 5521
Cardholder: Alex Morgan
Contact: alex.morgan@example.com
Call +81 3 1234 5678''');
      expect(masked.text, contains('•••• 5521'));
      expect(masked.text, isNot(contains('4929')));
      expect(masked.text, isNot(contains('Alex Morgan')));
      expect(masked.text, isNot(contains('example.com')));
      expect(masked.text, isNot(contains('1234 5678')));
      expect(masked.count, 4);
      expect(masked.accountLast4, '5521');
      expect(
        masked.kinds,
        containsAll([
          'card/account number',
          'email',
          'holder name',
          'phone number',
        ]),
      );
    });

    test('Leaves amounts, dates and times alone', () {
      final masked = PiiMasker.mask(
        'Amount: JPY 15,400 on 2026-11-16 at 11:42, VAT 10%',
      );
      expect(masked.count, 0);
      expect(masked.text, contains('15,400'));
      expect(masked.text, contains('2026-11-16'));
    });

    test('Masks IBANs and long contiguous account numbers', () {
      final masked = PiiMasker.mask(
        'IBAN DE89 3704 0044 0532 0130 00 acct 1234567890123',
      );
      expect(masked.text, isNot(contains('3704')));
      expect(masked.text, isNot(contains('1234567890123')));
      expect(masked.count, 2);
    });
  });

  group('SlipMatcher', () {
    final now = DateTime.now();
    final teamLab = ExpenseItem(
      id: 'teamlab',
      title: 'TeamLab Borderless Tickets',
      amount: 15400,
      currency: 'JPY',
      category: ExpenseCategory.ATTRACTION,
      payerId: 'alex',
      createdAt: now.subtract(const Duration(hours: 3)),
    );
    final metro = teamLab.copyWith(
      id: 'metro',
      title: 'Metro passes',
      amount: 6000,
      category: ExpenseCategory.TRANSPORT,
    );

    test('Exact amount + merchant + time is an exact match', () {
      final r = SlipMatcher.match(
        amount: 15400,
        currency: 'JPY',
        descriptor: 'TEAMLAB BORDERLESS TOKYO',
        slipTime: now.subtract(const Duration(hours: 2)),
        expenses: [metro, teamLab],
        baseCurrency: 'JPY',
      );
      expect(r.expense?.id, 'teamlab');
      expect(r.percent, greaterThanOrEqualTo(90));
    });

    test('Matching amount without a merchant hint is a potential match', () {
      final r = SlipMatcher.match(
        amount: 15400,
        currency: 'JPY',
        descriptor: 'UNKNOWN SHOP',
        slipTime: now.subtract(const Duration(hours: 40)),
        expenses: [teamLab],
        baseCurrency: 'JPY',
      );
      expect(r.expense, isNotNull);
      expect(r.percent, inInclusiveRange(55, 89));
    });

    test('Different amounts never match confidently', () {
      final r = SlipMatcher.match(
        amount: 1240,
        currency: 'JPY',
        descriptor: 'SEVEN-ELEVEN',
        slipTime: now,
        expenses: [teamLab, metro],
        baseCurrency: 'JPY',
      );
      expect(r.expense, isNull);
    });

    test('Foreign slips match after currency conversion', () {
      final eurExpense = teamLab.copyWith(
        id: 'eur',
        title: 'Paris dinner',
        amount: 16200,
        category: ExpenseCategory.MEAL,
      );
      final r = SlipMatcher.match(
        amount: 100,
        currency: 'EUR', // 100 EUR = 16,200 JPY
        descriptor: 'Bistro dinner',
        slipTime: now,
        expenses: [eurExpense],
        baseCurrency: 'JPY',
      );
      expect(r.expense?.id, 'eur');
    });

    test(
      'Verified expenses and already-linked expenses are never candidates',
      () {
        final done = teamLab.copyWith(slipStatus: SlipStatus.matched);
        expect(
          SlipMatcher.match(
            amount: 15400,
            currency: 'JPY',
            descriptor: 'teamlab',
            slipTime: now,
            expenses: [done],
            baseCurrency: 'JPY',
          ).expense,
          isNull,
        );
        expect(
          SlipMatcher.match(
            amount: 15400,
            currency: 'JPY',
            descriptor: 'teamlab',
            slipTime: now,
            expenses: [teamLab],
            baseCurrency: 'JPY',
            excludeExpenseIds: {'teamlab'},
          ).expense,
          isNull,
        );
      },
    );
  });

  group('SlipAnalyzer samples', () {
    final expenses = TripState.initial().trip.expenses;

    test(
      'Bank notification stays on-device and matches the TeamLab tickets',
      () async {
        final sample = SlipSamples.all.firstWhere(
          (s) => s.id == 'sample_chase_teamlab',
        );
        final analysis = await _analyzer().analyzeText(
          rawText: sample.rawText,
          baseCurrency: 'JPY',
          expenses: expenses,
        );
        final slip = analysis.slip;
        expect(
          slip.inferenceSource,
          InferenceSource.onDevice,
          reason: 'plain notifications use local AI',
        );
        expect(slip.amount, 15400);
        expect(slip.currency, 'JPY');
        expect(slip.targetExpenseId, 'exp_5');
        expect(slip.tier, SlipMatchTier.exact);
        expect(slip.maskedAccount, '•••• 5521');
        expect(slip.maskedFieldCount, greaterThanOrEqualTo(3));
        expect(slip.maskedText, isNot(contains('4929')));
        expect(slip.maskedText, isNot(contains('Alex Morgan')));
      },
    );

    test(
      'Unknown convenience-store notice requires manual verification',
      () async {
        final sample = SlipSamples.all.firstWhere(
          (s) => s.id == 'sample_wise_vending',
        );
        final slip = (await _analyzer().analyzeText(
          rawText: sample.rawText,
          baseCurrency: 'JPY',
          expenses: expenses,
        )).slip;
        expect(slip.inferenceSource, InferenceSource.onDevice);
        expect(slip.amount, 1240);
        expect(slip.targetExpenseId, isNull);
        expect(slip.tier, SlipMatchTier.manual);
      },
    );

    test(
      'Itemized EUR receipt falls back to the cloud model and keeps line items',
      () async {
        final sample = SlipSamples.all.firstWhere(
          (s) => s.id == 'sample_paris_bistro',
        );
        final slip = (await _analyzer().analyzeText(
          rawText: sample.rawText,
          baseCurrency: 'JPY',
          expenses: expenses,
        )).slip;
        expect(slip.inferenceSource, InferenceSource.inCloud);
        expect(slip.currency, 'EUR');
        expect(slip.amount, closeTo(67.65, 0.001));
        expect(slip.lineItems.length, 5);
        expect(slip.isItemized, isTrue);
        expect(slip.maskedText, isNot(contains('5100 2200')));
        expect(slip.maskedAccount, '•••• 4455');
      },
    );

    test(
      'Seoul night-market receipt parses KRW totals through the cloud route',
      () async {
        final sample = SlipSamples.all.firstWhere(
          (s) => s.id == 'sample_seoul_market',
        );
        final slip = (await _analyzer().analyzeText(
          rawText: sample.rawText,
          baseCurrency: 'JPY',
          expenses: expenses,
        )).slip;
        expect(slip.inferenceSource, InferenceSource.inCloud);
        expect(slip.currency, 'KRW');
        expect(slip.amount, 26000);
        expect(slip.lineItems.length, 4);
      },
    );

    test(
      'needsCloud routes only itemized or foreign multi-line text to the cloud',
      () {
        expect(
          SlipAnalyzer.needsCloud('Wise\nAmount: JPY 3,500', 'JPY'),
          isFalse,
        );
        expect(
          SlipAnalyzer.needsCloud(
            'Cafe\nLatte 4.50\nCake 6.00\nTotal EUR 10.50',
            'JPY',
          ),
          isTrue,
        );
        expect(
          SlipAnalyzer.needsCloud('Ramen 700\nTea 200\nCake 500', 'JPY'),
          isTrue,
        );
      },
    );
  });
}
