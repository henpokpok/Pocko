import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/features/settlement/pair_breakdown.dart';
import 'package:travmate/features/trip/trip_controller.dart';

void main() {
  group('computePairBreakdown', () {
    late ProviderContainer container;
    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
    });

    test('You vs Alex lists exactly the items each paid for the other, per-item shares', () {
      final state = container.read(tripControllerProvider);
      final b = computePairBreakdown(state, 'you', 'alex');
      // Alex paid exp_2 (6,000) and exp_5 (15,400) split 4 ways; you paid exp_1 (4,800) and exp_4 (8,800).
      final titles = b.lines.map((l) => l.title).toSet();
      expect(titles, {
        'Tokyo Metro 72hr Passes',
        'TeamLab Borderless Tickets',
        'Ichiran Ramen Shinjuku',
        'Shibuya Sky Observation Deck',
      });
      expect(b.aOwesB, closeTo(6000 / 4 + 15400 / 4, 0.01));
      expect(b.bOwesA, closeTo(4800 / 4 + 8800 / 4, 0.01));
      expect(b.net, closeTo(b.bOwesA - b.aOwesB, 0.01));
      final teamLab = b.lines.firstWhere((l) => l.title.startsWith('TeamLab'));
      expect(
        teamLab.amount,
        closeTo(-3850, 0.01),
        reason: 'your share of Alex\'s ¥15,400',
      );
      expect(teamLab.total, 15400);
    });

    test('Solo and Pre-Trip expenses never appear between two people', () {
      final state = container.read(tripControllerProvider);
      final b = computePairBreakdown(state, 'you', 'alex');
      expect(b.lines.any((l) => l.expense?.id == 'exp_pre1'), isFalse);
    });

    test('Recorded payments are part of the pair net', () {
      final notifier = container.read(tripControllerProvider.notifier);
      final t = container
          .read(tripControllerProvider)
          .simplifiedTransfers
          .firstWhere(
            (t) => t.fromMemberId == 'maya' && t.toMemberId == 'alex',
          );
      final before = computePairBreakdown(
        container.read(tripControllerProvider),
        'maya',
        'alex',
      );
      notifier.markTransferSettled(t.id);
      final after = computePairBreakdown(
        container.read(tripControllerProvider),
        'maya',
        'alex',
      );
      expect(after.lines.any((l) => l.isPayment), isTrue);
      expect(after.net, closeTo(before.net + t.amount, 0.01));
      expect(after.paymentsNet, closeTo(t.amount, 0.01));
    });

    test('Items are listed newest first', () {
      final b = computePairBreakdown(
        container.read(tripControllerProvider),
        'you',
        'alex',
      );
      for (var i = 1; i < b.lines.length; i++) {
        expect(
          b.lines[i - 1].when.isAfter(b.lines[i].when) ||
              b.lines[i - 1].when == b.lines[i].when,
          isTrue,
        );
      }
    });
  });
}
