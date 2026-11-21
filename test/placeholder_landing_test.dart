import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travmate/core/enums/inference_source.dart';
import 'package:travmate/core/widgets/telemetry_pill.dart';
import 'package:travmate/features/capture/ai_expense_capture_sheet.dart';
import 'package:travmate/features/expenses/manual_expense.dart';
import 'package:travmate/features/onboarding/onboarding_screen.dart';
import 'package:travmate/features/settings/settings_sheet.dart';
import 'package:travmate/features/shell/pocko_main_shell.dart';
import 'package:travmate/features/squad/join_group_sheet.dart';
import 'package:travmate/features/squad/rename_member_sheet.dart';
import 'package:travmate/features/squad/squad_setup_screen.dart';
import 'package:travmate/features/trip/trip_controller.dart';
import 'package:travmate/features/trip/trip_state.dart';
import 'package:travmate/services/session/session_store.dart';

import 'test_helpers.dart';

Finder _k(String key) => find.byKey(ValueKey(key));

/// Pumps [child] with a real [SessionStore] over mock preferences.
Future<(ProviderContainer, SessionStore)> _pumpApp(
  WidgetTester tester, {
  Widget? child,
  Map<String, Object> prefs = const {},
  TripState? savedTrip,
  Size size = const Size(390, 844),
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final store = SessionStore(await SharedPreferences.getInstance());
  if (savedTrip != null) await store.saveSession(savedTrip);
  final container = await pumpPocko(
    tester,
    child ?? const OnboardingGate(app: PockoMainShell()),
    size: size,
    scaffold: false,
    overrides: [sessionStoreProvider.overrideWithValue(store)],
  );
  await settle(tester, 600);
  return (container, store);
}

TripState _demo({DateTime? start}) {
  final base = TripState.initial(squadCode: '482-993');
  return start == null
      ? base
      : base.copyWith(trip: base.trip.copyWith(startDate: start));
}

void main() {
  group('Landing Page shows only on the first launch', () {
    testWidgets('first launch: landing with Get Started, Join Group and Demo', (
      tester,
    ) async {
      await _pumpApp(tester);
      expect(_k('onboarding_screen'), findsOneWidget);
      expect(_k('create_trip_button'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);
      expect(_k('join_group_button'), findsOneWidget);
      expect(_k('demo_trip_button'), findsOneWidget);
      expect(_k('landing_skip_button'), findsOneWidget);
      expect(_k('landing_back_to_trip'), findsNothing);
    });

    testWidgets('Join Group on the landing opens the name + code sheet', (
      tester,
    ) async {
      await _pumpApp(tester);
      await tester.tap(_k('join_group_button'));
      await settle(tester, 600);
      expect(find.text('Join a Group'), findsOneWidget);
      expect(_k('join_name_field'), findsOneWidget);
      expect(_k('join_code_field'), findsOneWidget);
      expect(_k('join_submit_button'), findsOneWidget);
    });

    testWidgets(
      'finishing the landing saves the flag; the next launch skips it',
      (tester) async {
        final (_, store) = await _pumpApp(tester);
        expect(store.hasSeenLanding, isFalse);
        await tester.tap(_k('demo_trip_button'));
        await settle(tester, 900);
        expect(store.hasSeenLanding, isTrue);
        expect(_k('onboarding_screen'), findsNothing);
        expect(find.text('TOTAL TRIP SPEND'), findsOneWidget);

        // "Second launch": a new app over the same storage.
        await tester.pumpWidget(const SizedBox());
        await _pumpApp(
          tester,
          prefs: {SessionStore.hasSeenLandingKey: true},
          savedTrip: _demo(),
        );
        expect(_k('onboarding_screen'), findsNothing);
        expect(find.text('TOTAL TRIP SPEND'), findsOneWidget);
      },
    );

    testWidgets('Skip for now lands on the placeholder Home and remembers it', (
      tester,
    ) async {
      final (_, store) = await _pumpApp(tester);
      await tester.tap(_k('landing_skip_button'));
      await settle(tester, 900);
      expect(store.hasSeenLanding, isTrue);
      expect(_k('placeholder_home'), findsOneWidget);
    });

    testWidgets(
      'a later launch with no saved trip goes straight to the placeholder',
      (tester) async {
        await _pumpApp(tester, prefs: {SessionStore.hasSeenLandingKey: true});
        expect(_k('onboarding_screen'), findsNothing);
        expect(_k('placeholder_home'), findsOneWidget);
      },
    );
  });

  group('Replay Landing Page (demo-safe)', () {
    testWidgets('Settings replays the landing without wiping any storage', (
      tester,
    ) async {
      final (container, store) = await _pumpApp(
        tester,
        prefs: {
          SessionStore.hasSeenLandingKey: true,
          'firebase_app_check_marker': 'keep-me',
        },
        savedTrip: _demo(),
      );
      expect(find.text('TOTAL TRIP SPEND'), findsOneWidget);

      await tester.tap(_k('settings_button'));
      await settle(tester, 600);
      expect(find.text('Settings'), findsOneWidget);
      await tester.tap(_k('settings_replay_landing'));
      await settle(tester, 900);

      expect(
        _k('onboarding_screen'),
        findsOneWidget,
        reason: 'landing is back',
      );
      expect(store.hasSeenLanding, isFalse);
      // Nothing else was touched: the trip, the session and unrelated keys.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('firebase_app_check_marker'), 'keep-me');
      expect(store.loadSession(), isNotNull);
      expect(container.read(tripControllerProvider).hasTrip, isTrue);

      // "Back to my trip" returns to the same trip.
      expect(_k('landing_back_to_trip'), findsOneWidget);
      await tester.tap(_k('landing_back_to_trip'));
      await settle(tester, 900);
      expect(find.text('TOTAL TRIP SPEND'), findsOneWidget);
      expect(store.hasSeenLanding, isTrue);
    });
  });

  group('Placeholder Home (no active trip)', () {
    testWidgets('a fresh install: two clear actions and a friendly message', (
      tester,
    ) async {
      await _pumpApp(tester, prefs: {SessionStore.hasSeenLandingKey: true});
      expect(_k('placeholder_home'), findsOneWidget);
      expect(find.text('Ready for your next trip?'), findsOneWidget);
      expect(find.text('Create a New Trip'), findsOneWidget);
      expect(find.text('Join Existing Group'), findsOneWidget);
      expect(find.text('TOTAL TRIP SPEND'), findsNothing);
      expect(_k('upcoming_trip_card'), findsNothing);
      expect(find.textContaining('No trip yet'), findsOneWidget);
    });

    testWidgets(
      'Create a New Trip opens the setup wizard; Join opens the sheet',
      (tester) async {
        await _pumpApp(tester, prefs: {SessionStore.hasSeenLandingKey: true});
        await tester.tap(_k('placeholder_create_trip'));
        await settle(tester, 900);
        expect(_k('setup_page'), findsOneWidget);
        await tester.tap(find.byTooltip('Close'));
        await settle(tester, 700);

        await tester.tap(_k('placeholder_join_group'));
        await settle(tester, 600);
        expect(find.text('Join a Group'), findsOneWidget);
      },
    );

    testWidgets(
      'only an upcoming trip: placeholder plus a quiet way to open it',
      (tester) async {
        final start = DateTime.now().add(const Duration(days: 6));
        await _pumpApp(
          tester,
          prefs: {SessionStore.hasSeenLandingKey: true},
          savedTrip: _demo(start: start),
        );
        expect(find.text('Your trip is coming up'), findsOneWidget);
        expect(_k('upcoming_trip_card'), findsOneWidget);
        expect(find.textContaining('in 6 days'), findsOneWidget);
        expect(find.text('TOTAL TRIP SPEND'), findsNothing);

        await tester.tap(_k('placeholder_view_upcoming'));
        await settle(tester, 700);
        expect(find.text('TOTAL TRIP SPEND'), findsOneWidget);
        expect(_k('placeholder_home'), findsNothing);
      },
    );

    testWidgets('an active trip shows the normal dashboard', (tester) async {
      await _pumpApp(
        tester,
        prefs: {SessionStore.hasSeenLandingKey: true},
        savedTrip: _demo(),
      );
      expect(_k('placeholder_home'), findsNothing);
      expect(find.text('TOTAL TRIP SPEND'), findsOneWidget);
    });
  });

  group('Null-trip crash guard', () {
    testWidgets('the + button asks for a trip instead of opening capture', (
      tester,
    ) async {
      await _pumpApp(tester, prefs: {SessionStore.hasSeenLandingKey: true});
      await tester.tap(find.byIcon(Icons.add_rounded));
      await settle(tester, 700);
      expect(_k('need_trip_sheet'), findsOneWidget);
      expect(find.text('Create or join a trip first'), findsOneWidget);
      expect(find.byType(AiExpenseCaptureSheet), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(_k('need_trip_join'));
      await settle(tester, 700);
      expect(find.text('Join a Group'), findsOneWidget);
    });

    testWidgets('Add Expense and Receipt Scan are guarded too', (tester) async {
      await _pumpApp(
        tester,
        prefs: {SessionStore.hasSeenLandingKey: true},
        child: Consumer(
          builder: (context, ref, _) => Center(
            child: ElevatedButton(
              onPressed: () => addManualExpense(context, ref),
              child: const Text('Add manually'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Add manually'));
      await settle(tester, 700);
      expect(_k('need_trip_sheet'), findsOneWidget);
      expect(find.text('Save Changes'), findsNothing);
      expect(find.text('Add Expense'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Matcher tab\'s Upload Slip Photo asks for a trip', (
      tester,
    ) async {
      await _pumpApp(tester, prefs: {SessionStore.hasSeenLandingKey: true});
      await tester.tap(find.text('Matcher'));
      await settle(tester, 700);
      await tester.tap(find.text('Upload Slip Photo'));
      await settle(tester, 700);
      expect(_k('need_trip_sheet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every tab renders on the placeholder without errors', (
      tester,
    ) async {
      await _pumpApp(tester, prefs: {SessionStore.hasSeenLandingKey: true});
      for (final tab in ['Expenses', 'Matcher', 'Settle', 'Home']) {
        await tester.tap(find.text(tab));
        await settle(tester, 600);
        expect(tester.takeException(), isNull, reason: tab);
      }
    });

    testWidgets(
      'with an upcoming trip the + button still works (pre-trip expenses)',
      (tester) async {
        await _pumpApp(
          tester,
          prefs: {SessionStore.hasSeenLandingKey: true},
          savedTrip: _demo(start: DateTime.now().add(const Duration(days: 4))),
        );
        await tester.tap(find.byIcon(Icons.add_rounded));
        await settle(tester, 900);
        expect(find.byType(AiExpenseCaptureSheet), findsOneWidget);
        expect(_k('need_trip_sheet'), findsNothing);
      },
    );
  });

  group('Settings and renaming from the UI', () {
    testWidgets('Settings: change your name, join a group, create a trip', (
      tester,
    ) async {
      final (container, _) = await _pumpApp(
        tester,
        prefs: {SessionStore.hasSeenLandingKey: true},
        savedTrip: _demo(),
      );
      await tester.tap(_k('settings_button'));
      await settle(tester, 600);
      for (final key in [
        'settings_display_name',
        'settings_join_group',
        'settings_new_trip',
        'settings_replay_landing',
      ]) {
        expect(_k(key), findsOneWidget, reason: key);
      }

      await tester.tap(_k('settings_display_name'));
      await settle(tester, 600);
      expect(find.text('Your display name'), findsWidgets);
      await tester.enterText(_k('rename_field'), 'Pong');
      await tester.tap(_k('rename_save_button'));
      await settle(tester, 700);
      final s = container.read(tripControllerProvider);
      expect(s.memberById(s.currentMemberId)!.name, 'Pong');
    });

    testWidgets('the rename sheet shows the error instead of closing', (
      tester,
    ) async {
      await _pumpApp(
        tester,
        child: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showRenameMemberSheet(context, 'alex'),
              child: const Text('open'),
            ),
          ),
        ),
        prefs: {SessionStore.hasSeenLandingKey: true},
        savedTrip: _demo(),
      );
      await tester.tap(find.text('open'));
      await settle(tester, 600);
      await tester.enterText(_k('rename_field'), 'Maya');
      await tester.tap(_k('rename_save_button'));
      await settle(tester, 400);
      expect(
        find.text('Someone in this group already uses that name.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'Manage Group: pencil buttons rename you and (as host) friends',
      (tester) async {
        final (container, _) = await _pumpApp(
          tester,
          child: SquadSetupScreen(onLaunchCanvas: () {}),
          prefs: {SessionStore.hasSeenLandingKey: true},
          savedTrip: _demo(),
          size: const Size(420, 2000),
        );
        expect(_k('rename_you'), findsOneWidget);
        expect(_k('rename_alex'), findsOneWidget);
        await tester.tap(_k('rename_alex'));
        await settle(tester, 600);
        await tester.enterText(_k('rename_field'), 'Pong');
        await tester.tap(_k('rename_save_button'));
        await settle(tester, 700);
        expect(container.read(tripControllerProvider).nameOf('alex'), 'Pong');
        expect(find.text('Pong'), findsWidgets);
      },
    );

    testWidgets('with no trip, the saved name is stored for the next group', (
      tester,
    ) async {
      final (_, store) = await _pumpApp(
        tester,
        child: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showSettingsSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
        prefs: {SessionStore.hasSeenLandingKey: true},
      );
      await tester.tap(find.text('open'));
      await settle(tester, 600);
      await tester.tap(_k('settings_display_name'));
      await settle(tester, 600);
      await tester.enterText(_k('saved_name_field'), 'Pong');
      await tester.tap(find.text('Save'));
      await settle(tester, 500);
      expect(store.displayName, 'Pong');
    });
  });

  group('Clear AI source indicator', () {
    Widget pill(InferenceSource s, {bool sim = false, String? model}) =>
        MaterialApp(
          home: Scaffold(
            body: TelemetryPill(
              plain: true,
              source: s,
              simulated: sim,
              latencyMs: 1480,
              modelInfo: model,
            ),
          ),
        );

    testWidgets('Cloud Gemini names the model', (tester) async {
      await tester.pumpWidget(
        pill(
          InferenceSource.inCloud,
          model: 'gemini-3.1-flash-lite (Firebase AI Logic Cloud)',
        ),
      );
      expect(
        find.text('☁️ Cloud Gemini • gemini-3.1-flash-lite'),
        findsOneWidget,
      );
      expect(find.text('1480 ms'), findsOneWidget);
    });

    testWidgets(
      'on-device says On-Device AI, and the offline parser says Offline Safety Net • Rule Engine',
      (tester) async {
        await tester.pumpWidget(pill(InferenceSource.onDevice));
        expect(find.text('🟢 On-Device AI • Gemini Nano'), findsOneWidget);
        await tester.pumpWidget(pill(InferenceSource.onDevice, sim: true));
        expect(find.text('📴 Offline Safety Net • Rule Engine'), findsOneWidget);
        expect(find.text('SIM'), findsNothing);
      },
    );

    testWidgets('the capture review shows the badge', (tester) async {
      await pumpPocko(
        tester,
        const AiExpenseCaptureSheet(enableSpeechRecognition: false),
        size: const Size(390, 1100),
      );
      await tester.enterText(_k('capture_text_field'), 'Ramen 4800 yen');
      await tester.pump();
      await tester.tap(_k('confirm_button'));
      await settle(tester, 1500);
      expect(_k('ai_source_badge'), findsOneWidget);
      expect(find.textContaining('Offline Safety Net • Rule Engine'), findsOneWidget);
      expect(find.textContaining('SIM'), findsNothing);
    });
  });

  group('iPad 11" layouts (portrait and landscape)', () {
    const portrait = Size(834, 1194);
    const landscape = Size(1194, 834);

    for (final size in [portrait, landscape]) {
      final label = size == portrait ? 'portrait' : 'landscape';

      testWidgets('placeholder Home, every tab and Settings ($label)', (
        tester,
      ) async {
        await _pumpApp(
          tester,
          prefs: {SessionStore.hasSeenLandingKey: true},
          size: size,
        );
        expect(_k('placeholder_home'), findsOneWidget);
        // The content is centered and never stretches across the whole screen.
        expect(
          tester.getSize(_k('placeholder_home')).width,
          lessThanOrEqualTo(520.5),
        );
        for (final tab in ['Expenses', 'Matcher', 'Settle', 'Home']) {
          await tester.tap(find.text(tab));
          await settle(tester, 500);
          expect(tester.takeException(), isNull, reason: '$tab $label');
        }
        await tester.tap(_k('settings_button'));
        await settle(tester, 600);
        expect(find.text('Settings'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets(
        'live trip: Group Sync, Receipt Matcher and Settle ($label)',
        (tester) async {
          await _pumpApp(
            tester,
            prefs: {SessionStore.hasSeenLandingKey: true},
            savedTrip: _demo(),
            size: size,
          );
          for (final tab in ['Expenses', 'Matcher', 'Settle', 'Home']) {
            await tester.tap(find.text(tab));
            await settle(tester, 500);
            expect(tester.takeException(), isNull, reason: '$tab $label');
          }
        },
      );

      testWidgets(
        'Manage Group (group sync) and the join / rename sheets ($label)',
        (tester) async {
          await _pumpApp(
            tester,
            child: SquadSetupScreen(onLaunchCanvas: () {}),
            prefs: {SessionStore.hasSeenLandingKey: true},
            savedTrip: _demo(),
            size: size,
          );
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Join Group'));
          await settle(tester, 600);
          expect(_k('join_code_field'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets('the Landing Page fits ($label)', (tester) async {
        await _pumpApp(tester, size: size);
        expect(_k('join_group_button'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  test('showJoinGroupSheet is exported for every entry point', () {
    expect(showJoinGroupSheet, isNotNull);
  });
}
