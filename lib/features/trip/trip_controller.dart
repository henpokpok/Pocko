import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/enums/expense_category.dart';
import '../../core/enums/slip_status.dart';
import '../../core/utils/currency_helper.dart';
import '../../features/settlement/debt_simplifier.dart';
import '../../models/bank_slip.dart';
import '../../models/expense_item.dart';
import '../../models/settlement_payment.dart';
import '../../models/settlement_transfer.dart';
import '../../models/trip.dart';
import '../../models/trip_member.dart';
import '../../services/identity/device_identity.dart';
import '../../services/session/session_store.dart';
import '../../services/sync/squad_sync_service.dart';
import 'date_filter.dart';
import 'trip_permissions.dart';
import 'trip_state.dart';

final tripControllerProvider = NotifierProvider<TripController, TripState>(
  TripController.new,
);

/// Outcome of attempting to join a group by code.
enum JoinSquadResult {
  /// Connected to an existing group document in Firestore.
  joined,

  /// No document existed, so a new synced group was created under that code.
  created,

  /// Firebase is not configured: the code is stored locally and sync will start
  /// as soon as the build is linked to a Firebase project.
  offline,

  /// The code is not a 6-digit group code.
  invalid,

  /// No group exists under that code (only returned when the caller asked not
  /// to create one, as the Join Group sheet does).
  notFound,
}

class TripController extends Notifier<TripState> {
  final SquadSyncService _syncService;
  StreamSubscription<TripStateUpdate?>? _syncSubscription;

  /// Random per-controller id so we can ignore the echo of our own writes.
  final String _writerId = 'w${DateTime.now().microsecondsSinceEpoch}';
  bool _disposed = false;

  /// Member id this device created when joining a group. Kept in the member list
  /// until the cloud copy contains it, so the first (stale) snapshot cannot drop it.
  String? _joinedMemberId;

  TripController({SquadSyncService? syncService})
    : _syncService = syncService ?? SquadSyncService();

  /// The person holding this device.
  String get _uid => ref.read(currentUidProvider);

  TripPermissions get _permissions => TripPermissions(state.trip, _uid);

  /// Whether this device may edit or delete [expense] (host / creator rule).
  bool canModifyExpense(ExpenseItem expense) =>
      _permissions.canModify(expense.createdByUid);

  /// Whether this device may undo / delete the repayment [payment].
  bool canModifyRepayment(SettlementPayment payment) =>
      _permissions.canModify(payment.createdByUid);

  /// The trip this device just created: it becomes the host.
  TripState _hostedBy(TripState s) =>
      s.copyWith(trip: s.trip.copyWith(hostUid: _uid));

  @override
  TripState build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _saveTimer?.cancel();
      _syncSubscription?.cancel();
    });

    final store = ref.read(sessionStoreProvider);
    final restored = store?.loadSession();

    // Every install gets its own group code so unrelated devices never write to
    // the same Firestore document.
    final TripState initial;
    if (restored != null) {
      // Next launches open straight on the trip this device was in.
      initial = TripState(
        trip: restored.trip,
        squadCode: restored.squadCode.isEmpty
            ? generateSquadCode()
            : restored.squadCode,
        currentMemberId: restored.currentMemberId,
        settlements: restored.settlements,
        hasTrip: restored.hasTrip,
      );
    } else if (store != null) {
      // A real install with no trip yet: a harmless placeholder, never a
      // null trip. Home shows the welcoming "create or join" state.
      initial = TripState.placeholder(squadCode: generateSquadCode());
    } else {
      initial = _hostedBy(TripState.initial(squadCode: generateSquadCode()));
    }
    final stateWithBalances = _withCalculatedBalances(initial);

    // Keep the saved session in step with every change (debounced).
    if (store != null) {
      listenSelf((previous, next) => _scheduleSave(store, next));
    }

    // Attach real-time cloud sync listener after the initial state is returned.
    // The controller is built lazily, so a wizard / demo / join call may already
    // have subscribed to a newer code by the time this runs. Only attach when
    // nothing else has, and always to the *current* code. A placeholder (no
    // trip yet) has nothing to listen to.
    Future.microtask(() {
      if (!_disposed && _syncSubscription == null && state.hasTrip) {
        _listenToSync(state.squadCode);
      }
    });

    return stateWithBalances;
  }

  Timer? _saveTimer;

  void _scheduleSave(SessionStore store, TripState next) {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), () {
      if (!_disposed) store.saveSession(next);
    });
  }

  /// Generates a fresh `NNN-NNN` group code.
  static String generateSquadCode([Random? random]) {
    final r = random ?? Random();
    final n = 100000 + r.nextInt(900000);
    final s = n.toString();
    return '${s.substring(0, 3)}-${s.substring(3)}';
  }

  // ---------------------------------------------------------------------------
  // Sync plumbing
  // ---------------------------------------------------------------------------

  void _listenToSync(String squadCode) {
    _syncSubscription?.cancel();
    if (!_syncService.isAvailable) {
      state = state.copyWith(syncStatus: SyncStatus.offline);
      return;
    }
    state = state.copyWith(syncStatus: SyncStatus.connecting);
    _syncSubscription = _syncService
        .streamTripUpdates(squadCode)
        .listen(
          (update) {
            if (_disposed) return;
            if (update == null) {
              // Document does not exist yet: publish ours so friends can join.
              state = state.copyWith(syncStatus: SyncStatus.live);
              return;
            }
            // Ignore the echo of our own writes and not-yet-acknowledged local writes.
            if (update.writerId == _writerId || update.hasPendingWrites) {
              state = state.copyWith(syncStatus: SyncStatus.live);
              return;
            }
            _applyRemote(update);
          },
          onError: (_) {
            if (_disposed) return;
            state = state.copyWith(syncStatus: SyncStatus.offline);
          },
        );
  }

  void _applyRemote(TripStateUpdate update) {
    // Deleting the last expense on another device is a legitimate update, so an
    // empty list is accepted. The member list, however, must never be empty.
    if (update.trip.members.isEmpty) return;

    final members = update.trip.members
        .map((m) => m.copyWith(isCurrentUser: m.id == state.currentMemberId))
        .toList();
    final joinedId = _joinedMemberId;
    if (joinedId != null) {
      if (members.any((m) => m.id == joinedId)) {
        _joinedMemberId = null;
      } else {
        final mine = state.trip.members.where((m) => m.id == joinedId);
        if (mine.isNotEmpty) {
          members.add(mine.first.copyWith(isCurrentUser: true));
        }
      }
    }
    final filter = state.selectedFilterCategory;
    // Photos too big for the synced document are stripped from the cloud copy:
    // keep the ones this device already has.
    final localExpenses = {for (final e in state.trip.expenses) e.id: e};
    final mergedExpenses = [
      for (final e in update.trip.expenses)
        (e.receiptImageBase64 == null &&
                localExpenses[e.id]?.receiptImageBase64 != null)
            ? e.copyWith(
                receiptImageBase64: localExpenses[e.id]!.receiptImageBase64,
              )
            : e,
    ];
    final localPayments = {for (final p in state.settlements) p.id: p};
    final mergedPayments = [
      for (final p in update.settlements)
        (p.slipImageBase64 == null &&
                localPayments[p.id]?.slipImageBase64 != null)
            ? SettlementPayment(
                id: p.id,
                fromMemberId: p.fromMemberId,
                toMemberId: p.toMemberId,
                amount: p.amount,
                currency: p.currency,
                paidAt: p.paidAt,
                note: p.note,
                slipImageBase64: localPayments[p.id]!.slipImageBase64,
                createdByUid: p.createdByUid,
              )
            : p,
    ];
    final remoteTrip = update.trip.copyWith(
      members: members,
      expenses: mergedExpenses,
    );
    final stillHasFilter =
        filter == null || remoteTrip.expenses.any((e) => e.category == filter);

    state = _withCalculatedBalances(
      state.copyWith(
        trip: remoteTrip,
        settlements: mergedPayments,
        syncStatus: SyncStatus.live,
        clearCategoryFilter: !stillHasFilter,
      ),
    );
  }

  void _pushSync() {
    _syncService.syncTripToCloud(state, writerId: _writerId);
  }

  TripState _withCalculatedBalances(TripState current) {
    final base = current.trip.baseCurrency;
    final netBalances = DebtSimplifier.calculateNetBalances(
      expenses: current.trip.expenses,
      members: current.trip.members,
      baseCurrency: base,
      settlements: current.settlements,
    );

    final transfers = DebtSimplifier.simplify(
      expenses: current.trip.expenses,
      members: current.trip.members,
      defaultCurrency: base,
      convertToDefaultCurrency: true,
      settlements: current.settlements,
    );

    return current.copyWith(
      netBalances: netBalances,
      simplifiedTransfers: transfers,
    );
  }

  /// Applies a trip mutation, recalculates every derived value, repairs the
  /// category filter and pushes the change to the group.
  void _commit(TripState next) {
    var s = _withCalculatedBalances(next);
    final filter = s.selectedFilterCategory;
    if (filter != null && !s.trip.expenses.any((e) => e.category == filter)) {
      s = s.copyWith(clearCategoryFilter: true);
    }
    state = s;
    _pushSync();
  }

  // ---------------------------------------------------------------------------
  // Expenses
  // ---------------------------------------------------------------------------

  ExpenseItem _sanitize(ExpenseItem item, Set<String> usedIds) {
    var id = item.id.isEmpty
        ? 'exp_${DateTime.now().microsecondsSinceEpoch}'
        : item.id;
    while (usedIds.contains(id)) {
      id = '${id}_${usedIds.length}';
    }
    final memberIds = state.trip.members.map((m) => m.id).toSet();
    var split = item.splitWithMemberIds.where(memberIds.contains).toList();
    if (split.isEmpty) {
      // An expense must be shared by somebody: default to the payer.
      split = memberIds.contains(item.payerId)
          ? [item.payerId]
          : memberIds.toList();
    }
    return item.copyWith(id: id, splitWithMemberIds: split);
  }

  void addExpense(ExpenseItem item) => addExpenses([item]);

  void addExpenses(List<ExpenseItem> items) {
    // No trip yet (fresh install placeholder): there is nothing to add to.
    if (items.isEmpty || !state.hasTrip) return;
    final used = state.trip.expenses.map((e) => e.id).toSet();
    final cleaned = <ExpenseItem>[];
    for (final item in items) {
      final c = _sanitize(
        item,
        used,
      ).copyWith(createdByUid: item.createdByUid ?? _uid);
      used.add(c.id);
      cleaned.add(c);
    }
    final updatedTrip = state.trip.copyWith(
      expenses: [...state.trip.expenses, ...cleaned],
    );
    _commit(state.copyWith(trip: updatedTrip));
  }

  /// Replaces an expense. Ignored (returns `false`) when this device is a guest
  /// and did not create it, or the host locked guest edits.
  bool updateExpense(ExpenseItem item) {
    ExpenseItem? existing;
    for (final e in state.trip.expenses) {
      if (e.id == item.id) existing = e;
    }
    if (existing != null && !canModifyExpense(existing)) return false;
    // The creator never changes when somebody (the host) edits an entry.
    final keep = item.createdByUid ?? existing?.createdByUid;
    final updated = keep == item.createdByUid
        ? item
        : item.copyWith(createdByUid: keep);
    final updatedExpenses = state.trip.expenses
        .map((e) => e.id == item.id ? updated : e)
        .toList();
    _commit(
      state.copyWith(trip: state.trip.copyWith(expenses: updatedExpenses)),
    );
    return true;
  }

  /// Removes an expense and returns it so the UI can offer "Undo".
  ExpenseItem? removeExpense(String expenseId) {
    ExpenseItem? removed;
    for (final e in state.trip.expenses) {
      if (e.id == expenseId) removed = e;
    }
    if (removed == null) return null;
    if (!canModifyExpense(removed)) return null;

    final updatedExpenses = state.trip.expenses
        .where((e) => e.id != expenseId)
        .toList();
    // Slips that pointed at the removed expense become "manual verification".
    final updatedSlips = state.slips
        .map(
          (s) => s.targetExpenseId == expenseId
              ? s.copyWith(
                  clearTarget: true,
                  matchPercentage: 0,
                  isConfirmed: false,
                )
              : s,
        )
        .toList();
    _commit(
      state.copyWith(
        trip: state.trip.copyWith(expenses: updatedExpenses),
        slips: updatedSlips,
      ),
    );
    return removed;
  }

  /// Re-inserts an expense removed by [removeExpense] (Undo).
  void restoreExpense(ExpenseItem item) {
    if (state.trip.expenses.any((e) => e.id == item.id)) return;
    _commit(
      state.copyWith(
        trip: state.trip.copyWith(expenses: [...state.trip.expenses, item]),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Group members
  // ---------------------------------------------------------------------------

  /// Adds a member. Returns `false` when the name is empty or already used.
  bool addMember(String name) {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return false;
    final exists = state.trip.members.any(
      (m) => m.name.toLowerCase() == cleanName.toLowerCase(),
    );
    if (exists) return false;

    final id = 'mem_${DateTime.now().microsecondsSinceEpoch}';
    final newMember = TripMember(id: id, name: cleanName);
    final updatedTrip = state.trip.copyWith(
      members: [...state.trip.members, newMember],
    );
    _commit(state.copyWith(trip: updatedTrip));
    return true;
  }

  /// Removes a member. Returns an error message when removal is not possible,
  /// otherwise `null`.
  String? removeMember(String memberId) {
    if (!_permissions.canRemoveMembers) {
      return 'Only the Trip Host can remove travelers.';
    }
    if (state.trip.members.length <= 1) {
      return 'A group needs at least one traveler.';
    }
    if (memberId == state.currentMemberId) {
      return 'You cannot remove yourself from your own group.';
    }
    final paidCount = state.trip.expenses
        .where((e) => e.payerId == memberId)
        .length;
    if (paidCount > 0) {
      final name = state.nameOf(memberId);
      return '$name paid for $paidCount expense${paidCount == 1 ? '' : 's'}. '
          'Delete or reassign them first.';
    }
    final hasPayments = state.settlements.any(
      (s) => s.fromMemberId == memberId || s.toMemberId == memberId,
    );
    if (hasPayments) {
      return 'This traveler has recorded settlements. Undo them first.';
    }

    final updatedMembers = state.trip.members
        .where((m) => m.id != memberId)
        .toList();
    final remaining = updatedMembers.map((m) => m.id).toSet();
    // Strip the member from every split; expenses left with nobody fall back to the payer.
    final updatedExpenses = state.trip.expenses.map((e) {
      if (!e.splitWithMemberIds.contains(memberId)) return e;
      var split = e.splitWithMemberIds.where(remaining.contains).toList();
      if (split.isEmpty) split = [e.payerId];
      return e.copyWith(splitWithMemberIds: split);
    }).toList();

    _commit(
      state.copyWith(
        trip: state.trip.copyWith(
          members: updatedMembers,
          expenses: updatedExpenses,
        ),
      ),
    );
    return null;
  }

  /// Longest display name accepted.
  static const int maxNameLength = 24;

  /// Renames a traveler. Only the **name** changes: expenses, splits, custom
  /// amounts and repayments all point at the member's immutable `id`, so every
  /// historical bill, balance and view shows the new name at once and no split
  /// math or ownership changes. Returns an error message, or `null` on success.
  ///
  /// Anyone may rename themselves; the Host may rename anyone.
  String? renameMember(String memberId, String newName) {
    final clean = newName.trim().replaceAll(RegExp(r'\s+'), ' ');
    final member = state.memberById(memberId);
    if (member == null) return 'That traveler is no longer in the group.';
    if (!state.hasTrip) return 'Create or join a trip first.';
    final isSelf = memberId == state.currentMemberId;
    if (!isSelf && !_permissions.canRemoveMembers) {
      return 'Only you or the Trip Host can rename this traveler.';
    }
    if (clean.isEmpty) return 'Enter a name.';
    if (clean.length > maxNameLength) {
      return 'Keep the name under $maxNameLength characters.';
    }
    final lower = clean.toLowerCase();
    if (lower == member.name.toLowerCase()) {
      if (clean == member.name) return null;
    } else if (const {'you', 'me', 'myself', 'i'}.contains(lower)) {
      return 'Pick a name other than "$clean".';
    }
    final taken = state.trip.members.any(
      (m) => m.id != memberId && m.name.toLowerCase() == lower,
    );
    if (taken) return 'Someone in this group already uses that name.';

    _commit(
      state.copyWith(
        trip: state.trip.copyWith(
          members: [
            for (final m in state.trip.members)
              m.id == memberId ? m.copyWith(name: clean) : m,
          ],
        ),
      ),
    );
    if (isSelf) ref.read(sessionStoreProvider)?.setDisplayName(clean);
    return null;
  }

  /// A name no one else in [taken] uses ("Maya", then "Maya 2", "Maya 3"...).
  static String uniqueName(String base, Iterable<String> taken) {
    final used = {for (final n in taken) n.toLowerCase()};
    if (!used.contains(base.toLowerCase())) return base;
    for (var i = 2; ; i++) {
      final candidate = '$base $i';
      if (!used.contains(candidate.toLowerCase())) return candidate;
    }
  }

  void updateTripName(String newName) {
    final clean = newName.trim();
    if (clean.isEmpty) return;
    state = state.copyWith(trip: state.trip.copyWith(name: clean));
    _pushSync();
  }

  /// Switches the base currency. Every total, balance, ring and transfer is
  /// recomputed with converted amounts (expenses keep their original currency).
  void updateBaseCurrency(String newCurrency) {
    final code = newCurrency.toUpperCase();
    if (code == state.trip.baseCurrency) return;
    // Settlements are stored in the currency they were paid in; rebase them.
    final rebased = state.settlements
        .map(
          (s) => SettlementPayment(
            id: s.id,
            fromMemberId: s.fromMemberId,
            toMemberId: s.toMemberId,
            amount: CurrencyHelper.convert(s.amount, s.currency, code),
            currency: code,
            paidAt: s.paidAt,
          ),
        )
        .toList();
    _commit(
      state.copyWith(
        trip: state.trip.copyWith(baseCurrency: code),
        settlements: rebased,
      ),
    );
  }

  /// Home currency used for the secondary "≈" amounts.
  void updateHomeCurrency(String newCurrency) {
    final code = newCurrency.toUpperCase();
    if (code == state.trip.homeCurrency) return;
    state = state.copyWith(trip: state.trip.copyWith(homeCurrency: code));
    _pushSync();
  }

  /// Starts a brand-new, empty trip from the Landing / Setup Wizard.
  ///
  /// [friends] are plain names (no app install needed): blanks, duplicates
  /// (case-insensitive) and the word "you" are ignored. The new trip gets its
  /// own group code, so it never collides with a previous one.
  void startNewTrip({
    required String name,
    required String currency,
    String homeCurrency = 'USD',
    List<String> friends = const [],
  }) {
    _joinedMemberId = null;
    final cleanName = name.trim().isEmpty ? 'My Trip' : name.trim();
    final seen = <String>{'you'};
    final members = <TripMember>[
      const TripMember(id: 'you', name: 'You', isCurrentUser: true),
    ];
    final stamp = DateTime.now().microsecondsSinceEpoch;
    for (final raw in friends) {
      final n = raw.trim();
      if (n.isEmpty || !seen.add(n.toLowerCase())) continue;
      members.add(TripMember(id: 'mem_${stamp}_${members.length}', name: n));
    }

    final now = DateTime.now();
    final code = generateSquadCode();
    final next = TripState(
      trip: Trip(
        id: 'trip_$stamp',
        name: cleanName,
        baseCurrency: currency.toUpperCase(),
        homeCurrency: homeCurrency.toUpperCase(),
        members: members,
        expenses: const [],
        createdAt: now,
        startDate: DateTime(now.year, now.month, now.day),
        hostUid: _uid,
      ),
      squadCode: code,
      currentMemberId: 'you',
      syncStatus: state.syncStatus,
    );
    state = _withCalculatedBalances(next);
    _listenToSync(code);
    _pushSync();
  }

  /// One-tap shortcut: the pre-loaded Tokyo demo trip.
  void loadDemoTrip() {
    _joinedMemberId = null;
    final code = generateSquadCode();
    state = _withCalculatedBalances(
      _hostedBy(TripState.initial(squadCode: code))
          .copyWith(syncStatus: state.syncStatus),
    );
    _listenToSync(code);
    _pushSync();
  }

  void setCategoryFilter(ExpenseCategory? category) {
    if (category == null) {
      state = state.copyWith(clearCategoryFilter: true);
    } else {
      state = state.copyWith(selectedFilterCategory: category);
    }
  }

  void setDateFilter(DateFilter filter) {
    state = state.copyWith(dateFilter: filter);
  }

  /// Changes the trip's first day; expenses before it become "Pre-Trip".
  void updateTripStartDate(DateTime start) {
    final day = startOfDay(start);
    _commit(
      state.copyWith(
        trip: state.trip.copyWith(startDate: day),
        dateFilter: const DateFilter.all(),
      ),
    );
  }

  void setAiMatcherActive(bool active) {
    state = state.copyWith(isAiMatcherActive: active);
  }

  // ---------------------------------------------------------------------------
  // Slips & matcher
  // ---------------------------------------------------------------------------

  void addSlip(BankSlip slip) {
    state = state.copyWith(
      slips: [slip, ...state.slips.where((s) => s.id != slip.id)],
    );
  }

  void dismissSlip(String slipId) {
    state = state.copyWith(
      slips: state.slips.where((s) => s.id != slipId).toList(),
    );
  }

  /// Links an unmatched slip to an expense (manual verification).
  void linkSlip(String slipId, String expenseId) {
    final updated = state.slips
        .map(
          (s) => s.id == slipId
              ? s.copyWith(targetExpenseId: expenseId, matchPercentage: 75)
              : s,
        )
        .toList();
    state = state.copyWith(slips: updated);
  }

  /// Confirms the given slips: the linked expenses become "Matched & Verified".
  /// Slips without a target are skipped. Returns the number confirmed.
  int confirmSlips(List<String> slipIds) {
    final ids = slipIds.toSet();
    final targets = <String>{};
    final updatedSlips = state.slips.map((s) {
      if (ids.contains(s.id) && s.targetExpenseId != null) {
        targets.add(s.targetExpenseId!);
        return s.copyWith(isConfirmed: true);
      }
      return s;
    }).toList();
    if (targets.isEmpty) return 0;

    final updatedExpenses = state.trip.expenses
        .map(
          (e) => targets.contains(e.id)
              ? e.copyWith(slipStatus: SlipStatus.matched)
              : e,
        )
        .toList();
    _commit(
      state.copyWith(
        trip: state.trip.copyWith(expenses: updatedExpenses),
        slips: updatedSlips,
      ),
    );
    return targets.length;
  }

  /// Batch matches slips: changes slipStatus to matched for given expense IDs
  void batchConfirmSlips(List<String> expenseIds) {
    final ids = expenseIds.toSet();
    final updatedExpenses = state.trip.expenses
        .map(
          (e) => ids.contains(e.id)
              ? e.copyWith(slipStatus: SlipStatus.matched)
              : e,
        )
        .toList();
    final updatedSlips = state.slips
        .map(
          (s) => s.targetExpenseId != null && ids.contains(s.targetExpenseId)
              ? s.copyWith(isConfirmed: true)
              : s,
        )
        .toList();
    _commit(
      state.copyWith(
        trip: state.trip.copyWith(expenses: updatedExpenses),
        slips: updatedSlips,
      ),
    );
  }

  /// Marks an expense as paid in cash: no receipt is needed and any slip that
  /// was proposed for it is detached (it returns to "manual verification").
  void markExpenseCash(String expenseId) {
    final updatedExpenses = state.trip.expenses
        .map(
          (e) =>
              e.id == expenseId ? e.copyWith(slipStatus: SlipStatus.cash) : e,
        )
        .toList();
    final updatedSlips = state.slips
        .map(
          (s) => s.targetExpenseId == expenseId
              ? s.copyWith(
                  clearTarget: true,
                  matchPercentage: 0,
                  isConfirmed: false,
                )
              : s,
        )
        .toList();
    _commit(
      state.copyWith(
        trip: state.trip.copyWith(expenses: updatedExpenses),
        slips: updatedSlips,
      ),
    );
  }

  /// Detaches a slip from its proposed expense (the user said "Wrong").
  void detachSlip(String slipId) {
    state = state.copyWith(
      slips: state.slips
          .map(
            (s) => s.id == slipId
                ? s.copyWith(
                    clearTarget: true,
                    matchPercentage: 0,
                    isConfirmed: false,
                  )
                : s,
          )
          .toList(),
    );
  }

  /// The user picked [slipId] as the right receipt for [expenseId]: any other
  /// slip proposed for that expense is detached, the pair is confirmed and the
  /// expense becomes "Matched & Verified".
  void replaceSlipForExpense(String expenseId, String slipId) {
    final updatedSlips = state.slips.map((s) {
      if (s.id == slipId) {
        return s.copyWith(
          targetExpenseId: expenseId,
          matchPercentage: 100,
          isConfirmed: true,
        );
      }
      if (s.targetExpenseId == expenseId) {
        return s.copyWith(
          clearTarget: true,
          matchPercentage: 0,
          isConfirmed: false,
        );
      }
      return s;
    }).toList();
    final updatedExpenses = state.trip.expenses
        .map(
          (e) => e.id == expenseId
              ? e.copyWith(slipStatus: SlipStatus.matched)
              : e,
        )
        .toList();
    _commit(
      state.copyWith(
        trip: state.trip.copyWith(expenses: updatedExpenses),
        slips: updatedSlips,
      ),
    );
  }

  /// Adds a freshly analysed [slip] and immediately pairs it with [expenseId].
  void attachNewSlipToExpense(String expenseId, BankSlip slip) {
    addSlip(slip);
    replaceSlipForExpense(expenseId, slip.id);
  }

  /// Logs [expense] for a slip that had no matching expense (typically an
  /// itemized foreign receipt). The expense is stored as "Matched & Verified"
  /// and the slip is linked to it and confirmed in one step.
  ExpenseItem addExpenseForSlip(String slipId, ExpenseItem expense) {
    BankSlip? slip;
    for (final s in state.slips) {
      if (s.id == slipId) slip = s;
    }
    final verified = expense.copyWith(
      slipStatus: SlipStatus.matched,
      inferenceSource: slip?.inferenceSource,
      modelInfo: slip?.modelInfo,
      latencyMs: slip?.latencyMs,
    );
    addExpense(verified);
    final created = state.trip.expenses.last;
    state = state.copyWith(
      slips: state.slips
          .map(
            (s) => s.id == slipId
                ? s.copyWith(
                    targetExpenseId: created.id,
                    matchPercentage: 100,
                    isConfirmed: true,
                  )
                : s,
          )
          .toList(),
    );
    return created;
  }

  // ---------------------------------------------------------------------------
  // Settlement
  // ---------------------------------------------------------------------------

  /// Marks a pending transfer as paid. The payment is applied on top of the
  /// expense balances, so every net balance, ring and banner updates at once.
  /// Returns `false` if the transfer is no longer part of the plan.
  bool markTransferSettled(String transferId) {
    SettlementTransfer? transfer;
    for (final t in state.simplifiedTransfers) {
      if (t.id == transferId) transfer = t;
    }
    if (transfer == null) return false;

    final payment = SettlementPayment(
      id: 'pay_${DateTime.now().microsecondsSinceEpoch}_${transfer.id}',
      fromMemberId: transfer.fromMemberId,
      toMemberId: transfer.toMemberId,
      amount: transfer.amount,
      currency: transfer.currency,
      paidAt: DateTime.now(),
      createdByUid: _uid,
    );
    _commit(state.copyWith(settlements: [...state.settlements, payment]));
    return true;
  }

  /// Records a real repayment: "[fromMemberId] paid [toMemberId] [amount]".
  /// It is deducted from the outstanding balances at once. Returns the stored
  /// payment, or `null` for invalid input (same person, no amount, unknown id).
  SettlementPayment? recordRepayment({
    required String fromMemberId,
    required String toMemberId,
    required double amount,
    String? currency,
    DateTime? paidAt,
    String? note,
    String? slipImageBase64,
  }) {
    final ids = state.trip.members.map((m) => m.id).toSet();
    if (fromMemberId == toMemberId ||
        !ids.contains(fromMemberId) ||
        !ids.contains(toMemberId) ||
        amount <= 0) {
      return null;
    }
    final cleanNote = note?.trim();
    final payment = SettlementPayment(
      id: 'pay_${DateTime.now().microsecondsSinceEpoch}_$fromMemberId',
      fromMemberId: fromMemberId,
      toMemberId: toMemberId,
      amount: amount,
      currency: (currency ?? state.trip.baseCurrency).toUpperCase(),
      paidAt: paidAt ?? DateTime.now(),
      note: (cleanNote == null || cleanNote.isEmpty) ? null : cleanNote,
      slipImageBase64: slipImageBase64,
      createdByUid: _uid,
    );
    _commit(state.copyWith(settlements: [...state.settlements, payment]));
    return payment;
  }

  /// Host only: guests can still add entries but not edit or delete any.
  bool setLockGuestEdits(bool locked) {
    if (!_permissions.canToggleLock) return false;
    _commit(state.copyWith(trip: state.trip.copyWith(lockGuestEdits: locked)));
    return true;
  }

  /// Reverts a recorded payment (Undo). Guests can only undo their own.
  void undoSettlement(String paymentId) {
    for (final p in state.settlements) {
      if (p.id == paymentId && !canModifyRepayment(p)) return;
    }
    _commit(
      state.copyWith(
        settlements: state.settlements.where((s) => s.id != paymentId).toList(),
      ),
    );
  }

  void resetSettledTransfers() {
    if (!_permissions.canRemoveMembers) return; // host (or legacy trip) only
    _commit(state.copyWith(settlements: const []));
  }

  // ---------------------------------------------------------------------------
  // Group join
  // ---------------------------------------------------------------------------

  /// Joins an existing 6-digit group code from another device.
  /// Joins a group by code (or a pasted invite link) under [displayName]
  /// (defaults to the name saved on this device, then "Traveler N"). The
  /// name can be changed at any time with [renameMember].
  ///
  /// The join is a **field-level write** of one new member entry: it never
  /// replaces the group's document, so a friend adding expenses at the same
  /// moment loses nothing.
  Future<JoinSquadResult> joinSquad(
    String squadCode, {
    String? displayName,
    bool createIfMissing = true,
  }) async {
    final cleanCode = normalizeSquadCode(squadCode);
    if (cleanCode == null) return JoinSquadResult.invalid;
    final store = ref.read(sessionStoreProvider);
    final wanted = (displayName ?? store?.displayName ?? '').trim().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );

    if (!_syncService.isAvailable) {
      state = state.copyWith(
        squadCode: cleanCode,
        syncStatus: SyncStatus.offline,
      );
      return JoinSquadResult.offline;
    }

    final remoteUpdate = await _syncService.fetchTrip(cleanCode);
    if (remoteUpdate != null && remoteUpdate.trip.members.isNotEmpty) {
      // Join as a new traveler so two devices never share one identity.
      final myId = 'mem_${DateTime.now().microsecondsSinceEpoch}';
      _joinedMemberId = myId;
      final existing = remoteUpdate.trip.members.map((m) => m.name).toList();
      final myName = uniqueName(
        wanted.isEmpty
            ? 'Traveler ${remoteUpdate.trip.members.length + 1}'
            : wanted.length > maxNameLength
            ? wanted.substring(0, maxNameLength)
            : wanted,
        existing,
      );
      final me = TripMember(id: myId, name: myName);
      final members = [
        ...remoteUpdate.trip.members.map(
          (m) => m.copyWith(isCurrentUser: false),
        ),
        me.copyWith(isCurrentUser: true),
      ];
      _saveTimer?.cancel();
      state = _withCalculatedBalances(
        state.copyWith(
          squadCode: cleanCode,
          currentMemberId: myId,
          trip: remoteUpdate.trip.copyWith(members: members),
          settlements: remoteUpdate.settlements,
          clearCategoryFilter: true,
          hasTrip: true,
        ),
      );
      if (wanted.isNotEmpty) store?.setDisplayName(myName);
      _listenToSync(cleanCode);
      _pushSync();
      return JoinSquadResult.joined;
    }

    if (!createIfMissing) return JoinSquadResult.notFound;

    // Create a new synced trip under this code
    state = state.copyWith(squadCode: cleanCode);
    _listenToSync(cleanCode);
    _pushSync();
    return JoinSquadResult.created;
  }
}
