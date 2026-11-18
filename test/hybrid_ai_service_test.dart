import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/core/enums/expense_category.dart';
import 'package:travmate/core/enums/inference_source.dart';
import 'package:travmate/services/hybrid_ai/hybrid_ai_service.dart';
import 'package:travmate/services/remote_config/remote_config_service.dart';

HybridAiService _service({RemoteConfigData Function()? policyReader}) =>
    HybridAiService(
      isMockEnabled: true,
      simulateLatency: false,
      policyReader: policyReader,
    );

void main() {
  const members = ['You', 'Alex', 'Maya', 'Liam'];
  const ids = {'You': 'you', 'Alex': 'alex', 'Maya': 'maya', 'Liam': 'liam'};

  group('HybridAiService (simulated engine)', () {
    test('Parses a single English expense with payer and split', () async {
      final result = await _service().parseExpenseText(
        text: 'Ichiran ramen 4800 Alex paid, split Maya and Liam',
        mode: InferenceMode.preferOnDevice,
        tripCurrency: 'JPY',
        memberNames: members,
        defaultPayer: 'You',
      );

      expect(result.inferenceSource, InferenceSource.onDevice);
      expect(
        result.isSimulated,
        isTrue,
        reason: 'offline engine results must be flagged',
      );
      expect(result.latencyMs, greaterThan(0));

      final item = result.items.single;
      expect(item['amount'], 4800.0);
      expect(item['category'], 'MEAL');
      expect(item['payer'], 'Alex');
      expect(item['title'], 'Ichiran Ramen');
      expect(item['splitWith'], containsAll(['Alex', 'Maya', 'Liam']));

      final expense = result.toExpenseItem(
        id: 'test_exp',
        defaultCurrency: 'JPY',
        defaultPayerId: 'you',
        allMemberIds: ids.values.toList(),
        nameToIdMap: ids,
      );
      expect(expense.payerId, 'alex');
      expect(expense.category, ExpenseCategory.MEAL);
      expect(expense.splitWithMemberIds, containsAll(['alex', 'maya', 'liam']));
    });

    test('Cloud-only mode marks the result as cloud fallback', () async {
      final result = await _service().parseExpenseText(
        text: 'Starbucks matcha latte 650 Maya paid for herself',
        mode: InferenceMode.onlyInCloud,
        memberNames: members,
      );

      expect(result.inferenceSource, InferenceSource.inCloud);
      final item = result.items.single;
      expect(item['amount'], 650.0);
      expect(item['category'], 'SNACK_CAFE');
      expect(item['payer'], 'Maya');
      expect(item['splitWith'], ['Maya']);
      expect(result.modelInfo, contains('gemini-3.1-flash-lite'));
    });

    test(
      'Splits a two-expense sentence and understands "me" and "split 4 ways"',
      () async {
        final result = await _service().parseExpenseText(
          text: 'Ramen 4800 split 4 ways, and Shinkansen tickets 18200 for Alex, Maya, and me',
          mode: InferenceMode.preferOnDevice,
          tripCurrency: 'JPY',
          memberNames: members,
          defaultPayer: 'You',
        );

        expect(result.items.length, 2);
        expect(result.items[0]['amount'], 4800.0);
        expect(result.items[0]['splitWith'], members);
        expect(result.items[1]['amount'], 18200.0);
        expect(result.items[1]['category'], 'TRANSPORT');
        expect(
          result.items[1]['splitWith'],
          unorderedEquals(['Alex', 'Maya', 'You']),
        );

        final expenses = result.toExpenseItems(
          defaultCurrency: 'JPY',
          defaultPayerId: 'you',
          allMemberIds: ids.values.toList(),
          nameToIdMap: ids,
        );
        expect(expenses.map((e) => e.amount), [4800.0, 18200.0]);
        expect(
          expenses[1].splitWithMemberIds,
          unorderedEquals(['alex', 'maya', 'you']),
        );
      },
    );

    test('Chains 5+ expenses in one sentence', () async {
      final result = await _service().parseExpenseText(
        text: 'Ramen 1200; coffee 450; museum ticket 2000; taxi 1800 and souvenirs 3000',
        mode: InferenceMode.preferOnDevice,
        memberNames: members,
      );
      expect(result.items.length, 5);
      expect(result.items.map((i) => i['amount']), [
        1200.0,
        450.0,
        2000.0,
        1800.0,
        3000.0,
      ]);
      expect(result.items.map((i) => i['category']), [
        'MEAL',
        'SNACK_CAFE',
        'ATTRACTION',
        'TRANSPORT',
        'SOUVENIR',
      ]);
    });

    test('Detects foreign currencies and thousands separators', () async {
      final result = await _service().parseExpenseText(
        text: 'Dinner 85 euro Alex paid, split everyone; hotel \$1,200',
        mode: InferenceMode.preferOnDevice,
        tripCurrency: 'JPY',
        memberNames: members,
      );
      expect(result.items[0]['currency'], 'EUR');
      expect(result.items[0]['amount'], 85.0);
      expect(result.items[1]['currency'], 'USD');
      expect(result.items[1]['amount'], 1200.0);
      expect(result.items[1]['category'], 'LODGING');
    });

    test('Text without an amount reports no parsed amount', () async {
      final result = await _service().parseExpenseText(
        text: 'hello pocko',
        memberNames: members,
      );
      expect(result.hasParsedAmount, isFalse);
    });

    test('Output contains no non-English text', () async {
      final result = await _service().parseExpenseText(
        text: 'dinner 5000',
        memberNames: members,
      );
      expect(
        result.rawJson.runes.any((r) => r >= 0x0E00 && r <= 0x0E7F),
        isFalse,
      );
    });
  });

  group('Remote Config policy', () {
    test('Remote Config mode, model and tokens drive the policy', () {
      final service = _service(
        policyReader: () => RemoteConfigData.initial().copyWith(
          isConfigured: true,
          aiInferenceMode: 'ONLY_IN_CLOUD',
          cloudFallbackModel: 'gemini-3.0-flash',
          maxOutputTokens: 256,
        ),
      );
      expect(service.policy.mode, InferenceMode.onlyInCloud);
      expect(service.policy.cloudModel, 'gemini-3.0-flash');
      expect(service.policy.maxOutputTokens, 256);
    });

    test(
      'Without an explicit mode, parseExpenseText follows Remote Config',
      () async {
        final service = _service(
          policyReader: () => RemoteConfigData.initial().copyWith(
            aiInferenceMode: 'only_in_cloud',
          ),
        );
        final result = await service.parseExpenseText(
          text: 'coffee 450',
          memberNames: members,
        );
        expect(result.inferenceSource, InferenceSource.inCloud);
      },
    );

    test('Blank or invalid remote values fall back to safe defaults', () {
      final service = _service(
        policyReader: () => RemoteConfigData.initial().copyWith(
          aiInferenceMode: '',
          cloudFallbackModel: '  ',
          maxOutputTokens: 0,
        ),
      );
      expect(service.policy.mode, InferenceMode.preferOnDevice);
      expect(service.policy.cloudModel, 'gemini-3.1-flash-lite');
      expect(service.policy.maxOutputTokens, 512);
    });

    test('InferenceMode wire names match Firebase SDK conventions', () {
      expect(InferenceMode.preferOnDevice.webName, 'prefer_on_device');
      expect(InferenceMode.preferOnDevice.wireName, 'PREFER_ON_DEVICE');
      expect(
        InferenceMode.fromRaw('PREFER_ON_DEVICE'),
        InferenceMode.preferOnDevice,
      );
      expect(
        InferenceMode.fromRaw('only_on_device'),
        InferenceMode.onlyOnDevice,
      );
      expect(InferenceMode.fromRaw('garbage'), InferenceMode.preferOnDevice);
    });
  });

  group('Receipts', () {
    test('Parses an itemized EUR receipt with European decimals', () async {
      final result = await _service().parseReceipt(
        maskedText: '''Bistro Montmartre - Paris
Croque monsieur        18,50
Onion soup             12,00
Espresso 3x            10,50
TOTAL EUR              41,00''',
        tripCurrency: 'JPY',
        forceCloud: true,
      );
      final receipt = result.receipt!;
      expect(result.inferenceSource, InferenceSource.inCloud);
      expect(receipt.currency, 'EUR');
      expect(receipt.total, 41.0);
      expect(receipt.lineItems.length, 3);
      expect(receipt.lineItems.first.amount, 18.5);
      expect(receipt.merchant, 'Bistro Montmartre - Paris');
    });
  });
}
