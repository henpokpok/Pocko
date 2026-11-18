import '../../core/enums/inference_source.dart';
import '../../models/expense_item.dart';
import '../../services/hybrid_ai/hybrid_ai_service.dart';

/// State of the Hybrid AI diagnostic sandbox. Trip data itself lives in the
/// shared trip controller, so anything added here appears everywhere.
class SandboxState {
  final String inputText;

  /// `null` follows the Firebase Remote Config `ai_inference_mode`.
  final InferenceMode? selectedMode;
  final bool forceSimulated;
  final bool isLoading;
  final bool isProbing;
  final HybridAiResult? latestResult;
  final List<ExpenseItem> parsedExpenses;
  final Map<String, dynamic>? runtimeStatus;
  final String? errorMessage;

  const SandboxState({
    this.inputText = 'Ichiran ramen 4800 Alex paid, split Maya and Liam',
    this.selectedMode,
    this.forceSimulated = false,
    this.isLoading = false,
    this.isProbing = false,
    this.latestResult,
    this.parsedExpenses = const [],
    this.runtimeStatus,
    this.errorMessage,
  });

  SandboxState copyWith({
    String? inputText,
    InferenceMode? selectedMode,
    bool clearMode = false,
    bool? forceSimulated,
    bool? isLoading,
    bool? isProbing,
    HybridAiResult? latestResult,
    List<ExpenseItem>? parsedExpenses,
    bool clearResults = false,
    Map<String, dynamic>? runtimeStatus,
    String? errorMessage,
    bool clearError = false,
  }) {
    return SandboxState(
      inputText: inputText ?? this.inputText,
      selectedMode: clearMode ? null : (selectedMode ?? this.selectedMode),
      forceSimulated: forceSimulated ?? this.forceSimulated,
      isLoading: isLoading ?? this.isLoading,
      isProbing: isProbing ?? this.isProbing,
      latestResult: clearResults ? null : (latestResult ?? this.latestResult),
      parsedExpenses: clearResults
          ? const []
          : (parsedExpenses ?? this.parsedExpenses),
      runtimeStatus: runtimeStatus ?? this.runtimeStatus,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
