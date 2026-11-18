import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/adaptive_layout.dart';
import '../../core/widgets/pocko_mascot.dart';
import '../squad/join_group_sheet.dart';
import '../trip/date_filter.dart';
import '../trip/require_trip.dart';
import '../trip/trip_controller.dart';

/// Id of the upcoming trip the user chose to open from the placeholder Home.
/// Resets by itself: it only applies to that trip's id.
final openedUpcomingTripProvider =
    NotifierProvider<OpenedUpcomingTripNotifier, String?>(
      OpenedUpcomingTripNotifier.new,
    );

class OpenedUpcomingTripNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void open(String tripId) => state = tripId;
  void close() => state = null;
}

/// Home for a device with **no active trip**: a fresh install (no trip at all)
/// or only a trip that starts in the future. A calm, welcoming screen with two
/// clear actions, plus a quiet card for an upcoming trip.
class PlaceholderHome extends ConsumerWidget {
  const PlaceholderHome({super.key});

  static const double maxContentWidth = 520;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tripControllerProvider);
    final upcoming = state.isUpcoming;
    final trip = state.trip;
    final days = startOfDay(trip.startDate)
        .difference(startOfDay(DateTime.now()))
        .inDays;

    return TabScrollBody(
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxContentWidth),
            child: Column(
              key: const ValueKey('placeholder_home'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                  decoration: BoxDecoration(
                    gradient: AppTheme.mintToSkyGradient,
                    borderRadius: AppTheme.cardRadius,
                    boxShadow: AppTheme.elevatedCardShadow,
                  ),
                  child: Column(
                    children: [
                      PockoMascot(
                        mood: PockoMood.waving,
                        size: PockoSizes.hero(context),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        upcoming
                            ? 'Your trip is coming up'
                            : 'Ready for your next trip?',
                        key: const ValueKey('placeholder_title'),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        upcoming
                            ? 'Nothing is happening yet. Pocko will be here when it starts, or start another trip now.'
                            : 'Create a trip, or join your friends\' group with a code. Then just say what you spend.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13.5,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textSlate,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          key: const ValueKey('placeholder_create_trip'),
                          onPressed: () => openCreateTripWizard(context),
                          icon: const Icon(
                            Icons.flight_takeoff_rounded,
                            size: 20,
                          ),
                          label: const Text('Create a New Trip'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(0, 54),
                            shape: const StadiumBorder(),
                            textStyle: GoogleFonts.plusJakartaSans(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          key: const ValueKey('placeholder_join_group'),
                          onPressed: () => showJoinGroupSheet(context),
                          icon: const Icon(Icons.group_add_rounded, size: 20),
                          label: const Text('Join Existing Group'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 52),
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.7,
                            ),
                            side: const BorderSide(
                              color: AppTheme.primaryEmerald,
                              width: 2,
                            ),
                            foregroundColor: AppTheme.primaryEmeraldDark,
                            shape: const StadiumBorder(),
                            textStyle: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 300.ms),
                if (upcoming) ...[
                  const SizedBox(height: 16),
                  Container(
                    key: const ValueKey('upcoming_trip_card'),
                    padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
                    decoration: AppTheme.surfaceDecoration(radius: 24),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryEmeraldSubtle,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.event_rounded,
                            color: AppTheme.primaryEmeraldDark,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'UPCOMING',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                              Text(
                                trip.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textDark,
                                ),
                              ),
                              Text(
                                'Starts ${DateFormat('EEE, MMM d').format(trip.startDate)} • in $days ${days == 1 ? 'day' : 'days'}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: AppTheme.textSlate,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          key: const ValueKey('placeholder_view_upcoming'),
                          onPressed: () => ref
                              .read(openedUpcomingTripProvider.notifier)
                              .open(trip.id),
                          child: const Text('View trip'),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
