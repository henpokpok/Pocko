import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/enums/inference_source.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_helper.dart';
import '../../core/widgets/pocko_snack.dart';
import '../../core/widgets/pocko_toast.dart';
import '../../core/widgets/telemetry_pill.dart';
import '../../models/settlement_transfer.dart';
import '../../services/remote_config/remote_config_service.dart';
import '../trip/trip_controller.dart';
import 'sandbox_controller.dart';
import 'sandbox_state.dart';

class HybridSandboxScreen extends ConsumerStatefulWidget {
  const HybridSandboxScreen({super.key});

  @override
  ConsumerState<HybridSandboxScreen> createState() =>
      _HybridSandboxScreenState();
}

class _HybridSandboxScreenState extends ConsumerState<HybridSandboxScreen> {
  late final TextEditingController _textController;

  static const List<String> _presets = [
    'Ichiran ramen 4800 Alex paid, split Maya and Liam',
    'Starbucks matcha latte 650 Maya paid for herself',
    'Shinkansen bullet train 14000 Liam paid, split all',
    'Motion sickness medicine 850 Alex paid',
  ];

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(
      text: ref.read(sandboxControllerProvider).inputText,
    );
    // Probe the real runtime as soon as the console opens.
    Future.microtask(() {
      if (mounted) ref.read(sandboxControllerProvider.notifier).probeRuntime();
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sandboxControllerProvider);
    final controller = ref.read(sandboxControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.primaryEmeraldSubtle,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.hub_rounded,
                color: AppTheme.primaryEmeraldDark,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pocko Hybrid AI',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Diagnostic Sandbox',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: AppTheme.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Clear results',
            icon: const Icon(Icons.layers_clear_rounded),
            onPressed: controller.clearResults,
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTripHeaderCard(),
                const SizedBox(height: 12),
                _buildRuntimeCard(state, controller),
                const SizedBox(height: 12),
                _buildRemoteConfigCard(),
                const SizedBox(height: 12),
                _buildInputCard(controller),
                const SizedBox(height: 12),
                _buildInferenceControlsCard(state, controller),
                if (state.errorMessage != null) ...[
                  const SizedBox(height: 8),
                  _buildErrorBanner(state.errorMessage!),
                ],
                if (state.latestResult != null &&
                    state.parsedExpenses.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildParsedCard(state, controller),
                ],
                const SizedBox(height: 16),
                _buildSettlementCard(),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card({required Widget child, Color? border}) => DecoratedBox(
    decoration: AppTheme.surfaceDecoration(radius: 20, borderColor: border),
    child: Material(
      type: MaterialType.transparency,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );

  Widget _title(
    IconData icon,
    String text, {
    Color color = AppTheme.primaryEmeraldDark,
  }) => Row(
    children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: AppTheme.textDark,
          ),
        ),
      ),
    ],
  );

  Widget _buildTripHeaderCard() {
    final trip = ref.watch(tripControllerProvider);
    final memberListStr = trip.trip.members
        .map(trip.displayName)
        .join(', ');
    return _card(
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: AppTheme.primaryEmeraldSubtle,
            radius: 20,
            child: Text('🇯🇵', style: TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trip.trip.name,
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                Text(
                  'Members ($memberListStr) • Currency: ${trip.trip.baseCurrency}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: AppTheme.textSlate,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: AppTheme.pillRadius,
            ),
            child: Text(
              '${trip.trip.expenses.length} items',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Honest runtime diagnostics: what can this device actually execute?
  Widget _buildRuntimeCard(SandboxState state, SandboxController controller) {
    final status = state.runtimeStatus;
    final runtime = (status?['runtime'] as String?) ?? 'probing';
    final available = status?['isAvailable'] == true;
    final live = runtime != 'simulated' && runtime != 'none' && available;

    return _card(
      border: live ? AppTheme.primaryEmerald.withValues(alpha: 0.4) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _title(Icons.memory_rounded, 'Live Runtime Probe'),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: live
                      ? const Color(0xFFE8F8F0)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  live
                      ? 'LIVE RUNTIME'
                      : (status == null ? 'PROBING…' : 'SIMULATED ENGINE'),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: live
                        ? AppTheme.primaryEmeraldDark
                        : AppTheme.textSlate,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (status != null) ...[
            _kv('runtime', runtime),
            _kv('status', '${status['status']}'),
            _kv('model', '${status['modelInfo']}'),
          ],
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: state.isProbing ? null : controller.probeRuntime,
              icon: state.isProbing
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 14),
              label: const Text('Re-check', style: TextStyle(fontSize: 11)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            k,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: AppTheme.textMuted,
            ),
          ),
        ),
        Expanded(
          child: Text(
            v,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildRemoteConfigCard() {
    final remoteConfig = ref.watch(remoteConfigProvider);
    final effective = InferenceMode.fromRaw(remoteConfig.aiInferenceMode);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _title(
                  Icons.cloud_sync_rounded,
                  'Live Firebase Remote Config',
                  color: const Color(0xFFEA580C),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: remoteConfig.isConfigured
                      ? const Color(0xFFE8F8F0)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  remoteConfig.isConfigured ? 'LIVE CLOUD' : 'STANDALONE',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: remoteConfig.isConfigured
                        ? AppTheme.primaryEmeraldDark
                        : AppTheme.textSlate,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderColor),
            ),
            child: Column(
              children: [
                _rcRow(
                  'ai_inference_mode',
                  remoteConfig.aiInferenceMode,
                  Icons.tune_rounded,
                ),
                const Divider(height: 12, color: AppTheme.borderColor),
                _rcRow(
                  'cloud_fallback_model',
                  remoteConfig.cloudFallbackModel,
                  Icons.psychology_rounded,
                ),
                const Divider(height: 12, color: AppTheme.borderColor),
                _rcRow(
                  'max_output_tokens',
                  '${remoteConfig.maxOutputTokens}',
                  Icons.data_object_rounded,
                ),
                const Divider(height: 12, color: AppTheme.borderColor),
                _rcRow(
                  'prompt_template_override',
                  remoteConfig.promptTemplateOverride.isEmpty
                      ? '(default)'
                      : 'custom',
                  Icons.edit_note_rounded,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Applied to every request → ${effective.wireName} (web: ${effective.webName})',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: AppTheme.textSlate,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Status: ${remoteConfig.lastStatus}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  final success = await ref
                      .read(remoteConfigProvider.notifier)
                      .refresh();
                  if (!mounted || !context.mounted) return;
                  showPockoToast(
                    context,
                    message: success
                        ? 'Remote Config refreshed'
                        : 'Using local defaults',
                    detail: success
                        ? 'New AI policy values are active.'
                        : 'The fetch completed without new values.',
                    kind: success
                        ? PockoToastKind.success
                        : PockoToastKind.info,
                    icon: Icons.tune_rounded,
                  );
                },
                icon: const Icon(Icons.refresh_rounded, size: 14),
                label: const Text(
                  'Fetch & Activate',
                  style: TextStyle(fontSize: 11),
                ),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rcRow(String key, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppTheme.textSlate),
        const SizedBox(width: 6),
        Flexible(
          flex: 3,
          child: Text(
            key,
            style: const TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const Spacer(),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFE0E7FF),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                color: Color(0xFF3730A3),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInputCard(SandboxController controller) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(
            Icons.auto_awesome,
            'Natural Language Expense Input (English)',
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _textController,
            onChanged: controller.setInputText,
            maxLines: 2,
            decoration: InputDecoration(
              hintText:
                  'e.g. Ichiran ramen 4800 Alex paid, split Maya and Liam',
              suffixIcon: IconButton(
                tooltip: 'Clear text',
                icon: const Icon(Icons.clear_rounded, size: 20),
                onPressed: () {
                  _textController.clear();
                  controller.setInputText('');
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Preset Test Prompts (Tap to test):',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: _presets
                .map(
                  (preset) => ActionChip(
                    label: Text(preset, style: const TextStyle(fontSize: 11)),
                    backgroundColor: const Color(0xFFF8FAFC),
                    onPressed: () {
                      _textController.text = preset;
                      controller.setInputText(preset);
                    },
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildInferenceControlsCard(
    SandboxState state,
    SandboxController controller,
  ) {
    final rc = ref.watch(remoteConfigProvider);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AI Inference Mode',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final entry in <(InferenceMode?, String, IconData)>[
                (null, 'Remote', Icons.cloud_sync_rounded),
                (
                  InferenceMode.preferOnDevice,
                  'Prefer Local',
                  Icons.memory_rounded,
                ),
                (
                  InferenceMode.onlyOnDevice,
                  'Local Only',
                  Icons.offline_bolt_rounded,
                ),
                (InferenceMode.onlyInCloud, 'Cloud Only', Icons.cloud_outlined),
              ])
                ChoiceChip(
                  selected: state.selectedMode == entry.$1,
                  showCheckmark: false,
                  avatar: Icon(entry.$3, size: 14),
                  label: Text(entry.$2, style: const TextStyle(fontSize: 11)),
                  selectedColor: AppTheme.primaryEmeraldLight,
                  onSelected: (_) => controller.setInferenceMode(entry.$1),
                ),
            ],
          ),

          const SizedBox(height: 4),
          Text(
            state.selectedMode == null
                ? 'Following Remote Config: ${rc.aiInferenceMode}'
                : 'Override: ${state.selectedMode!.displayLabel}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          const Divider(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: state.isLoading ? null : controller.parseExpense,
              icon: state.isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.bolt_rounded),
              label: Text(
                state.isLoading
                    ? 'Analyzing with Hybrid AI...'
                    : 'Process with Hybrid AI',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String error) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.coralOwesBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFCDD2)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline,
            color: AppTheme.coralOwesText,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(
                color: AppTheme.coralOwesText,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParsedCard(SandboxState state, SandboxController controller) {
    final result = state.latestResult!;
    final trip = ref.watch(tripControllerProvider);

    return _card(
      border: AppTheme.primaryEmerald,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TelemetryPill(
            source: result.inferenceSource,
            latencyMs: result.latencyMs,
            modelInfo: result.modelInfo,
            simulated: result.isSimulated,
          ),
          const SizedBox(height: 6),
          Text(
            'Model: ${result.modelInfo}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: AppTheme.textSlate,
            ),
          ),
          const Divider(height: 20),
          for (final exp in state.parsedExpenses) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exp.title,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: exp.category.pastelColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              exp.category.icon,
                              size: 14,
                              color: exp.category.accentColor,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              exp.category.englishLabel,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: exp.category.accentColor,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '(${exp.category.name})',
                              style: TextStyle(
                                fontSize: 10,
                                color: exp.category.accentColor.withValues(
                                  alpha: 0.8,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  CurrencyHelper.formatAmount(exp.amount, exp.currency),
                  style: AppTheme.tabularNumberStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.primaryEmeraldDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.payment_rounded,
                        size: 16,
                        color: AppTheme.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Payer: ',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: AppTheme.textSlate,
                        ),
                      ),
                      Text(
                        trip.nameOf(exp.payerId),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.people_outline_rounded,
                        size: 16,
                        color: AppTheme.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Split with: ',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: AppTheme.textSlate,
                        ),
                      ),
                      Expanded(
                        child: Wrap(
                          spacing: 4,
                          children: [
                            for (final id in exp.splitWithMemberIds)
                              Chip(
                                label: Text(
                                  trip.nameOf(id),
                                  style: const TextStyle(fontSize: 10),
                                ),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          ExpansionTile(
            title: Text(
              'View Raw JSON Response from AI',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            tilePadding: EdgeInsets.zero,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  result.rawJson,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    color: Color(0xFF38BDF8),
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryEmeraldDark,
                side: const BorderSide(color: AppTheme.primaryEmerald),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                final n = controller.addParsedToTrip();
                showPockoSnack(
                  context,
                  '$n expense${n == 1 ? '' : 's'} added to the trip • debts recalculated 🎉',
                );
              },
              icon: const Icon(Icons.add_task_rounded),
              label: Text(
                'Add ${state.parsedExpenses.length} to Trip & Recalculate Settle Debt',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettlementCard() {
    final trip = ref.watch(tripControllerProvider);
    final transfers = trip.simplifiedTransfers;
    final balances = trip.netBalances;
    final base = trip.trip.baseCurrency;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _title(
                  Icons.account_balance_wallet_rounded,
                  'Debt Simplification (Greedy Net Balances)',
                ),
              ),
              Text(
                '${trip.trip.expenses.length} items',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: AppTheme.textSlate,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Net Balances per Person:',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: trip.trip.members.map((member) {
              final balance = balances[member.id] ?? 0.0;
              final positive = balance > 0.01;
              final negative = balance < -0.01;
              final color = positive
                  ? AppTheme.primaryEmeraldDark
                  : (negative ? AppTheme.coralOwesText : AppTheme.textSlate);
              final bg = positive
                  ? AppTheme.primaryEmeraldSubtle
                  : (negative ? AppTheme.coralOwesBg : const Color(0xFFF1F5F9));
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      trip.displayName(member),
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      CurrencyHelper.formatAmount(
                        balance,
                        base,
                        showSign: true,
                      ),
                      style: AppTheme.tabularNumberStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Minimum Transfer Plan:',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primaryEmeraldSubtle,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${transfers.length} transfers',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primaryEmeraldDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (transfers.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                trip.trip.expenses.isEmpty
                    ? 'No expenses recorded yet in this trip.\nTap "Process with Hybrid AI" and "Add to Trip" to inspect settlement.'
                    : 'All balances are settled! Nobody owes anything. 🎉',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: AppTheme.textSlate,
                ),
              ),
            )
          else
            for (final t in transfers)
              _buildTransferItem(
                trip.nameOf(t.fromMemberId),
                trip.nameOf(t.toMemberId),
                t,
              ),
        ],
      ),
    );
  }

  Widget _buildTransferItem(
    String from,
    String to,
    SettlementTransfer transfer,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: AppTheme.coralOwesBg,
            child: Text(
              from.isEmpty ? '?' : from[0],
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppTheme.coralOwesText,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              from,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Icon(
              Icons.arrow_forward_rounded,
              color: AppTheme.primaryEmeraldDark,
              size: 16,
            ),
          ),
          CircleAvatar(
            radius: 14,
            backgroundColor: AppTheme.primaryEmeraldSubtle,
            child: Text(
              to.isEmpty ? '?' : to[0],
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryEmeraldDark,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              to,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          const Spacer(),
          Text(
            CurrencyHelper.formatAmount(transfer.amount, transfer.currency),
            style: AppTheme.tabularNumberStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppTheme.primaryEmeraldDark,
            ),
          ),
        ],
      ),
    );
  }
}
