import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_helper.dart';
import '../settlement/pair_breakdown.dart';
import '../trip/trip_state.dart';

/// Itemized explanation of what two travelers owe each other: every expense
/// one paid for the other's share, plus recorded payments, down to the
/// per-item split amount.
class PairBreakdownView extends StatelessWidget {
  final TripState tripState;
  final PairBreakdown breakdown;
  final Widget? trailing;

  const PairBreakdownView({
    super.key,
    required this.tripState,
    required this.breakdown,
    this.trailing,
  });

  String _fmt(double v) =>
      CurrencyHelper.formatAmount(v.abs(), tripState.trip.baseCurrency);

  @override
  Widget build(BuildContext context) {
    final a = tripState.nameOf(breakdown.aId);
    final b = tripState.nameOf(breakdown.bId);
    final net = breakdown.net;
    final String headline;
    final Color headlineColor;
    if (net < -0.5) {
      headline = '$a owe${a == 'You' ? '' : 's'} $b ${_fmt(net)}';
      headlineColor = AppTheme.coralOwesText;
    } else if (net > 0.5) {
      headline = '$b owe${b == 'You' ? '' : 's'} $a ${_fmt(net)}';
      headlineColor = AppTheme.primaryEmeraldDark;
    } else {
      headline = '$a and $b are square';
      headlineColor = AppTheme.textSlate;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          headline,
          key: const ValueKey('breakdown_headline'),
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: headlineColor,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _SummaryChip(
                label: '$a paid for $b',
                value: _fmt(breakdown.bOwesA),
                color: AppTheme.primaryEmeraldDark,
                bg: AppTheme.primaryEmeraldSubtle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SummaryChip(
                label: '$b paid for $a',
                value: _fmt(breakdown.aOwesB),
                color: AppTheme.coralOwesText,
                bg: AppTheme.coralOwesBg,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (breakdown.lines.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No shared expenses between $a and $b yet.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                color: AppTheme.textSlate,
              ),
            ),
          )
        else
          for (final line in breakdown.lines) _line(line, a, b),
        if (breakdown.paymentsNet.abs() > 0.5) ...[
          const SizedBox(height: 4),
          Text(
            'Includes payments already recorded as settled.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: AppTheme.textMuted,
            ),
          ),
        ],
        const Divider(height: 22),
        Row(
          children: [
            Expanded(
              child: Text(
                'Net after ${breakdown.expenseCount} item${breakdown.expenseCount == 1 ? '' : 's'}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSlate,
                ),
              ),
            ),
            Text(
              CurrencyHelper.formatAmount(
                net,
                tripState.trip.baseCurrency,
                showSign: true,
              ),
              style: AppTheme.tabularNumberStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: headlineColor,
              ),
            ),
          ],
        ),
        if (trailing != null) ...[const SizedBox(height: 12), trailing!],
      ],
    );
  }

  Widget _line(BreakdownLine line, String a, String b) {
    final e = line.expense;
    final aShares = line.amount < 0; // a owes b for this item
    final payer = aShares ? b : a;
    final sharer = aShares ? a : b;
    final sharerLabel = sharer == 'You' ? 'your share' : '$sharer’s share';
    final color = line.amount < 0
        ? AppTheme.coralOwesText
        : AppTheme.primaryEmeraldDark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color:
                  e?.category.pastelColor.withValues(alpha: 0.6) ??
                  const Color(0xFFE2E8F0),
              shape: BoxShape.circle,
            ),
            child: Icon(
              e?.category.icon ?? Icons.check_circle_rounded,
              size: 17,
              color: e?.category.accentColor ?? AppTheme.textSlate,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${line.title} • ${DateFormat('MMM d').format(line.when)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                ),
                Text(
                  line.isPayment
                      ? (aShares ? '$b paid $a back' : '$a paid $b back')
                      : '$payer paid ${_fmt(line.total)} • $sharerLabel',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.tabularNumberStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            CurrencyHelper.formatAmount(
              line.amount,
              tripState.trip.baseCurrency,
              showSign: true,
            ),
            style: AppTheme.tabularNumberStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final Color bg;

  const _SummaryChip({
    required this.label,
    required this.value,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            value,
            style: AppTheme.tabularNumberStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
