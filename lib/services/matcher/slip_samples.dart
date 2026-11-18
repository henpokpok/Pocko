import 'package:flutter/material.dart';

/// A curated slip that judges and testers can run without a camera.
class SlipSample {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final String rawText;

  /// What the sample is designed to demonstrate.
  final bool demonstratesCloudFallback;

  const SlipSample({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.rawText,
    this.demonstratesCloudFallback = false,
  });
}

class SlipSamples {
  SlipSamples._();

  static const List<SlipSample> all = [
    SlipSample(
      id: 'sample_chase_teamlab',
      title: 'Card alert • TeamLab',
      subtitle: '🟢 Local AI masks the card number, then matches your TeamLab tickets',
      icon: Icons.credit_card_rounded,
      rawText: '''Chase • Card transaction alert
Merchant: TEAMLAB BORDERLESS TOKYO
Amount: JPY 15,400
Card: 4929 1823 7701 5521
Cardholder: Alex Morgan
Time: 11:42
Contact: alex.morgan@example.com''',
    ),
    SlipSample(
      id: 'sample_wise_vending',
      title: 'Bank notice • Unknown shop',
      subtitle: '🟢 Local AI • no confident match, so Pocko asks you to verify',
      icon: Icons.account_balance_rounded,
      rawText: '''Wise • Card payment
Merchant: SEVEN-ELEVEN SHINJUKU
Amount: JPY 1,240
Card: 5412 7512 3456 2087
Account holder: Maya Tanaka
Time: 20:15''',
    ),
    SlipSample(
      id: 'sample_paris_bistro',
      title: 'Paris bistro receipt (EUR)',
      subtitle:
          '☁️ Itemized foreign receipt → cloud fallback, PII already masked',
      icon: Icons.receipt_long_rounded,
      demonstratesCloudFallback: true,
      rawText: '''Bistro Montmartre - Paris
Table 7   Server 3
Croque monsieur        18,50
Onion soup             12,00
Sparkling water 2x      9,00
Tarte tatin            11,50
Espresso 3x            10,50
Subtotal               61,50
VAT 10%                 6,15
TOTAL EUR              67,65
Card: 5100 2200 3300 4455
Time: 13:05''',
    ),
    SlipSample(
      id: 'sample_seoul_market',
      title: 'Seoul night-market (KRW)',
      subtitle:
          '☁️ Faded paper slip with 4 street-food lines → cloud itemizing',
      icon: Icons.local_dining_rounded,
      demonstratesCloudFallback: true,
      rawText: '''Gwangjang Night Market - Seoul
Tteokbokki             6,000
Mung bean pancake      9,000
Kimbap rolls           8,000
Sikhye drink           3,000
TOTAL KRW             26,000
Cash receipt  Time: 19:30''',
    ),
  ];
}
