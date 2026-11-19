/// A destination offered by the first-trip setup. Picking one pairs the trip
/// currency automatically.
class TripDestination {
  final String name;
  final String currency;

  /// Country flag emoji shown in the picker.
  final String flag;
  const TripDestination(this.name, this.currency, this.flag);

  static const List<TripDestination> all = [
    TripDestination('Japan', 'JPY', '🇯🇵'),
    TripDestination('South Korea', 'KRW', '🇰🇷'),
    TripDestination('Thailand', 'THB', '🇹🇭'),
    TripDestination('United States', 'USD', '🇺🇸'),
    TripDestination('United Kingdom', 'GBP', '🇬🇧'),
    TripDestination('Europe', 'EUR', '🇪🇺'),
    TripDestination('Singapore', 'SGD', '🇸🇬'),
    TripDestination('Taiwan', 'TWD', '🇹🇼'),
    TripDestination('Vietnam', 'VND', '🇻🇳'),
    TripDestination('Australia', 'AUD', '🇦🇺'),
    TripDestination('Switzerland', 'CHF', '🇨🇭'),
    TripDestination('Hong Kong', 'HKD', '🇭🇰'),
    TripDestination('China', 'CNY', '🇨🇳'),
    TripDestination('Canada', 'CAD', '🇨🇦'),
  ];

  static TripDestination byName(String name) =>
      all.firstWhere((d) => d.name == name, orElse: () => all.first);

  /// `🇯🇵 Japan` (the picker's trigger).
  String get flagAndName => '$flag $name';

  /// `Japan (¥ JPY)` / `Switzerland (CHF)`: the dropdown row text. The row shows
  /// the flag once, in its own circle, so the label must not repeat it.
  String rowLabel(String symbol) {
    final s = symbol.trim();
    return s == currency ? '$name ($currency)' : '$name ($s $currency)';
  }

  /// `🇯🇵 Japan (¥ JPY)`, or `🇨🇭 Switzerland (CHF)` when the symbol is the code.
  String pickerLabel(String symbol) {
    final s = symbol.trim();
    return s == currency
        ? '$flag $name ($currency)'
        : '$flag $name ($s $currency)';
  }
}

/// What the setup card hands back when the user taps **Start Trip**.
class TripSetupData {
  final String name;
  final TripDestination destination;
  final String tripCurrency;
  final String homeCurrency;
  final List<String> friends;

  const TripSetupData({
    required this.name,
    required this.destination,
    required this.tripCurrency,
    required this.homeCurrency,
    required this.friends,
  });
}
