import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/features/capture/capture_overlay_host.dart';
import 'package:travmate/features/trip/squad_balance_card.dart';
import 'package:travmate/features/trip/trip_state.dart';
import 'package:travmate/models/trip_member.dart';

import 'test_helpers.dart';

/// Screenshot-review fixes: no clipped 5th avatar, darker capture scrim, no
/// "SIM" wording anywhere, and the documented cloud models are the real ones.
void main() {
  TripState withMembers(int n) {
    final base = TripState.initial();
    const names = ['You', 'Alex', 'Maya', 'Liam', 'Sam', 'Kai'];
    final members = [
      for (var i = 0; i < n; i++)
        TripMember(
          id: i == 0 ? 'you' : 'm$i',
          name: names[i],
          isCurrentUser: i == 0,
        ),
    ];
    return base.copyWith(trip: base.trip.copyWith(members: members));
  }

  Future<void> pumpCard(WidgetTester tester, TripState s) => pumpPocko(
    tester,
    SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: SquadBalanceCard(
        tripState: s,
        onManage: () {},
        showInviteOrb: true,
      ),
    ),
    size: const Size(412, 892),
  );

  group('Group net balance row at 412 px', () {
    testWidgets('4+ members: no redundant 5th invite orb, nothing clipped', (
      tester,
    ) async {
      await pumpCard(tester, withMembers(4));
      expect(find.text('+ Group'), findsNothing);
      expect(find.text('Manage Group →'), findsOneWidget);
      for (final n in ['You', 'Alex', 'Maya', 'Liam']) {
        expect(find.text(n), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('small groups still get the invite orb', (tester) async {
      await pumpCard(tester, withMembers(3));
      expect(find.text('+ Group'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  test('capture scrim is 90% opaque', () {
    expect(CaptureOverlayHost.scrimColor, const Color(0xE6070F18));
    expect(CaptureOverlayHost.scrimColor.a, closeTo(0.90, 0.005));
    expect(CaptureOverlayHost.scrimAlpha, 0.90);
  });

  test('the word SIM never reaches the UI', () {
    for (final f
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            // category keyword list ("SIM" card / eSIM): not UI text
            .where((f) => !f.path.endsWith('expense_category.dart'))) {
      final code = f
          .readAsStringSync()
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      // user-visible strings only: quoted "SIM"/'Sim' labels
      expect(
        RegExp(r"""['"](SIM|Sim)['"]|\((Sim|SIM)\)""").hasMatch(code),
        isFalse,
        reason: f.path,
      );
    }
  });

  test('cloud model chain uses the live models (2.5 Flash is retired)', () {
    final js = File('web/firebase_ai_web.js').readAsStringSync();
    expect(js, contains('FAST_CLOUD_MODEL = "gemini-3.1-flash-lite"'));
    expect(js, contains('SLOW_CLOUD_MODEL = "gemini-3.8-flash"'));
    expect(js, isNot(contains('gemini-2.5-flash')));
  });
}
