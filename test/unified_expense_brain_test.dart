import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/core/enums/expense_category.dart';
import 'package:travmate/services/hybrid_ai/local_expense_parser.dart';

const _members = ['You', 'Alex', 'Maya', 'Liam'];

Map<String, dynamic> _one(String s) => LocalExpenseParser.parseExpenses(
  s,
  tripCurrency: 'JPY',
  memberNames: _members,
  defaultPayer: 'You',
).first;

void main() {
  group('Spec examples not covered elsewhere', () {
    test('venue + food / merch / admission', () {
      expect(_one('Disneyland popcorn 500 yen')['category'], 'MEAL');
      expect(_one('Museum gift shop 1500 yen')['category'], 'SOUVENIR');
      expect(_one('National Center 1500 yen')['category'], 'ATTRACTION');
      expect(_one('Cosmo Land 1200 yen')['category'], 'ATTRACTION');
    });

    test('landmarks, lodging and shopping brands', () {
      for (final s in [
        'Tokyo Tower 1200 yen',
        'Palace 800 yen',
        'Temple 300 yen',
        'Gallery 900 yen',
        'Observatory 1000 yen',
        'Science Center 700 yen',
      ]) {
        expect(_one(s)['category'], 'ATTRACTION', reason: s);
      }
      expect(_one('Hostel 4000 yen')['category'], 'LODGING');
      expect(_one('Duty Free 5000 yen')['category'], 'SOUVENIR');
      expect(_one('GU 2000 yen')['category'], 'APPAREL');
      expect(_one('Uniqlo 2000 yen')['category'], 'APPAREL');
      expect(ExpenseCategory.fromString('Pop Mart'), ExpenseCategory.SOUVENIR);
    });

    test('typo\'d and spoken multipliers', () {
      expect(_one('Lunch 1 thousan yen')['amount'], 1000.0);
      expect(_one('Lunch five hundred yen')['amount'], 500.0);
      expect(_one('Villa 1 million yen')['amount'], 1000000.0);
    });

    test('a member name is never the item title', () {
      expect(_one('Liam 800 yen')['title'], isNot('Liam'));
      expect(_one('Maya paid 6k yen for taxi')['title'], 'Taxi');
      for (final m in _members) {
        expect(
          (_one('Ramen with $m 500 yen')['title'] as String).toLowerCase(),
          isNot(m.toLowerCase()),
        );
      }
    });

    test('"for Maya" stays Maya-only, "with Maya" includes the payer', () {
      expect(_one('Bought water for Maya 200 yen')['splitWith'], ['Maya']);
      expect(_one('Water with Maya 200 yen')['splitWith'], ['You', 'Maya']);
      final item = _one('Eat ramen with Maya and Liam 500 yen each');
      expect(item['splitWith'], ['You', 'Maya', 'Liam']);
      expect(item['amount'], 1500.0);
      expect(item['category'], 'MEAL');
    });
  });
}
