import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/enums/expense_category.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_helper.dart';
import '../../core/widgets/adaptive_layout.dart';
import '../../core/widgets/animated_amount.dart';
import '../../core/widgets/photo_attachment_field.dart';
import '../../core/widgets/pocko_empty_state.dart';
import '../../core/widgets/pocko_mascot.dart';
import '../../core/widgets/pocko_snack.dart';
import '../../core/widgets/tactile.dart';
import '../../models/settlement_payment.dart';
import '../../models/settlement_transfer.dart';
import '../settlement/pair_breakdown.dart';
import '../trip/trip_controller.dart';
import '../trip/trip_permissions.dart';
import 'pair_breakdown_view.dart';
import 'repayment_sheet.dart';
import 'transfer_lane_card.dart';
import '../trip/trip_state.dart';

class VisualSettleScreen extends ConsumerStatefulWidget {
  const VisualSettleScreen({super.key});

  @override
  ConsumerState<VisualSettleScreen> createState() => _VisualSettleScreenState();
}

class _VisualSettleScreenState extends ConsumerState<VisualSettleScreen> {
  int _touchedCategoryIndex = -1;
  final Set<String> _expandedPairs = {};

  void _markSettled(SettlementTransfer transfer) {
    final controller = ref.read(tripControllerProvider.notifier);
    final before = ref.read(tripControllerProvider).settlements.length;
    final ok = controller.markTransferSettled(transfer.id);
    if (!ok) return;
    final after = ref.read(tripControllerProvider).settlements;
    final paymentId = after.length > before ? after.last.id : null;
    final state = ref.read(tripControllerProvider);
    showPockoSnack(
      context,
      '${state.nameOf(transfer.fromMemberId)} ➔ ${state.nameOf(transfer.toMemberId)} settled',
      detail: 'Marked as paid. Balances are square for this pair.',
      icon: Icons.handshake_rounded,
      actionLabel: paymentId == null ? null : 'Undo',
      onAction: paymentId == null
          ? null
          : () => controller.undoSettlement(paymentId),
    );
  }

  /// Opens the Record Repayment sheet (pre-filled from a lane when given),
  /// then confirms with a toast that can undo it.
  Future<void> _recordRepayment({SettlementTransfer? transfer}) async {
    final payment = await showRepaymentSheet(
      context,
      fromMemberId: transfer?.fromMemberId,
      toMemberId: transfer?.toMemberId,
      amount: transfer?.amount,
      currency: transfer?.currency,
    );
    if (payment == null || !mounted) return;
    final state = ref.read(tripControllerProvider);
    showPockoSnack(
      context,
      '${state.nameOf(payment.fromMemberId)} paid back ${state.nameOf(payment.toMemberId)}',
      detail:
          '${CurrencyHelper.formatAmount(payment.amount, payment.currency)} deducted from the balances.',
      icon: Icons.handshake_rounded,
      actionLabel: 'Undo',
      onAction: () =>
          ref.read(tripControllerProvider.notifier).undoSettlement(payment.id),
    );
  }

  /// "Your Itemized Breakdown": per person, every expense that makes up what
  /// you owe (or are owed), expandable, with Mark Settled when a transfer exists.
  Widget _buildYourBreakdown(TripState state) {
    final me = state.currentMemberId;
    final others = state.trip.members.where((m) => m.id != me).toList();
    return Container(
      key: const ValueKey('your_breakdown'),
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.surfaceDecoration(radius: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOUR ITEMIZED BREAKDOWN',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Every expense behind what you owe or are owed, item by item.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11.5,
              color: AppTheme.textSlate,
            ),
          ),
          const SizedBox(height: 10),
          for (final other in others) _pairTile(state, me, other.id),
        ],
      ),
    );
  }

  Widget _pairTile(TripState state, String me, String otherId) {
    final breakdown = computePairBreakdown(state, me, otherId);
    final other = state.nameOf(otherId);
    final net = breakdown.net;
    final expanded = _expandedPairs.contains(otherId);
    final color = net < -0.5
        ? AppTheme.coralOwesText
        : (net > 0.5 ? AppTheme.primaryEmeraldDark : AppTheme.textMuted);
    final label = net < -0.5
        ? 'You owe $other'
        : (net > 0.5 ? '$other owes you' : 'Square with $other');
    SettlementTransfer? transfer;
    for (final t in state.simplifiedTransfers) {
      if ((t.fromMemberId == me && t.toMemberId == otherId) ||
          (t.toMemberId == me && t.fromMemberId == otherId)) {
        transfer = t;
      }
    }

    return Container(
      key: ValueKey('pair_$otherId'),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        children: [
          Tactile(
            onTap: () => setState(() {
              if (!_expandedPairs.add(otherId)) _expandedPairs.remove(otherId);
            }),
            pressedScale: 0.99,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.white,
                    child: Text(
                      other.isEmpty ? '?' : other[0].toUpperCase(),
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textDark,
                      ),
                    ),
                  ),
                  Text(
                    CurrencyHelper.formatAmount(
                      net.abs(),
                      state.trip.baseCurrency,
                    ),
                    style: AppTheme.tabularNumberStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: AppTheme.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: PairBreakdownView(
                tripState: state,
                breakdown: breakdown,
                trailing: transfer == null
                    ? null
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if ((transfer.amount - net.abs()).abs() > 1)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                'Pocko’s plan settles the whole group in the fewest transfers, so the amount to send (${CurrencyHelper.formatAmount(transfer.amount, transfer.currency)}) can differ from this direct total.',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  height: 1.35,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ),
                          (transfer.fromMemberId == me
                              ? ElevatedButton.icon(
                                  key: ValueKey('pair_settle_$otherId'),
                                  onPressed: () => _markSettled(transfer!),
                                  icon: const Icon(
                                    Icons.check_rounded,
                                    size: 18,
                                  ),
                                  label: Text(
                                    'Mark Settled • ${CurrencyHelper.formatAmount(transfer.amount, transfer.currency)}',
                                  ),
                                )
                              : OutlinedButton.icon(
                                  key: ValueKey('pair_settle_$otherId'),
                                  onPressed: () => _markSettled(transfer!),
                                  icon: const Icon(
                                    Icons.check_rounded,
                                    size: 18,
                                  ),
                                  label: Text(
                                    'Mark Settled • ${CurrencyHelper.formatAmount(transfer.amount, transfer.currency)}',
                                  ),
                                )),
                        ],
                      ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tripState = ref.watch(tripControllerProvider);
    final perms = ref.watch(tripPermissionsProvider);
    final trip = tripState.trip;
    final pending = tripState.simplifiedTransfers;
    final settled = tripState.settlements;
    final allSettled = trip.expenses.isNotEmpty && pending.isEmpty;

    // Category spend in the base currency (mixed-currency trips convert correctly).
    final Map<ExpenseCategory, double> categorySpends = {};
    for (final exp in trip.expenses) {
      categorySpends[exp.category] =
          (categorySpends[exp.category] ?? 0.0) +
          exp.amountIn(trip.baseCurrency);
    }
    final totalSpend = tripState.totalSpend > 0 ? tripState.totalSpend : 1.0;
    final sortedCategories = categorySpends.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final focusIndex =
        (_touchedCategoryIndex >= 0 &&
            _touchedCategoryIndex < sortedCategories.length)
        ? _touchedCategoryIndex
        : 0;
    final focus = sortedCategories.isNotEmpty
        ? sortedCategories[focusIndex]
        : null;
    final focusPercent = focus == null
        ? '0'
        : ((focus.value / totalSpend) * 100).toStringAsFixed(0);

    final donutCard = Container(
      padding: const EdgeInsets.all(22),
      decoration: AppTheme.surfaceDecoration(radius: 28, elevated: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'CATEGORY BREAKDOWN',
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
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primaryEmeraldSubtle,
                  borderRadius: AppTheme.pillRadius,
                ),
                child: Text(
                  '${sortedCategories.length} Categories',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryEmeraldDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (focus == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: PockoEmptyState(
                title: 'Nothing to chart yet',
                message:
                    'Log an expense and your category rings will appear here.',
              ),
            )
          else ...[
            SizedBox(
              height: 190,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  RepaintBoundary(
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 3,
                        centerSpaceRadius: 56,
                        pieTouchData: PieTouchData(
                          touchCallback: (event, response) {
                            setState(() {
                              if (!event.isInterestedForInteractions ||
                                  response == null ||
                                  response.touchedSection == null) {
                                _touchedCategoryIndex = -1;
                                return;
                              }
                              _touchedCategoryIndex =
                                  response.touchedSection!.touchedSectionIndex;
                            });
                          },
                        ),
                        sections: [
                          for (
                            int idx = 0;
                            idx < sortedCategories.length;
                            idx++
                          )
                            PieChartSectionData(
                              color: sortedCategories[idx].key.pastelColor,
                              value: sortedCategories[idx].value,
                              title: '',
                              radius: idx == focusIndex ? 30.0 : 22.0,
                            ),
                        ],
                      ),
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        focus.key.icon,
                        size: 24,
                        color: focus.key.accentColor,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$focusPercent%',
                        style: AppTheme.tabularNumberStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        focus.key.englishLabel,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      Text(
                        CurrencyHelper.formatAmount(
                          focus.value,
                          trip.baseCurrency,
                        ),
                        style: AppTheme.tabularNumberStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSlate,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (int idx = 0; idx < sortedCategories.take(6).length; idx++)
                  Tactile(
                    onTap: () => setState(
                      () => _touchedCategoryIndex = idx == _touchedCategoryIndex
                          ? -1
                          : idx,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: idx == focusIndex
                            ? AppTheme.primaryEmeraldSubtle
                            : const Color(0xFFF8FAFC),
                        borderRadius: AppTheme.pillRadius,
                        border: Border.all(
                          color: idx == focusIndex
                              ? AppTheme.primaryEmerald
                              : AppTheme.borderColor,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: sortedCategories[idx].key.pastelColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '${sortedCategories[idx].key.englishLabel} '
                              '${((sortedCategories[idx].value / totalSpend) * 100).toStringAsFixed(0)}%',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textDark,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );

    final maxNet = tripState.netBalances.values.fold<double>(
      1.0,
      (m, v) => v.abs() > m ? v.abs() : m,
    );
    final balanceCard = Container(
      padding: const EdgeInsets.all(22),
      decoration: AppTheme.surfaceDecoration(radius: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'NET BALANCE SNAPSHOT',
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
              Row(
                children: [
                  Text(
                    '◄ Owes',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.coralOwes,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Receives ►',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryEmeraldDark,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final member in trip.members)
            _BalanceBar(
              name: tripState.displayName(member),
              net: tripState.netBalances[member.id] ?? 0.0,
              maxNet: maxNet,
              currency: trip.baseCurrency,
            ),
        ],
      ),
    );

    final Widget transfersSection;
    if (trip.expenses.isEmpty) {
      transfersSection = const PockoEmptyState(
        title: 'Nothing to settle yet',
        message: 'Once expenses are logged, Pocko shows the fewest transfers that make everyone square.',
      );
    } else if (allSettled) {
      transfersSection = Container(
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(
          gradient: AppTheme.mintToSkyGradient,
          borderRadius: AppTheme.cardRadius,
          boxShadow: AppTheme.elevatedCardShadow,
        ),
        child: Column(
          children: [
            PockoMascot(
              mood: PockoMood.celebrating,
              size: PockoSizes.hero(context),
            ),
            const SizedBox(height: 16),
            Text(
              'All settled with 0 awkward math! 🎉',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Everyone is square. Zero outstanding debts across all group members.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppTheme.textSlate,
              ),
            ),
            if (settled.isNotEmpty && perms.canRemoveMembers) ...[
              const SizedBox(height: 14),
              TextButton.icon(
                onPressed: () => ref
                    .read(tripControllerProvider.notifier)
                    .resetSettledTransfers(),
                icon: const Icon(
                  Icons.refresh_rounded,
                  size: 16,
                  color: AppTheme.primaryEmeraldDark,
                ),
                label: Text(
                  'Reset Settle Status',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryEmeraldDark,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    } else {
      transfersSection = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'OPTIMIZED SETTLEMENT TRANSFERS (${pending.length})',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    color: AppTheme.textMuted,
                  ),
                ),
              ),
              AnimatedAmount(
                value: tripState.outstandingTotal,
                currency: trip.baseCurrency,
                style: AppTheme.tabularNumberStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.coralOwesText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < pending.length; i++)
            TransferLaneCard(
                  key: ValueKey('transfer_${pending[i].id}'),
                  tripState: tripState,
                  transfer: pending[i],
                  onRecordPayment: () => _recordRepayment(transfer: pending[i]),
                )
                .animate()
                .fadeIn(
                  delay: Duration(milliseconds: 50 * i),
                  duration: 240.ms,
                )
                .slideY(
                  delay: Duration(milliseconds: 50 * i),
                  begin: 0.05,
                  end: 0,
                  duration: 240.ms,
                  curve: Curves.easeOutCubic,
                ),
        ],
      );
    }

    final history = settled.isEmpty
        ? const <Widget>[]
        : <Widget>[
            const SizedBox(height: 18),
            Text(
              'REPAYMENT HISTORY (${settled.length})',
              key: const ValueKey('repayment_history_title'),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
                color: AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 10),
            for (final p in settled.reversed)
              _RepaymentRow(
                key: ValueKey('repayment_${p.id}'),
                payment: p,
                fromName: tripState.nameOf(p.fromMemberId),
                toName: tripState.nameOf(p.toMemberId),
                onUndo: perms.canModify(p.createdByUid)
                    ? () => ref
                          .read(tripControllerProvider.notifier)
                          .undoSettlement(p.id)
                    : null,
              ),
          ];

    final recordButton = trip.members.length < 2
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: OutlinedButton.icon(
              key: const ValueKey('record_repayment_button'),
              onPressed: () => _recordRepayment(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Record Repayment'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryEmeraldDark,
                side: const BorderSide(
                  color: AppTheme.primaryEmerald,
                  width: 2,
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: const StadiumBorder(),
                textStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          );

    final header = Container(
      key: const ValueKey('settle_header'),
      padding: const EdgeInsets.fromLTRB(22, 16, 14, 16),
      decoration: BoxDecoration(
        gradient: AppTheme.mintToSkyGradient,
        borderRadius: AppTheme.cardRadius,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Settle up',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  trip.expenses.isEmpty
                      ? 'Log expenses to see who owes whom.'
                      : allSettled
                      ? 'Everyone is square. Nicely done!'
                      : '${pending.length} transfer${pending.length == 1 ? '' : 's'} '
                            'to make everyone square.',
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
            mood: allSettled
                ? PockoMood.celebrating
                : (trip.expenses.isEmpty ? PockoMood.sleepy : PockoMood.waving),
            size: PockoSizes.header(context),
          ),
        ],
      ),
    );

    return TabScrollBody(
      children: [
        header,
        const SizedBox(height: 18),
        AdaptiveColumns(
          leftFlex: 1,
          rightFlex: 1,
          left: [
            donutCard,
            const SizedBox(height: 18),
            balanceCard,
            const SizedBox(height: 18),
          ],
          right: [
            recordButton,
            transfersSection,
            if (trip.expenses.isNotEmpty) ...[
              const SizedBox(height: 18),
              _buildYourBreakdown(tripState),
            ],
            ...history,
          ],
        ),
      ],
    );
  }
}

class _BalanceBar extends StatelessWidget {
  final String name;
  final double net;
  final double maxNet;
  final String currency;

  const _BalanceBar({
    required this.name,
    required this.net,
    required this.maxNet,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final isPositive = net >= 0;
    final ratio = net.abs() < 0.5 ? 0.0 : (net.abs() / maxNet).clamp(0.05, 1.0);

    Widget bar({required bool left}) {
      final show = ratio > 0 && (left ? !isPositive : isPositive);
      return Expanded(
        child: Align(
          alignment: left ? Alignment.centerRight : Alignment.centerLeft,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: show ? ratio : 0.0),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
            builder: (context, w, _) => FractionallySizedBox(
              widthFactor: w,
              child: Container(
                height: 16,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: left
                        ? [AppTheme.coralOwes, const Color(0xFFFFA399)]
                        : [AppTheme.primaryEmerald, const Color(0xFF6EE7B7)],
                  ),
                  borderRadius: left
                      ? const BorderRadius.horizontal(left: Radius.circular(8))
                      : const BorderRadius.horizontal(
                          right: Radius.circular(8),
                        ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              name,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.textDark,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(width: 2, height: 24, color: const Color(0xFFCBD5E1)),
                Row(
                  children: [
                    bar(left: true),
                    const SizedBox(width: 2),
                    bar(left: false),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 96,
            // Large numbers shrink to fit instead of clipping.
            child: FittedBox(
              key: const ValueKey('balance_amount_fit'),
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: AnimatedAmount(
                value: net,
                currency: currency,
                showSign: true,
                textAlign: TextAlign.right,
                style: AppTheme.tabularNumberStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: net.abs() < 0.5
                      ? AppTheme.textMuted
                      : (isPositive
                            ? AppTheme.primaryEmeraldDark
                            : AppTheme.coralOwesText),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RepaymentRow extends StatelessWidget {
  final SettlementPayment payment;
  final String fromName;
  final String toName;

  /// `null` when this person may not undo the entry (guest, not the creator).
  final VoidCallback? onUndo;

  const _RepaymentRow({
    super.key,
    required this.payment,
    required this.fromName,
    required this.toName,
    required this.onUndo,
  });

  @override
  Widget build(BuildContext context) {
    final note = payment.note;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 18,
            color: AppTheme.primaryEmerald,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$fromName paid back $toName • ${CurrencyHelper.formatAmount(payment.amount, payment.currency)}',
                  key: ValueKey('repayment_title_${payment.id}'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                ),
                Text(
                  [
                    DateFormat('MMM d, HH:mm').format(payment.paidAt),
                    if (note != null && note.isNotEmpty) note,
                  ].join(' • '),
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
          if (payment.slipImageBase64 != null)
            IconButton(
              key: ValueKey('repayment_slip_${payment.id}'),
              tooltip: 'View slip',
              icon: const Icon(
                Icons.receipt_long_rounded,
                size: 20,
                color: AppTheme.primaryEmeraldDark,
              ),
              onPressed: () =>
                  showFullscreenPhoto(context, payment.slipImageBase64!),
            ),
          if (onUndo != null)
            TextButton(onPressed: onUndo, child: const Text('Undo')),
        ],
      ),
    );
  }
}
