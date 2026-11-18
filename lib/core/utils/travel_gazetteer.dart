import '../enums/expense_category.dart';

/// A lightweight travel proper-noun gazetteer: famous venues, transit cards,
/// food and retail chains and lodging brands, plus suffix cues such as
/// `-land`, `-world`, `Studio(s)`, `Museum` or `National Center`.
///
/// It powers three things:
/// * the offline classifier ([ExpenseCategory.fromString]);
/// * the 2.5 s Manual Expense auto-category and its keyword fallback;
/// * a *rescue* for real on-device models: when Gemini Nano / Apple
///   Foundation Models answer `MISC` for a known venue or brand, the answer is
///   corrected here (never the other way round).
///
/// **Context rule (venue vs. what you bought there).** A bare venue or ticket
/// (`Disneyland 9400`, `Teamlab ticket`) is an Attraction. With a merchandise
/// or food noun the item wins: `Disneyland headband` is Souvenirs,
/// `Universal popcorn` is Meals, `Museum gift shop` is Souvenirs.
class TravelGazetteer {
  TravelGazetteer._();

  /// The category for [text], or `null` when nothing in it is a known travel
  /// venue / brand (callers then fall back to their own keyword table).
  static ExpenseCategory? classify(String text) {
    final t = _normalize(text);
    if (t.isEmpty) return null;

    if (_venue(t)) {
      // The thing bought wins over the venue it was bought at.
      if (_has(t, _apparelNouns)) return ExpenseCategory.APPAREL;
      if (_has(t, _merchNouns)) return ExpenseCategory.SOUVENIR;
      if (_has(t, _lodgingNouns)) return ExpenseCategory.LODGING;
      if (_has(t, _transportNouns)) return ExpenseCategory.TRANSPORT;
      if (_has(t, _cafeNouns)) return ExpenseCategory.SNACK_CAFE;
      if (_has(t, _foodNouns)) return ExpenseCategory.MEAL;
      return ExpenseCategory.ATTRACTION;
    }

    // A transit brand is Transport unless food was bought ("Grab a coffee",
    // "Shinkansen bento"): then the food wins.
    if (_has(t, _transportBrands)) {
      if (_has(t, _cafeNouns)) return ExpenseCategory.SNACK_CAFE;
      if (_has(t, _foodNouns)) return ExpenseCategory.MEAL;
      return ExpenseCategory.TRANSPORT;
    }
    if (_has(t, _lodgingBrands)) return ExpenseCategory.LODGING;
    if (_has(t, _mealBrands)) return ExpenseCategory.MEAL;
    if (_has(t, _cafeBrands)) return ExpenseCategory.SNACK_CAFE;
    if (_has(t, _apparelBrands)) return ExpenseCategory.APPAREL;
    if (_has(t, _retailBrands)) return ExpenseCategory.SOUVENIR;
    return null;
  }

  /// Whether [text] names a known travel venue or brand at all (used to decide
  /// if a `MISC` answer from a model deserves a second look).
  static bool isKnownTravelName(String text) => classify(text) != null;

  // ---------------------------------------------------------------------------
  // Venues
  // ---------------------------------------------------------------------------

  static const List<String> _venueNames = [
    // Theme parks
    r'disney ?land', r'disney ?sea', r'disney', r'universal studios?',
    r'universal', r'usj', r'lego ?land', r'cosmo ?land', r'cosmo ?world',
    r'lotte ?world', r'ever ?land', r'sanrio puroland', r'fuji ?q',
    r'seaworld', r'sea world', r'theme park', r'amusement park',
    // Digital art & immersive
    r'team ?lab(?: planets| borderless)?', r'immersive',
    // Cultural & public institutions
    r'museum',
    r'gallery',
    r'national (?:center|centre|museum|gallery|art|theat(?:er|re))',
    r'art (?:center|centre|museum)', r'science (?:center|centre|museum)',
    r'palace', r'temple', r'shrine', r'castle', r'cathedral', r'pagoda',
    // Observatories & landmarks
    r'shibuya sky', r'sky ?tree', r'skytree', r'tokyo tower', r'tower',
    r'observatory', r'observation (?:deck|tower)', r'aquarium', r'zoo',
    r'botanical garden', r'sky deck',
  ];

  /// `-land`, `-world`, `Studio(s)`, `Park`... as a proper-noun suffix.
  static final RegExp _landSuffix = RegExp(r'(^| )[a-z]{3,}land( |$)');
  static final RegExp _worldSuffix = RegExp(r'(^| )[a-z]{3,}world( |$)');
  static const Set<String> _notLandmarks = {
    'iceland',
    'thailand',
    'finland',
    'poland',
    'ireland',
    'holland',
    'switzerland',
    'england',
    'scotland',
    'newzealand',
    'greenland',
    'island',
    'mainland',
    'homeland',
    'highland',
    'highlands',
    'lowland',
    'wasteland',
    'portland',
    'maryland',
    'queensland',
    'lapland',
    'netherland',
    'netherlands',
    'zealand',
    'swaziland',
    'cleveland',
    'auckland',
    'copland',
    'cumberland',
    'sunderland',
    'rowland',
    'leland',
    'roland',
    'worldwide',
    'underworld',
    'newworld',
  };

  static bool _venue(String t) {
    if (_has(t, _venueNames)) return true;
    for (final m in _landSuffix.allMatches(t)) {
      final w = m.group(0)!.trim();
      if (!_notLandmarks.contains(w)) return true;
    }
    for (final m in _worldSuffix.allMatches(t)) {
      final w = m.group(0)!.trim();
      if (!_notLandmarks.contains(w)) return true;
    }
    // "Park" / "Studio(s)" as a standalone proper-noun word (not a car park).
    if (RegExp(r'(^| )(studios?|observatory)( |$)').hasMatch(t)) return true;
    if (RegExp(r'(^| )park( |$)').hasMatch(t) &&
        !RegExp(r'(^| )(car|parking|valet) park( |$)').hasMatch(t) &&
        !RegExp(r'(^| )park (hotel|hyatt|inn)( |$)').hasMatch(t)) {
      return true;
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Items bought at a venue (these override the venue)
  // ---------------------------------------------------------------------------

  static const List<String> _merchNouns = [
    r'headbands?',
    r'souvenirs?',
    r'merch(?:andise)?',
    r'gift ?shop',
    r'gifts?',
    r'plush(?:ies|ie)?',
    r'toys?',
    r'key ?chains?',
    r'magnets?',
    r'posters?',
    r'postcards?',
    r'stickers?',
    r'mugs?',
    r'figures?',
    r'figurines?',
    r'omiyage',
    r'goods',
    r'charms?',
    r'ears',
    r'tote(?: bag)?',
  ];
  static const List<String> _apparelNouns = [
    r't ?shirts?',
    r'shirts?',
    r'hoodies?',
    r'jackets?',
    r'hats?',
    r'caps?',
    r'shoes',
    r'clothes',
    r'clothing',
    r'apparel',
    r'dress(?:es)?',
    r'socks',
  ];
  static const List<String> _foodNouns = [
    r'churros?',
    r'popcorn',
    r'hot ?dogs?',
    r'turkey legs?',
    r'ice ?cream',
    r'dessert',
    r'burgers?',
    r'fries',
    r'pizza',
    r'lunch',
    r'dinner',
    r'breakfast',
    r'brunch',
    r'meals?',
    r'food',
    r'ramen',
    r'sushi',
    r'noodles?',
    r'curry',
    r'bento',
    r'snacks?',
    r'drinks?',
    r'beer',
    r'juice',
    r'soda',
    r'cola',
    r'pretzels?',
    r'waffles?',
    r'crepes?',
    r'gyoza',
    r'dumplings?',
    r'skewers?',
    r'yakitori',
    r'takoyaki',
    r'sandwich(?:es)?',
    r'restaurant',
    r'buffet',
    r'set menu',
    r'cake',
    r'cookies?',
  ];
  static const List<String> _cafeNouns = [
    r'coffee',
    r'latte',
    r'tea',
    r'matcha',
    r'cafe',
    r'espresso',
    r'cappuccino',
    r'bubble tea',
    r'boba',
  ];
  static const List<String> _lodgingNouns = [
    r'hotel',
    r'hostel',
    r'inn',
    r'ryokan',
    r'resort stay',
    r'room',
    r'lodging',
    r'accommodation',
    r'airbnb',
  ];
  static const List<String> _transportNouns = [
    r'shuttle',
    r'bus',
    r'train',
    r'taxi',
    r'monorail',
    r'ferry',
    r'cab',
    r'subway',
  ];

  // ---------------------------------------------------------------------------
  // Brands
  // ---------------------------------------------------------------------------

  static const List<String> _transportBrands = [
    r'suica',
    r'pasmo',
    r'icoca',
    r'toica',
    r'manaca',
    r'pitapa',
    r't ?money',
    r'octopus(?: card)?',
    r'ez ?link',
    r'shinkansen',
    r'bullet train',
    r'jr',
    r'jr pass',
    r'narita express',
    r'n ?ex',
    r'mrt',
    r'bts',
    r'uber',
    r'grab',
    r'kakao t',
    r'haneda',
    r'airport limousine',
    r'skyliner',
    r'oyster card',
    r'metro card',
  ];
  static const List<String> _lodgingBrands = [
    r'apa(?: hotel)?',
    r'toyoko inn',
    r'airbnb',
    r'agoda',
    r'booking ?com',
    r'hostel',
    r'ryokan',
    r'hotel',
    r'super hotel',
    r'dormy inn',
    r'mercure',
    r'ibis',
  ];
  static const List<String> _mealBrands = [
    r'ichiran',
    r'ippudo',
    r'sushi',
    r'ramen',
    r'izakaya',
    r'yakiniku',
    r'mcdonald(?:s)?',
    r'kfc',
    r'burger king',
    r'gyukaku',
    r'sukiya',
    r'yoshinoya',
    r'matsuya',
    r'coco ichibanya',
  ];
  static const List<String> _cafeBrands = [
    r'starbucks',
    r'7 ?eleven',
    r'seven eleven',
    r'lawson',
    r'family ?mart',
    r'ministop',
    r'konbini',
    r'convenience store',
    r'doutor',
    r'tully',
    r'blue bottle',
    r'mister donut',
  ];
  static const List<String> _apparelBrands = [
    r'uniqlo',
    r'gu',
    r'zara',
    r'muji wear',
  ];
  static const List<String> _retailBrands = [
    r'don quijote',
    r'donki',
    r'donkihote',
    r'don ki',
    r'olive young',
    r'pop ?mart',
    r'daiso',
    r'duty ?free',
    r'tokyu hands',
    r'bic camera',
    r'yodobashi',
  ];

  // ---------------------------------------------------------------------------
  // Matching helpers
  // ---------------------------------------------------------------------------

  /// Lower-case, accents folded out, everything but letters/digits becomes a
  /// single space (so `7-Eleven` and `Booking.com` become `7 eleven`,
  /// `booking com`).
  static String _normalize(String text) =>
      text.toLowerCase().replaceAll(RegExp(r"[^a-z0-9]+"), ' ').trim();

  static final Map<List<String>, RegExp> _cache = {};

  static bool _has(String normalized, List<String> patterns) {
    final re = _cache.putIfAbsent(
      patterns,
      () => RegExp('(^| )(?:${patterns.join('|')})( |\$)'),
    );
    return re.hasMatch(normalized);
  }
}
