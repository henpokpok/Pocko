import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/services/hybrid_ai/hybrid_ai_service.dart';

void main() {
  group('LiveInferenceGate (fast path for unconfigured environments)', () {
    test(
      'a negative probe returns null at once and never runs the call',
      () async {
        final gate = LiveInferenceGate();
        var called = false;
        final sw = Stopwatch()..start();
        final r = await gate.run<int>(
          probe: () async => false,
          call: () async {
            called = true;
            return 1;
          },
        );
        expect(r, isNull);
        expect(called, isFalse);
        expect(sw.elapsedMilliseconds, lessThan(100));
      },
    );

    test('a hanging probe is cut off by the strict probe timeout', () async {
      final gate = LiveInferenceGate(
        probeTimeout: const Duration(milliseconds: 60),
      );
      final sw = Stopwatch()..start();
      final r = await gate.run<int>(
        probe: () => Completer<bool>().future, // never completes
        call: () async => 1,
      );
      expect(r, isNull);
      expect(sw.elapsedMilliseconds, lessThan(400));
    });

    test(
      'a configured runtime runs directly and the probe result is cached',
      () async {
        final gate = LiveInferenceGate();
        var probes = 0;
        Future<bool> probe() async {
          probes++;
          return true;
        }

        expect(await gate.run<int>(probe: probe, call: () async => 7), 7);
        expect(await gate.run<int>(probe: probe, call: () async => 8), 8);
        expect(probes, 1, reason: 'second request pays no probe cost');
      },
    );

    test(
      'a stuck live call times out and the next request re-probes',
      () async {
        final gate = LiveInferenceGate(
          callTimeout: const Duration(milliseconds: 60),
        );
        var probes = 0;
        Future<bool> probe() async {
          probes++;
          return true;
        }

        final r = await gate.run<int>(
          probe: probe,
          call: () => Completer<int?>().future,
        );
        expect(r, isNull);
        await gate.run<int>(probe: probe, call: () async => 1);
        expect(probes, 2);
      },
    );

    test(
      'a throwing call falls back to null instead of surfacing the error',
      () async {
        final gate = LiveInferenceGate();
        final r = await gate.run<int>(
          probe: () async => true,
          call: () async => throw StateError('boom'),
        );
        expect(r, isNull);
      },
    );
  });
}
