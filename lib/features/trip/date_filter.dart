import '../../models/expense_item.dart';

DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

enum DateFilterKind { all, preTrip, day }

/// Date filter of the Expenses tab: every date, only Pre-Trip expenses (dated
/// before the trip's start day) or a single calendar day.
class DateFilter {
  final DateFilterKind kind;
  final DateTime? day;

  const DateFilter.all() : kind = DateFilterKind.all, day = null;
  const DateFilter.preTrip() : kind = DateFilterKind.preTrip, day = null;
  DateFilter.day(DateTime d) : kind = DateFilterKind.day, day = startOfDay(d);

  bool get isAll => kind == DateFilterKind.all;

  bool matches(ExpenseItem e, DateTime tripStart) {
    final tripDay = startOfDay(tripStart);
    switch (kind) {
      case DateFilterKind.all:
        return true;
      case DateFilterKind.preTrip:
        return e.expenseDateTime.isBefore(tripDay);
      case DateFilterKind.day:
        return startOfDay(e.expenseDateTime) == day;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is DateFilter && other.kind == kind && other.day == day;

  @override
  int get hashCode => Object.hash(kind, day);
}
