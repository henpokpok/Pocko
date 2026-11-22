import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/core/enums/expense_category.dart';
import 'package:travmate/core/utils/travel_gazetteer.dart';
import 'package:travmate/services/hybrid_ai/expense_normalizer.dart';
import 'package:travmate/services/hybrid_ai/expense_prompt_builder.dart';
import 'package:travmate/services/hybrid_ai/hybrid_ai_service.dart';
import 'package:travmate/services/hybrid_ai/local_expense_parser.dart';

const _members = ['You', 'Alex', 'Maya', 'Liam'];

String _category(String sentence) =>
    LocalExpenseParser.parseExpenses(
          sentence,
          tripCurrency: 'JPY',
          memberNames: _members,
          defaultPayer: 'You',
        ).single['category']
        as String;

void main() {
  group('Venues and landmarks are Attractions, never MISC', () {
    test('theme parks, immersive art and parks', () {
      for (final s in [
        'Disneyland 9400 yen',
        'DisneySea 9400 yen',
        'Universal Studio 8600 yen',
        'Universal Studios Japan 8600 yen',
        'USJ 8600 yen',
        'Teamlab 3800 yen',
        'teamLab Planets 3800 yen',
        'Cosmo Land 1200 yen',
        'Cosmoworld 1200 yen',
        'Lego land 6500 yen',
        'Legoland 6500 yen',
        'Lotte World 5000 yen',
        'Everland 5000 yen',
      ]) {
        expect(_category(s), 'ATTRACTION', reason: s);
        expect(ExpenseCategory.fromString(s), ExpenseCategory.ATTRACTION);
      }
    });

    test('museums, centres and observation decks', () {
      for (final s in [
        'Tokyo National Museum 1000 yen',
        'National Art Center 2000 yen',
        'National Center 1500 yen',
        'Science Center 800 yen',
        'Mori Art Museum 2000 yen',
        'Shibuya Sky 2200 yen',
        'Skytree 2100 yen',
        'Aquarium 2400 yen',
        'Zoo 600 yen',
        'Meiji Shrine 0 yen',
        'Imperial Palace tour 1000 yen',
        'Ueno Park boat 700 yen',
      ]) {
        expect(_category(s), 'ATTRACTION', reason: s);
      }
    });

    test('proper nouns with -land / -world / Studio suffix cues', () {
      expect(
        ExpenseCategory.fromString('Fantasyland 3000'),
        ExpenseCategory.ATTRACTION,
      );
      expect(
        ExpenseCategory.fromString('Mystery Studios 2000'),
        ExpenseCategory.ATTRACTION,
      );
      expect(
        ExpenseCategory.fromString('Funworld 1500'),
        ExpenseCategory.ATTRACTION,
      );
    });

    test('countries and plain words ending in -land are not venues', () {
      expect(TravelGazetteer.classify('Thailand trip'), isNull);
      expect(TravelGazetteer.classify('Iceland tour'), isNull);
      expect(
        ExpenseCategory.fromString('Parking 500'),
        ExpenseCategory.TRANSPORT,
      );
      expect(TravelGazetteer.classify('Car park 500'), isNull);
    });
  });

  group('Context override: the item beats the venue', () {
    test('merchandise is Shopping (Souvenirs)', () {
      expect(_category('Disneyland souvenir headband 2200 yen'), 'SOUVENIR');
      expect(_category('Disneyland headband 2200 yen'), 'SOUVENIR');
      expect(_category('Museum gift shop 1800 yen'), 'SOUVENIR');
      expect(_category('Teamlab keychain 800 yen'), 'SOUVENIR');
    });

    test('food and drink inside a venue is Meals', () {
      expect(_category('Universal Studio churros 700 yen'), 'MEAL');
      expect(_category('Universal popcorn 600 yen'), 'MEAL');
      expect(_category('Disneyland turkey leg 900 yen'), 'MEAL');
      expect(_category('Legoland lunch 1500 yen'), 'MEAL');
    });

    test('apparel, lodging and transport at a venue follow the item', () {
      expect(_category('Disneyland t-shirt 3000 yen'), 'APPAREL');
      expect(_category('Disneyland hotel 30000 yen'), 'LODGING');
      expect(_category('Universal shuttle bus 500 yen'), 'TRANSPORT');
    });

    test('a bare venue ticket stays an Attraction', () {
      expect(_category('Disneyland ticket 9400 yen'), 'ATTRACTION');
      expect(_category('Teamlab ticket 3800 yen'), 'ATTRACTION');
    });
  });

  group('Brands', () {
    test('transport', () {
      for (final s in [
        'Suica top up',
        'Pasmo',
        'ICOCA 2000',
        'T-money 5000',
        'Octopus card 150',
        'EZ-Link 10',
        'Narita Express 3000',
        'JR pass',
        'Grab 800',
        'Uber 1500',
        'MRT 2',
        'BTS 40',
      ]) {
        expect(
          ExpenseCategory.fromString(s),
          ExpenseCategory.TRANSPORT,
          reason: s,
        );
      }
    });

    test('food beats a transit brand ("Grab a coffee")', () {
      expect(
        ExpenseCategory.fromString('Grab coffee 500'),
        ExpenseCategory.SNACK_CAFE,
      );
      expect(
        ExpenseCategory.fromString('Shinkansen bento 1200'),
        ExpenseCategory.MEAL,
      );
    });

    test('meals and cafés', () {
      expect(ExpenseCategory.fromString('Ichiran 1200'), ExpenseCategory.MEAL);
      expect(ExpenseCategory.fromString('Sushi'), ExpenseCategory.MEAL);
      for (final s in [
        'Starbucks',
        '7-Eleven',
        'Lawson snacks',
        'FamilyMart drinks',
      ]) {
        expect(
          ExpenseCategory.fromString(s),
          ExpenseCategory.SNACK_CAFE,
          reason: s,
        );
      }
    });

    test('shopping, apparel and lodging', () {
      for (final s in [
        'Don Quijote 3000',
        'Donki',
        'Olive Young',
        'Uniqlo',
        'Pop Mart',
        'Daiso',
        'Duty Free',
      ]) {
        final c = ExpenseCategory.fromString(s);
        expect(
          c == ExpenseCategory.SOUVENIR || c == ExpenseCategory.APPAREL,
          isTrue,
          reason: '$s -> $c',
        );
      }
      expect(ExpenseCategory.fromString('Uniqlo'), ExpenseCategory.APPAREL);
      for (final s in [
        'APA Hotel',
        'Toyoko Inn',
        'Airbnb',
        'Agoda',
        'Booking.com',
        'Hostel',
        'Ryokan',
      ]) {
        expect(
          ExpenseCategory.fromString(s),
          ExpenseCategory.LODGING,
          reason: s,
        );
      }
    });
  });

  group('Manual auto-category and post-LLM rescue', () {
    test('suggestCategory never answers MISC for a known venue', () async {
      final service = HybridAiService(
        isMockEnabled: true,
        simulateLatency: false,
      );
      for (final s in [
        'Disneyland',
        'Universal Studio',
        'Teamlab',
        'Cosmo Land',
        'Lego land',
        'Museum',
        'National Center',
      ]) {
        expect(
          await service.suggestCategory(s),
          ExpenseCategory.ATTRACTION,
          reason: s,
        );
      }
      expect(
        await service.suggestCategory('Disneyland headband'),
        ExpenseCategory.SOUVENIR,
      );
      expect(await service.suggestCategory('Qwertyuiop'), ExpenseCategory.MISC);
    });

    test('a MISC answer from an on-device model is rescued', () {
      for (final sentence in [
        'Disneyland 9400 yen',
        'Universal Studio 8600 yen',
        'Teamlab 3800 yen',
        'Cosmo Land 1200 yen',
        'Lego land 6500 yen',
        'Tokyo National Museum 1000 yen',
        'National Art Center 2000 yen',
      ]) {
        final r = ExpenseNormalizer.normalize(
          [
            {
              'title': sentence.split(' ').first,
              'unitAmount': 1000,
              'category': 'MISC',
              'splitWith': <String>[],
            },
          ],
          userInput: sentence,
          tripCurrency: 'JPY',
          memberNames: _members,
          defaultPayer: 'You',
        ).single;
        expect(r['category'], 'ATTRACTION', reason: sentence);
      }
    });

    test('only MISC is ever overridden', () {
      final r = ExpenseNormalizer.normalize(
        [
          {
            'title': 'Disneyland',
            'unitAmount': 9400,
            'category': 'TRANSPORT',
            'splitWith': <String>[],
          },
        ],
        userInput: 'Disneyland 9400 yen',
        tripCurrency: 'JPY',
        memberNames: _members,
        defaultPayer: 'You',
      ).single;
      expect(r['category'], 'TRANSPORT');
    });

    test('merchandise at a venue is rescued as Souvenirs / Meals', () {
      Map<String, dynamic> fix(String s) => ExpenseNormalizer.normalize(
        [
          {
            'title': s.split(' 2').first,
            'unitAmount': 2200,
            'category': 'MISC',
            'splitWith': <String>[],
          },
        ],
        userInput: s,
        tripCurrency: 'JPY',
        memberNames: _members,
        defaultPayer: 'You',
      ).single;
      expect(
        fix('Disneyland souvenir headband 2200 yen')['category'],
        'SOUVENIR',
      );
      expect(fix('Universal Studio churros 700 yen')['category'], 'MEAL');
    });
  });

  group('Prompt carries the semantic anchors', () {
    test('anchors, suffix cues and the venue-vs-item rule', () {
      final p = ExpensePromptBuilder.buildPrompt(
        userInput: 'x 1',
      );
      for (final needle in [
        'Disneyland',
        'DisneySea',
        'Universal Studios',
        'USJ',
        'Legoland',
        'Cosmo Land',
        'Lotte World',
        'Everland',
        'teamLab',
        'National Center',
        'Art Center',
        'Science Center',
        'Shibuya Sky',
        'Skytree',
        '-land',
        '-world',
        'Studio(s)',
        'Observatory',
        'Suica',
        'Pasmo',
        'ICOCA',
        'T-money',
        'Octopus',
        'EZ-Link',
        'Shinkansen',
        'Narita Express',
        'MRT',
        'BTS',
        'Uber',
        'Grab',
        'Ichiran',
        'Starbucks',
        '7-Eleven',
        'Lawson',
        'FamilyMart',
        'Don Quijote',
        'Olive Young',
        'Uniqlo',
        'Pop Mart',
        'Daiso',
        'Duty Free',
        'APA',
        'Toyoko Inn',
        'Airbnb',
        'Agoda',
        'Booking.com',
        'ryokan',
        'never MISC',
        'Venue rule',
        'Disneyland headband',
        'Universal popcorn',
        'Museum gift shop',
      ]) {
        expect(p, contains(needle), reason: needle);
      }
    });

    test('the Manual Expense category prompt shares the anchors', () {
      final p = ExpensePromptBuilder.buildCategoryPrompt('Disneyland');
      expect(p, contains('Venue rule'));
      expect(p, contains('Cosmo Land'));
      expect(p, contains('{"category"'));
    });
  });
}
