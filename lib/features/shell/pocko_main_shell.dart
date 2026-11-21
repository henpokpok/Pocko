import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/adaptive_layout.dart';
import '../../core/widgets/pocko_mascot.dart';
import '../../core/widgets/tactile.dart';
import '../capture/ai_expense_capture_sheet.dart';
import '../capture/capture_overlay_host.dart';
import '../expenses/expenses_canvas_screen.dart';
import '../expenses/manual_expense.dart';
import '../home/trip_home_screen.dart';
import '../matcher/smart_slip_matcher_screen.dart';
import '../sandbox/hybrid_sandbox_screen.dart';
import '../settle/visual_settle_screen.dart';
import '../settings/settings_sheet.dart';
import '../squad/squad_setup_screen.dart';
import '../trip/require_trip.dart';
import '../trip/trip_controller.dart';
import '../trip/trip_state.dart';

class PockoMainShell extends ConsumerStatefulWidget {
  const PockoMainShell({super.key});

  @override
  ConsumerState<PockoMainShell> createState() => _PockoMainShellState();
}

class _PockoMainShellState extends ConsumerState<PockoMainShell>
    with SingleTickerProviderStateMixin {
  int _currentTabIndex = PockoTabs.home;
  late final AnimationController _tabFade;

  static const _tabNames = ['Home', 'Expenses', '', 'Matcher', 'Settle'];

  @override
  void initState() {
    super.initState();
    _tabFade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _tabFade.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    if (index == _currentTabIndex) return;
    setState(() => _currentTabIndex = index);
    _tabFade.forward(from: 0.35);
  }

  bool _captureOpen = false;

  void _openCaptureModal() {
    if (_captureOpen) return;
    // No trip yet: prompt to create / join one instead of opening capture.
    if (!ensureTrip(context, ref)) return;
    setState(() => _captureOpen = true);
  }

  void _closeCapture() {
    if (!_captureOpen) return;
    setState(() => _captureOpen = false);
  }

  /// "Manual Expense": fade the overlay out, then open the standard Add
  /// Expense bottom sheet.
  void _openManualExpense() {
    _closeCapture();
    Future<void>.delayed(CaptureOverlayHost.duration, () {
      if (mounted) addManualExpense(context, ref);
    });
  }

  void _navigateToSandbox() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const HybridSandboxScreen()));
  }

  void _navigateToSquadSetup() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SquadSetupScreen(
          onLaunchCanvas: () {
            Navigator.of(context).pop();
            _selectTab(PockoTabs.expenses);
          },
        ),
      ),
    );
  }

  Color _syncColor(SyncStatus status) {
    switch (status) {
      case SyncStatus.live:
        return AppTheme.primaryEmerald;
      case SyncStatus.connecting:
        return const Color(0xFFF59E0B);
      case SyncStatus.offline:
        return AppTheme.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only what the chrome shows (trip name, sync dot, Matcher badge): typing,
    // balance changes and unrelated edits no longer rebuild the whole shell.
    final slice = ref.watch(
      tripControllerProvider.select(
        (s) => (
          hasTrip: s.hasTrip,
          name: s.trip.name,
          sync: s.syncStatus,
          badge: _slipBadge(s),
        ),
      ),
    );
    final isWide = Breakpoints.isWide(context);

    // A brand-new trip (Setup Wizard / Demo Trip) always lands on Home.
    ref.listen<String>(tripControllerProvider.select((s) => s.trip.id), (
      previous,
      next,
    ) {
      if (previous != null && previous != next) {
        if (_captureOpen) setState(() => _captureOpen = false);
        _selectTab(PockoTabs.home);
      }
    });

    // Hidden tabs stay mounted (their scroll position and state survive) but
    // their tickers are muted, so off-screen mascot breathing, chart and
    // shimmer animations cost no CPU / GPU. Each tab also gets its own repaint
    // boundary, and the tab change is a pure opacity + small slide (both
    // GPU-composited, no layout or shadow animation).
    Widget tab(int index, Widget child) => TickerMode(
      enabled: _currentTabIndex == index,
      child: RepaintBoundary(child: child),
    );
    final fade = CurvedAnimation(parent: _tabFade, curve: Curves.easeOut);
    final content = FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.012),
          end: Offset.zero,
        ).animate(fade),
        child: IndexedStack(
          index: _currentTabIndex,
          children: [
            tab(
              PockoTabs.home,
              TripHomeScreen(
                onNavigateTab: _selectTab,
                onOpenSquadSetup: _navigateToSquadSetup,
                onOpenCaptureModal: _openCaptureModal,
              ),
            ),
            tab(
              PockoTabs.expenses,
              ExpensesCanvasScreen(onOpenCaptureModal: _openCaptureModal),
            ),
            const SizedBox.shrink(), // Index 2 reserved for Center + FAB
            tab(PockoTabs.matcher, const SmartSlipMatcherScreen()),
            tab(PockoTabs.settle, const VisualSettleScreen()),
          ],
        ),
      ),
    );

    final scaffold = Scaffold(
      backgroundColor: AppTheme.canvasBackground,
      extendBody: !isWide,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: _buildTopBar(slice),
      ),
      body: isWide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSideRail(slice.badge),
                Expanded(child: content),
              ],
            )
          : content,
      bottomNavigationBar: isWide ? null : _buildFloatingBottomBar(slice.badge),
    );

    // "Dim & drop": the page scales back under a light scrim while the capture
    // overlay fades in on top. No blur filter, so it stays at full frame rate.
    return PopScope(
      canPop: !_captureOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeCapture();
      },
      child: CaptureOverlayHost(
        open: _captureOpen,
        page: scaffold,
        overlayBuilder: (_) => AiExpenseCaptureSheet(
          onClose: _closeCapture,
          onManualExpense: _openManualExpense,
        ),
      ),
    );
  }

  Widget _buildTopBar(
    ({
      bool hasTrip,
      String name,
      SyncStatus sync,
      ({int count, bool needsReview}) badge,
    })
    slice,
  ) {
    final currentTab =
        (_currentTabIndex >= 0 && _currentTabIndex < _tabNames.length)
        ? _tabNames[_currentTabIndex]
        : '';
    final tripName = slice.hasTrip ? slice.name : 'No trip yet';
    final label = currentTab.isNotEmpty ? '$tripName • $currentTab' : tripName;

    final narrow = MediaQuery.sizeOf(context).width < 360;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: narrow ? 12 : 20,
          vertical: 8,
        ),
        child: Row(
          children: [
            // Pocko Mini Badge + Brand Title
            if (!narrow)
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.primaryEmeraldSubtle,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.primaryEmerald.withValues(alpha: 0.3),
                  ),
                ),
                child: const Center(
                  child: PockoMascot(
                    mood: PockoMood.waving,
                    size: 30,
                    animate: false,
                  ),
                ),
              ),
            if (!narrow) const SizedBox(width: 10),
            Text(
              'Pocko',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                color: AppTheme.textDark,
              ),
            ),
            Tooltip(
              message: slice.sync.label,
              child: Container(
                margin: const EdgeInsets.only(left: 5, top: 4),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _syncColor(slice.sync),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Current Screen Context Pill (Tapping opens Group & Trip Settings)
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: Tactile(
                  onTap: _navigateToSquadSetup,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 260),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: AppTheme.pillRadius,
                      border: Border.all(color: AppTheme.borderColor),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x08000000),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textDark,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.arrow_drop_down_rounded,
                          size: 18,
                          color: AppTheme.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              key: const ValueKey('settings_button'),
              tooltip: 'Settings',
              visualDensity: VisualDensity.compact,
              icon: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.borderColor),
                ),
                child: const Icon(
                  Icons.settings_rounded,
                  size: 18,
                  color: AppTheme.textSlate,
                ),
              ),
              onPressed: () => showSettingsSheet(context),
            ),
            IconButton(
              tooltip: 'AI Diagnostic Sandbox',
              icon: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.borderColor),
                ),
                child: const Icon(
                  Icons.terminal_rounded,
                  size: 18,
                  color: AppTheme.textSlate,
                ),
              ),
              onPressed: _navigateToSandbox,
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Navigation chrome
  // ---------------------------------------------------------------------------

  Widget _centerFab({double size = 52}) {
    return Tactile(
      onTap: _openCaptureModal,
      pressedScale: 0.9,
      semanticLabel: 'Add expense with AI',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: AppTheme.emeraldShineGradient,
          shape: BoxShape.circle,
          boxShadow: AppTheme.emeraldGlowShadow,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.6),
            width: 1.5,
          ),
        ),
        child: const Center(
          child: Icon(Icons.add_rounded, color: Colors.white, size: 32),
        ),
      ),
    );
  }

  // Tab index -> visual slot (index 2 is the center + button, not a slot).
  static const _slotOfTab = {0: 0, 1: 1, 3: 2, 4: 3};

  /// Pending slips shown as a badge on the Matcher icon.
  ({int count, bool needsReview}) _slipBadge(TripState state) {
    final pending = state.pendingSlips;
    return (
      count: pending.length,
      needsReview: pending.any((s) => s.targetExpenseId == null),
    );
  }

  /// Tablet / desktop navigation: a translucent vertical rail with the center + at
  /// the top and a single indicator that glides between tabs.
  Widget _buildSideRail(({int count, bool needsReview}) badge) {
    const itemHeight = 64.0;
    const railWidth = 88.0;
    final slot = _slotOfTab[_currentTabIndex] ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 0, 16),
      child: SizedBox(
        width: railWidth,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            boxShadow: AppTheme.elevatedCardShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.8),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _centerFab(size: 56),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: itemHeight * 4,
                        width: railWidth,
                        child: Stack(
                          children: [
                            AnimatedPositioned(
                              key: const ValueKey('nav_indicator'),
                              duration: const Duration(milliseconds: 260),
                              curve: Curves.easeOutCubic,
                              top: slot * itemHeight + (itemHeight - 45) / 2,
                              left: (railWidth - 56) / 2,
                              width: 56,
                              height: 30,
                              child: const _NavIndicatorPill(),
                            ),
                            Column(
                              children: [
                                _buildNavItem(
                                  index: PockoTabs.home,
                                  icon: Icons.home_rounded,
                                  label: 'Home',
                                  height: itemHeight,
                                ),
                                _buildNavItem(
                                  index: PockoTabs.expenses,
                                  icon: Icons.receipt_long_rounded,
                                  label: 'Expenses',
                                  height: itemHeight,
                                ),
                                _buildNavItem(
                                  index: PockoTabs.matcher,
                                  icon: Icons.document_scanner_rounded,
                                  label: 'Matcher',
                                  height: itemHeight,
                                  badgeCount: badge.count,
                                  badgeNeedsReview: badge.needsReview,
                                ),
                                _buildNavItem(
                                  index: PockoTabs.settle,
                                  icon: Icons.account_balance_wallet_rounded,
                                  label: 'Settle',
                                  height: itemHeight,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingBottomBar(({int count, bool needsReview}) badge) {
    const fabSlot = 64.0;
    const barHeight = 68.0;
    final slot = _slotOfTab[_currentTabIndex] ?? 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      height: barHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        boxShadow: AppTheme.elevatedCardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(34),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.8),
              width: 1.5,
            ),
          ),
          child: LayoutBuilder(
            builder: (context, c) {
              final tabWidth = (c.maxWidth - fabSlot) / 4;
              final pillWidth = tabWidth.clamp(0.0, 60.0) - 4;
              final left =
                  slot * tabWidth +
                  (slot >= 2 ? fabSlot : 0) +
                  (tabWidth - pillWidth) / 2;
              return Stack(
                children: [
                  // One indicator that slides between slots (no rebuild, no flicker).
                  AnimatedPositioned(
                    key: const ValueKey('nav_indicator'),
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    top: (barHeight - 45) / 2 - 3,
                    left: left,
                    width: pillWidth,
                    height: 30,
                    child: const _NavIndicatorPill(),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _buildNavItem(
                          index: PockoTabs.home,
                          icon: Icons.home_rounded,
                          label: 'Home',
                          height: barHeight,
                        ),
                      ),
                      Expanded(
                        child: _buildNavItem(
                          index: PockoTabs.expenses,
                          icon: Icons.receipt_long_rounded,
                          label: 'Expenses',
                          height: barHeight,
                        ),
                      ),
                      SizedBox(
                        width: fabSlot,
                        child: Center(child: _centerFab()),
                      ),
                      Expanded(
                        child: _buildNavItem(
                          index: PockoTabs.matcher,
                          icon: Icons.document_scanner_rounded,
                          label: 'Matcher',
                          height: barHeight,
                          badgeCount: badge.count,
                          badgeNeedsReview: badge.needsReview,
                        ),
                      ),
                      Expanded(
                        child: _buildNavItem(
                          index: PockoTabs.settle,
                          icon: Icons.account_balance_wallet_rounded,
                          label: 'Settle',
                          height: barHeight,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required String label,
    required double height,
    int badgeCount = 0,
    bool badgeNeedsReview = false,
  }) {
    final isSelected = _currentTabIndex == index;
    final color = isSelected
        ? AppTheme.primaryEmerald
        : const Color(0xFF8A99AD);

    return Tactile(
      onTap: () => _selectTab(index),
      pressedScale: 0.92,
      semanticLabel: badgeCount > 0
          ? '$label tab, $badgeCount pending'
          : '$label tab',
      child: SizedBox(
        height: height,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 30,
              child: Center(
                // The badge is anchored to the icon itself (not the tab
                // cell): top-right corner of the 22px glyph.
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    TweenAnimationBuilder<Color?>(
                      tween: ColorTween(end: color),
                      duration: const Duration(milliseconds: 220),
                      builder: (context, c, _) =>
                          Icon(icon, color: c, size: 22),
                    ),
                    if (badgeCount > 0)
                      Positioned(
                        key: ValueKey('nav_badge_$index'),
                        top: -5,
                        right: -8,
                        child: _NavBadge(
                          count: badgeCount,
                          needsReview: badgeNeedsReview,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 2),
            TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: color),
              duration: const Duration(milliseconds: 220),
              builder: (context, c, _) => Text(
                label,
                maxLines: 1,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: c,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavIndicatorPill extends StatelessWidget {
  const _NavIndicatorPill();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.primaryEmeraldSubtle,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primaryEmerald.withValues(alpha: 0.12),
        ),
      ),
    );
  }
}

/// Count badge on the Matcher icon: emerald when every pending slip has a
/// proposed match, coral when at least one needs manual verification.
class _NavBadge extends StatelessWidget {
  final int count;
  final bool needsReview;

  const _NavBadge({required this.count, required this.needsReview});

  @override
  Widget build(BuildContext context) {
    final color = needsReview ? AppTheme.coralOwes : AppTheme.primaryEmerald;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Container(
        constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 6),
          ],
        ),
        child: Text(
          count > 99 ? '99+' : '$count',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 9.5,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}
