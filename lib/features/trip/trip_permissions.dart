import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/trip.dart';
import '../../services/identity/device_identity.dart';
import 'trip_controller.dart';

/// Anti-griefing rules for a shared trip.
///
/// * **Host** (`trip.hostUid == uid`, the device that created the trip): may
///   edit or delete anything, remove travelers and lock guest edits.
/// * **Guests** (joined with the 6-digit code): may view everything and add
///   expenses / repayments, but may only edit or delete entries **they
///   created** (`createdByUid == uid`), and nothing at all while the host has
///   locked guest edits.
/// * **Legacy trips** without a `hostUid` stay open to everyone.
class TripPermissions {
  final Trip trip;
  final String uid;

  const TripPermissions(this.trip, this.uid);

  /// A trip from before host tracking: everyone may edit.
  bool get isLegacy => trip.hostUid == null;

  bool get isHost => trip.hostUid != null && trip.hostUid == uid;

  bool get isGuest => !isLegacy && !isHost;

  /// May this person edit or delete an entry created by [createdByUid]?
  bool canModify(String? createdByUid) {
    if (isLegacy || isHost) return true;
    if (trip.lockGuestEdits) return false;
    return createdByUid != null && createdByUid == uid;
  }

  bool get canRemoveMembers => isLegacy || isHost;

  bool get canToggleLock => isHost;

  /// The member who created the trip (always the first one), shown with the
  /// "Host" crown. `null` on legacy trips that never tracked a host.
  String? get hostMemberId =>
      isLegacy || trip.members.isEmpty ? null : trip.members.first.id;

  /// Polite explanation shown when opening an entry for editing is not allowed.
  String get deniedEditMessage => trip.lockGuestEdits && isGuest
      ? 'The Trip Host has locked guest edits'
      : 'Only the Trip Host or creator can edit this entry';

  /// Polite explanation shown when deleting is not allowed.
  String get deniedMessage => trip.lockGuestEdits && isGuest
      ? 'The Trip Host has locked guest edits'
      : 'Only the Trip Host or creator can delete this entry';
}

/// Permissions of the person holding this device for the current trip.
final tripPermissionsProvider = Provider<TripPermissions>((ref) {
  final trip = ref.watch(tripControllerProvider.select((s) => s.trip));
  final uid = ref.watch(currentUidProvider);
  return TripPermissions(trip, uid);
});
