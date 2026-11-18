// ignore_for_file: constant_identifier_names

import 'package:flutter/material.dart';

import '../utils/travel_gazetteer.dart';

/// The 12 official travel expense categories with Material icons and
/// distinct pastel palettes (100% English).
enum ExpenseCategory {
  MEAL,
  SNACK_CAFE,
  TRANSPORT,
  ATTRACTION,
  LODGING,
  SOUVENIR,
  APPAREL,
  MEDICAL,
  CONNECTIVITY,
  INSURANCE,
  SERVICE,
  MISC;

  /// English readable display label
  String get englishLabel {
    switch (this) {
      case ExpenseCategory.MEAL:
        return 'Meals';
      case ExpenseCategory.SNACK_CAFE:
        return 'Snacks & Cafe';
      case ExpenseCategory.TRANSPORT:
        return 'Transport';
      case ExpenseCategory.ATTRACTION:
        return 'Attractions';
      case ExpenseCategory.LODGING:
        return 'Lodging';
      case ExpenseCategory.SOUVENIR:
        return 'Souvenirs';
      case ExpenseCategory.APPAREL:
        return 'Apparel';
      case ExpenseCategory.MEDICAL:
        return 'Medical & Emergencies';
      case ExpenseCategory.CONNECTIVITY:
        return 'Connectivity';
      case ExpenseCategory.INSURANCE:
        return 'Travel Insurance';
      case ExpenseCategory.SERVICE:
        return 'Services';
      case ExpenseCategory.MISC:
        return 'Miscellaneous';
    }
  }

  /// Primary display name (100% English)
  String get displayName => englishLabel;

  /// Corresponding Material Icon
  IconData get icon {
    switch (this) {
      case ExpenseCategory.MEAL:
        return Icons.restaurant_rounded;
      case ExpenseCategory.SNACK_CAFE:
        return Icons.local_cafe_rounded;
      case ExpenseCategory.TRANSPORT:
        return Icons.directions_subway_rounded;
      case ExpenseCategory.ATTRACTION:
        return Icons.attractions_rounded;
      case ExpenseCategory.LODGING:
        return Icons.hotel_rounded;
      case ExpenseCategory.SOUVENIR:
        return Icons.card_giftcard_rounded;
      case ExpenseCategory.APPAREL:
        return Icons.checkroom_rounded;
      case ExpenseCategory.MEDICAL:
        return Icons.medical_services_rounded;
      case ExpenseCategory.CONNECTIVITY:
        return Icons.wifi_rounded;
      case ExpenseCategory.INSURANCE:
        return Icons.shield_rounded;
      case ExpenseCategory.SERVICE:
        return Icons.room_service_rounded;
      case ExpenseCategory.MISC:
        return Icons.category_rounded;
    }
  }

  /// Distinct pastel background color
  Color get pastelColor {
    switch (this) {
      case ExpenseCategory.MEAL:
        return const Color(0xFFFFAB91); // Pastel Coral
      case ExpenseCategory.SNACK_CAFE:
        return const Color(0xFFFFCC80); // Pastel Peach/Amber
      case ExpenseCategory.TRANSPORT:
        return const Color(0xFF90CAF9); // Pastel Blue
      case ExpenseCategory.ATTRACTION:
        return const Color(0xFFCE93D8); // Pastel Purple
      case ExpenseCategory.LODGING:
        return const Color(0xFF9FA8DA); // Pastel Indigo
      case ExpenseCategory.SOUVENIR:
        return const Color(0xFFF48FB1); // Pastel Pink
      case ExpenseCategory.APPAREL:
        return const Color(0xFF80CBC4); // Pastel Mint/Teal
      case ExpenseCategory.MEDICAL:
        return const Color(0xFFEF9A9A); // Pastel Soft Red
      case ExpenseCategory.CONNECTIVITY:
        return const Color(0xFFA5D6A7); // Pastel Light Green
      case ExpenseCategory.INSURANCE:
        return const Color(0xFFB0BEC5); // Pastel Blue Grey
      case ExpenseCategory.SERVICE:
        return const Color(0xFFFFF59D); // Pastel Soft Yellow
      case ExpenseCategory.MISC:
        return const Color(0xFFCFD8DC); // Pastel Warm Grey
    }
  }

  /// Darker accent color suitable for text and icons on the pastel background
  Color get accentColor {
    switch (this) {
      case ExpenseCategory.MEAL:
        return const Color(0xFFD84315);
      case ExpenseCategory.SNACK_CAFE:
        return const Color(0xFFE65100);
      case ExpenseCategory.TRANSPORT:
        return const Color(0xFF1565C0);
      case ExpenseCategory.ATTRACTION:
        return const Color(0xFF6A1B9A);
      case ExpenseCategory.LODGING:
        return const Color(0xFF283593);
      case ExpenseCategory.SOUVENIR:
        return const Color(0xFFAD1457);
      case ExpenseCategory.APPAREL:
        return const Color(0xFF00695C);
      case ExpenseCategory.MEDICAL:
        return const Color(0xFFC62828);
      case ExpenseCategory.CONNECTIVITY:
        return const Color(0xFF2E7D32);
      case ExpenseCategory.INSURANCE:
        return const Color(0xFF37474F);
      case ExpenseCategory.SERVICE:
        return const Color(0xFFF57F17);
      case ExpenseCategory.MISC:
        return const Color(0xFF455A64);
    }
  }

  /// Ordered keyword table: the first category with a matching keyword wins,
  /// so specific phrases (e.g. "museum ticket") precede generic ones ("ticket").
  static const List<MapEntry<ExpenseCategory, List<String>>> _keywords = [
    MapEntry(ExpenseCategory.INSURANCE, ['INSURANCE']),
    MapEntry(ExpenseCategory.CONNECTIVITY, [
      'ESIM',
      'SIM_CARD',
      'SIM',
      'WIFI',
      'WI_FI',
      'DATA_PLAN',
      'ROAMING',
    ]),
    MapEntry(ExpenseCategory.MEDICAL, [
      'MEDICINE',
      'MEDICAL',
      'PHARMACY',
      'CLINIC',
      'DOCTOR',
      'HOSPITAL',
      'PILLS',
      'BANDAGE',
      'BAND_AID',
    ]),
    MapEntry(ExpenseCategory.LODGING, [
      'HOTEL',
      'LODGING',
      'AIRBNB',
      'HOSTEL',
      'RYOKAN',
      'RESORT',
      'ACCOMMODATION',
      'CHECK_IN',
      'NIGHTS',
    ]),
    MapEntry(ExpenseCategory.ATTRACTION, [
      'MUSEUM',
      'TEMPLE',
      'SHRINE',
      'ATTRACTION',
      'OBSERVATION',
      'SKY',
      'TOUR',
      'THEME_PARK',
      'AQUARIUM',
      'ZOO',
      'ADMISSION',
      'ENTRY',
      'TEAMLAB',
      'CASTLE',
      'GALLERY',
      'PARK_PASS',
      'UNIVERSAL',
    ]),
    MapEntry(ExpenseCategory.TRANSPORT, [
      'SHINKANSEN',
      'TRAIN',
      'METRO',
      'SUBWAY',
      'FLIGHT',
      'TAXI',
      'UBER',
      'BUS',
      'FERRY',
      'SUICA',
      'PASMO',
      'TRANSPORT',
      'TRAM',
      'RAIL',
      'CAB',
      'TICKET',
      'FARE',
      'GRAB',
      'RENTAL_CAR',
      'PARKING',
      'TOLL',
    ]),
    MapEntry(ExpenseCategory.SNACK_CAFE, [
      'CAFE',
      'COFFEE',
      'LATTE',
      'MATCHA',
      'TEA',
      'SNACK',
      'BAKERY',
      'PASTRY',
      'DESSERT',
      'ICE_CREAM',
      'GACHAPON',
      'CONVENIENCE',
      'VENDING',
      'BUBBLE',
      'CAKE',
      'CROISSANT',
      'STARBUCKS',
      'TAKOYAKI',
      'WATER',
      'DRINK',
      'BEER',
      'WINE',
      'SAKE',
      'JUICE',
      'SODA',
      'COLA',
      'SMOOTHIE',
    ]),
    MapEntry(ExpenseCategory.MEAL, [
      'RAMEN',
      'MEAL',
      'LUNCH',
      'DINNER',
      'BREAKFAST',
      'FOOD',
      'SUSHI',
      'RESTAURANT',
      'BUFFET',
      'BBQ',
      'IZAKAYA',
      'NOODLE',
      'CURRY',
      'STEAK',
      'PIZZA',
      'BRUNCH',
      'BISTRO',
      'EATERY',
      'TEMPURA',
      'UDON',
      'GYOZA',
      'DUMPLING',
      'TONKATSU',
      'YAKITORI',
      'YAKINIKU',
      'OKONOMIYAKI',
      'BURGER',
      'DONBURI',
      'BENTO',
      'SASHIMI',
      'SOBA',
      'TACO',
      'SANDWICH',
    ]),
    MapEntry(ExpenseCategory.SOUVENIR, [
      'SOUVENIR',
      'GIFT',
      'OMIYAGE',
      'TOKYO_BANANA',
      'KEYCHAIN',
      'POSTCARD',
      'HANDICRAFT',
    ]),
    MapEntry(ExpenseCategory.APPAREL, [
      'JACKET',
      'SHIRT',
      'T_SHIRT',
      'APPAREL',
      'CLOTHES',
      'SUNGLASSES',
      'PONCHO',
      'SHOES',
      'HAT',
      'COAT',
      'UNIQLO',
    ]),
    MapEntry(ExpenseCategory.SERVICE, [
      'LAUNDRY',
      'LOCKER',
      'TIP',
      'LUGGAGE',
      'TAKKYUBIN',
      'SERVICE',
      'MASSAGE',
      'SPA',
    ]),
  ];

  /// Parses string representations (case-insensitive, handles aliases and
  /// free-form English descriptions such as "shinkansen tickets").
  static ExpenseCategory fromString(String? value) {
    if (value == null) return ExpenseCategory.MISC;
    final normalized = value.trim().toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9]+'),
      '_',
    );
    for (final cat in ExpenseCategory.values) {
      if (cat.name == normalized) return cat;
    }

    // Famous venues, transit cards and chains ("Disneyland", "Teamlab",
    // "Suica") with the venue-vs-item rule ("Disneyland headband" = Souvenirs).
    final known = TravelGazetteer.classify(value);
    if (known != null) return known;

    // Whole-word matching (with optional plural) avoids false positives such as
    // "TEA" inside "STEAK" or "TIP" inside "MULTIPLE".
    for (final entry in _keywords) {
      for (final keyword in entry.value) {
        if (RegExp('(^|_)$keyword(S|ES)?(_|\$)').hasMatch(normalized)) {
          return entry.key;
        }
      }
    }

    return ExpenseCategory.MISC;
  }
}
