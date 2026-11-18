import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/enums/expense_category.dart';
import '../../core/enums/inference_source.dart';
import '../../core/enums/slip_status.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_helper.dart';
import '../../core/widgets/adaptive_layout.dart';
import '../../core/widgets/pocko_bottom_sheet.dart';
import '../../core/widgets/pocko_empty_state.dart';
import '../../core/widgets/pocko_mascot.dart';
import '../../core/widgets/pocko_snack.dart';
import '../../core/widgets/slip_thumbnail.dart';
import '../../core/widgets/tactile.dart';
import '../../core/widgets/telemetry_pill.dart';
import '../../models/bank_slip.dart';
import '../../models/expense_item.dart';
import '../../services/hybrid_ai/hybrid_ai_service.dart';
import '../../services/matcher/slip_analyzer.dart';
import '../../services/matcher/slip_samples.dart';
import '../expenses/expense_editor_sheet.dart';
import '../trip/trip_controller.dart';
import '../trip/trip_state.dart';

/// "Grade Pocko's work": every proposed match shows the logged expense next to
/// the candidate slip with tactile ✓ Correct / ✕ Wrong buttons. Wrong lets the
/// user pick another slip or mark the expense as paid in cash.
class SmartSlipMatcherScreen extends ConsumerStatefulWidget {
  const SmartSlipMatcherScreen({super.key});

  @override
  ConsumerState<SmartSlipMatcherScreen> createState() =>
      _SmartSlipMatcherScreenState();
}

class _SmartSlipMatcherScreenState
    extends ConsumerState<SmartSlipMatcherScreen> {
  String? _busyStep;
  bool _showVerified = false;

  SlipAnalyzer get _analyzer => SlipAnalyzer(ref.read(hybridAiServiceProvider));

  Set<String> _takenIds() => ref
      .read(tripControllerProvider)
      .slips
      .where((s) => s.targetExpenseId != null)
      .map((s) => s.targetExpenseId!)
      .toSet();

  /// Runs an analysis job. When [forExpenseId] is set the resulting slip is
  /// attached to that expense (the user chose it), otherwise it is just added.
  Future<void> _runAnalysis(
    Future<SlipAnalysis> Function() job, {
    String? forExpenseId,
  }) async {
    setState(() => _busyStep = '🛡️ Masking account numbers on-device…');
    try {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      setState(() => _busyStep = '🧠 Parsing with Hybrid AI…');
      final analysis = await job();
      if (!mounted) return;
      final controller = ref.read(tripControllerProvider.notifier);
      final slip = analysis.slip;
      if (forExpenseId != null) {
        controller.attachNewSlipToExpense(forExpenseId, slip);
      } else {
        controller.addSlip(slip);
      }
      final route = slip.inferenceSource == InferenceSource.onDevice
          ? '🟢 On-device'
          : '☁️ Cloud fallback';
      final extra = slip.isItemized
          ? ' • ${slip.lineItems.length} line items'
          : '';
      showPockoSnack(
        context,
        '$route parsed ${CurrencyHelper.formatAmount(slip.amount, slip.currency)}$extra'
        ' • ${analysis.masked.count} private field${analysis.masked.count == 1 ? '' : 's'} masked',
      );
    } catch (e) {
      if (mounted) {
        showPockoSnack(
          context,
          'Could not analyze that slip: $e',
          success: false,
        );
      }
    } finally {
      if (mounted) setState(() => _busyStep = null);
    }
  }

  Future<void> _pickImage({String? forExpenseId}) async {
    final tripState = ref.read(tripControllerProvider);
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 80,
      );
      if (image == null || !mounted) return;
      final Uint8List bytes = await image.readAsBytes();
      final name = image.name.toLowerCase();
      final mime = name.endsWith('.png')
          ? 'image/png'
          : (name.endsWith('.webp') ? 'image/webp' : 'image/jpeg');
      await _runAnalysis(
        () => _analyzer.analyzeImage(
          bytes: bytes,
          name: image.name,
          mimeType: mime,
          baseCurrency: tripState.trip.baseCurrency,
          expenses: tripState.trip.expenses,
          takenExpenseIds: forExpenseId == null ? _takenIds() : const {},
        ),
        forExpenseId: forExpenseId,
      );
    } catch (e) {
      if (mounted) {
        showPockoSnack(
          context,
          'Photo picker unavailable here. Try a sample slip instead.',
          success: false,
        );
      }
    }
  }

  Future<void> _runSample(SlipSample sample, {String? forExpenseId}) async {
    final tripState = ref.read(tripControllerProvider);
    await _runAnalysis(
      () => _analyzer.analyzeText(
        rawText: sample.rawText,
        baseCurrency: tripState.trip.baseCurrency,
        expenses: tripState.trip.expenses,
        takenExpenseIds: forExpenseId == null ? _takenIds() : const {},
      ),
      forExpenseId: forExpenseId,
    );
  }

  void _openSampleSheet() {
    showPockoBottomSheet<void>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Try a sample slip',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Compare 🟢 Local AI PII-masked matching with ☁️ Cloud Fallback itemized foreign receipt parsing.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12.5,
              height: 1.4,
              color: AppTheme.textSlate,
            ),
          ),
          const SizedBox(height: 14),
          for (final sample in SlipSamples.all)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SampleTile(
                sample: sample,
                onTap: () {
                  Navigator.pop(ctx);
                  _runSample(sample);
                },
              ),
            ),
        ],
      ),
    );
  }

  /// ✕ Wrong: pick a different slip or mark the expense as paid in cash.
  void _openWrongSheet(ExpenseItem expense, BankSlip? currentSlip) {
    final tripState = ref.read(tripControllerProvider);
    final others = tripState.slips
        .where((s) => !s.isConfirmed && s.id != currentSlip?.id)
        .toList();
    final controller = ref.read(tripControllerProvider.notifier);

    showPockoBottomSheet<void>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Which slip belongs to “${expense.title}”?',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Thanks for grading Pocko’s work! Pick the right receipt, or skip it for cash.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12.5,
              height: 1.4,
              color: AppTheme.textSlate,
            ),
          ),
          const SizedBox(height: 14),
          Tactile(
            key: const ValueKey('wrong_cash'),
            onTap: () {
              Navigator.pop(ctx);
              controller.markExpenseCash(expense.id);
              showPockoSnack(
                context,
                '${expense.title} marked as paid in cash. No receipt needed.',
              );
            },
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppTheme.borderColor),
              ),
              child: Row(
                children: [
                  const Icon(Icons.payments_rounded, color: AppTheme.textSlate),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Paid in Cash (No Slip Needed)',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textDark,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppTheme.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (others.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sheetLabel('OTHER SLIPS I FOUND'),
            for (final s in others)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Tactile(
                  key: ValueKey('pick_slip_${s.id}'),
                  onTap: () {
                    Navigator.pop(ctx);
                    controller.replaceSlipForExpense(expense.id, s.id);
                    showPockoSnack(
                      context,
                      'Linked that slip to ${expense.title}',
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: AppTheme.surfaceDecoration(radius: 16),
                    child: Row(
                      children: [
                        SlipThumbnail(slip: s, width: 36, height: 46),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            s.merchant.isEmpty ? s.bankName : s.merchant,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          CurrencyHelper.formatAmount(s.amount, s.currency),
                          style: AppTheme.tabularNumberStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 12),
          _sheetLabel('OR ADD A NEW SLIP'),
          OutlinedButton.icon(
            key: const ValueKey('wrong_gallery'),
            onPressed: () {
              Navigator.pop(ctx);
              _pickImage(forExpenseId: expense.id);
            },
            icon: const Icon(Icons.add_photo_alternate_rounded, size: 18),
            label: const Text('Choose from gallery'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: AppTheme.pillRadius),
            ),
          ),
          const SizedBox(height: 8),
          for (final sample in SlipSamples.all)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SampleTile(
                sample: sample,
                compact: true,
                onTap: () {
                  Navigator.pop(ctx);
                  _runSample(sample, forExpenseId: expense.id);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _sheetLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.0,
        color: AppTheme.textMuted,
      ),
    ),
  );

  Future<void> _createExpenseFromSlip(BankSlip slip) async {
    final tripState = ref.read(tripControllerProvider);
    final category = ExpenseCategory.fromString(
      '${slip.merchant} ${slip.lineItems.map((l) => l.name).join(' ')}',
    );
    final draft = ExpenseItem(
      id: 'exp_${DateTime.now().microsecondsSinceEpoch}',
      title: slip.merchant.isNotEmpty ? slip.merchant : slip.bankName,
      amount: slip.amount,
      currency: slip.currency,
      category: category,
      payerId: tripState.currentMemberId,
      splitWithMemberIds: tripState.trip.members.map((m) => m.id).toList(),
      createdAt: slip.createdAt,
      note: slip.isItemized
          ? slip.lineItems.map((i) => '${i.name} ${i.amount}').join(' • ')
          : null,
    );
    final edited = await showExpenseEditor(
      context,
      expense: draft,
      tripState: tripState,
    );
    if (edited == null || !mounted) return;
    ref
        .read(tripControllerProvider.notifier)
        .addExpenseForSlip(slip.id, edited);
    showPockoSnack(
      context,
      'Logged ${edited.title} and verified it with this slip',
    );
  }

  void _openLinkSheet(BankSlip slip) {
    final tripState = ref.read(tripControllerProvider);
    final taken = _takenIds();
    final base = tripState.trip.baseCurrency;
    final target = CurrencyHelper.convert(slip.amount, slip.currency, base);
    final candidates =
        tripState.trip.expenses
            .where(
              (e) =>
                  e.slipStatus == SlipStatus.waitingForSlip &&
                  !taken.contains(e.id),
            )
            .toList()
          ..sort(
            (a, b) => (a.amountIn(base) - target).abs().compareTo(
              (b.amountIn(base) - target).abs(),
            ),
          );

    showPockoBottomSheet<void>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Link slip to an expense',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            candidates.isEmpty
                ? 'Every expense already has a slip.'
                : 'Closest amounts first',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12.5,
              color: AppTheme.textSlate,
            ),
          ),
          const SizedBox(height: 10),
          for (final e in candidates)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: e.category.pastelColor,
                child: Icon(
                  e.category.icon,
                  size: 18,
                  color: e.category.accentColor,
                ),
              ),
              title: Text(
                e.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(tripState.nameOf(e.payerId)),
              trailing: Text(
                CurrencyHelper.formatAmount(e.amount, e.currency),
                style: AppTheme.tabularNumberStyle(fontSize: 14),
              ),
              onTap: () {
                ref
                    .read(tripControllerProvider.notifier)
                    .linkSlip(slip.id, e.id);
                Navigator.pop(ctx);
                showPockoSnack(
                  context,
                  'Linked slip to ${e.title}. Grade the match below.',
                );
              },
            ),
        ],
      ),
    );
  }

  void _approve(BankSlip slip) {
    final n = ref.read(tripControllerProvider.notifier).confirmSlips([slip.id]);
    if (n > 0) {
      showPockoSnack(context, '✓ Verified. Slip linked to the expense.');
    }
  }

  void _approveAll(List<BankSlip> slips) {
    final n = ref
        .read(tripControllerProvider.notifier)
        .confirmSlips(slips.map((s) => s.id).toList());
    showPockoSnack(
      context,
      '🎉 $n receipt${n == 1 ? '' : 's'} matched & verified',
    );
  }

  @override
  Widget build(BuildContext context) {
    final tripState = ref.watch(tripControllerProvider);
    final pending = tripState.pendingSlips;
    final verified = tripState.slips.where((s) => s.isConfirmed).toList();
    final expensesById = {for (final e in tripState.trip.expenses) e.id: e};
    final pairs = pending
        .where(
          (s) =>
              s.targetExpenseId != null &&
              expensesById.containsKey(s.targetExpenseId),
        )
        .toList();
    final slipOnly = pending.where((s) => !pairs.contains(s)).toList();
    final proposedIds = pairs.map((s) => s.targetExpenseId).toSet();
    final waitingNoSlip = tripState.trip.expenses
        .where(
          (e) =>
              e.slipStatus == SlipStatus.waitingForSlip &&
              !proposedIds.contains(e.id),
        )
        .toList();
    final busy = _busyStep != null;

    final header = Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: AppTheme.apricotToLavenderGradient,
        borderRadius: AppTheme.cardRadius,
        boxShadow: AppTheme.elevatedCardShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
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
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: AppTheme.pillRadius,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.shield_rounded,
                        size: 13,
                        color: AppTheme.primaryEmeraldDark,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Privacy Shield Active',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryEmeraldDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Smart Slip\nMatcher',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Grade Pocko’s work: ✓ Correct or ✕ Wrong. Account numbers are masked on-device before any AI sees them. Slips never sync to your group.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSlate,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          PockoMascot(
            mood: busy ? PockoMood.juggling : PockoMood.scanning,
            size: PockoSizes.header(context),
          ),
        ],
      ),
    );

    final actions = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                icon: Icons.add_photo_alternate_rounded,
                color: AppTheme.primaryEmeraldDark,
                label: 'Upload Slip Photo',
                onTap: busy ? null : _pickImage,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActionButton(
                icon: Icons.science_rounded,
                color: const Color(0xFF6366F1),
                label: 'Sample Slips',
                onTap: busy ? null : _openSampleSheet,
              ),
            ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          child: busy
              ? Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: AppTheme.primaryEmerald.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: AppTheme.primaryEmerald,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _busyStep!,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );

    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Text(
        text,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.0,
          color: AppTheme.textMuted,
        ),
      ),
    );

    final cards = <Widget>[];
    if (pending.isEmpty && waitingNoSlip.isEmpty && !busy) {
      cards.add(
        const PockoEmptyState(
          mood: PockoMood.celebrating,
          title: 'All Slips Matched! 🎉',
          message: 'Every expense in this trip has a verified receipt (or was paid in cash).',
        ),
      );
    } else if (pending.isEmpty && !busy) {
      cards.add(
        PockoEmptyState(
          mood: PockoMood.scanning,
          title: 'No slips to match yet',
          message: 'Upload a photo or run a sample slip, or mark cash expenses below.',
          actionLabel: 'Try a sample slip',
          onAction: _openSampleSheet,
        ),
      );
      cards.add(const SizedBox(height: 16));
    }

    if (pending.isNotEmpty) {
      cards.add(label('DETECTED SLIP MATCHES (${pending.length})'));
      var i = 0;
      for (final slip in pairs) {
        final expense = expensesById[slip.targetExpenseId]!;
        cards.add(
          _MatchCard(
                key: ValueKey('match_${slip.id}'),
                expense: expense,
                slip: slip,
                tripState: tripState,
                onApprove: () => _approve(slip),
                onReject: () => _openWrongSheet(expense, slip),
                onDismiss: () => ref
                    .read(tripControllerProvider.notifier)
                    .dismissSlip(slip.id),
              )
              .animate()
              .fadeIn(
                delay: Duration(milliseconds: 40 * i),
                duration: 260.ms,
              )
              .slideY(
                delay: Duration(milliseconds: 40 * i),
                begin: 0.05,
                end: 0,
                duration: 260.ms,
                curve: Curves.easeOutCubic,
              ),
        );
        i++;
      }
      for (final slip in slipOnly) {
        cards.add(
          _MatchCard(
            key: ValueKey('match_${slip.id}'),
            expense: null,
            slip: slip,
            tripState: tripState,
            onLink: () => _openLinkSheet(slip),
            onCreate: () => _createExpenseFromSlip(slip),
            onDismiss: () =>
                ref.read(tripControllerProvider.notifier).dismissSlip(slip.id),
          ).animate().fadeIn(duration: 260.ms),
        );
      }
      if (pairs.isNotEmpty) {
        cards.add(
          Container(
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              borderRadius: AppTheme.pillRadius,
              boxShadow: AppTheme.emeraldGlowShadow,
            ),
            child: ElevatedButton(
              onPressed: () => _approveAll(pairs),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryEmerald,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: AppTheme.pillRadius,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.verified_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Batch Confirm & Split (${pairs.length})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }

    if (waitingNoSlip.isNotEmpty) {
      cards.add(const SizedBox(height: 18));
      cards.add(label('WAITING FOR A SLIP (${waitingNoSlip.length})'));
      for (final e in waitingNoSlip) {
        cards.add(
          _MatchCard(
            key: ValueKey('waiting_${e.id}'),
            expense: e,
            slip: null,
            tripState: tripState,
            onChoose: () => _openWrongSheet(e, null),
            onCash: () {
              ref.read(tripControllerProvider.notifier).markExpenseCash(e.id);
              showPockoSnack(context, '${e.title} marked as paid in cash');
            },
          ),
        );
      }
    }

    if (verified.isNotEmpty) {
      cards.add(const SizedBox(height: 18));
      cards.add(
        Tactile(
          onTap: () => setState(() => _showVerified = !_showVerified),
          child: Row(
            children: [
              Text(
                'VERIFIED SLIPS (${verified.length})',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                _showVerified
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                size: 18,
                color: AppTheme.textMuted,
              ),
            ],
          ),
        ),
      );
      if (_showVerified) {
        cards.add(const SizedBox(height: 10));
        for (final s in verified) {
          cards.add(
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: AppTheme.surfaceDecoration(radius: 18),
              child: Row(
                children: [
                  const Icon(
                    Icons.verified_rounded,
                    size: 18,
                    color: AppTheme.primaryEmerald,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${s.bankName} • ${s.merchant.isEmpty ? s.maskedAccount : s.merchant}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textDark,
                      ),
                    ),
                  ),
                  Text(
                    CurrencyHelper.formatAmount(s.amount, s.currency),
                    style: AppTheme.tabularNumberStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      }
    }

    return TabScrollBody(
      children: [
        AdaptiveColumns(
          leftFlex: 5,
          rightFlex: 6,
          left: [
            header,
            const SizedBox(height: 16),
            actions,
            const SizedBox(height: 20),
          ],
          right: cards,
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Tactile(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.borderColor),
            boxShadow: AppTheme.softCardShadow,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SampleTile extends StatelessWidget {
  final SlipSample sample;
  final VoidCallback onTap;
  final bool compact;

  const _SampleTile({
    required this.sample,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tactile(
      onTap: onTap,
      pressedScale: 0.98,
      child: Container(
        padding: EdgeInsets.all(compact ? 10 : 14),
        decoration: BoxDecoration(
          color: sample.demonstratesCloudFallback
              ? const Color(0xFFF1F6FF)
              : const Color(0xFFF2FBF6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: sample.demonstratesCloudFallback
                ? const Color(0xFFBFD6FF)
                : const Color(0xFFBDEBD2),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: compact ? 34 : 42,
              height: compact ? 34 : 42,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                sample.icon,
                size: compact ? 18 : 22,
                color: AppTheme.textSlate,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sample.title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: compact ? 13 : 14,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textDark,
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 2),
                    Text(
                      sample.subtitle,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5,
                        height: 1.35,
                        color: AppTheme.textSlate,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.play_circle_fill_rounded,
              color: AppTheme.primaryEmerald,
            ),
          ],
        ),
      ),
    );
  }
}

/// One graded item: logged expense (left) ↔ candidate slip (right), with the
/// ✓ Correct / ✕ Wrong controls and the AI telemetry badge at the very bottom.
class _MatchCard extends StatelessWidget {
  final ExpenseItem? expense;
  final BankSlip? slip;
  final TripState tripState;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback? onLink;
  final VoidCallback? onCreate;
  final VoidCallback? onChoose;
  final VoidCallback? onCash;
  final VoidCallback? onDismiss;

  const _MatchCard({
    super.key,
    required this.expense,
    required this.slip,
    required this.tripState,
    this.onApprove,
    this.onReject,
    this.onLink,
    this.onCreate,
    this.onChoose,
    this.onCash,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final e = expense;
    final s = slip;
    final tier = s?.tier;
    final tierColor = switch (tier) {
      SlipMatchTier.exact => AppTheme.primaryEmeraldDark,
      SlipMatchTier.potential => const Color(0xFFB45309),
      _ => AppTheme.coralOwesText,
    };
    final tierBg = switch (tier) {
      SlipMatchTier.exact => AppTheme.primaryEmeraldLight,
      SlipMatchTier.potential => const Color(0xFFFFF1D6),
      _ => AppTheme.coralOwesBg,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.surfaceDecoration(radius: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (s != null)
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: tierBg,
                      borderRadius: AppTheme.pillRadius,
                    ),
                    child: Text(
                      tier == SlipMatchTier.manual
                          ? tier!.label
                          : '${tier!.label} • ${s.matchPercentage}% Match',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: tierColor,
                      ),
                    ),
                  ),
                )
              else
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF4E0),
                      borderRadius: AppTheme.pillRadius,
                    ),
                    child: Text(
                      'No slip yet',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFFB45309),
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              if (onDismiss != null)
                InkWell(
                  onTap: onDismiss,
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: e != null
                      ? _ExpensePanel(expense: e, tripState: tripState)
                      : const _EmptyPanel(
                          icon: Icons.receipt_long_rounded,
                          text: 'No matching expense',
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.compare_arrows_rounded,
                        size: 20,
                        color: (e != null && s != null)
                            ? AppTheme.primaryEmerald
                            : AppTheme.textMuted,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: s != null
                      ? _SlipPanel(
                          slip: s,
                          baseCurrency: tripState.trip.baseCurrency,
                        )
                      : const _EmptyPanel(
                          icon: Icons.add_photo_alternate_rounded,
                          text: 'Candidate slip not found',
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (onApprove != null && onReject != null)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: ValueKey('reject_${s!.id}'),
                    onPressed: onReject,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Wrong'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.coralOwesText,
                      side: const BorderSide(color: Color(0xFFFFC9C2)),
                      backgroundColor: const Color(0xFFFFF5F3),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: AppTheme.pillRadius,
                      ),
                      textStyle: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    key: ValueKey('approve_${s.id}'),
                    onPressed: onApprove,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Correct'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: AppTheme.pillRadius,
                      ),
                      textStyle: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ),
              ],
            )
          else if (onLink != null && onCreate != null)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onLink,
                    icon: const Icon(Icons.link_rounded, size: 16),
                    label: const Text('Link to expense'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: AppTheme.pillRadius,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onCreate,
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Create expense'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                  ),
                ),
              ],
            )
          else if (onChoose != null && onCash != null)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: ValueKey('choose_${e!.id}'),
                    onPressed: onChoose,
                    icon: const Icon(Icons.receipt_long_rounded, size: 16),
                    label: const Text('Choose slip'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: AppTheme.pillRadius,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    key: ValueKey('cash_${e.id}'),
                    onPressed: onCash,
                    icon: const Icon(Icons.payments_rounded, size: 16),
                    label: const Text('Paid in Cash'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.textSlate,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: s != null
                ? TelemetryFooter(
                    key: ValueKey('footer_${s.id}'),
                    source: s.inferenceSource,
                    latencyMs: s.latencyMs,
                    simulated: s.isSimulated,
                  )
                : TelemetryFooter(
                    key: ValueKey('footer_${e!.id}'),
                    source: e.inferenceSource,
                    latencyMs: e.latencyMs,
                    simulated: (e.modelInfo ?? '').toLowerCase().contains(
                      'simulated',
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PanelShell extends StatelessWidget {
  final String caption;
  final Widget child;
  const _PanelShell({required this.caption, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _ExpensePanel extends StatelessWidget {
  final ExpenseItem expense;
  final TripState tripState;
  const _ExpensePanel({required this.expense, required this.tripState});

  @override
  Widget build(BuildContext context) {
    final cat = expense.category;
    return _PanelShell(
      caption: 'LOGGED EXPENSE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
          const SizedBox(height: 8),
          Text(
            expense.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            CurrencyHelper.formatAmount(expense.amount, expense.currency),
            style: AppTheme.tabularNumberStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${tripState.nameOf(expense.payerId)} paid',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SlipPanel extends StatelessWidget {
  final BankSlip slip;
  final String baseCurrency;
  const _SlipPanel({required this.slip, required this.baseCurrency});

  @override
  Widget build(BuildContext context) {
    final converted = slip.currency.toUpperCase() != baseCurrency.toUpperCase()
        ? CurrencyHelper.convert(slip.amount, slip.currency, baseCurrency)
        : null;
    return _PanelShell(
      caption: 'CANDIDATE SLIP',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SlipThumbnail(slip: slip),
              const Spacer(),
              if (slip.maskedFieldCount > 0)
                Tooltip(
                  message:
                      '${slip.maskedFieldCount} private field(s) masked on-device before AI',
                  child: const Icon(
                    Icons.shield_rounded,
                    size: 16,
                    color: AppTheme.primaryEmeraldDark,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            slip.merchant.isEmpty ? slip.bankName : slip.merchant,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            CurrencyHelper.formatAmount(slip.amount, slip.currency),
            style: AppTheme.tabularNumberStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (converted != null)
            Text(
              '≈ ${CurrencyHelper.formatAmount(converted, baseCurrency)}',
              style: AppTheme.tabularNumberStyle(
                fontSize: 11,
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(height: 2),
          Text(
            '${slip.bankName} ${slip.maskedAccount} • ${slip.time}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.tabularNumberStyle(
              fontSize: 10.5,
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (slip.isItemized)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${slip.lineItems.length} line items',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10.5,
                  color: AppTheme.textSlate,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyPanel({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 1.4),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 26, color: AppTheme.textMuted),
          const SizedBox(height: 6),
          Text(
            text,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
