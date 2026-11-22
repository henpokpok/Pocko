import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/features/trip/trip_controller.dart';
import 'package:travmate/features/trip/trip_state.dart';
import 'package:travmate/models/trip.dart';
import 'package:travmate/models/trip_member.dart';
import 'package:travmate/services/sync/squad_sync_service.dart';

/// In-memory stand-in for Firestore so the live-sync wiring can be tested.
class _FakeSync extends SquadSyncService {
  final subscribed = <String>[];
  final controllers = <String, StreamController<TripStateUpdate?>>{};
  final pushes = <TripState>[];
  TripStateUpdate? fetchResult;

  @override
  bool get isAvailable => true;

  @override
  Stream<TripStateUpdate?> streamTripUpdates(String squadCode) {
    subscribed.add(squadCode);
    // ignore: close_sinks (closed by the test via `controllers`)
    final c = StreamController<TripStateUpdate?>.broadcast();
    controllers[squadCode] = c;
    return c.stream;
  }

  @override
  Future<TripStateUpdate?> fetchTrip(String squadCode) async => fetchResult;

  @override
  Future<void> syncTripToCloud(TripState state, {String? writerId}) async {
    pushes.add(state);
  }
}

Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  late _FakeSync fake;
  late ProviderContainer container;

  TripState read() => container.read(tripControllerProvider);

  setUp(() {
    fake = _FakeSync();
    container = ProviderContainer(
      overrides: [
        tripControllerProvider.overrideWith(
          () => TripController(syncService: fake),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  group('Live group listener', () {
    test(
      'A trip created right after the controller is first used listens to its '
      'own code, not the stale starting code',
      () async {
        // First access builds the controller lazily, then the demo loads.
        final notifier = container.read(tripControllerProvider.notifier);
        notifier.loadDemoTrip();
        await _tick();

        final code = read().squadCode;
        expect(fake.subscribed, [
          code,
        ], reason: 'only the new trip code may be subscribed');

        // Another device renames the trip: this device must see it live.
        fake.controllers[code]!.add(
          TripStateUpdate(
            trip: read().trip.copyWith(name: 'Renamed elsewhere'),
            writerId: 'someone-else',
          ),
        );
        await _tick();
        expect(read().trip.name, 'Renamed elsewhere');
      },
    );

    test(
      'Without any other call the controller still listens to its own code',
      () async {
        container.read(tripControllerProvider.notifier);
        await _tick();
        expect(fake.subscribed, [read().squadCode]);
      },
    );

    test('The setup wizard also keeps listening to the new trip', () async {
      final notifier = container.read(tripControllerProvider.notifier);
      notifier.startNewTrip(name: 'Seoul', currency: 'KRW', friends: ['Mina']);
      await _tick();

      final code = read().squadCode;
      expect(fake.subscribed, [code]);
      fake.controllers[code]!.add(
        TripStateUpdate(
          trip: read().trip.copyWith(name: 'Seoul 2027'),
          writerId: 'someone-else',
        ),
      );
      await _tick();
      expect(read().trip.name, 'Seoul 2027');
    });
  });

  group('Joining a group', () {
    TripStateUpdate remote({List<TripMember>? extra}) {
      final base = TripState.initial(squadCode: '123-456').trip;
      return TripStateUpdate(
        trip: Trip(
          id: base.id,
          name: base.name,
          baseCurrency: base.baseCurrency,
          members: [
            for (final m in base.members) m.copyWith(isCurrentUser: false),
            ...?extra,
          ],
          expenses: base.expenses,
          createdAt: base.createdAt,
          startDate: base.startDate,
        ),
        writerId: 'host-device',
      );
    }

    test(
      'The joiner stays in the member list after the first remote snapshot',
      () async {
        fake.fetchResult = remote();
        final notifier = container.read(tripControllerProvider.notifier);
        expect(await notifier.joinSquad('123-456'), JoinSquadResult.joined);
        await _tick();

        final me = read().trip.members.firstWhere((m) => m.isCurrentUser);
        expect(read().trip.members.length, 5);
        expect(read().currentMemberId, me.id);
        expect(
          fake.pushes.last.trip.members.any((m) => m.id == me.id),
          isTrue,
          reason: 'the joiner is published to the cloud',
        );

        // The cached copy of the host's trip arrives (without the joiner).
        fake.controllers['123-456']!.add(remote());
        await _tick();
        expect(read().trip.members.length, 5);
        expect(read().trip.members.where((m) => m.id == me.id), hasLength(1));
        expect(
          read().trip.members.firstWhere((m) => m.id == me.id).isCurrentUser,
          isTrue,
        );
      },
    );

    test(
      'Once the cloud has the joiner the member is not duplicated',
      () async {
        fake.fetchResult = remote();
        final notifier = container.read(tripControllerProvider.notifier);
        await notifier.joinSquad('123-456');
        await _tick();
        final me = read().trip.members.firstWhere((m) => m.isCurrentUser);

        fake.controllers['123-456']!.add(
          remote(
            extra: [TripMember(id: me.id, name: me.name)],
          ),
        );
        await _tick();
        expect(read().trip.members.where((m) => m.id == me.id), hasLength(1));
        expect(read().trip.members.length, 5);

        // Later the group removes this traveler: that removal must stick.
        fake.controllers['123-456']!.add(remote());
        await _tick();
        expect(read().trip.members.any((m) => m.id == me.id), isFalse);
      },
    );
  });
}
