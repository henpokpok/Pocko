import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/services/hybrid_ai/expense_normalizer.dart';
import 'package:travmate/services/hybrid_ai/expense_prompt_builder.dart';
import 'package:travmate/services/hybrid_ai/hybrid_ai_service.dart';
import 'package:travmate/services/hybrid_ai/local_expense_parser.dart';
import 'package:travmate/services/hybrid_ai/parsed_expense_draft.dart';

const _members = ['You', 'Alex', 'Maya', 'Liam'];

List<Map<String, dynamic>> _parse(String text) =>
    LocalExpenseParser.parseExpenses(
      text,
      tripCurrency: 'JPY',
      memberNames: _members,
      defaultPayer: 'You',
    );

Map<String, dynamic> _one(String text) => _parse(text).single;

void main() {
  group(
    'Neuro-symbolic pricing: the model reports intent, Dart does the maths',
    () {
      test('"500 yen each" with Maya and Liam = 500 x 3', () {
        final i = _one('Eat ramen with Maya and Liam 500 yen each');
        expect(i['unitAmount'], 500.0);
        expect(i['amountMode'], 'PER_PERSON');
        expect(i['splitWith'], ['You', 'Maya', 'Liam']);
        expect(i['amount'], 1500.0);
        expect(i['category'], 'MEAL');
        expect(i['quantity'], 1);
        expect(i['extraPercent'], 0.0);
      });

      test('every spelling of per-person triggers PER_PERSON', () {
        for (final t in [
          'Lunch with Alex 800 yen each',
          'Lunch with Alex 800 yen per person',
          'Lunch with Alex 800 yen apiece',
          'Lunch with Alex 800 yen per head',
          'Lunch with Alex 800 yen a head',
        ]) {
          final i = _one(t);
          expect(i['amountMode'], 'PER_PERSON', reason: t);
          expect(i['amount'], 1600.0, reason: t);
        }
      });

      test('"4 coffees at 5 dollars a cup" = 4 x 5', () {
        final i = _one('4 coffees at 5 dollars a cup');
        expect(i['unitAmount'], 5.0);
        expect(i['quantity'], 4);
        expect(i['amountMode'], 'TOTAL');
        expect(i['amount'], 20.0);
        expect(i['currency'], 'USD');
      });

      test('"3 tickets 1200 yen each": each belongs to the tickets', () {
        final i = _one('3 tickets 1200 yen each');
        expect(i['quantity'], 3);
        expect(i['amountMode'], 'TOTAL');
        expect(i['amount'], 3600.0);
      });

      test('head-counts are never quantities', () {
        expect(_one('Dinner for 2 4000 yen')['quantity'], 1);
        expect(_one('Ramen 4800 split 4 ways')['quantity'], 1);
        expect(_one('Ramen 4800 split 4 ways')['amount'], 4800.0);
      });

      test('"plus 10% service charge" adds 10%', () {
        final i = _one('Dinner 10 thousand yen plus 10% service charge');
        expect(i['unitAmount'], 10000.0);
        expect(i['extraPercent'], 10.0);
        expect(i['amount'], 11000.0);
        expect(_one('Dinner 10k plus 10%')['amount'], 11000.0);
        expect(_one('Lunch 5000 yen with 8% tax')['amount'], 5400.0);
      });

      test('a discount is not a surcharge', () {
        expect(_one('Shoes 10000 yen 20% off')['extraPercent'], 0.0);
      });

      test('modifiers combine: 2 beers 500 each per person', () {
        final i = _one('2 beers at 500 yen per person with Alex');
        expect(i['quantity'], 2);
        expect(i['amountMode'], 'PER_PERSON');
        expect(i['amount'], 2000.0); // 500 x 2 x (You + Alex)
      });

      test('a plain price has no modifiers', () {
        final i = _one('Ramen 4800 yen');
        expect(i['amountMode'], 'TOTAL');
        expect(i['quantity'], 1);
        expect(i['extraPercent'], 0.0);
        expect(i['amount'], 4800.0);
      });
    },
  );

  group('ParsedExpenseDraft', () {
    test('totalFor follows the number of people only when per person', () {
      const each = ParsedExpenseDraft(
        title: 'Ramen',
        unitAmount: 500,
        amountMode: AmountMode.perPerson,
      );
      expect(each.totalFor(3), 1500);
      expect(each.totalFor(2), 1000);
      expect(each.totalFor(0), 500, reason: 'never fewer than one person');
      const total = ParsedExpenseDraft(title: 'Ramen', unitAmount: 4800);
      expect(total.totalFor(4), 4800);
      expect(total.totalFor(2), 4800);
    });

    test('percent maths is exact (no float noise)', () {
      const d = ParsedExpenseDraft(
        title: 'Dinner',
        unitAmount: 10000,
        extraPercent: 10,
      );
      expect(d.totalFor(1), 11000);
    });

    test('breakdown labels', () {
      const each = ParsedExpenseDraft(
        title: 'Ramen',
        unitAmount: 500,
        amountMode: AmountMode.perPerson,
      );
      expect(each.breakdown(3), '¥1,500 (¥500 × 3 each)');
      expect(each.breakdown(2), '¥1,000 (¥500 × 2 each)');
      const qty = ParsedExpenseDraft(
        title: 'Coffee',
        unitAmount: 5,
        quantity: 4,
        currency: 'USD',
      );
      expect(qty.breakdown(2), '\$20 (4 × \$5)');
      const pct = ParsedExpenseDraft(
        title: 'Dinner',
        unitAmount: 10000,
        extraPercent: 10,
      );
      expect(pct.breakdown(4), '¥11,000 (¥10,000 + 10%)');
      expect(
        const ParsedExpenseDraft(title: 'x', unitAmount: 1).breakdown(2),
        isNull,
      );
    });

    test('fromMap accepts the new and the legacy schema', () {
      final fresh = ParsedExpenseDraft.fromMap({
        'title': 'Ramen',
        'unitAmount': 500,
        'amountMode': 'PER_PERSON',
        'quantity': 2,
        'extraPercent': '10',
      });
      expect(fresh.amountMode, AmountMode.perPerson);
      expect(fresh.quantity, 2);
      expect(fresh.extraPercent, 10);
      final legacy = ParsedExpenseDraft.fromMap({
        'title': 'Ramen',
        'amount': 4800,
      });
      expect(legacy.unitAmount, 4800);
      expect(legacy.hasModifiers, isFalse);
      // Garbage never crashes or goes below 1.
      final odd = ParsedExpenseDraft.fromMap({
        'unitAmount': 'abc',
        'quantity': 0,
      });
      expect(odd.unitAmount, 0);
      expect(odd.quantity, 1);
    });
  });

  group('Natural split & payer patterns', () {
    test('"with X" includes the payer; "for X" / "bought X" do not', () {
      expect(_one('Bought water for Maya 200 yen')['splitWith'], ['Maya']);
      expect(_one('Water with Maya 200 yen')['splitWith'], ['You', 'Maya']);
      expect(_one('Bought Maya a ticket 2000')['splitWith'], ['Maya']);
      expect(_one('Snack for me 300 yen')['splitWith'], ['You']);
      expect(_one('Souvenir 900 yen solo')['splitWith'], ['You']);
    });

    test('"everyone", "all" and "the group" map to every member', () {
      for (final t in [
        'Taxi 3000 yen with everyone',
        'Taxi 3000 yen for all',
        'Taxi 3000 yen for the group',
      ]) {
        expect(_one(t)['splitWith'], _members, reason: t);
      }
    });

    test('third-party payers', () {
      final i = _one('Maya paid 6 thousand yen for taxi with everyone');
      expect(i['payer'], 'Maya');
      expect(i['amount'], 6000.0);
      expect(i['splitWith'], _members);
      expect(i['title'], 'Taxi');
      expect(i['category'], 'TRANSPORT');
      expect(_one('Alex covered dinner 8000')['payer'], 'Alex');
      expect(_one('Taxi 5 pounds paid by Liam')['payer'], 'Liam');
    });

    test('spoken numbers and currency slang', () {
      expect(_one('Souvenir five hundred yen')['amount'], 500.0);
      expect(_one('Lunch 2.5k yen')['amount'], 2500.0);
      expect(_one('Hotel 8 thousand yen')['amount'], 8000.0);
      expect(_one('Villa 1 million yen')['amount'], 1000000.0);
      expect(_one('Coffee 12 bucks')['currency'], 'USD');
      expect(_one('Coffee 12 dollars')['currency'], 'USD');
      expect(_one('Ramen 800 yen')['currency'], 'JPY');
      expect(_one('Pad thai 120 baht')['currency'], 'THB');
      expect(_one('Bibimbap 9000 won')['currency'], 'KRW');
      expect(_one('Croissant 4 euros')['currency'], 'EUR');
      expect(_one('Pint 6 pounds')['currency'], 'GBP');
      expect(_one('Pint 6 quid')['currency'], 'GBP');
    });

    test('compound utterances become separate items', () {
      final items = _parse(
        'Matcha 600 yen for me, and gyoza 1200 yen with Alex',
      );
      expect(items, hasLength(2));
      expect(items[0]['title'], 'Matcha');
      expect(items[0]['amount'], 600.0);
      expect(items[0]['splitWith'], ['You']);
      expect(items[1]['title'], 'Gyoza');
      expect(items[1]['amount'], 1200.0);
      expect(items[1]['splitWith'], ['You', 'Alex']);
      expect(items[1]['category'], 'MEAL');
    });

    test('per-item modifiers stay with their own item', () {
      final items = _parse(
        'Ramen with Alex 500 yen each, and taxi 3000 yen plus 10%',
      );
      expect(items, hasLength(2));
      expect(items[0]['amount'], 1000.0);
      expect(items[1]['amount'], 3300.0);
      expect(items[1]['amountMode'], 'TOTAL');
    });
  });

  group('Normalizer keeps real answers honest', () {
    List<Map<String, dynamic>> fix(String text, Map<String, dynamic> live) =>
        ExpenseNormalizer.normalize(
          [live],
          userInput: text,
          tripCurrency: 'JPY',
          memberNames: _members,
          defaultPayer: 'You',
        );

    test('a model that multiplied by itself is corrected', () {
      final r = fix('Eat ramen with Maya and Liam 500 yen each', {
        'title': 'Ramen',
        'unitAmount': 1500, // multiplied already
        'amountMode': 'TOTAL', // and forgot "each"
        'currency': 'JPY',
        'category': 'MEAL',
        'payer': 'You',
        'splitWith': ['You', 'Maya', 'Liam'],
      }).single;
      expect(r['unitAmount'], 500.0);
      expect(r['amountMode'], 'PER_PERSON');
      expect(r['amount'], 1500.0);
    });

    test('a correct new-schema answer is kept and totalled by Dart', () {
      final r = fix('Eat ramen with Maya and Liam 500 yen each', {
        'title': 'Ramen',
        'unitAmount': 500,
        'amountMode': 'PER_PERSON',
        'quantity': 1,
        'extraPercent': 0,
        'currency': 'JPY',
        'category': 'MEAL',
        'payer': 'You',
        'splitWith': ['You', 'Maya', 'Liam'],
      }).single;
      expect(r['amount'], 1500.0);
      expect(r['splitWith'], ['You', 'Maya', 'Liam']);
    });

    test('an invented percentage or per-person flag is dropped', () {
      final r = fix('Ramen 800 yen', {
        'title': 'Ramen',
        'unitAmount': 800,
        'amountMode': 'PER_PERSON',
        'extraPercent': 15,
        'category': 'MEAL',
        'splitWith': ['You', 'Alex'],
      }).single;
      expect(r['amountMode'], 'TOTAL');
      expect(r['extraPercent'], 0.0);
      expect(r['amount'], 800.0);
    });

    test('a dropped multiplier and a MISC answer are repaired', () {
      final r = fix('Dinner 10 thousand yen plus 10% service charge', {
        'title': 'Dinner',
        'unitAmount': 10,
        'category': 'MISC',
        'splitWith': [],
      }).single;
      expect(r['unitAmount'], 10000.0);
      expect(r['extraPercent'], 10.0);
      expect(r['amount'], 11000.0);
      expect(r['category'], 'MEAL');
    });

    test('third-party payer from the text beats the default', () {
      final r = fix('Maya paid 6 thousand yen for taxi with everyone', {
        'title': 'Taxi',
        'unitAmount': 6000,
        'category': 'TRANSPORT',
        'payer': 'You',
        'splitWith': ['You'],
      }).single;
      expect(r['splitWith'], _members, reason: 'everyone');
    });
  });

  group('Schema end to end', () {
    test('unitAmount-only items total correctly and count as parsed', () {
      final result = HybridAiResult.fromMap({
        'rawJson': '{"items":[{"title":"Ramen","unitAmount":500,"amountMode":"PER_PERSON","quantity":1,"extraPercent":0,"currency":"JPY","category":"MEAL","payer":"You","splitWith":["You","Maya","Liam"]}]}',
        'inferenceSource': 'in_cloud',
      });
      expect(result.hasParsedAmount, isTrue, reason: 'no legacy "amount" key');
      final items = result.toExpenseItems(
        allMemberIds: const ['you', 'alex', 'maya', 'liam'],
        nameToIdMap: const {
          'You': 'you',
          'Alex': 'alex',
          'Maya': 'maya',
          'Liam': 'liam',
        },
      );
      expect(items.single.amount, 1500);
      expect(items.single.splitWithMemberIds, ['you', 'maya', 'liam']);
      expect(result.drafts.single.amountMode, AmountMode.perPerson);
    });

    test('the prompt documents the new schema, examples and venue rule', () {
      final p = ExpensePromptBuilder.buildPrompt(
        userInput: 'x 500',
      );
      for (final needle in [
        'unitAmount',
        'amountMode',
        'PER_PERSON',
        'quantity',
        'extraPercent',
        'NEVER multiplied',
        'bucks',
        'quid',
        'with Maya and Liam',
        'for Maya',
        'Maya paid',
        'Examples:',
      ]) {
        expect(p, contains(needle), reason: needle);
      }
    });
  });
}
