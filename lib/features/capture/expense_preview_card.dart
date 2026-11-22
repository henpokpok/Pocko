import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_helper.dart';
import '../../models/expense_item.dart';
import '../trip/trip_state.dart';

/// Miniature live preview of how the focused expense will look in the
/// Expenses list: pastel category icon, title, who shares it, who paid and the
/// formatted amount. Updates instantly as the user edits words, category,
/// payer, currency or group members.
class ExpensePreviewCard extends StatelessWidget {
  final ExpenseItem item;
  final TripState tripState;

  /// Optional pill selectors (payer / currency) rendered on the card's footer.
  final List<Widget> actions;

  /// How the total was computed, e.g. `¥1,500 (¥500 × 3 each)`; shown as a
  /// badge when a pricing modifier (each / quantity / percent) is in play.
  final String? breakdown;

  /// `true` for a shared bill split by exact per-person amounts: shows the
  /// "Itemized split" badge.
  final bool itemized;

  const ExpensePreviewCard({
    super.key,
    required this.item,
    required this.tripState,
    this.actions = const [],
    this.breakdown,
    this.itemized = false,
  });

  /// "Everyone", or "Alex, Maya +1".
  static String sharedWith(ExpenseItem item, TripState state) {
    final all = state.trip.members.length;
    final ids = item.splitWithMemberIds;
    if (ids.length == all && all > 1) return 'Everyone ($all)';
    final names = [for (final id in ids) state.nameOf(id)];
    if (names.length <= 2) return names.join(', ');
    return '${names.take(2).join(', ')} +${names.length - 2}';
  }

  @override
  Widget build(BuildContext context) {
    final base = tripState.trip.baseCurrency;
    final count = item.splitWithMemberIds.isEmpty
        ? 1
        : item.splitWithMemberIds.length;
    final each = item.amountIn(base) / count;
    final c = item.category;

    return Container(
      key: const ValueKey('expense_preview'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                key: const ValueKey('preview_icon'),
                duration: const Duration(milliseconds: 220),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c.pastelColor.withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                ),
                child: Icon(c.icon, size: 20, color: c.accentColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title.isEmpty ? c.displayName : item.title,
                      key: const ValueKey('preview_title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${tripState.nameOf(item.payerId)} paid • ${sharedWith(item, tripState)}',
                      key: const ValueKey('preview_meta'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSlate,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyHelper.formatAmount(item.amount, item.currency),
                    key: const ValueKey('preview_amount'),
                    style: AppTheme.tabularNumberStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    // Unequal (itemized) shares have no single "each".
                    itemized
                        ? 'Custom split • $count people'
                        : '${CurrencyHelper.formatAmount(each, base)} each',
                    key: const ValueKey('preview_each'),
                    style: AppTheme.tabularNumberStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (itemized) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                key: const ValueKey('preview_itemized'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE9FE),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.receipt_long_rounded,
                      size: 14,
                      color: Color(0xFF6D28D9),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Itemized split',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF6D28D9),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (breakdown != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                key: const ValueKey('preview_breakdown'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primaryEmeraldLight,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.calculate_rounded,
                      size: 14,
                      color: AppTheme.primaryEmeraldDark,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        breakdown!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.tabularNumberStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primaryEmeraldDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}
