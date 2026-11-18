import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/pocko_bottom_sheet.dart';
import '../onboarding/onboarding_screen.dart';
import '../squad/join_group_sheet.dart';
import 'trip_controller.dart';

/// Opens the standard "create a trip" wizard (the Landing's setup page) as a
/// full-screen route; finishing it returns to the shell.
void openCreateTripWizard(BuildContext context) {
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

/// Guard for every "add something to the trip" trigger (voice capture, receipt
/// scan, Add Expense). Returns `true` when a trip exists. With no trip yet it
/// shows a friendly "create or join a trip first" prompt instead of opening a
/// flow that would need a trip, so nothing can ever run on a missing trip or
/// currency context.
bool ensureTrip(BuildContext context, WidgetRef ref) {
  if (ref.read(tripControllerProvider).hasTrip) return true;
  showPockoBottomSheet<void>(
    context: context,
    builder: (ctx) => Padding(
      key: const ValueKey('need_trip_sheet'),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Create or join a trip first',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Expenses and receipts belong to a trip. Start one, or join your friends\' group with a code.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              height: 1.4,
              color: AppTheme.textSlate,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            key: const ValueKey('need_trip_create'),
            onPressed: () {
              Navigator.pop(ctx);
              openCreateTripWizard(context);
            },
            icon: const Icon(Icons.flight_takeoff_rounded, size: 18),
            label: const Text('Create a New Trip'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('need_trip_join'),
            onPressed: () {
              Navigator.pop(ctx);
              showJoinGroupSheet(context);
            },
            icon: const Icon(Icons.group_add_rounded, size: 18),
            label: const Text('Join Existing Group'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: const StadiumBorder(),
            ),
          ),
        ],
      ),
    ),
  );
  return false;
}
