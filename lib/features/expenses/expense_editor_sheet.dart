import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/enums/expense_category.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_helper.dart';
import '../../core/widgets/photo_attachment_field.dart';
import '../../core/widgets/pocko_pickers.dart';
import '../../core/widgets/pocko_bottom_sheet.dart';
import '../../core/widgets/pocko_mascot.dart';
import '../../core/widgets/pocko_selector.dart';
import '../../services/hybrid_ai/hybrid_ai_service.dart';
import '../../models/expense_item.dart';
import '../../models/raw_prompt_note.dart';
import '../capture/selected_names.dart';
import '../trip/date_filter.dart';
import '../trip/trip_state.dart';

/// How long the title field must stay idle before Pocko suggests a category.
const Duration kCategoryAssistDebounce = Duration(milliseconds: 2500);

/// Opens the shared expense editor (used by the Expenses tab and by the AI
/// capture confirmation). Resolves the edited expense, or `null` if dismissed.
/// When [onDelete] is provided a destructive "Delete expense" button is shown.
Future<ExpenseItem?> showExpenseEditor(
  BuildContext context, {
  required ExpenseItem expense,
  required TripState tripState,
  VoidCallback? onDelete,
  bool isNew = false,
}) {
  return showPockoBottomSheet<ExpenseItem>(
    context: context,
    scrollable: false,
    builder: (ctx) => _ExpenseEditor(
      expense: expense,
      tripState: tripState,
      onDelete: onDelete,
      isNew: isNew,
    ),
  );
}

class _ExpenseEditor extends StatefulWidget {
  final ExpenseItem expense;
  final TripState tripState;
  final VoidCallback? onDelete;

  /// `true` for the manual "Add Expense" flow (changes the heading and CTA).
  final bool isNew;

  const _ExpenseEditor({
    required this.expense,
    required this.tripState,
    this.onDelete,
    this.isNew = false,
  });

  @override
  State<_ExpenseEditor> createState() => _ExpenseEditorState();
}

class _ExpenseEditorState extends State<_ExpenseEditor> {
  late final TextEditingController _title;
  late final TextEditingController _amount;
  late final TextEditingController _note;

  /// The verbatim words the expense was captured from (read-only audit trail).
  String? _rawPrompt;
  late ExpenseCategory _category;
  late String _payerId;
  late String _currency;
  late Set<String> _split;
  late DateTime _when;
  String? _error;

  // --- Unequal split ---------------------------------------------------------
  /// `true` = "Custom Amounts": one exact amount per person, total = their sum.
  late bool _custom;
  final Map<String, TextEditingController> _customCtrls = {};

  // --- Receipt / slip photo ---------------------------------------------------
  String? _receiptB64;

  // --- Pocko auto-category assist ------------------------------------------
  Timer? _assistTimer;

  /// `true` once the user picked a category by hand (or when editing an
  /// existing expense), so Pocko never overrides a deliberate choice.
  late bool _categoryLocked;
  ExpenseCategory? _suggested;
  int _suggestionTick = 0;

  @override
  void initState() {
    super.initState();
    final e = widget.expense;
    _title = TextEditingController(text: e.title);
    _amount = TextEditingController(
      text: e.amount % 1 == 0
          ? e.amount.toStringAsFixed(0)
          : e.amount.toStringAsFixed(2),
    );
    final parsedNote = RawPromptNote.parse(e.note);
    _rawPrompt = parsedNote.raw;
    _note = TextEditingController(text: parsedNote.rest);
    _category = e.category;
    _payerId = e.payerId;
    _currency = e.currency.toUpperCase();
    _split = e.splitWithMemberIds.toSet();
    _when = e.expenseDateTime;
    _categoryLocked = !widget.isNew;
    _custom = e.isItemized;
    if (_custom) {
      final fractions = e.shareFractions(e.splitWithMemberIds);
      for (final id in e.splitWithMemberIds) {
        _customCtrls[id] = TextEditingController(
          text: _fmt(e.amount * (fractions[id] ?? 0)),
        );
      }
    }
    _receiptB64 = e.receiptImageBase64;
  }

  static String _fmt(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  void dispose() {
    _assistTimer?.cancel();
    _title.dispose();
    _amount.dispose();
    _note.dispose();
    for (final c in _customCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Restarts the idle timer; when it fires, a lightweight local classifier
  /// picks the best category for the typed title.
  void _scheduleAssist() {
    _assistTimer?.cancel();
    _assistTicket++; // an answer for older text must never apply
    if (_categoryLocked) return;
    _assistTimer = Timer(kCategoryAssistDebounce, _runAssist);
  }

  int _assistTicket = 0;

  /// Asks [HybridAiService.suggestCategory] (`PREFER_ON_DEVICE`: Gemini Nano
  /// first, cloud only if needed, offline keywords as the last resort).
  Future<void> _runAssist() async {
    if (!mounted || _categoryLocked) return;
    final text = _title.text.trim();
    if (text.isEmpty) return;
    final ticket = ++_assistTicket;

    ExpenseCategory best;
    try {
      best = await ProviderScope.containerOf(
        context,
        listen: false,
      ).read(hybridAiServiceProvider).suggestCategory(text);
    } catch (_) {
      best = ExpenseCategory.fromString(text);
    }
    // Typing, a hand-picked category or closing the sheet cancels the answer.
    if (!mounted ||
        _categoryLocked ||
        ticket != _assistTicket ||
        _title.text.trim() != text) {
      return;
    }
    // "Miscellaneous" means no match: stay quiet instead of guessing.
    if (best == ExpenseCategory.MISC || best == _category) return;
    setState(() {
      _category = best;
      _suggested = best;
      _suggestionTick++;
    });
  }

  double? get _typedAmount =>
      double.tryParse(_amount.text.replaceAll(',', '').trim());

  double? _customValue(String id) => double.tryParse(
    (_customCtrls[id]?.text ?? '').replaceAll(',', '').trim(),
  );

  /// Sum of the per-person amounts (custom mode only).
  double get _customTotal => _split.fold(
    0.0,
    (sum, id) => sum + ((_customValue(id) ?? 0) > 0 ? _customValue(id)! : 0),
  );

  /// The expense total: the typed amount, or the sum of custom amounts.
  double? get _parsedAmount => _custom ? _customTotal : _typedAmount;

  /// Switches between equal and custom split. Custom mode is pre-filled with
  /// the current equal share so the total never jumps.
  void _setCustom(bool value) {
    if (value == _custom) return;
    setState(() {
      _error = null;
      _custom = value;
      if (value) {
        final total = _typedAmount ?? 0;
        final each = _split.isEmpty ? 0.0 : total / _split.length;
        for (final id in _split) {
          _customCtrls.putIfAbsent(
            id,
            () => TextEditingController(
              text: each > 0 ? _fmt(double.parse(each.toStringAsFixed(2))) : '',
            ),
          );
        }
      } else {
        final total = _customTotal;
        if (total > 0) _amount.text = _fmt(total);
      }
    });
  }

  void _toggleMember(String id, bool on) {
    setState(() {
      _error = null;
      if (on) {
        _split.add(id);
        _customCtrls.putIfAbsent(id, () => TextEditingController());
      } else {
        _split.remove(id);
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _when,
      builder: pockoPickerBuilder,
      // Any date is allowed, including Pre-Trip dates before the trip starts.
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 366)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _when = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _when.hour,
        _when.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
      builder: pockoPickerBuilder,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _when = DateTime(
        _when.year,
        _when.month,
        _when.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  void _save() {
    final amount = _parsedAmount;
    Map<String, double>? customSplits;
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Give this expense a short title.');
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return;
    }
    if (_split.isEmpty) {
      setState(() => _error = 'Pick at least one person to split with.');
      return;
    }
    if (_custom && _split.length >= 2) {
      final entries = <String, double>{};
      for (final id in _split) {
        final v = _customValue(id);
        if (v == null || v <= 0) {
          setState(() => _error = 'Enter an amount for every person.');
          return;
        }
        entries[id] = v;
      }
      customSplits = entries;
    }
    Navigator.pop(
      context,
      widget.expense.copyWith(
        title: _title.text.trim(),
        amount: amount,
        customSplits: customSplits,
        clearCustomSplits: customSplits == null,
        receiptImageBase64: _receiptB64,
        clearReceipt: _receiptB64 == null,
        currency: _currency,
        category: _category,
        payerId: _payerId,
        splitWithMemberIds: _split.toList(),
        // The original prompt is never lost: it stays first, the user's own
        // note follows on the next line.
        note: _rawPrompt != null
            ? RawPromptNote.compose(_rawPrompt!, extra: _note.text)
            : (_note.text.trim().isEmpty ? null : _note.text.trim()),
        createdAt: _when,
      ),
    );
  }

  /// Tiny Pocko + "Pocko suggested Meals" with a gentle bounce.
  Widget _suggestionBadge(ExpenseCategory c) {
    return TweenAnimationBuilder<double>(
      key: ValueKey('pocko_suggestion_$_suggestionTick'),
      tween: Tween<double>(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.elasticOut,
      builder: (context, scale, child) => Transform.scale(
        scale: scale,
        alignment: Alignment.centerLeft,
        child: child,
      ),
      child: Container(
        key: const ValueKey('pocko_suggestion'),
        padding: const EdgeInsets.fromLTRB(4, 2, 10, 2),
        decoration: BoxDecoration(
          color: AppTheme.primaryEmeraldLight,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: AppTheme.primaryEmerald.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PockoMascot(
              size: 22,
              animate: false,
              enableEntranceAnimation: false,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                'Pocko suggested ${c.displayName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primaryEmeraldDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
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

  /// Pill-shaped tappable value (date / time).
  Widget _pill({
    required Key key,
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFFF1F5F9),
      shape: const StadiumBorder(
        side: BorderSide(color: AppTheme.borderColor, width: 2),
      ),
      child: InkWell(
        key: key,
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: AppTheme.primaryEmeraldDark),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
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

  /// Equal Split / Custom Amounts segmented toggle.
  Widget _splitModeToggle() {
    Widget seg(String label, bool value, Key key) {
      final active = _custom == value;
      return Expanded(
        child: GestureDetector(
          key: key,
          behavior: HitTestBehavior.opaque,
          onTap: () => _setCustom(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: ShapeDecoration(
              color: active ? Colors.white : Colors.transparent,
              shape: const StadiumBorder(),
              shadows: active
                  ? const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: active
                    ? AppTheme.primaryEmeraldDark
                    : AppTheme.textSlate,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      key: const ValueKey('split_mode_toggle'),
      padding: const EdgeInsets.all(4),
      decoration: const ShapeDecoration(
        color: Color(0xFFF1F5F9),
        shape: StadiumBorder(),
      ),
      child: Row(
        children: [
          seg('Equal Split', false, const ValueKey('split_mode_equal')),
          seg('Custom Amounts', true, const ValueKey('split_mode_custom')),
        ],
      ),
    );
  }

  Widget _customRows(List<dynamic> members) {
    return Column(
      key: const ValueKey('custom_split_rows'),
      children: [
        for (final m in members)
          if (_split.contains(m.id))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.tripState.displayName(m),
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textDark,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 130,
                    child: TextField(
                      key: ValueKey('custom_amount_${m.id}'),
                      controller: _customCtrls[m.id],
                      textAlign: TextAlign.end,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: AppTheme.tabularNumberStyle(fontSize: 15),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: '0',
                        prefixText: '${CurrencyHelper.symbol(_currency)} ',
                      ),
                      onChanged: (_) => setState(() => _error = null),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final members = widget.tripState.trip.members;
    final amount = _parsedAmount ?? 0;
    final perPerson = _split.isEmpty ? 0.0 : amount / _split.length;
    final currencies = {
      ...CurrencyHelper.currencyNames.keys,
      _currency,
    }.toList();
    final selectedNames = [
      for (final m in members)
        if (_split.contains(m.id)) widget.tripState.displayName(m),
    ];

    return Padding(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.isNew ? 'Add Expense' : 'Edit Details & Splits',
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
            const SizedBox(height: 8),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Expense Title'),
              onChanged: (_) {
                setState(() => _error = null);
                _scheduleAssist();
              },
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('editor_amount'),
              controller: _amount,
              readOnly: _custom,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: AppTheme.tabularNumberStyle(fontSize: 16),
              decoration: InputDecoration(
                labelText: 'Amount',
                helperText: _custom
                    ? 'Total of the custom amounts below'
                    : null,
                // The currency lives inside the field, as a pill prefix.
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 8, right: 6),
                  child: PockoSelector<String>(
                    key: const ValueKey('editor_currency'),
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
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _pill(
                    key: const ValueKey('editor_date'),
                    icon: Icons.calendar_today_rounded,
                    text: DateFormat('EEE, MMM d, y').format(_when),
                    onTap: _pickDate,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: _pill(
                    key: const ValueKey('editor_time'),
                    icon: Icons.schedule_rounded,
                    text: DateFormat('HH:mm').format(_when),
                    onTap: _pickTime,
                  ),
                ),
              ],
            ),
            if (_when.isBefore(startOfDay(widget.tripState.trip.startDate)))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Pre-Trip expense (before the trip starts)',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryEmeraldDark,
                  ),
                ),
              ),
            const SizedBox(height: 14),
            Row(
              children: [
                _label('CATEGORY'),
                const SizedBox(width: 8),
                if (_suggested != null && !_categoryLocked)
                  Flexible(child: _suggestionBadge(_suggested!)),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: PockoSelector<ExpenseCategory>(
                key: const ValueKey('editor_category'),
                label: _category.displayName,
                leadingIcon: _category.icon,
                leadingColor: _category.accentColor,
                onDark: false,
                selected: _category,
                tooltip: 'Category',
                entries: [
                  for (final cat in ExpenseCategory.values)
                    PockoMenuEntry<ExpenseCategory>(
                      value: cat,
                      label: cat.displayName,
                      icon: cat.icon,
                      accent: cat.accentColor,
                      pastel: cat.pastelColor,
                    ),
                ],
                onSelected: (cat) => setState(() {
                  // A deliberate choice locks the category for good.
                  _category = cat;
                  _categoryLocked = true;
                  _suggested = null;
                  _assistTimer?.cancel();
                }),
              ),
            ),
            const SizedBox(height: 14),
            _label('PAID BY'),
            Align(
              alignment: Alignment.centerLeft,
              child: PockoSelector<String>(
                key: const ValueKey('editor_payer'),
                label: widget.tripState.nameOf(_payerId),
                leadingIcon: Icons.account_circle_rounded,
                onDark: false,
                selected: _payerId,
                tooltip: 'Paid by',
                entries: [
                  for (final m in members)
                    PockoMenuEntry<String>(
                      value: m.id,
                      label: widget.tripState.displayName(m),
                      icon: Icons.person_rounded,
                    ),
                ],
                onSelected: (id) => setState(() => _payerId = id),
              ),
            ),
            const SizedBox(height: 14),
            PhotoAttachmentField(
              title: 'Receipt / Slip Photo',
              base64: _receiptB64,
              onChanged: (v) => setState(() => _receiptB64 = v),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _label('SPLIT WITH')),
                TextButton(
                  onPressed: () => setState(() {
                    _error = null;
                    if (_split.length == members.length) {
                      _split = {_payerId};
                    } else {
                      for (final m in members) {
                        _split.add(m.id);
                        _customCtrls.putIfAbsent(
                          m.id,
                          () => TextEditingController(),
                        );
                      }
                    }
                  }),
                  child: Text(
                    _split.length == members.length
                        ? 'Only payer'
                        : 'Select all',
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: members.map((m) {
                final on = _split.contains(m.id);
                // Fully rounded stadium pill, like every other Pocko button.
                return FilterChip(
                  key: ValueKey('split_member_${m.id}'),
                  label: Text(widget.tripState.displayName(m)),
                  selected: on,
                  shape: StadiumBorder(
                    side: BorderSide(
                      color: on
                          ? AppTheme.primaryEmerald
                          : AppTheme.borderColor,
                      width: 2,
                    ),
                  ),
                  backgroundColor: const Color(0xFFF1F5F9),
                  selectedColor: AppTheme.primaryEmeraldSubtle,
                  checkmarkColor: AppTheme.primaryEmeraldDark,
                  labelStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: on ? AppTheme.primaryEmeraldDark : AppTheme.textDark,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                  onSelected: (val) => _toggleMember(m.id, val),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            _splitModeToggle(),
            const SizedBox(height: 12),
            if (_custom) _customRows(members),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Container(
                key: ValueKey(
                  '${_custom}_${_split.length}_${amount.toStringAsFixed(2)}_$_currency',
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primaryEmeraldSubtle,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.pie_chart_rounded,
                      size: 16,
                      color: AppTheme.primaryEmeraldDark,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _split.isEmpty
                            ? 'Nobody selected'
                            : _custom
                            ? 'Total ${CurrencyHelper.formatAmount(amount, _currency)} • '
                                  '${formatSelectedNames(selectedNames)}'
                            : '${CurrencyHelper.formatAmount(perPerson, _currency)} each • '
                                  '${formatSelectedNames(selectedNames)}',
                        key: const ValueKey('split_summary'),
                        style: AppTheme.tabularNumberStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryEmeraldDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            if (_rawPrompt != null) ...[
              const SizedBox(height: 12),
              Container(
                key: const ValueKey('raw_prompt_card'),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F3FF),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFDDD6FE)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.record_voice_over_rounded,
                      size: 18,
                      color: Color(0xFF7C3AED),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ORIGINAL VOICE / TEXT PROMPT',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                              color: const Color(0xFF7C3AED),
                            ),
                          ),
                          const SizedBox(height: 3),
                          SelectableText(
                            _rawPrompt!,
                            key: const ValueKey('raw_prompt_text'),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                              color: AppTheme.textSlate,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.coralOwesText,
                ),
              ),
            ],
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(widget.isNew ? 'Add Expense' : 'Save Changes'),
            ),
            if (widget.onDelete != null) ...[
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onDelete!();
                },
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppTheme.coralOwesText,
                  size: 18,
                ),
                label: Text(
                  'Delete expense',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.coralOwesText,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
