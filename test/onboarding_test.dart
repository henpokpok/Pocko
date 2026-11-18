import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/core/widgets/pocko_mascot.dart';
import 'package:travmate/features/onboarding/first_trip_setup_card.dart';
import 'package:travmate/features/onboarding/onboarding_screen.dart';
import 'package:travmate/features/onboarding/trip_destinations.dart';
import 'package:travmate/features/shell/pocko_main_shell.dart';
import 'package:travmate/features/trip/trip_controller.dart';
import 'package:travmate/main.dart';

import 'test_helpers.dart';

Future<(ProviderContainer, List<int>)> _pumpOnboarding(
  WidgetTester tester, {
  bool startAtSetup = false,
  Size size = const Size(390, 844),
}) async {
  final done = <int>[];
  final container = await pumpPocko(
    tester,
    OnboardingScreen(startAtSetup: startAtSetup, onDone: () => done.add(1)),
    size: size,
    scaffold: false,
  );
  return (container, done);
}

Finder _key(String k) => find.byKey(ValueKey(k));

Future<void> _pick(
  WidgetTester tester,
  String selectorKey,
  String entry,
) async {
  await tester.ensureVisible(_key(selectorKey));
  await tester.tap(_key(selectorKey));
  await settle(tester, 400);
  // The popover is capped at 320 px and scrolls: bring the option into view.
  await tester.ensureVisible(find.text(entry).last);
  await tester.pump();
  await tester.tap(find.text(entry).last);
  await settle(tester, 400);
}

void main() {
  group('Animated Pocko story', () {
    testWidgets(
      'three superpowers with the Pocko mascot, swipeable and animated',
      (tester) async {
        await _pumpOnboarding(tester);
        await settle(tester, 600);

        expect(find.byType(PockoMascot), findsWidgets);
        expect(find.text('Speak offline in 3s'), findsOneWidget);
        expect(find.text('Works offline'), findsOneWidget);

        await tester.drag(_key('onboarding_pages'), const Offset(-300, 0));
        await settle(tester, 700);
        expect(find.text('Slips snap onto expenses'), findsOneWidget);

        await tester.tap(_key('next_button'));
        await settle(tester, 700);
        expect(find.text('Your card numbers stay yours'), findsOneWidget);
        expect(
          find.text('Set up my trip'),
          findsOneWidget,
          reason: 'last story page CTA',
        );
      },
    );

    testWidgets(
      'page dots track the page and the story ends at the setup card',
      (tester) async {
        await _pumpOnboarding(tester);
        final dots = find.descendant(
          of: _key('onboarding_dots'),
          matching: find.byType(AnimatedContainer),
        );
        expect(dots, findsNWidgets(4));
        double width(int i) => tester.getSize(dots.at(i)).width;
        await settle(tester, 400);
        expect(width(0), 30, reason: '24px active dot + margins');
        expect(width(1), 14, reason: '8px dot + margins');

        for (var i = 0; i < 3; i++) {
          await tester.tap(_key('next_button'));
          await settle(tester, 700);
        }
        expect(_key('first_trip_setup_card'), findsOneWidget);
        expect(width(3), 30);
        expect(_key('next_button'), findsNothing);
      },
    );

    testWidgets('Skip jumps straight to the setup card', (tester) async {
      await _pumpOnboarding(tester);
      await tester.tap(_key('skip_button'));
      await settle(tester, 800);
      expect(_key('first_trip_setup_card'), findsOneWidget);
      expect(find.text('Set up your first trip'), findsOneWidget);
    });

    testWidgets('Try Tokyo Demo Trip is one tap away on every page', (
      tester,
    ) async {
      await _pumpOnboarding(tester);
      expect(_key('demo_trip_button'), findsOneWidget);
      await tester.tap(_key('skip_button'));
      await settle(tester, 800);
      expect(_key('demo_trip_button'), findsOneWidget);
      expect(find.text('Try Tokyo Demo Trip'), findsOneWidget);
    });

    testWidgets('the demo shortcut loads the Tokyo trip and finishes', (
      tester,
    ) async {
      final (container, done) = await _pumpOnboarding(tester);
      container
          .read(tripControllerProvider.notifier)
          .startNewTrip(name: 'Temp', currency: 'USD');
      await tester.tap(_key('demo_trip_button'));
      await settle(tester, 300);
      final s = container.read(tripControllerProvider);
      expect(done, [1]);
      expect(s.trip.baseCurrency, 'JPY');
      expect(s.trip.expenses.length, 7);
    });
  });

  group('First-trip setup card', () {
    testWidgets(
      'defaults: Japan with the paired yen currency and a USD home currency',
      (tester) async {
        await _pumpOnboarding(tester, startAtSetup: true);
        await settle(tester, 500);
        expect(find.text('🇯🇵 Japan'), findsOneWidget);
        expect(find.text('Trip: ¥ JPY'), findsOneWidget);
        expect(find.text('Home: \$ USD'), findsOneWidget);
        expect(
          find.text('Seoul Autumn Trip'),
          findsOneWidget,
          reason: 'name hint',
        );
      },
    );

    testWidgets('destination automatically pairs the trip currency', (
      tester,
    ) async {
      await _pumpOnboarding(tester, startAtSetup: true);
      final cases = {
        'South Korea': 'Trip: ₩ KRW',
        'Europe': 'Trip: € EUR',
        'United States': 'Trip: \$ USD',
        'United Kingdom': 'Trip: £ GBP',
        'Thailand': 'Trip: ฿ THB',
        'Japan': 'Trip: ¥ JPY',
      };
      for (final entry in cases.entries) {
        final d = TripDestination.byName(entry.key);
        await _pick(
          tester,
          'destination_selector',
          d.pickerLabel(entry.value.substring(6, 7)),
        );
        expect(find.text(entry.value), findsOneWidget, reason: entry.key);
      }
    });

    testWidgets('trip and home currency can be overridden', (tester) async {
      await _pumpOnboarding(tester, startAtSetup: true);
      await _pick(tester, 'home_currency_selector', 'GBP £ • British Pound');
      expect(find.text('Home: £ GBP'), findsOneWidget);
      await _pick(tester, 'trip_currency_selector', 'EUR € • Euro');
      expect(find.text('Trip: € EUR'), findsOneWidget);
    });

    testWidgets(
      'friends are added as simple name tags, deduped, removable, with micro-copy',
      (tester) async {
        await _pumpOnboarding(tester, startAtSetup: true);
        expect(find.text('No app install needed for friends'), findsOneWidget);
        expect(_key('member_tag_you'), findsOneWidget);

        Future<void> add(String name) async {
          await tester.ensureVisible(_key('member_name_field'));
          await tester.enterText(_key('member_name_field'), name);
          await tester.tap(_key('add_member_button'));
          await settle(tester, 300);
        }

        await add('Jisoo');
        await add('Min');
        expect(_key('member_tag_Jisoo'), findsOneWidget);
        expect(_key('member_tag_Min'), findsOneWidget);

        await add('jisoo');
        expect(find.textContaining('already in the group'), findsOneWidget);
        expect(_key('member_tag_jisoo'), findsNothing);

        await add('You');
        expect(find.textContaining('already in the group'), findsOneWidget);

        await tester.tap(
          find.descendant(
            of: _key('member_tag_Min'),
            matching: find.byIcon(Icons.close_rounded),
          ),
        );
        await settle(tester, 300);
        expect(_key('member_tag_Min'), findsNothing);
      },
    );

    testWidgets('Start Trip needs a name', (tester) async {
      final (container, done) = await _pumpOnboarding(
        tester,
        startAtSetup: true,
      );
      await tester.ensureVisible(_key('start_trip_button'));
      await tester.tap(_key('start_trip_button'));
      await settle(tester, 300);
      expect(find.text('Give your trip a name first'), findsOneWidget);
      expect(done, isEmpty);
      expect(container.read(tripControllerProvider).trip.name, isNot(''));
    });

    testWidgets('Start Trip initializes the live trip state', (tester) async {
      final (container, done) = await _pumpOnboarding(
        tester,
        startAtSetup: true,
      );
      await tester.enterText(_key('trip_name_field'), 'Seoul Autumn Trip');
      await _pick(tester, 'destination_selector', '🇰🇷 South Korea (₩ KRW)');
      await _pick(tester, 'home_currency_selector', 'EUR € • Euro');
      await tester.ensureVisible(_key('member_name_field'));
      await tester.enterText(_key('member_name_field'), 'Jisoo');
      await tester.tap(_key('add_member_button'));
      await settle(tester, 300);
      // A name typed but not yet added still counts.
      await tester.enterText(_key('member_name_field'), 'Min');
      await tester.ensureVisible(_key('start_trip_button'));
      await tester.tap(_key('start_trip_button'));
      await settle(tester, 300);

      final s = container.read(tripControllerProvider);
      expect(done, [1]);
      expect(s.trip.name, 'Seoul Autumn Trip');
      expect(s.trip.baseCurrency, 'KRW');
      expect(s.trip.homeCurrency, 'EUR');
      expect(s.trip.members.map((m) => m.name), ['You', 'Jisoo', 'Min']);
      expect(s.trip.expenses, isEmpty);
      expect(s.totalSpend, 0);
    });

    testWidgets('the setup card works on its own', (tester) async {
      TripSetupData? data;
      await pumpPocko(
        tester,
        SingleChildScrollView(
          child: FirstTripSetupCard(onStart: (d) => data = d),
        ),
        size: const Size(420, 1300),
      );
      await tester.enterText(_key('trip_name_field'), 'Bangkok Weekend');
      await tester.tap(_key('start_trip_button'));
      await tester.pump();
      expect(data!.name, 'Bangkok Weekend');
      expect(data!.destination.name, 'Japan');
      expect(data!.friends, isEmpty);
    });
  });

  group('Gate and app flow', () {
    testWidgets('the app opens on the landing story, not the dashboard', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const ProviderScope(child: TravMateApp()));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Speak offline in 3s'), findsOneWidget);
      expect(find.text('TOTAL TRIP SPEND'), findsNothing);
    });

    testWidgets(
      'Start Trip transitions smoothly into the Home screen of the new trip',
      (tester) async {
        final container = await pumpPocko(
          tester,
          const OnboardingGate(app: PockoMainShell()),
          scaffold: false,
        );
        await tester.tap(_key('skip_button'));
        await settle(tester, 800);
        await tester.enterText(_key('trip_name_field'), 'Seoul Autumn Trip');
        await _pick(tester, 'destination_selector', '🇰🇷 South Korea (₩ KRW)');
        await tester.ensureVisible(_key('start_trip_button'));
        await tester.tap(_key('start_trip_button'));
        await tester.pump();
        // Mid-transition both screens are alive (cross-fade).
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(AnimatedSwitcher), findsWidgets);
        await settle(tester, 900);

        expect(container.read(onboardingCompleteProvider), isTrue);
        expect(find.byKey(const ValueKey('onboarding_screen')), findsNothing);
        expect(find.text('TOTAL TRIP SPEND'), findsOneWidget);
        expect(find.textContaining('Seoul Autumn Trip'), findsWidgets);
        expect(find.text('₩0'), findsWidgets);
      },
    );

    testWidgets(
      'Try Tokyo Demo Trip opens the pre-loaded dashboard in one tap',
      (tester) async {
        await pumpPocko(
          tester,
          const OnboardingGate(app: PockoMainShell()),
          scaffold: false,
        );
        await tester.tap(_key('demo_trip_button'));
        await settle(tester, 1000);
        expect(find.text('¥60,000'), findsOneWidget);
        expect(find.textContaining('Tokyo Trip'), findsWidgets);
      },
    );

    testWidgets(
      'Manage Group offers a New Trip / Setup Wizard that returns to Home',
      (tester) async {
        final container = await pumpPocko(
          tester,
          const PockoMainShell(),
          scaffold: false,
          size: const Size(390, 1000),
        );
        await tester.tap(find.textContaining('Edit Group'));
        await settle(tester, 800);

        await tester.ensureVisible(_key('new_trip_wizard_button'));
        expect(find.text('New Trip / Setup Wizard'), findsOneWidget);
        expect(find.text('Try Tokyo Demo Trip'), findsOneWidget);
        await tester.tap(_key('new_trip_wizard_button'));
        await settle(tester, 900);

        expect(
          _key('first_trip_setup_card'),
          findsOneWidget,
          reason: 'opens on the setup card',
        );
        await tester.enterText(_key('trip_name_field'), 'Lisbon Long Weekend');
        await _pick(tester, 'destination_selector', '🇪🇺 Europe (€ EUR)');
        await tester.ensureVisible(_key('start_trip_button'));
        await tester.tap(_key('start_trip_button'));
        await settle(tester, 1000);

        expect(
          container.read(tripControllerProvider).trip.name,
          'Lisbon Long Weekend',
        );
        expect(
          find.text('TOTAL TRIP SPEND'),
          findsOneWidget,
          reason: 'back on Home',
        );
        expect(
          find.byKey(const ValueKey('first_trip_setup_card')),
          findsNothing,
        );
      },
    );
  });

  group('Layouts', () {
    testWidgets('320 x 568 phone: story and setup do not overflow', (
      tester,
    ) async {
      await _pumpOnboarding(tester, size: const Size(320, 568));
      await settle(tester, 600);
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 3; i++) {
        await tester.tap(_key('next_button'));
        await settle(tester, 700);
        expect(tester.takeException(), isNull);
      }
      expect(_key('first_trip_setup_card'), findsOneWidget);
    });

    testWidgets('tablet: content is centered at a readable width', (
      tester,
    ) async {
      await _pumpOnboarding(tester, size: const Size(1180, 820));
      await settle(tester, 600);
      expect(tester.takeException(), isNull);
      final c = tester.getCenter(find.text('Speak offline in 3s'));
      expect(c.dx, closeTo(590, 40));
    });
  });
}
