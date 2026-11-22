import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_helper.dart';
import '../../core/widgets/pocko_mascot.dart';
import '../../core/widgets/pocko_bottom_sheet.dart';
import '../../core/widgets/pocko_snack.dart';
import '../../core/widgets/tactile.dart';
import '../onboarding/onboarding_screen.dart';
import '../trip/trip_controller.dart';
import 'join_group_sheet.dart';
import 'rename_member_sheet.dart';
import '../trip/trip_permissions.dart';
import '../trip/trip_state.dart';

class SquadSetupScreen extends ConsumerStatefulWidget {
  final VoidCallback onLaunchCanvas;

  const SquadSetupScreen({super.key, required this.onLaunchCanvas});

  @override
  ConsumerState<SquadSetupScreen> createState() => _SquadSetupScreenState();
}

class _SquadSetupScreenState extends ConsumerState<SquadSetupScreen> {
  RoundedRectangleBorder get _dialogShape =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(24));

  void _showAddMemberDialog(BuildContext context) {
    final controller = TextEditingController();
    String? error;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void submit() {
            final name = controller.text.trim();
            if (name.isEmpty) {
              setDialogState(() => error = 'Enter a name');
              return;
            }
            final added = ref
                .read(tripControllerProvider.notifier)
                .addMember(name);
            if (!added) {
              setDialogState(() => error = '$name is already in the group');
              return;
            }
            Navigator.pop(ctx);
            showPockoSnack(context, '$name joined the group');
          }

          return AlertDialog(
            shape: _dialogShape,
            title: Text(
              'Add Group Member',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => submit(),
              onChanged: (_) => setDialogState(() => error = null),
              decoration: InputDecoration(
                hintText: 'Enter friend name (e.g. Nan, Ken)',
                errorText: error,
                prefixIcon: const Icon(
                  Icons.person_add_rounded,
                  color: AppTheme.primaryEmerald,
                ),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: submit,
                child: const Text('Add Friend'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditTripNameDialog(BuildContext context, String currentName) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: _dialogShape,
        title: Text(
          'Edit Trip Name',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            hintText: 'Trip name',
            prefixIcon: Icon(
              Icons.flight_takeoff_rounded,
              color: AppTheme.primaryEmerald,
            ),
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
              if (name.isNotEmpty) {
                ref.read(tripControllerProvider.notifier).updateTripName(name);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showCurrencySelector(BuildContext context, String currentCurrency) {
    showPockoBottomSheet<void>(
      context: context,
      scrollable: false,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          children: [
            Text(
              'Select Base Currency',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Every total, balance and transfer converts at approximate travel rates. Expenses keep their own currency.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                height: 1.4,
                color: AppTheme.textSlate,
              ),
            ),
            const SizedBox(height: 12),
            for (final entry in CurrencyHelper.currencyNames.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  tileColor: entry.key == currentCurrency
                      ? AppTheme.primaryEmeraldSubtle
                      : Colors.transparent,
                  title: Text(
                    '${entry.value} (${CurrencyHelper.symbol(entry.key).trim()})',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: entry.key == currentCurrency
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: entry.key == currentCurrency
                          ? AppTheme.primaryEmeraldDark
                          : AppTheme.textDark,
                    ),
                  ),
                  trailing: entry.key == currentCurrency
                      ? const Icon(
                          Icons.check_circle_rounded,
                          color: AppTheme.primaryEmerald,
                        )
                      : null,
                  onTap: () {
                    ref
                        .read(tripControllerProvider.notifier)
                        .updateBaseCurrency(entry.key);
                    Navigator.pop(ctx);
                    showPockoSnack(
                      context,
                      'Base currency is now ${entry.key}. All totals recalculated.',
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _removeMember(BuildContext context, String memberId) {
    final error = ref
        .read(tripControllerProvider.notifier)
        .removeMember(memberId);
    if (error != null) showPockoSnack(context, error, success: false);
  }

  /// Opens the Landing / Setup Wizard straight on the setup card; finishing
  /// it returns to the shell, which switches to Home for the new trip.
  void _openSetupWizard() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (ctx) => OnboardingScreen(
          startAtSetup: true,
          onDone: () => Navigator.of(ctx).popUntil((r) => r.isFirst),
        ),
      ),
    );
  }

  void _loadDemoTrip() {
    ref.read(tripControllerProvider.notifier).loadDemoTrip();
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final tripState = ref.watch(tripControllerProvider);
    final perms = ref.watch(tripPermissionsProvider);
    final trip = tripState.trip;
    final syncLive = tripState.syncStatus == SyncStatus.live;
    final syncColor = syncLive
        ? AppTheme.primaryEmerald
        : (tripState.syncStatus == SyncStatus.connecting
              ? const Color(0xFFF59E0B)
              : AppTheme.textMuted);

    return Scaffold(
      backgroundColor: AppTheme.canvasBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Navigator.canPop(context)
            ? IconButton(
                tooltip: 'Back',
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: AppTheme.textDark,
                ),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: Text(
          'Group & Settings',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: AppTheme.textDark,
          ),
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Peach to Mint Gradient Hero Card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: AppTheme.peachToMintGradient,
                    borderRadius: AppTheme.cardRadius,
                    boxShadow: AppTheme.elevatedCardShadow,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Tactile(
                              onTap: () =>
                                  _showEditTripNameDialog(context, trip.name),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  borderRadius: AppTheme.pillRadius,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        '${trip.name} • ${trip.baseCurrency}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.textDark,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Icon(
                                      Icons.edit_rounded,
                                      size: 14,
                                      color: AppTheme.textSlate,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Group Ready\nfor Adventure!',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                height: 1.15,
                                color: AppTheme.textDark,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryEmerald.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: AppTheme.pillRadius,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.calendar_today_rounded,
                                    size: 12,
                                    color: AppTheme.primaryEmeraldDark,
                                  ),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text(
                                      tripState.dateRange,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.primaryEmeraldDark,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      PockoMascot(
                        size: PockoSizes.header(context),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // 2. Travel Group Card
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: AppTheme.surfaceDecoration(radius: 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: const BoxDecoration(
                                    color: AppTheme.primaryEmeraldSubtle,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.group_rounded,
                                    color: AppTheme.primaryEmerald,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Text(
                                    'Travel Group',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.textDark,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryEmeraldLight,
                                    borderRadius: AppTheme.pillRadius,
                                  ),
                                  child: Text(
                                    '${trip.members.length}',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.primaryEmeraldDark,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Tactile(
                            onTap: () => _showAddMemberDialog(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryEmeraldSubtle,
                                borderRadius: AppTheme.pillRadius,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.add_rounded,
                                    size: 16,
                                    color: AppTheme.primaryEmerald,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Add',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.primaryEmeraldDark,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 12,
                        runSpacing: 14,
                        children: trip.members.map((member) {
                          final isMe = member.id == tripState.currentMemberId;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isMe
                                  ? AppTheme.primaryEmeraldSubtle
                                  : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isMe
                                    ? AppTheme.primaryEmerald.withValues(
                                        alpha: 0.3,
                                      )
                                    : AppTheme.borderColor,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: isMe
                                      ? AppTheme.primaryEmerald
                                      : const Color(0xFFE2E8F0),
                                  child: Text(
                                    member.name.isNotEmpty
                                        ? member.name[0].toUpperCase()
                                        : '?',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: isMe
                                          ? Colors.white
                                          : AppTheme.textSlate,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      tripState.displayName(member),
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.textDark,
                                      ),
                                    ),
                                    if (member.id == perms.hostMemberId)
                                      Container(
                                        key: const ValueKey('host_badge'),
                                        margin: const EdgeInsets.only(
                                          bottom: 3,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFEF3C7),
                                          borderRadius: AppTheme.pillRadius,
                                        ),
                                        child: Text(
                                          '👑 Host',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            color: const Color(0xFFB45309),
                                          ),
                                        ),
                                      ),
                                    Text(
                                      isMe
                                          ? (member.name.toLowerCase() == 'you'
                                                ? 'This device'
                                                : 'This device • ${member.name}')
                                          : 'Active',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: isMe
                                            ? AppTheme.primaryEmeraldDark
                                            : AppTheme.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                                if (isMe || perms.canRemoveMembers)
                                  IconButton(
                                    key: ValueKey('rename_${member.id}'),
                                    tooltip: isMe
                                        ? 'Change your name'
                                        : 'Rename ${member.name}',
                                    visualDensity: VisualDensity.compact,
                                    constraints: const BoxConstraints(
                                      minWidth: 32,
                                      minHeight: 32,
                                    ),
                                    padding: EdgeInsets.zero,
                                    icon: const Icon(
                                      Icons.edit_rounded,
                                      size: 15,
                                      color: AppTheme.textMuted,
                                    ),
                                    onPressed: () => showRenameMemberSheet(
                                      context,
                                      member.id,
                                    ),
                                  ),
                                if (!isMe && perms.canRemoveMembers) ...[
                                  const SizedBox(width: 6),
                                  IconButton(
                                    tooltip: 'Remove ${member.name}',
                                    visualDensity: VisualDensity.compact,
                                    constraints: const BoxConstraints(
                                      minWidth: 32,
                                      minHeight: 32,
                                    ),
                                    padding: EdgeInsets.zero,
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 16,
                                      color: AppTheme.textMuted,
                                    ),
                                    onPressed: () =>
                                        _removeMember(context, member.id),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                      if (!perms.isLegacy) ...[
                        const SizedBox(height: 14),
                        _GuestEditsLock(
                          isHost: perms.isHost,
                          locked: trip.lockGuestEdits,
                          onChanged: (v) => ref
                              .read(tripControllerProvider.notifier)
                              .setLockGuestEdits(v),
                        ),
                      ],
                      const SizedBox(height: 18),
                      const Divider(height: 1, color: AppTheme.borderColor),
                      const SizedBox(height: 16),

                      // Invite & Group Code
                      Row(
                        children: [
                          Expanded(
                            child: Tactile(
                              onTap: () {
                                Clipboard.setData(
                                  ClipboardData(text: tripState.squadCode),
                                );
                                showPockoSnack(
                                  context,
                                  'Group Code ${tripState.squadCode} copied to clipboard',
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.qr_code_2_rounded,
                                      size: 18,
                                      color: AppTheme.textSlate,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Group Code',
                                            style: GoogleFonts.plusJakartaSans(
                                              fontSize: 10,
                                              color: AppTheme.textMuted,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            tripState.squadCode,
                                            style: AppTheme.tabularNumberStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(
                                      Icons.copy_rounded,
                                      size: 16,
                                      color: AppTheme.primaryEmerald,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(
                                  text:
                                      'Join my Pocko trip "${trip.name}": ${squadInviteLink(tripState.squadCode)} (group code ${tripState.squadCode})',
                                ),
                              );
                              showPockoSnack(
                                context,
                                'Invite message copied. Share it with your friends.',
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                            icon: const Icon(Icons.share_rounded, size: 16),
                            label: const Text('Invite'),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Live sync status & Join Group
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: syncLive
                              ? AppTheme.primaryEmeraldSubtle
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: syncColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: syncColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                tripState.syncStatus.label,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: syncLive
                                      ? AppTheme.primaryEmeraldDark
                                      : AppTheme.textSlate,
                                ),
                              ),
                            ),
                            Tactile(
                              onTap: () => showJoinGroupSheet(context),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: AppTheme.primaryEmerald.withValues(
                                      alpha: 0.3,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.hub_rounded,
                                      size: 13,
                                      color: AppTheme.primaryEmerald,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Join Group',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.primaryEmeraldDark,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // 3. Trip parameter cards (all live)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _StatCard(
                        icon: Icons.pie_chart_rounded,
                        iconColor: const Color(0xFF6366F1),
                        label: 'Per person',
                        value: CurrencyHelper.formatAmount(
                          tripState.perPersonSpend,
                          trip.baseCurrency,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatCard(
                        icon: Icons.currency_exchange_rounded,
                        iconColor: const Color(0xFFF59E0B),
                        label: 'Currency',
                        value: trip.baseCurrency,
                        onTap: () =>
                            _showCurrencySelector(context, trip.baseCurrency),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatCard(
                        icon: Icons.auto_awesome_rounded,
                        iconColor: AppTheme.primaryEmerald,
                        label: 'AI Matcher',
                        value: tripState.isAiMatcherActive
                            ? 'Active'
                            : 'Paused',
                        valueColor: tripState.isAiMatcherActive
                            ? AppTheme.primaryEmeraldDark
                            : AppTheme.textMuted,
                        onTap: () => ref
                            .read(tripControllerProvider.notifier)
                            .setAiMatcherActive(!tripState.isAiMatcherActive),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Start over: guided wizard or the pre-loaded Tokyo demo.
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: AppTheme.surfaceDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'START A DIFFERENT TRIP',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.9,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        key: const ValueKey('new_trip_wizard_button'),
                        onPressed: _openSetupWizard,
                        icon: const Icon(Icons.add_location_alt_rounded),
                        label: const Text('New Trip / Setup Wizard'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: AppTheme.pillRadius,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextButton.icon(
                        key: const ValueKey('group_demo_trip_button'),
                        onPressed: _loadDemoTrip,
                        icon: const Icon(Icons.rocket_launch_rounded, size: 18),
                        label: const Text('Try Tokyo Demo Trip'),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                Container(
                  decoration: BoxDecoration(
                    borderRadius: AppTheme.pillRadius,
                    boxShadow: AppTheme.emeraldGlowShadow,
                  ),
                  child: ElevatedButton(
                    onPressed: widget.onLaunchCanvas,
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
                        Flexible(
                          child: Text(
                            'Launch Trip Canvas',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ],
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

/// Host-only "Lock Guest Edits" switch; guests see the current state.
class _GuestEditsLock extends StatelessWidget {
  final bool isHost;
  final bool locked;
  final ValueChanged<bool> onChanged;

  const _GuestEditsLock({
    required this.isHost,
    required this.locked,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('guest_lock_tile'),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: locked ? const Color(0xFFFEF3C7) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: locked ? const Color(0xFFFCD34D) : AppTheme.borderColor,
        ),
      ),
      child: Row(
        children: [
          Icon(
            locked ? Icons.lock_rounded : Icons.lock_open_rounded,
            size: 20,
            color: locked ? const Color(0xFFB45309) : AppTheme.textSlate,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lock Guest Edits',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                ),
                Text(
                  isHost
                      ? 'Guests can still add entries, but cannot edit or delete any.'
                      : locked
                      ? 'The Trip Host has locked guest edits.'
                      : 'Guests can edit or delete only the entries they created.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    height: 1.3,
                    color: AppTheme.textSlate,
                  ),
                ),
              ],
            ),
          ),
          if (isHost)
            Switch(
              key: const ValueKey('guest_lock_switch'),
              value: locked,
              activeThumbColor: AppTheme.primaryEmeraldDark,
              onChanged: onChanged,
            ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final Color? valueColor;
  final VoidCallback? onTap;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.valueColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tactile(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.surfaceDecoration(radius: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: AppTheme.tabularNumberStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: valueColor ?? AppTheme.textDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
