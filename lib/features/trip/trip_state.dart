import 'package:intl/intl.dart';

import '../../core/enums/expense_category.dart';
import '../../core/enums/inference_source.dart';
import '../../core/enums/slip_status.dart';
import '../../models/bank_slip.dart';
import '../../models/expense_item.dart';
import '../../models/settlement_payment.dart';
import '../../models/settlement_transfer.dart';
import '../../models/trip.dart';
import '../../models/trip_member.dart';
import 'date_filter.dart';

/// Live status of the Firestore group-sync channel.
enum SyncStatus {
  /// Firebase is not configured on this build (standalone / offline-first mode).
  offline('Offline-first • local only'),
  connecting('Connecting to group…'),
  live('Live • Firestore multi-device sync');

  final String label;
  const SyncStatus(this.label);
}

/// Normalizes user input such as `782901`, `782 901` or `782-901` into `782-901`.
/// Also accepts a pasted invite link (`pocko://join/782-901`,
/// `https://pocko.app/join/782901`, "Join my trip: ... 782-901").
/// Returns `null` when the input is not a 6-digit group code.
String? normalizeSquadCode(String input) {
  // A full "NNN-NNN" / "NNN NNN" / "NNNNNN" group somewhere in the text wins,
  // so ports, dates or other numbers in a link are ignored.
  final match = RegExp(r'(?<!\d)(\d{3})[\s\-]?(\d{3})(?!\d)').firstMatch(input);
  if (match != null) return '${match.group(1)}-${match.group(2)}';
  final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length != 6) return null;
  return '${digits.substring(0, 3)}-${digits.substring(3)}';
}

/// The shareable invite text for a group: a deep-link style URL plus the code.
String squadInviteLink(String squadCode) =>
    'pocko://join/${squadCode.replaceAll('-', '')}';

class TripState {
  final Trip trip;
  final String squadCode;

  /// Id of the member that represents the person holding this device.
  final String currentMemberId;
  final bool isAiMatcherActive;

  /// Outstanding net balances (expenses minus settlements already paid).
  final Map<String, double> netBalances;

  /// Remaining transfers needed to settle every outstanding balance.
  final List<SettlementTransfer> simplifiedTransfers;

  /// Transfers that were marked as paid.
  final List<SettlementPayment> settlements;
  final List<BankSlip> slips;
  final ExpenseCategory? selectedFilterCategory;
  final DateFilter dateFilter;
  final SyncStatus syncStatus;

  /// `false` for the placeholder state of a fresh install that has not created
  /// or joined a trip yet. The [trip] is then a harmless stand-in (one member,
  /// no expenses, a valid currency) so no screen ever meets a null trip.
  final bool hasTrip;

  const TripState({
    required this.trip,
    this.squadCode = '782-901',
    this.currentMemberId = 'you',
    this.isAiMatcherActive = true,
    this.netBalances = const {},
    this.simplifiedTransfers = const [],
    this.settlements = const [],
    this.slips = const [],
    this.selectedFilterCategory,
    this.dateFilter = const DateFilter.all(),
    this.syncStatus = SyncStatus.offline,
    this.hasTrip = true,
  });

  TripState copyWith({
    Trip? trip,
    String? squadCode,
    String? currentMemberId,
    bool? isAiMatcherActive,
    Map<String, double>? netBalances,
    List<SettlementTransfer>? simplifiedTransfers,
    List<SettlementPayment>? settlements,
    List<BankSlip>? slips,
    ExpenseCategory? selectedFilterCategory,
    bool clearCategoryFilter = false,
    DateFilter? dateFilter,
    SyncStatus? syncStatus,
    bool? hasTrip,
  }) {
    return TripState(
      trip: trip ?? this.trip,
      squadCode: squadCode ?? this.squadCode,
      currentMemberId: currentMemberId ?? this.currentMemberId,
      isAiMatcherActive: isAiMatcherActive ?? this.isAiMatcherActive,
      netBalances: netBalances ?? this.netBalances,
      simplifiedTransfers: simplifiedTransfers ?? this.simplifiedTransfers,
      settlements: settlements ?? this.settlements,
      slips: slips ?? this.slips,
      selectedFilterCategory: clearCategoryFilter
          ? null
          : (selectedFilterCategory ?? this.selectedFilterCategory),
      dateFilter: dateFilter ?? this.dateFilter,
      syncStatus: syncStatus ?? this.syncStatus,
      hasTrip: hasTrip ?? this.hasTrip,
    );
  }

  /// The placeholder for a device that has no trip yet (fresh install).
  factory TripState.placeholder({required String squadCode}) {
    final now = DateTime.now();
    return TripState(
      trip: Trip(
        id: 'no_trip',
        name: '',
        baseCurrency: 'USD',
        homeCurrency: 'USD',
        members: const [
          TripMember(id: 'you', name: 'You', isCurrentUser: true),
        ],
        expenses: const [],
        createdAt: now,
        startDate: DateTime(now.year, now.month, now.day),
      ),
      squadCode: squadCode,
      hasTrip: false,
    );
  }

  /// The trip exists but its first day is still in the future.
  bool get isUpcoming =>
      hasTrip && startOfDay(trip.startDate).isAfter(startOfDay(DateTime.now()));

  /// Home shows the welcoming placeholder instead of the live dashboard: no
  /// trip at all, or only a trip that has not started yet.
  bool get hasNoActiveTrip => !hasTrip || isUpcoming;

  /// Ids of transfers that were paid (kept for UI/test compatibility).
  Set<String> get settledTransferIds => settlements.map((s) => s.id).toSet();

  /// Total spend converted into the trip's base currency.
  double get totalSpend => trip.expenses.fold(
    0.0,
    (sum, item) => sum + item.amountIn(trip.baseCurrency),
  );

  /// Expenses newest-first, honouring the category and date filters.
  List<ExpenseItem> get filteredExpenses {
    final list = trip.expenses
        .where(
          (e) =>
              (selectedFilterCategory == null ||
                  e.category == selectedFilterCategory) &&
              dateFilter.matches(e, trip.startDate),
        )
        .toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  bool isPreTrip(ExpenseItem e) =>
      e.expenseDateTime.isBefore(startOfDay(trip.startDate));

  List<ExpenseItem> get preTripExpenses =>
      trip.expenses.where(isPreTrip).toList();

  /// Calendar days of the trip, from its start day to today (or the latest
  /// expense), used by the date filter strip.
  List<DateTime> get tripDays {
    final first = startOfDay(trip.startDate);
    var last = startOfDay(DateTime.now());
    for (final e in trip.expenses) {
      final d = startOfDay(e.expenseDateTime);
      if (!d.isBefore(first) && d.isAfter(last)) last = d;
    }
    final days = <DateTime>[];
    for (
      var d = first;
      !d.isAfter(last) && days.length < 60;
      d = DateTime(d.year, d.month, d.day + 1)
    ) {
      days.add(d);
    }
    return days;
  }

  /// Total spent (base currency) on the expenses a [filter] selects.
  double spendFor(DateFilter filter) => trip.expenses
      .where((e) => filter.matches(e, trip.startDate))
      .fold(0.0, (sum, e) => sum + e.amountIn(trip.baseCurrency));

  /// The [count] highest-value expenses (base currency), biggest first.
  List<ExpenseItem> topExpenses([int count = 3]) {
    final list = List<ExpenseItem>.from(trip.expenses)
      ..sort(
        (a, b) => b
            .amountIn(trip.baseCurrency)
            .compareTo(a.amountIn(trip.baseCurrency)),
      );
    return list.take(count).toList();
  }

  List<ExpenseItem> get recentExpenses {
    final list = List<ExpenseItem>.from(trip.expenses)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list.take(3).toList();
  }

  List<BankSlip> get pendingSlips =>
      slips.where((s) => !s.isConfirmed).toList();

  int get waitingExpenseCount => trip.expenses
      .where((e) => e.slipStatus == SlipStatus.waitingForSlip)
      .length;

  /// Average cost per traveler in the base currency.
  double get perPersonSpend =>
      trip.members.isEmpty ? 0.0 : totalSpend / trip.members.length;

  /// Sum of everything still owed (base currency).
  double get outstandingTotal =>
      simplifiedTransfers.fold(0.0, (sum, t) => sum + t.amount);

  TripMember? memberById(String id) {
    for (final m in trip.members) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Friendly label: "You" for this device, "Host" for another device's "You".
  String displayName(TripMember member) {
    if (member.id == currentMemberId) return 'You';
    if (member.name.trim().toLowerCase() == 'you') return 'Host';
    return member.name;
  }

  String nameOf(String memberId) {
    final m = memberById(memberId);
    return m == null ? memberId : displayName(m);
  }

  /// Human readable, always-fresh date range ("Nov 14 – Nov 16 • 3 Days").
  /// Pre-Trip expenses do not stretch the range.
  String get dateRange {
    final start = startOfDay(trip.startDate);
    var end = DateTime.now();
    for (final e in trip.expenses) {
      if (!isPreTrip(e) && e.createdAt.isAfter(end)) end = e.createdAt;
    }
    final days = startOfDay(end).difference(start).inDays + 1;
    final fmt = DateFormat('MMM d');
    return '${fmt.format(start)} – ${fmt.format(end)} • $days ${days == 1 ? 'Day' : 'Days'}';
  }

  factory TripState.initial({String squadCode = '782-901'}) {
    const you = TripMember(id: 'you', name: 'You', isCurrentUser: true);
    const alex = TripMember(id: 'alex', name: 'Alex');
    const maya = TripMember(id: 'maya', name: 'Maya');
    const liam = TripMember(id: 'liam', name: 'Liam');

    final now = DateTime.now();
    // Demo timestamps hang off 15:00 today (not off the wall clock): shortly
    // after midnight "2 hours ago" used to land on yesterday and the demo
    // showed no Today group.
    final anchor = DateTime(now.year, now.month, now.day, 15);

    final initialExpenses = [
      ExpenseItem(
        id: 'exp_pre1',
        title: 'Travel Insurance (booked in advance)',
        amount: 3300,
        currency: 'JPY',
        category: ExpenseCategory.INSURANCE,
        payerId: 'you',
        splitWithMemberIds: const ['you'],
        createdAt: anchor.subtract(const Duration(days: 12, hours: 3)),
        inferenceSource: InferenceSource.manual,
        slipStatus: SlipStatus.matched,
      ),
      ExpenseItem(
        id: 'exp_1',
        title: 'Ichiran Ramen Shinjuku',
        amount: 4800,
        currency: 'JPY',
        category: ExpenseCategory.MEAL,
        payerId: 'you',
        splitWithMemberIds: const ['you', 'alex', 'maya', 'liam'],
        createdAt: anchor.subtract(const Duration(hours: 28)),
        inferenceSource: InferenceSource.onDevice,
        modelInfo: 'Gemini Nano (seed data)',
        latencyMs: 92,
        slipStatus: SlipStatus.matched,
      ),
      ExpenseItem(
        id: 'exp_2',
        title: 'Tokyo Metro 72hr Passes',
        amount: 6000,
        currency: 'JPY',
        category: ExpenseCategory.TRANSPORT,
        payerId: 'alex',
        splitWithMemberIds: const ['you', 'alex', 'maya', 'liam'],
        createdAt: anchor.subtract(const Duration(hours: 24)),
        inferenceSource: InferenceSource.onDevice,
        modelInfo: 'Gemini Nano (seed data)',
        latencyMs: 110,
        slipStatus: SlipStatus.matched,
      ),
      ExpenseItem(
        id: 'exp_3',
        title: 'Akihabara Gachapon & Snacks',
        amount: 3500,
        currency: 'JPY',
        category: ExpenseCategory.SNACK_CAFE,
        payerId: 'maya',
        splitWithMemberIds: const ['you', 'alex', 'maya', 'liam'],
        createdAt: anchor.subtract(const Duration(hours: 18)),
        inferenceSource: InferenceSource.onDevice,
        modelInfo: 'Gemini Nano (seed data)',
        latencyMs: 85,
        slipStatus: SlipStatus.waitingForSlip,
      ),
      ExpenseItem(
        id: 'exp_4',
        title: 'Shibuya Sky Observation Deck',
        amount: 8800,
        currency: 'JPY',
        category: ExpenseCategory.ATTRACTION,
        payerId: 'you',
        splitWithMemberIds: const ['you', 'alex', 'maya', 'liam'],
        createdAt: anchor.subtract(const Duration(hours: 12)),
        inferenceSource: InferenceSource.inCloud,
        modelInfo: 'Gemini Flash (seed data)',
        latencyMs: 480,
        slipStatus: SlipStatus.waitingForSlip,
      ),
      ExpenseItem(
        id: 'exp_5',
        title: 'TeamLab Borderless Tickets',
        amount: 15400,
        currency: 'JPY',
        category: ExpenseCategory.ATTRACTION,
        payerId: 'alex',
        splitWithMemberIds: const ['you', 'alex', 'maya', 'liam'],
        createdAt: anchor.subtract(const Duration(hours: 6)),
        inferenceSource: InferenceSource.onDevice,
        modelInfo: 'Gemini Nano (seed data)',
        latencyMs: 98,
        slipStatus: SlipStatus.waitingForSlip,
      ),
      ExpenseItem(
        id: 'exp_6',
        title: 'Shinkansen to Kyoto',
        amount: 18200,
        currency: 'JPY',
        category: ExpenseCategory.TRANSPORT,
        payerId: 'liam',
        splitWithMemberIds: const ['you', 'alex', 'maya', 'liam'],
        createdAt: anchor.subtract(const Duration(hours: 2)),
        inferenceSource: InferenceSource.onDevice,
        modelInfo: 'Gemini Nano (seed data)',
        latencyMs: 104,
        slipStatus: SlipStatus.waitingForSlip,
      ),
    ];

    final initialTrip = Trip(
      id: 'tokyo_trip',
      name: 'Tokyo Trip 🇯🇵',
      baseCurrency: 'JPY',
      members: const [you, alex, maya, liam],
      expenses: initialExpenses,
      createdAt: anchor.subtract(const Duration(days: 3)),
      startDate: DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 1)),
    );

    final initialSlips = [
      BankSlip(
        id: 'slip_1',
        bankName: 'Travel Card',
        maskedAccount: '•••• 4829',
        amount: 3500,
        currency: 'JPY',
        time: '14:22',
        merchant: 'Akihabara Gachapon',
        targetExpenseId: 'exp_3',
        matchPercentage: 100,
        maskedText: 'Travel Card • Card payment ¥3,500 • Akihabara Gachapon • Card •••• 4829',
        maskedFieldCount: 1,
        latencyMs: 71,
        modelInfo: 'Gemini Nano (seed data)',
        createdAt: anchor.subtract(const Duration(hours: 17)),
      ),
      BankSlip(
        id: 'slip_2',
        bankName: 'Credit Card',
        maskedAccount: '•••• 1104',
        amount: 8800,
        currency: 'JPY',
        time: '16:05',
        merchant: 'Shibuya Sky',
        targetExpenseId: 'exp_4',
        matchPercentage: 100,
        maskedText:
            'Credit Card • You spent ¥8,800 at SHIBUYA SKY • Card •••• 1104',
        maskedFieldCount: 1,
        latencyMs: 68,
        modelInfo: 'Gemini Nano (seed data)',
        createdAt: anchor.subtract(const Duration(hours: 11)),
      ),
      BankSlip(
        id: 'slip_3',
        bankName: 'Mobile Pay • Transit Card',
        maskedAccount: '•••• 9021',
        amount: 18200,
        currency: 'JPY',
        time: '18:40',
        merchant: 'Shinkansen Ticket',
        targetExpenseId: 'exp_6',
        matchPercentage: 98,
        maskedText: 'Mobile Pay • Transit card top-up ¥18,200 • Rail ticket • Device •••• 9021',
        maskedFieldCount: 1,
        latencyMs: 74,
        modelInfo: 'Gemini Nano (seed data)',
        createdAt: anchor.subtract(const Duration(hours: 1)),
      ),
    ];

    return TripState(
      trip: initialTrip,
      squadCode: squadCode,
      slips: initialSlips,
    );
  }
}
