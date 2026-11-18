import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/core/enums/slip_status.dart';
import 'package:travmate/services/sync/squad_sync_service.dart';

void main() {
  group('SquadSyncService.deserializeTrip', () {
    test('Parses members, expenses (with notes), settlements, writer id and pending state', () {
      final update = SquadSyncService.deserializeTrip(
        {
          'id': 'trip_1',
          'name': 'Kyoto Weekend',
          'baseCurrency': 'USD',
          'createdAt': '2026-11-10T08:00:00.000',
          'writerId': 'w123',
          'members': [
            {'id': 'a', 'name': 'Ann'},
            {'id': 'b', 'name': 'Bo'},
          ],
          'expenses': [
            {
              'id': 'e1',
              'title': 'Tea house',
              'amount': 42.5,
              'currency': 'USD',
              'category': 'SNACK_CAFE',
              'payerId': 'a',
              'splitWithMemberIds': ['a', 'b'],
              'createdAt': '2026-11-11T10:00:00.000',
              'inferenceSource': 'in_cloud',
              'slipStatus': 'matched',
              'note': 'Matcha set',
            },
          ],
          'settlements': [
            {
              'id': 'p1',
              'fromMemberId': 'b',
              'toMemberId': 'a',
              'amount': 10,
              'currency': 'USD',
              'paidAt': '2026-11-12T09:00:00.000',
            },
          ],
        },
        '123-456',
        hasPendingWrites: true,
      );

      expect(update.trip.name, 'Kyoto Weekend');
      expect(update.trip.baseCurrency, 'USD');
      expect(update.trip.members.map((m) => m.name), ['Ann', 'Bo']);
      expect(update.trip.expenses.single.note, 'Matcha set');
      expect(update.trip.expenses.single.slipStatus, SlipStatus.matched);
      expect(update.trip.createdAt, DateTime(2026, 11, 10, 8));
      expect(update.settlements.single.amount, 10);
      expect(update.writerId, 'w123');
      expect(update.hasPendingWrites, isTrue);
    });

    test('Tolerates empty or malformed documents without throwing', () {
      final update = SquadSyncService.deserializeTrip({}, '000-000');
      expect(update.trip.id, 'trip_000-000');
      expect(update.trip.members, isEmpty);
      expect(update.trip.expenses, isEmpty);
      expect(update.settlements, isEmpty);

      final odd = SquadSyncService.deserializeTrip({
        'members': [
          'not a map',
          {'id': 'x', 'name': 'Xin'},
        ],
        'expenses': [
          42,
          {'title': 'Only a title'},
        ],
        'settlements': [null],
      }, '111-111');
      expect(odd.trip.members.length, 1);
      expect(odd.trip.expenses.length, 1);
      expect(odd.trip.expenses.single.title, 'Only a title');
    });

    test('Without Firebase the service reports itself unavailable instead of throwing', () async {
      final service = SquadSyncService();
      expect(service.isAvailable, isFalse);
      expect(await service.fetchTrip('123-456'), isNull);
      expect(await service.streamTripUpdates('123-456').isEmpty, isTrue);
    });
  });
}
