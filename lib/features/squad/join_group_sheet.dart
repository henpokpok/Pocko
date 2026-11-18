import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/pocko_bottom_sheet.dart';
import '../../core/widgets/pocko_snack.dart';
import '../../services/session/session_store.dart';
import '../trip/trip_controller.dart';
import '../trip/trip_state.dart';

/// Opens the **Join Group** sheet: pick the name your friends will see, paste
/// the 6-digit code (or an invite link) and join. The same sheet is used from
/// the Landing Page, the empty Home, Settings and Manage Group.
///
/// Resolves `true` when a group was joined. The name can be changed later at
/// any time (Settings or Manage Group).
Future<bool?> showJoinGroupSheet(BuildContext context) {
  return showPockoBottomSheet<bool>(
    context: context,
    builder: (_) => const _JoinGroupForm(),
  );
}

class _JoinGroupForm extends ConsumerStatefulWidget {
  const _JoinGroupForm();

  @override
  ConsumerState<_JoinGroupForm> createState() => _JoinGroupFormState();
}

class _JoinGroupFormState extends ConsumerState<_JoinGroupForm> {
  late final TextEditingController _name;
  final TextEditingController _code = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: ref.read(sessionStoreProvider)?.displayName ?? '',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty) return;
    setState(() {
      _code.text = text.trim();
      _error = null;
    });
  }

  Future<void> _join() async {
    final code = normalizeSquadCode(_code.text);
    if (code == null) {
      setState(
        () => _error = 'Enter the 6-digit group code (e.g. 782-901) or paste the invite link.',
      );
      return;
    }
    final name = _name.text.trim();
    if (name.length > TripController.maxNameLength) {
      setState(
        () => _error =
            'Keep your name under ${TripController.maxNameLength} characters.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(tripControllerProvider.notifier)
        .joinSquad(code, displayName: name, createIfMissing: false);
    if (!mounted) return;
    switch (result) {
      case JoinSquadResult.joined:
        final who = ref
            .read(tripControllerProvider)
            .memberById(ref.read(tripControllerProvider).currentMemberId)
            ?.name;
        final messenger = Navigator.of(context);
        messenger.pop(true);
        showPockoSnack(
          messenger.context,
          'Joined group $code as ${who ?? 'a new traveler'}',
          detail: 'Your friends\' expenses are live. You can rename yourself any time.',
          icon: Icons.group_add_rounded,
        );
      case JoinSquadResult.notFound:
        setState(() {
          _busy = false;
          _error =
              'No group found with code $code. Check the code and your connection.';
        });
      case JoinSquadResult.offline:
        setState(() {
          _busy = false;
          _error = 'Group sync is not available on this build or connection.';
        });
      case JoinSquadResult.invalid:
        setState(() {
          _busy = false;
          _error = 'That is not a valid group code.';
        });
      case JoinSquadResult.created:
        // Never requested here; treated like a missing group.
        setState(() {
          _busy = false;
          _error = 'No group found with code $code.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  'Join a Group',
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
            'Pick the name your friends will see, then enter the group code from their device or paste the invite link.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12.5,
              height: 1.4,
              color: AppTheme.textSlate,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            key: const ValueKey('join_name_field'),
            controller: _name,
            textCapitalization: TextCapitalization.words,
            maxLength: TripController.maxNameLength,
            decoration: const InputDecoration(
              labelText: 'Your name',
              hintText: 'e.g. Pong',
              counterText: '',
              prefixIcon: Icon(
                Icons.person_rounded,
                color: AppTheme.primaryEmerald,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('join_code_field'),
            controller: _code,
            keyboardType: TextInputType.text,
            onSubmitted: (_) => _join(),
            onChanged: (_) => setState(() => _error = null),
            decoration: InputDecoration(
              labelText: 'Group code or invite link',
              hintText: '782-901',
              errorText: _error,
              errorMaxLines: 3,
              prefixIcon: const Icon(
                Icons.hub_rounded,
                color: AppTheme.primaryEmerald,
              ),
              suffixIcon: IconButton(
                key: const ValueKey('join_paste_button'),
                tooltip: 'Paste',
                icon: const Icon(Icons.content_paste_rounded),
                onPressed: _paste,
              ),
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            key: const ValueKey('join_submit_button'),
            onPressed: _busy ? null : _join,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : const Text('Join Group'),
          ),
        ],
      ),
    );
  }
}
