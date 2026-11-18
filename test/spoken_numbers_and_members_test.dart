import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/services/hybrid_ai/expense_prompt_builder.dart';
import 'package:travmate/services/hybrid_ai/local_expense_parser.dart';
import 'package:travmate/services/hybrid_ai/spoken_numbers.dart';

const _members = ['You', 'Alex', 'Maya', 'Liam'];

List<Map<String, dynamic>> _parse(String text) =>
    LocalExpenseParser.parseExpenses(
      text,
      tripCurrency: 'JPY',
      memberNames: _members,
      defaultPayer: 'You',
    );

double _amount(String text) => (_parse(text).first['amount'] as num).toDouble();

List<String> _split(String text, [int item = 0]) =>
    List<String>.from(_parse(text)[item]['splitWith'] as List);

void main() {
  group('SpokenNumbers.scan', () {
    double? one(String t) {
      final spans = SpokenNumbers.scan(t);
      return spans.isEmpty ? null : spans.first.value;
    }

    test('digit + multiplier word', () {
      expect(one('dinner 1 thousand'), 1000);
      expect(one('dinner 15 thousand yen'), 15000);
      expect(one('hotel 2.5 thousand'), 2500);
      expect(one('villa 1 million'), 1000000);
      expect(one('tickets 3 hundred'), 300);
      expect(one('2 grand'), 2000);
    });

    test('typos in the multiplier are tolerated', () {
      expect(one('dinner 1 thousan'), 1000);
      expect(one('dinner 1 thosand'), 1000);
      expect(one('dinner 2 tousand'), 2000);
      expect(one('villa 1 milion'), 1000000);
      expect(one('villa 2 millon'), 2000000);
    });

    test('suffix letters k and m', () {
      expect(one('dinner 2.5k'), 2500);
      expect(one('dinner 2.5K'), 2500);
      expect(one('dinner 15 k'), 15000);
      expect(one('villa 1m'), 1000000);
      expect(one('villa 1.2M'), 1200000);
    });

    test('number words', () {
      expect(one('dinner one thousand'), 1000);
      expect(one('dinner one thousan'), 1000);
      expect(one('dinner fifteen thousand'), 15000);
      expect(one('dinner two hundred fifty'), 250);
      expect(one('dinner two hundred and fifty'), 250);
      expect(one('dinner a hundred'), 100);
      expect(one('villa one million'), 1000000);
      expect(one('dinner twenty five thousand'), 25000);
      expect(one('two thousand five hundred'), 2500);
    });

    test('plain words and head-counts are not amounts', () {
      expect(SpokenNumbers.scan('one for the road, no one cares'), isEmpty);
      expect(one('ramen 4800 split 4 ways'), 4800);
      expect(SpokenNumbers.scan('3 mins away').single.value, 3);
    });

    test('commas and decimals', () {
      expect(one('ramen 1,200'), 1200);
      expect(one('latte 4.50'), 4.5);
    });

    test('normalize rewrites spoken numbers as digits', () {
      expect(
        SpokenNumbers.normalize('Dinner 1 thousan yen'),
        'Dinner 1000 yen',
      );
      expect(
        SpokenNumbers.normalize('Hotel 2.5k and taxi one thousand'),
        'Hotel 2500 and taxi 1000',
      );
      expect(
        SpokenNumbers.normalize('nothing special 400'),
        'nothing special 400',
      );
    });
  });

  group('LocalExpenseParser amounts', () {
    test('1 thousand / 1 thousan / one thousand all give 1000', () {
      expect(_amount('Dinner 1 thousand'), 1000);
      expect(_amount('Dinner 1 thousan'), 1000);
      expect(_amount('Dinner one thousand'), 1000);
    });

    test('2.5 thousand, 2.5k, 15 thousand, 1 million', () {
      expect(_amount('Taxi 2.5 thousand'), 2500);
      expect(_amount('Taxi 2.5k'), 2500);
      expect(_amount('Hotel 15 thousand yen'), 15000);
      expect(_amount('Villa deposit 1 million'), 1000000);
      expect(_amount('Villa deposit 1m'), 1000000);
    });

    test('titles never swallow the spoken number', () {
      final t =
          _parse('Ramen 1 thousand split 4 ways').first['title'] as String;
      expect(t, 'Ramen');
      final t2 = _parse('One thousand yen ramen').first['title'] as String;
      expect(t2.toLowerCase(), contains('ramen'));
    });

    test('two spoken amounts become two expenses', () {
      final items = _parse('Ramen 1 thousand and Shinkansen 18 thousand');
      expect(items.length, 2);
      expect(items[0]['amount'], 1000);
      expect(items[1]['amount'], 18000);
    });

    test('head-counts are still ignored', () {
      expect(_amount('Dinner 4800 split 4 ways'), 4800);
      expect(_amount('Dinner 3 thousand for 4 people'), 3000);
    });
  });

  group('LocalExpenseParser members', () {
    test('Alex, Maya and Liam: every mentioned member is extracted', () {
      expect(
        _split('Dinner 4800 split with Alex, Maya and Liam'),
        containsAll(['Alex', 'Maya', 'Liam']),
      );
    });

    test('ampersand lists', () {
      expect(
        _split('Taxi 1200 for Alex & Maya'),
        containsAll(['Alex', 'Maya']),
      );
      expect(
        _split('Taxi 1200 for Alex & Maya').length,
        greaterThanOrEqualTo(2),
      );
    });

    test('Oxford comma and "and me"', () {
      final s = _split('Tickets 18200 for Alex, Maya, Liam, and me');
      expect(s, unorderedEquals(['You', 'Alex', 'Maya', 'Liam']));
    });

    test('everyone / all / the whole group', () {
      for (final phrase in [
        'Dinner 4800 split with everyone',
        'Dinner 4800 for all',
        'Dinner 4800 split with all',
        'Dinner 4800 for the whole group',
        'Dinner 4800 all of us',
      ]) {
        expect(_split(phrase), unorderedEquals(_members), reason: phrase);
      }
    });

    test('multi-member lists with spoken multipliers in the same sentence', () {
      final s = _split('Hotel 2.5 thousand split with Maya, Liam and Alex');
      expect(s, containsAll(['Maya', 'Liam', 'Alex']));
    });

    test('names across two expenses stay with their own expense', () {
      final items = _parse(
        'Ramen 1 thousand for Alex and Maya, and taxi 2 thousand for Liam',
      );
      expect(items.length, 2);
      expect(
        List<String>.from(items[0]['splitWith'] as List),
        containsAll(['Alex', 'Maya']),
      );
      expect(items[0]['splitWith'], isNot(contains('Liam')));
      expect(items[1]['splitWith'], contains('Liam'));
    });

    test('solo still means just the payer', () {
      expect(
        _split('Matcha latte 650 just for Maya').length,
        greaterThanOrEqualTo(1),
      );
      expect(_split('Coffee 400 just me'), ['You']);
    });
  });

  group('Prompt rules', () {
    test(
      'the AI prompt documents multipliers, typos and multi-member lists',
      () {
        final prompt = ExpensePromptBuilder.buildPrompt(
          userInput: 'Dinner 1 thousan split with Alex and Maya',
        );
        expect(prompt, contains('hundred'));
        expect(prompt, contains('thousand'));
        expect(prompt, contains('thousan'));
        expect(prompt, contains('million'));
        expect(prompt.toLowerCase(), contains('every'));
        expect(prompt, contains('2.5k'));
      },
    );

    test('the user input inside the prompt is normalized to digits', () {
      final prompt = ExpensePromptBuilder.buildPrompt(
        userInput: 'Dinner 1 thousan yen',
      );
      expect(prompt, contains('Dinner 1000 yen'));
    });
  });
}
