import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/enums/inference_source.dart';
import '../../services/hybrid_ai/ai_unavailable.dart';
import '../../services/hybrid_ai/hybrid_ai_service.dart';
import '../trip/trip_controller.dart';
import 'sandbox_state.dart';

final sandboxControllerProvider =
    NotifierProvider<SandboxController, SandboxState>(SandboxController.new);

class SandboxController extends Notifier<SandboxState> {
  @override
  SandboxState build() => const SandboxState();

  HybridAiService get _ai => ref.read(hybridAiServiceProvider);

  void setInputText(String text) {
    state = state.copyWith(inputText: text, clearError: true);
  }

  void setInferenceMode(InferenceMode? mode) {
    state = mode == null
        ? state.copyWith(clearMode: true)
        : state.copyWith(selectedMode: mode);
  }

  /// Re-checks which runtime this device can really execute.
  Future<void> probeRuntime() async {
    state = state.copyWith(isProbing: true);
    try {
      final status = await _service().checkModelStatus();
      state = state.copyWith(runtimeStatus: status, isProbing: false);
    } catch (e) {
      state = state.copyWith(
        isProbing: false,
        runtimeStatus: {
          'isAvailable': false,
          'status': 'PROBE_FAILED',
          'modelInfo': '$e',
          'runtime': 'simulated',
        },
      );
    }
  }

  HybridAiService _service() => _ai;

  Future<void> parseExpense() async {
    final text = state.inputText.trim();
    if (text.isEmpty) {
      state = state.copyWith(
        errorMessage: 'Please enter an expense description',
      );
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final trip = ref.read(tripControllerProvider);
      final self =
          trip.memberById(trip.currentMemberId) ?? trip.trip.members.first;

      final result = await _service().parseExpenseText(
        text: text,
        mode: state.selectedMode,
        tripCurrency: trip.trip.baseCurrency,
        memberNames: trip.trip.members.map((m) => m.name).toList(),
        defaultPayer: self.name,
      );

      final items = result
          .toExpenseItems(
            defaultCurrency: trip.trip.baseCurrency,
            defaultPayerId: self.id,
            allMemberIds: trip.trip.members.map((m) => m.id).toList(),
            nameToIdMap: {for (final m in trip.trip.members) m.name: m.id},
          )
          .where((e) => e.amount > 0)
          .toList();

      state = state.copyWith(
        isLoading: false,
        latestResult: result,
        parsedExpenses: items,
        errorMessage: items.isEmpty
            ? 'No amount found in that sentence.'
            : null,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e is AiUnavailableException
            ? e.userMessage
            : 'Processing failed: $e',
      );
    }
  }

  /// Adds every parsed expense to the shared trip (all tabs update at once).
  int addParsedToTrip() {
    final items = state.parsedExpenses;
    if (items.isEmpty) return 0;
    ref.read(tripControllerProvider.notifier).addExpenses(items);
    state = state.copyWith(clearResults: true);
    return items.length;
  }

  void clearResults() =>
      state = state.copyWith(clearResults: true, clearError: true);
}
