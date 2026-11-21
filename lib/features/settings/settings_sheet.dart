import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/pocko_bottom_sheet.dart';
import '../../core/widgets/pocko_snack.dart';
import '../../services/hybrid_ai/hybrid_ai_service.dart';
import '../../services/session/session_store.dart';
import '../onboarding/onboarding_screen.dart';
import '../squad/join_group_sheet.dart';
import '../squad/rename_member_sheet.dart';
import '../trip/trip_controller.dart';

/// App settings: your display name, joining or creating a trip, and the
/// demo-safe "Replay Landing Page".
Future<void> showSettingsSheet(BuildContext context) {
  return showPockoBottomSheet<void>(
    context: context,
    builder: (_) => const _SettingsBody(),
  );
}

class _SettingsBody extends ConsumerWidget {
  const _SettingsBody();

  Widget _tile({
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return Material(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.primaryEmeraldSubtle,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: iconColor ?? AppTheme.primaryEmeraldDark,
                ),
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
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textDark,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5,
                        height: 1.3,
                        color: AppTheme.textSlate,
                      ),
                    ),
                  ],
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
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tripControllerProvider);
    final me = state.memberById(state.currentMemberId);
    final myName = (me == null || me.name.toLowerCase() == 'you')
        ? (ref.watch(sessionStoreProvider)?.displayName)
        : me.name;

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
                  'Settings',
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
          const SizedBox(height: 6),
          _tile(
            key: const ValueKey('settings_display_name'),
            icon: Icons.badge_rounded,
            title: 'Your display name',
            subtitle: myName == null || myName.isEmpty
                ? 'Not set yet. Friends see this name on every bill.'
                : '$myName • change it any time, even after joining',
            onTap: () {
              if (state.hasTrip && me != null) {
                showRenameMemberSheet(context, me.id);
              } else {
                _editSavedName(context, ref);
              }
            },
          ),
          const SizedBox(height: 10),
          _tile(
            key: const ValueKey('settings_join_group'),
            icon: Icons.group_add_rounded,
            title: 'Join a Group',
            subtitle: 'Enter a 6-digit code or paste an invite link.',
            onTap: () async {
              final nav = Navigator.of(context);
              nav.pop();
              await showJoinGroupSheet(nav.context);
            },
          ),
          const SizedBox(height: 10),
          _tile(
            key: const ValueKey('settings_new_trip'),
            icon: Icons.flight_takeoff_rounded,
            title: 'Create a New Trip',
            subtitle: 'Start a fresh trip with its own group code.',
            onTap: () {
              final nav = Navigator.of(context);
              nav.pop();
              nav.push(
                MaterialPageRoute<void>(
                  fullscreenDialog: true,
                  builder: (ctx) => OnboardingScreen(
                    startAtSetup: true,
                    onDone: () => Navigator.of(ctx).popUntil((r) => r.isFirst),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          const OnDeviceAiTile(),
          const SizedBox(height: 22),
          Align(
            alignment: Alignment.center,
            child: TextButton.icon(
              key: const ValueKey('settings_replay_landing'),
              onPressed: () {
                Navigator.pop(context);
                ref.read(onboardingCompleteProvider.notifier).replay();
              },
              icon: const Icon(Icons.replay_rounded, size: 16),
              label: const Text('Replay Landing Page'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.textSlate,
                textStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Text(
            'Shows the intro again for a clean demo take. Your trip, local data, sign-in and App Check token are kept.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              height: 1.35,
              color: AppTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  /// No trip yet: remember the name for the next group the user joins.
  void _editSavedName(BuildContext context, WidgetRef ref) {
    final store = ref.read(sessionStoreProvider);
    final controller = TextEditingController(text: store?.displayName ?? '');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Your display name'),
        content: TextField(
          key: const ValueKey('saved_name_field'),
          controller: controller,
          autofocus: true,
          maxLength: TripController.maxNameLength,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'e.g. Pong',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) store?.setDisplayName(name);
              Navigator.pop(ctx);
              if (name.isNotEmpty) {
                showPockoSnack(context, 'Saved. Used when you join a group.');
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

/// "On-device AI (Gemini Nano)": download status and a one-time download button
/// on Android phones with AICore. Hidden where there is nothing to manage.
class OnDeviceAiTile extends ConsumerStatefulWidget {
  const OnDeviceAiTile({super.key});

  @override
  ConsumerState<OnDeviceAiTile> createState() => _OnDeviceAiTileState();
}

class _OnDeviceAiTileState extends ConsumerState<OnDeviceAiTile> {
  OnDeviceAiStatus? _status;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final s = await ref.read(hybridAiServiceProvider).onDeviceStatus();
    if (!mounted) return;
    setState(() => _status = s);
    _poll?.cancel();
    if (s.isDownloading) {
      _poll = Timer(const Duration(seconds: 2), _refresh);
    }
  }

  Future<void> _download() async {
    setState(() => _status = const OnDeviceAiStatus('downloading'));
    await ref.read(hybridAiServiceProvider).downloadOnDeviceModel();
    _poll?.cancel();
    _poll = Timer(const Duration(seconds: 1), _refresh);
  }

  static String _mb(int bytes) => (bytes / 1048576).toStringAsFixed(0);

  @override
  Widget build(BuildContext context) {
    final s = _status;
    if (s == null || !s.isManageable) return const SizedBox.shrink();
    final String subtitle;
    if (s.isAvailable) {
      subtitle = 'Ready. Expenses can be read offline by Gemini Nano.';
    } else if (s.isDownloading) {
      subtitle = s.totalBytes > 0
          ? 'Downloading… ${_mb(s.downloadedBytes)} / ${_mb(s.totalBytes)} MB'
          : 'Downloading… keep the app open.';
    } else if (s.canDownload) {
      subtitle =
          'Not downloaded yet. Download it once (Wi-Fi recommended) to read '
          'expenses with no internet.';
    } else {
      subtitle =
          'Not available on this phone right now${s.error == null ? '' : ' (${s.error})'}.';
    }
    return Container(
      key: const ValueKey('settings_on_device_ai'),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        children: [
          Icon(
            s.isAvailable
                ? Icons.memory_rounded
                : Icons.download_for_offline_rounded,
            color: AppTheme.primaryEmeraldDark,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'On-device AI (Gemini Nano)',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: AppTheme.textSlate,
                  ),
                ),
              ],
            ),
          ),
          if (s.canDownload)
            FilledButton(
              key: const ValueKey('download_nano_button'),
              onPressed: _download,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryEmerald,
                minimumSize: const Size(0, 38),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: const Text('Download'),
            ),
          if (s.isDownloading)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
        ],
      ),
    );
  }
}
