import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/pocko_bottom_sheet.dart';
import '../../core/widgets/pocko_snack.dart';
import '../trip/trip_controller.dart';

/// Opens the rename sheet for [memberId]. Works at any time, before or after
/// the group has expenses: only the display name changes, never the member's
/// id, so every bill, split and repayment keeps pointing at the same person.
Future<bool?> showRenameMemberSheet(BuildContext context, String memberId) {
  return showPockoBottomSheet<bool>(
    context: context,
    builder: (_) => _RenameForm(memberId: memberId),
  );
}

class _RenameForm extends ConsumerStatefulWidget {
  final String memberId;
  const _RenameForm({required this.memberId});

  @override
  ConsumerState<_RenameForm> createState() => _RenameFormState();
}

class _RenameFormState extends ConsumerState<_RenameForm> {
  late final TextEditingController _name;
  String? _error;

  @override
  void initState() {
    super.initState();
    final state = ref.read(tripControllerProvider);
    final m = state.memberById(widget.memberId);
    // A device's own "You" is the default name: start empty so typing is quick.
    final current = m?.name ?? '';
    _name = TextEditingController(
      text: current.toLowerCase() == 'you' ? '' : current,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final error = ref
        .read(tripControllerProvider.notifier)
        .renameMember(widget.memberId, _name.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final nav = Navigator.of(context);
    nav.pop(true);
    showPockoSnack(
      nav.context,
      'Renamed to ${_name.text.trim()}',
      detail:
          'Every bill and balance shows the new name. Amounts are unchanged.',
      icon: Icons.badge_rounded,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tripControllerProvider);
    final isSelf = widget.memberId == state.currentMemberId;
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
                  isSelf ? 'Your display name' : 'Rename traveler',
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
                onPressed: () => Navigator.pop(context, false),
              ),
            ],
          ),
          Text(
            'Friends see this name on every bill. Renaming never changes any amount or who paid.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12.5,
              height: 1.4,
              color: AppTheme.textSlate,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            key: const ValueKey('rename_field'),
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            maxLength: TripController.maxNameLength,
            onSubmitted: (_) => _save(),
            onChanged: (_) => setState(() => _error = null),
            decoration: InputDecoration(
              labelText: 'Name',
              counterText: '',
              errorText: _error,
              errorMaxLines: 3,
              prefixIcon: const Icon(
                Icons.person_rounded,
                color: AppTheme.primaryEmerald,
              ),
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            key: const ValueKey('rename_save_button'),
            onPressed: _save,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Save name'),
          ),
        ],
      ),
    );
  }
}
