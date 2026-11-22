import 'package:flutter/material.dart';

import 'placeholder_home.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/enums/slip_status.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_helper.dart';
import '../../core/widgets/adaptive_layout.dart';
import '../../core/widgets/animated_amount.dart';
import '../../core/widgets/pocko_empty_state.dart';
import '../../core/widgets/pocko_mascot.dart';
import '../../core/widgets/tactile.dart';
import '../../models/expense_item.dart';
import '../squad/squad_setup_screen.dart';
import '../trip/squad_balance_card.dart';
import '../trip/trip_controller.dart';

/// Tab indexes used by [TripHomeScreen.onNavigateTab] (index 2 is the center + button).
class PockoTabs {
  PockoTabs._();
  static const home = 0;
  static const expenses = 1;
  static const matcher = 3;
  static const settle = 4;
}

class TripHomeScreen extends ConsumerWidget {
  final void Function(int tabIndex)? onNavigateTab;
  final VoidCallback? onOpenSquadSetup;
  final VoidCallback? onOpenCaptureModal;

  const TripHomeScreen({
    super.key,
    this.onNavigateTab,
    this.onOpenSquadSetup,
    this.onOpenCaptureModal,
  });

  void _handleOpenSquad(BuildContext context) {
    if (onOpenSquadSetup != null) {
      onOpenSquadSetup!();
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SquadSetupScreen(
            onLaunchCanvas: () {
              Navigator.of(context).pop();
              onNavigateTab?.call(PockoTabs.expenses);
            },
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripState = ref.watch(tripControllerProvider);
    // No active trip (fresh install, or only a trip that has not started):
    // the welcoming placeholder, unless the user opened the upcoming trip.
    if (tripState.hasNoActiveTrip &&
        ref.watch(openedUpcomingTripProvider) != tripState.trip.id) {
      return const PlaceholderHome();
    }
    final trip = tripState.trip;
    final totalSpend = tripState.totalSpend;
    final secondarySubtitle = CurrencyHelper.getSecondarySubtitle(
      totalSpend,
      trip.baseCurrency,
      target: trip.homeCurrency,
    );
    final pendingTransfers = tripState.simplifiedTransfers.length;
    final recentExpenses = tripState.recentExpenses;
    final allSquare = trip.expenses.isNotEmpty && pendingTransfers == 0;

    final hero = Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: AppTheme.mintToSkyGradient,
        borderRadius: AppTheme.cardRadius,
        boxShadow: AppTheme.elevatedCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.8),
                        borderRadius: AppTheme.pillRadius,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              trip.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textDark,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '• ${trip.baseCurrency}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSlate,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'TOTAL TRIP SPEND',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                        color: AppTheme.textSlate,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: AnimatedAmount(
                        value: totalSpend,
                        currency: trip.baseCurrency,
                        style: AppTheme.tabularNumberStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (secondarySubtitle != null) ...[
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryEmeraldSubtle,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          secondarySubtitle,
                          style: AppTheme.tabularNumberStyle(
                            fontSize: 13,
                            color: AppTheme.primaryEmeraldDark,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              PockoMascot(
                mood: allSquare
                    ? PockoMood.celebrating
                    : (totalSpend > 0 ? PockoMood.waving : PockoMood.sleepy),
                size: PockoSizes.header(context),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _StatChip(
                  label: 'Per person',
                  value: CurrencyHelper.formatAmount(
                    tripState.perPersonSpend,
                    trip.baseCurrency,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatChip(
                  label: 'Still owed',
                  value: CurrencyHelper.formatAmount(
                    tripState.outstandingTotal,
                    trip.baseCurrency,
                  ),
                  highlight: pendingTransfers > 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 8,
            spacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.calendar_today_rounded,
                    size: 14,
                    color: AppTheme.textSlate,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      tripState.dateRange,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSlate,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Tactile(
                onTap: () => _handleOpenSquad(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: AppTheme.pillRadius,
                    border: Border.all(color: AppTheme.borderColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.group_rounded,
                        size: 14,
                        color: AppTheme.primaryEmerald,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Edit Group / Invite →',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final top = tripState.topExpenses();
    final topExpensesCard = _TopExpensesCard(
      key: const ValueKey('top_expenses_card'),
      expenses: top,
      baseCurrency: trip.baseCurrency,
      onSeeAll: () => onNavigateTab?.call(PockoTabs.expenses),
      onAdd: onOpenCaptureModal,
    );

    final recent = Container(
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.surfaceDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'RECENT EXPENSES',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    color: AppTheme.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Tactile(
                onTap: () => onNavigateTab?.call(PockoTabs.expenses),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                  child: Text(
                    'See all →',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryEmerald,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (recentExpenses.isEmpty)
            PockoEmptyState(
              title: 'No expenses recorded yet',
              message: 'Tap + to add the first one by voice or text.',
              actionLabel: onOpenCaptureModal == null ? null : 'Log an expense',
              onAction: onOpenCaptureModal,
            )
          else
            for (int idx = 0; idx < recentExpenses.length; idx++) ...[
              if (idx > 0) const Divider(height: 20, color: Color(0xFFF1F5F9)),
              _RecentRow(
                title: recentExpenses[idx].title,
                payerName: tripState.nameOf(recentExpenses[idx].payerId),
                categoryName: recentExpenses[idx].category.displayName,
                icon: recentExpenses[idx].category.icon,
                pastel: recentExpenses[idx].category.pastelColor,
                accent: recentExpenses[idx].category.accentColor,
                matched: recentExpenses[idx].slipStatus == SlipStatus.matched,
                amount: CurrencyHelper.formatAmount(
                  recentExpenses[idx].amount,
                  recentExpenses[idx].currency,
                ),
                secondary: CurrencyHelper.getSecondarySubtitle(
                  recentExpenses[idx].amount,
                  recentExpenses[idx].currency,
                  target: trip.homeCurrency,
                ),
                onTap: () => onNavigateTab?.call(PockoTabs.expenses),
              ),
            ],
        ],
      ),
    );

    return TabScrollBody(
      children: [
        AdaptiveColumns(
          left: [
            hero,
            const SizedBox(height: 18),
            SquadBalanceCard(
              tripState: tripState,
              onManage: () => _handleOpenSquad(context),
              showInviteOrb: true,
            ),
            const SizedBox(height: 16),
          ],
          right: [topExpensesCard, const SizedBox(height: 16), recent],
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _StatChip({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppTheme.tabularNumberStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: highlight ? AppTheme.coralOwesText : AppTheme.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Top Expenses": the three highest-value expenses of the trip as rounded
/// progress tubes, proportional to the biggest one.
class _TopExpensesCard extends StatelessWidget {
  final List<ExpenseItem> expenses;
  final String baseCurrency;
  final VoidCallback? onSeeAll;
  final VoidCallback? onAdd;

  const _TopExpensesCard({
    super.key,
    required this.expenses,
    required this.baseCurrency,
    this.onSeeAll,
    this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final maxValue = expenses.isEmpty
        ? 1.0
        : expenses.first.amountIn(baseCurrency).clamp(1.0, double.infinity);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.surfaceDecoration(elevated: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'TOP EXPENSES',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    color: AppTheme.textMuted,
                  ),
                ),
              ),
              Tactile(
                onTap: onSeeAll,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                  child: Text(
                    'See all →',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryEmerald,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (expenses.isEmpty)
            PockoEmptyState(
              title: 'No expenses yet',
              message: 'Your three biggest expenses will show up here.',
              actionLabel: onAdd == null ? null : 'Log an expense',
              onAction: onAdd,
            )
          else
            for (int i = 0; i < expenses.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              _TopExpenseBar(
                key: ValueKey('top_bar_$i'),
                expense: expenses[i],
                baseCurrency: baseCurrency,
                fraction: (expenses[i].amountIn(baseCurrency) / maxValue).clamp(
                  0.04,
                  1.0,
                ),
                rank: i + 1,
              ),
            ],
        ],
      ),
    );
  }
}

class _TopExpenseBar extends StatelessWidget {
  final ExpenseItem expense;
  final String baseCurrency;
  final double fraction;
  final int rank;

  const _TopExpenseBar({
    super.key,
    required this.expense,
    required this.baseCurrency,
    required this.fraction,
    required this.rank,
  });

  @override
  Widget build(BuildContext context) {
    final cat = expense.category;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: cat.pastelColor.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: Icon(cat.icon, size: 17, color: cat.accentColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${expense.title} • ${DateFormat('MMM d').format(expense.expenseDateTime)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textDark,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              CurrencyHelper.formatAmount(expense.amount, expense.currency),
              style: AppTheme.tabularNumberStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, c) => Stack(
            children: [
              Container(
                height: 10,
                width: c.maxWidth,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              TweenAnimationBuilder<double>(
                tween: Tween<double>(end: fraction),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                builder: (context, f, _) => Container(
                  key: ValueKey('top_fill_$rank'),
                  height: 10,
                  width: c.maxWidth * f,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        cat.pastelColor,
                        cat.accentColor.withValues(alpha: 0.85),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(99),
                    boxShadow: [
                      BoxShadow(
                        color: cat.accentColor.withValues(alpha: 0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecentRow extends StatelessWidget {
  final String title;
  final String payerName;
  final String categoryName;
  final IconData icon;
  final Color pastel;
  final Color accent;
  final bool matched;
  final String amount;
  final String? secondary;
  final VoidCallback onTap;

  const _RecentRow({
    required this.title,
    required this.payerName,
    required this.categoryName,
    required this.icon,
    required this.pastel,
    required this.accent,
    required this.matched,
    required this.amount,
    required this.secondary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tactile(
      onTap: onTap,
      pressedScale: 0.985,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: pastel, shape: BoxShape.circle),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '$payerName paid • $categoryName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ),
                    if (matched) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.verified_rounded,
                        size: 13,
                        color: AppTheme.primaryEmerald,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amount,
                style: AppTheme.tabularNumberStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (secondary != null)
                Text(
                  secondary!,
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
    );
  }
}
