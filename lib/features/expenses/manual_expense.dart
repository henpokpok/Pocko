import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/enums/expense_category.dart';
import '../../core/enums/inference_source.dart';
import '../../core/widgets/pocko_snack.dart';
import '../../models/expense_item.dart';
import '../trip/trip_controller.dart';
import 'expense_editor_sheet.dart';

/// Opens the standard Add Expense sheet (80 % draggable `showPockoBottomSheet`)
/// with a blank draft and logs the result. Used by the capture overlay's
/// "Manual Expense" action.
Future<void> addManualExpense(BuildContext context, WidgetRef ref) async {
  final tripState = ref.read(tripControllerProvider);
  final draft = ExpenseItem(
    id: 'exp_${DateTime.now().microsecondsSinceEpoch}',
    title: '',
    amount: 0,
    currency: tripState.trip.baseCurrency,
    category: ExpenseCategory.MISC,
    payerId: tripState.currentMemberId,
    splitWithMemberIds: tripState.trip.members.map((m) => m.id).toList(),
    createdAt: DateTime.now(),
    inferenceSource: InferenceSource.manual,
  );
  final result = await showExpenseEditor(
    context,
    expense: draft,
    tripState: tripState,
    isNew: true,
  );
  if (result == null || !context.mounted) return;
  ref.read(tripControllerProvider.notifier).addExpense(result);
  showPockoSnack(
    context,
    '${result.title} added',
    detail:
        '${result.category.displayName} • split ${result.splitWithMemberIds.length} ways • balances updated',
    icon: result.category.icon,
  );
}
