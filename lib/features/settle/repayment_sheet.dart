import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_helper.dart';
import '../../core/widgets/photo_attachment_field.dart';
import '../../core/widgets/pocko_bottom_sheet.dart';
import '../../core/widgets/pocko_pickers.dart';
import '../../core/widgets/pocko_selector.dart';
import '../../models/settlement_payment.dart';
import '../trip/trip_controller.dart';

/// Opens the "Record Repayment" sheet: who paid whom, how much, when, an
/// optional note and an optional transfer-slip photo. Pre-filled from a
/// transfer lane for the 1-tap flow. Resolves the stored payment, or `null`
/// if dismissed. The payment is deducted from the balances at once.
Future<SettlementPayment?> showRepaymentSheet(
  BuildContext context, {
  String? fromMemberId,
  String? toMemberId,
  double? amount,
  String? currency,
}) {
  return showPockoBottomSheet<SettlementPayment>(
    context: context,
    builder: (_) => _RepaymentForm(
      fromMemberId: fromMemberId,
      toMemberId: toMemberId,
      amount: amount,
      currency: currency,
    ),
  );
}

class _RepaymentForm extends ConsumerStatefulWidget {
  final String? fromMemberId;
  final String? toMemberId;
  final double? amount;
  final String? currency;

  const _RepaymentForm({
    this.fromMemberId,
    this.toMemberId,
    this.amount,
    this.currency,
  });

  @override
  ConsumerState<_RepaymentForm> createState() => _RepaymentFormState();
}

class _RepaymentFormState extends ConsumerState<_RepaymentForm> {
  late String _from;
  late String _to;
  late String _currency;
  late DateTime _paidAt;
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();
  String? _slip;
  String? _error;

  @override
  void initState() {
    super.initState();
    final state = ref.read(tripControllerProvider);
    final ids = state.trip.members.map((m) => m.id).toList();
    final me = state.currentMemberId;
    final others = ids.where((id) => id != me).toList();
    _from = widget.fromMemberId ?? (others.isNotEmpty ? others.first : me);
    _to = widget.toMemberId ?? me;
    if (_from == _to && ids.length > 1) {
      _to = ids.firstWhere((id) => id != _from);
    }
    _currency = (widget.currency ?? state.trip.baseCurrency).toUpperCase();
    _paidAt = DateTime.now();
    final a = widget.amount;
    if (a != null && a > 0) {
      _amount.text = a % 1 == 0 ? a.toStringAsFixed(0) : a.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paidAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: pockoPickerBuilder,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _paidAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _paidAt.hour,
        _paidAt.minute,
      );
    });
  }

  void _save() {
    final amount = double.tryParse(_amount.text.replaceAll(',', '').trim());
    if (_from == _to) {
      setState(() => _error = 'Choose two different people.');
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return;
    }
    final payment = ref
        .read(tripControllerProvider.notifier)
        .recordRepayment(
          fromMemberId: _from,
          toMemberId: _to,
          amount: amount,
          currency: _currency,
          paidAt: _paidAt,
          note: _note.text,
          slipImageBase64: _slip,
        );
    if (payment == null) {
      setState(() => _error = 'That repayment could not be recorded.');
      return;
    }
    Navigator.pop(context, payment);
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6, top: 4),
    child: Text(
      text,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.4,
        color: AppTheme.textSlate,
      ),
    ),
  );

  PockoSelector<String> _memberSelector(
    Key key,
    String value,
    ValueChanged<String> onSelected,
  ) {
    final state = ref.read(tripControllerProvider);
    return PockoSelector<String>(
      key: key,
      label: state.nameOf(value),
      leadingIcon: Icons.account_circle_rounded,
      onDark: false,
      selected: value,
      tooltip: 'Person',
      entries: [
        for (final m in state.trip.members)
          PockoMenuEntry<String>(
            value: m.id,
            label: state.displayName(m),
            icon: Icons.person_rounded,
          ),
      ],
      onSelected: (v) => setState(() {
        _error = null;
        onSelected(v);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currencies = {
      ...CurrencyHelper.currencyNames.keys,
      _currency,
    }.toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Record Repayment',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Log money that already changed hands. It is deducted from what is owed right away. Pocko never moves money for you.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              height: 1.4,
              color: AppTheme.textSlate,
            ),
          ),
          const SizedBox(height: 14),
          _label('WHO PAID WHOM'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _memberSelector(
                const ValueKey('repay_from'),
                _from,
                (v) => _from = v,
              ),
              const Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: AppTheme.primaryEmeraldDark,
              ),
              _memberSelector(const ValueKey('repay_to'), _to, (v) => _to = v),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            key: const ValueKey('repay_amount'),
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: AppTheme.tabularNumberStyle(fontSize: 16),
            decoration: InputDecoration(
              labelText: 'Amount',
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 8, right: 6),
                child: PockoSelector<String>(
                  key: const ValueKey('repay_currency'),
                  label: _currency,
                  compact: true,
                  onDark: false,
                  selected: _currency,
                  tooltip: 'Currency',
                  entries: [
                    for (final c in currencies)
                      PockoMenuEntry<String>(
                        value: c,
                        label: CurrencyHelper.currencyNames[c] == null
                            ? c
                            : '$c  ${CurrencyHelper.currencyNames[c]}',
                        icon: Icons.payments_rounded,
                      ),
                  ],
                  onSelected: (v) => setState(() => _currency = v),
                ),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 0),
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: PockoValuePill(
              key: const ValueKey('repay_date'),
              icon: Icons.calendar_today_rounded,
              text: DateFormat('EEE, MMM d, y').format(_paidAt),
              onTap: _pickDate,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('repay_note'),
            controller: _note,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              hintText: 'Cash at the hotel, bank transfer...',
            ),
          ),
          const SizedBox(height: 12),
          PhotoAttachmentField(
            title: 'Transfer Slip / Proof (optional)',
            base64: _slip,
            onChanged: (v) => setState(() => _slip = v),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              key: const ValueKey('repay_error'),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.coralOwesText,
              ),
            ),
          ],
          const SizedBox(height: 18),
          ElevatedButton(
            key: const ValueKey('repay_save'),
            onPressed: _save,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Record Repayment'),
          ),
        ],
      ),
    );
  }
}
