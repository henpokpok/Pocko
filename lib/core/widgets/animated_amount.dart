import 'package:flutter/material.dart';

import '../utils/currency_helper.dart';

/// Currency text that glides to its new value (tabular figures keep digits
/// aligned while counting). The first build shows the value immediately.
class AnimatedAmount extends StatelessWidget {
  final double value;
  final String currency;
  final TextStyle style;
  final bool showSign;
  final TextAlign? textAlign;
  final Duration duration;

  const AnimatedAmount({
    super.key,
    required this.value,
    required this.currency,
    required this.style,
    this.showSign = false,
    this.textAlign,
    this.duration = const Duration(milliseconds: 450),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(
        CurrencyHelper.formatAmount(v, currency, showSign: showSign),
        style: style,
        textAlign: textAlign,
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
      ),
    );
  }
}
