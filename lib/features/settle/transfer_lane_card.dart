import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_helper.dart';
import '../../core/widgets/tactile.dart';
import '../../models/settlement_transfer.dart';
import '../settlement/pair_breakdown.dart';
import '../trip/trip_state.dart';
import 'pair_breakdown_view.dart';

/// One directional transfer "lane": Debtor ──▶ amount ──▶ Creditor, with an
/// expandable "why this amount" itemized breakdown and a 1-tap Record Payment.
class TransferLaneCard extends StatefulWidget {
  final TripState tripState;
  final SettlementTransfer transfer;
  final VoidCallback onRecordPayment;

  const TransferLaneCard({
    super.key,
    required this.tripState,
    required this.transfer,
    required this.onRecordPayment,
  });

  @override
  State<TransferLaneCard> createState() => _TransferLaneCardState();
}

class _TransferLaneCardState extends State<TransferLaneCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.transfer;
    final state = widget.tripState;
    final from = state.nameOf(t.fromMemberId);
    final to = state.nameOf(t.toMemberId);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
      decoration: AppTheme.surfaceDecoration(radius: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Badge(
                key: ValueKey('lane_from_${t.id}'),
                name: from,
                caption: 'pays',
                bg: AppTheme.coralOwesBg,
                fg: AppTheme.coralOwesText,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    children: [
                      Container(
                        key: ValueKey('lane_amount_${t.id}'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryEmeraldSubtle,
                          borderRadius: AppTheme.pillRadius,
                          border: Border.all(
                            color: AppTheme.primaryEmerald.withValues(
                              alpha: 0.35,
                            ),
                          ),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            CurrencyHelper.formatAmount(t.amount, t.currency),
                            style: AppTheme.tabularNumberStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.primaryEmeraldDark,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      _FlowArrow(key: ValueKey('lane_arrow_${t.id}')),
                    ],
                  ),
                ),
              ),
              _Badge(
                key: ValueKey('lane_to_${t.id}'),
                name: to,
                caption: 'receives',
                bg: AppTheme.primaryEmeraldSubtle,
                fg: AppTheme.primaryEmeraldDark,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Tactile(
                  key: ValueKey('lane_expand_${t.id}'),
                  onTap: () => setState(() => _expanded = !_expanded),
                  pressedScale: 0.98,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(
                          _expanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 18,
                          color: AppTheme.textSlate,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            _expanded ? 'Hide breakdown' : 'Why this amount?',
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textSlate,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                key: ValueKey('lane_record_${t.id}'),
                onPressed: widget.onRecordPayment,
                icon: const Icon(Icons.check_rounded, size: 16),
                label: const Text('Record Payment'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  textStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: AppTheme.pillRadius,
                  ),
                ),
              ),
            ],
          ),
          if (_expanded)
            Padding(
              key: ValueKey('lane_breakdown_${t.id}'),
              padding: const EdgeInsets.only(top: 6),
              child: PairBreakdownView(
                tripState: state,
                breakdown: computePairBreakdown(
                  state,
                  t.fromMemberId,
                  t.toMemberId,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String name;
  final String caption;
  final Color bg;
  final Color fg;

  const _Badge({
    super.key,
    required this.name,
    required this.caption,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 68,
      child: Column(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: bg,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: fg,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
            ),
          ),
          Text(
            caption,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// Emerald arrow whose shaft sweeps from debtor to creditor once, as the card
/// appears (a single cheap transform animation, no blur, no endless loop).
class _FlowArrow extends StatelessWidget {
  const _FlowArrow({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 16,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: t,
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6EE7B7), AppTheme.primaryEmerald],
                      ),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              ),
            ),
            Opacity(
              opacity: t,
              child: const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: AppTheme.primaryEmerald,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
