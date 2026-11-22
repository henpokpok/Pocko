import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/enums/expense_category.dart';
import '../../core/enums/slip_status.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_helper.dart';
import '../../core/widgets/adaptive_layout.dart';
import '../../core/widgets/animated_amount.dart';
import '../../core/widgets/pocko_empty_state.dart';
import '../../core/widgets/pocko_mascot.dart';
import '../../core/widgets/pocko_snack.dart';
import '../../core/widgets/tactile.dart';
import '../../core/widgets/telemetry_pill.dart';
import '../../models/expense_item.dart';
import '../../models/raw_prompt_note.dart';
import '../trip/date_filter.dart';
import '../trip/trip_controller.dart';
import '../trip/trip_permissions.dart';
import '../trip/trip_state.dart';
import 'expense_editor_sheet.dart';

class ExpensesCanvasScreen extends ConsumerWidget {
  final VoidCallback onOpenCaptureModal;

  const ExpensesCanvasScreen({super.key, required this.onOpenCaptureModal});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    ExpenseItem expense,
  ) async {
    if (!_allowed(context, ref, expense, forDelete: false)) return;
    final tripState = ref.read(tripControllerProvider);
    final updated = await showExpenseEditor(
      context,
      expense: expense,
      tripState: tripState,
      onDelete: () => _delete(context, ref, expense),
    );
    if (updated != null) {
      ref.read(tripControllerProvider.notifier).updateExpense(updated);
      if (context.mounted) {
        showPockoSnack(
          context,
          'Updated ${updated.title}',
          detail: 'Balances recalculated for everyone in the split',
          icon: updated.category.icon,
        );
      }
    }
  }

  /// Host-or-creator rule: shows a polite toast and returns `false` when this
  /// device may not edit or delete [expense].
  bool _allowed(
    BuildContext context,
    WidgetRef ref,
    ExpenseItem expense, {
    bool forDelete = true,
  }) {
    if (ref.read(tripControllerProvider.notifier).canModifyExpense(expense)) {
      return true;
    }
    final perms = ref.read(tripPermissionsProvider);
    showPockoSnack(
      context,
      forDelete ? perms.deniedMessage : perms.deniedEditMessage,
      icon: Icons.lock_rounded,
      success: false,
    );
    return false;
  }

  void _delete(BuildContext context, WidgetRef ref, ExpenseItem expense) {
    final controller = ref.read(tripControllerProvider.notifier);
    final removed = controller.removeExpense(expense.id);
    if (removed == null) return;
    showPockoSnack(
      context,
      'Removed ${removed.title}',
      detail: 'Balances updated. Tap Undo to bring it back.',
      icon: Icons.delete_outline_rounded,
      actionLabel: 'Undo',
      onAction: () => controller.restoreExpense(removed),
    );
  }

  static String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('EEE, MMM d').format(d);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripState = ref.watch(tripControllerProvider);
    final trip = tripState.trip;
    final expenses = tripState.filteredExpenses;
    final totalSpend = tripState.totalSpend;
    final secondarySpend = CurrencyHelper.getSecondarySubtitle(
      totalSpend,
      trip.baseCurrency,
      target: trip.homeCurrency,
    );

    // Group newest-first expenses by calendar day.
    final groups = <String, List<ExpenseItem>>{};
    for (final e in expenses) {
      groups.putIfAbsent(_dayLabel(e.createdAt), () => []).add(e);
    }

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
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TOTAL EXPENSES',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: AppTheme.primaryEmeraldDark,
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
                    if (secondarySpend != null)
                      Text(
                        secondarySpend,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSlate,
                        ),
                      ),
                  ],
                ),
              ),
              PockoMascot(
                mood: trip.expenses.isEmpty
                    ? PockoMood.sleepy
                    : PockoMood.celebrating,
                size: PockoSizes.header(context),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Tactile(
            onTap: onOpenCaptureModal,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: AppTheme.pillRadius,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.tips_and_updates_rounded,
                    size: 16,
                    color: Color(0xFFF59E0B),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tap + to speak or type multiple expenses at once',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textDark,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    final filterBar = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          _filterChip(
            ref,
            label: 'All (${trip.expenses.length})',
            isSelected: tripState.selectedFilterCategory == null,
            category: null,
          ),
          ...ExpenseCategory.values
              .where((cat) => trip.expenses.any((e) => e.category == cat))
              .map(
                (cat) => _filterChip(
                  ref,
                  label:
                      '${cat.englishLabel} (${trip.expenses.where((e) => e.category == cat).length})',
                  isSelected: tripState.selectedFilterCategory == cat,
                  category: cat,
                  icon: cat.icon,
                ),
              ),
        ],
      ),
    );

    Widget feed;
    if (trip.expenses.isEmpty) {
      feed = PockoEmptyState(
        title: 'No expenses yet',
        message: 'Tap the glowing + to say or type what you spent. Pocko will split it for you.',
        actionLabel: 'Log first expense',
        onAction: onOpenCaptureModal,
      );
    } else if (expenses.isEmpty) {
      feed = PockoEmptyState(
        mood: PockoMood.waving,
        title: 'Nothing in this category',
        message:
            'No ${tripState.selectedFilterCategory?.englishLabel.toLowerCase() ?? 'matching'} expenses right now.',
        actionLabel: 'Show all expenses',
        onAction: () =>
            ref.read(tripControllerProvider.notifier).setCategoryFilter(null),
      );
    } else {
      var index = 0;
      feed = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
              child: Row(
                children: [
                  Text(
                    entry.key.toUpperCase(),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${entry.value.length} item${entry.value.length == 1 ? '' : 's'}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            for (final expense in entry.value)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child:
                    _ExpenseCard(
                          key: ValueKey('card_${expense.id}'),
                          expense: expense,
                          tripState: tripState,
                          onTap: () => _edit(context, ref, expense),
                          onDelete: () => _delete(context, ref, expense),
                          confirmDelete: () async =>
                              _allowed(context, ref, expense),
                        )
                        .animate()
                        .fadeIn(
                          delay: Duration(
                            milliseconds: 35 * (index).clamp(0, 10),
                          ),
                          duration: 260.ms,
                        )
                        .slideY(
                          delay: Duration(
                            milliseconds: 35 * (index++).clamp(0, 10),
                          ),
                          begin: 0.06,
                          end: 0,
                          duration: 260.ms,
                          curve: Curves.easeOutCubic,
                        ),
              ),
          ],
        ],
      );
    }

    final dateStrip = _DateFilterStrip(tripState: tripState);

    return TabScrollBody(
      children: [
        AdaptiveColumns(
          leftFlex: 5,
          rightFlex: 6,
          left: [
            hero,
            const SizedBox(height: 18),
            dateStrip,
            const SizedBox(height: 14),
            filterBar,
            const SizedBox(height: 16),
          ],
          right: [feed],
        ),
      ],
    );
  }

  Widget _filterChip(
    WidgetRef ref, {
    required String label,
    required bool isSelected,
    required ExpenseCategory? category,
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: isSelected,
        showCheckmark: false,
        label: Text(label),
        avatar: icon != null
            ? Icon(icon, size: 14, color: category?.accentColor)
            : null,
        onSelected: (_) => ref
            .read(tripControllerProvider.notifier)
            .setCategoryFilter(category),
        backgroundColor: Colors.white,
        selectedColor: AppTheme.primaryEmeraldSubtle,
        labelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
          color: isSelected ? AppTheme.primaryEmeraldDark : AppTheme.textSlate,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: AppTheme.pillRadius,
          side: BorderSide(
            color: isSelected ? AppTheme.primaryEmerald : AppTheme.borderColor,
          ),
        ),
      ),
    );
  }
}

class _ExpenseCard extends StatelessWidget {
  final ExpenseItem expense;
  final TripState tripState;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  /// Asked before a swipe deletes the card (permission check + toast).
  final Future<bool> Function() confirmDelete;

  const _ExpenseCard({
    super.key,
    required this.expense,
    required this.tripState,
    required this.onTap,
    required this.onDelete,
    required this.confirmDelete,
  });

  @override
  Widget build(BuildContext context) {
    final payerName = tripState.nameOf(expense.payerId);
    final splitIds = expense.splitWithMemberIds;
    final splitCount = splitIds.isEmpty
        ? tripState.trip.members.length
        : splitIds.length;
    final perPerson = splitCount > 0
        ? (expense.amount / splitCount)
        : expense.amount;
    final isMatched = expense.slipStatus != SlipStatus.waitingForSlip;
    final isCash = expense.slipStatus == SlipStatus.cash;
    final secondary = CurrencyHelper.getSecondarySubtitle(
      expense.amount,
      expense.currency,
      target: tripState.trip.homeCurrency,
    );
    final names = [for (final id in splitIds) tripState.nameOf(id)];
    final rawPrompt = RawPromptNote.parse(expense.note).raw;

    // Each card repaints on its own while the list scrolls or swipes.
    return RepaintBoundary(
      child: Dismissible(
        key: ValueKey('dismiss_${expense.id}'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          decoration: BoxDecoration(
            color: AppTheme.coralOwes,
            borderRadius: AppTheme.cardRadius,
          ),
          child: const Icon(
            Icons.delete_outline_rounded,
            color: Colors.white,
            size: 26,
          ),
        ),
        confirmDismiss: (_) => confirmDelete(),
        onDismissed: (_) => onDelete(),
        child: Tactile(
          onTap: onTap,
          pressedScale: 0.98,
          semanticLabel: 'Edit ${expense.title}',
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: AppTheme.surfaceDecoration(radius: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            expense.category.pastelColor.withValues(
                              alpha: 0.75,
                            ),
                            expense.category.pastelColor.withValues(alpha: 0.4),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        expense.category.icon,
                        color: expense.category.accentColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            expense.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textDark,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Paid by $payerName • ${expense.category.displayName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textMuted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${DateFormat('MMM d').format(expense.expenseDateTime)} • ${DateFormat('HH:mm').format(expense.expenseDateTime)}'
                            '${tripState.isPreTrip(expense) ? ' • Pre-Trip' : ''}',
                            key: ValueKey('time_${expense.id}'),
                            maxLines: 1,
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          CurrencyHelper.formatAmount(
                            expense.amount,
                            expense.currency,
                          ),
                          style: AppTheme.tabularNumberStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (secondary != null)
                          Text(
                            secondary,
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
                const SizedBox(height: 14),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _AvatarStack(names: names),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${CurrencyHelper.formatAmount(perPerson, expense.currency)} / person',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.tabularNumberStyle(
                          fontSize: 11.5,
                          color: AppTheme.textSlate,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isMatched
                            ? AppTheme.primaryEmeraldSubtle
                            : const Color(0xFFFFF7E6),
                        borderRadius: AppTheme.pillRadius,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isCash
                                ? Icons.payments_rounded
                                : (isMatched
                                      ? Icons.check_circle_rounded
                                      : Icons.photo_camera_rounded),
                            size: 12,
                            color: isMatched
                                ? AppTheme.primaryEmeraldDark
                                : const Color(0xFFB45309),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isCash
                                ? 'Cash ✓'
                                : (isMatched ? 'Linked ✓' : 'Need Slip'),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: isMatched
                                  ? AppTheme.primaryEmeraldDark
                                  : const Color(0xFFB45309),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (rawPrompt != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    key: ValueKey('raw_prompt_preview_${expense.id}'),
                    children: [
                      const Icon(
                        Icons.format_quote_rounded,
                        size: 14,
                        color: AppTheme.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          rawPrompt,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TelemetryFooter(
                    key: ValueKey('footer_${expense.id}'),
                    source: expense.inferenceSource,
                    latencyMs: expense.latencyMs,
                    simulated: (expense.modelInfo ?? '').toLowerCase().contains(
                      'simulated',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Horizontal date filter: All Dates, Pre-Trip and each trip day, with the
/// total spent for whichever filter is selected.
class _DateFilterStrip extends ConsumerWidget {
  final TripState tripState;
  const _DateFilterStrip({required this.tripState});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(tripControllerProvider.notifier);
    final trip = tripState.trip;
    final selected = tripState.dateFilter;
    final days = tripState.tripDays;

    Widget chip(
      String label,
      DateFilter filter, {
      IconData? icon,
      String? key,
    }) {
      final isSel = selected == filter;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(
          key: key == null ? null : ValueKey(key),
          selected: isSel,
          showCheckmark: false,
          avatar: icon == null
              ? null
              : Icon(
                  icon,
                  size: 14,
                  color: isSel
                      ? AppTheme.primaryEmeraldDark
                      : AppTheme.textSlate,
                ),
          label: Text(label),
          onSelected: (_) => controller.setDateFilter(filter),
          backgroundColor: Colors.white,
          selectedColor: AppTheme.primaryEmeraldSubtle,
          labelStyle: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
            color: isSel ? AppTheme.primaryEmeraldDark : AppTheme.textSlate,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: AppTheme.pillRadius,
            side: BorderSide(
              color: isSel ? AppTheme.primaryEmerald : AppTheme.borderColor,
            ),
          ),
        ),
      );
    }

    // The strip total follows both filters (date and category), exactly the
    // expenses listed below it.
    final shown = tripState.filteredExpenses;
    final total = shown.fold<double>(
      0.0,
      (sum, e) => sum + e.amountIn(trip.baseCurrency),
    );
    final count = shown.length;
    final title = switch (selected.kind) {
      DateFilterKind.all => 'All dates',
      DateFilterKind.preTrip => 'Pre-Trip',
      DateFilterKind.day => DateFormat('EEE, MMM d').format(selected.day!),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              chip('All Dates', const DateFilter.all(), key: 'date_all'),
              chip(
                'Pre-Trip',
                const DateFilter.preTrip(),
                icon: Icons.flight_takeoff_rounded,
                key: 'date_pretrip',
              ),
              for (final d in days)
                chip(
                  DateFormat('MMM d').format(d),
                  DateFilter.day(d),
                  key: 'date_${DateFormat('yyyyMMdd').format(d)}',
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          key: const ValueKey('date_total'),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.borderColor),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.today_rounded,
                size: 16,
                color: AppTheme.primaryEmerald,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$title • $count expense${count == 1 ? '' : 's'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSlate,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${CurrencyHelper.formatAmount(total, trip.baseCurrency)} spent',
                style: AppTheme.tabularNumberStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AvatarStack extends StatelessWidget {
  final List<String> names;
  const _AvatarStack({required this.names});

  static const _tints = [
    Color(0xFFD1FAE5),
    Color(0xFFDBEAFE),
    Color(0xFFFCE7F3),
    Color(0xFFFEF3C7),
    Color(0xFFEDE9FE),
  ];

  @override
  Widget build(BuildContext context) {
    final shown = names.take(4).toList();
    final extra = names.length - shown.length;
    final count = shown.length + (extra > 0 ? 1 : 0);
    return SizedBox(
      width: count == 0 ? 0 : (count - 1) * 16.0 + 24,
      height: 24,
      child: Stack(
        children: [
          for (int i = 0; i < shown.length; i++)
            Positioned(
              left: i * 16.0,
              child: CircleAvatar(
                radius: 12,
                backgroundColor: Colors.white,
                child: CircleAvatar(
                  radius: 10.5,
                  backgroundColor: _tints[i % _tints.length],
                  child: Text(
                    shown[i].isNotEmpty ? shown[i][0].toUpperCase() : '?',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textSlate,
                    ),
                  ),
                ),
              ),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * 16.0,
              child: CircleAvatar(
                radius: 12,
                backgroundColor: Colors.white,
                child: CircleAvatar(
                  radius: 10.5,
                  backgroundColor: const Color(0xFFE2E8F0),
                  child: Text(
                    '+$extra',
                    style: const TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textSlate,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
