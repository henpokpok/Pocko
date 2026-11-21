import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../../services/session/session_store.dart';
import '../squad/join_group_sheet.dart';
import '../trip/trip_controller.dart';
import 'first_trip_setup_card.dart';
import 'story_scenes.dart';
import 'trip_destinations.dart';

/// Whether the landing / setup experience is done. It starts `true` once the
/// Landing Page was seen on an earlier launch (`has_seen_landing`), so later
/// launches go straight to Home; Settings can replay it for demo recordings.
final onboardingCompleteProvider =
    NotifierProvider<OnboardingCompleteNotifier, bool>(
      OnboardingCompleteNotifier.new,
    );

class OnboardingCompleteNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(sessionStoreProvider)?.hasSeenLanding ?? false;

  /// The landing was used (trip created, group joined, demo started or
  /// skipped): never show it automatically again.
  void complete() {
    state = true;
    ref.read(sessionStoreProvider)?.setHasSeenLanding(true);
  }

  /// "Replay Landing Page": shows the landing again and clears the saved flag
  /// without touching the trip, the local storage, the Firebase user or the
  /// App Check debug token.
  void replay() {
    state = false;
    ref.read(sessionStoreProvider)?.setHasSeenLanding(false);
  }
}

/// Shows the landing story first and the live app once a trip is ready, with
/// a soft cross-fade / scale between the two.
class OnboardingGate extends ConsumerWidget {
  final Widget app;
  const OnboardingGate({super.key, required this.app});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final done = ref.watch(onboardingCompleteProvider);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 520),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1).animate(anim),
          child: child,
        ),
      ),
      child: done
          ? KeyedSubtree(key: const ValueKey('app'), child: app)
          : OnboardingScreen(
              key: const ValueKey('onboarding'),
              onDone: () =>
                  ref.read(onboardingCompleteProvider.notifier).complete(),
            ),
    );
  }
}

class _StoryData {
  final StoryScene scene;
  final String title;
  final String body;
  final List<String> chips;
  const _StoryData(this.scene, this.title, this.body, this.chips);
}

const List<_StoryData> _stories = [
  _StoryData(
    StoryScene.cafe,
    'Speak offline in 3s',
    'At a café or a market stall, just say or type what you spent. Pocko '
        'understands it on your device, so no signal is needed.',
    ['Works offline', 'Voice or type', 'On-device AI'],
  ),
  _StoryData(
    StoryScene.slipMatch,
    'Slips snap onto expenses',
    'Drop in a bank transfer slip and Pocko matches it to the trip expense '
        'that was waiting for it.',
    ['Auto-match', 'Waiting list', 'One-tap verify'],
  ),
  _StoryData(
    StoryScene.privacyShield,
    'Your card numbers stay yours',
    'Card and account digits are masked on your phone before any AI sees a '
        'slip. Only the last four ever sync.',
    ['PII masked first', 'Slips never sync', 'On-device shield'],
  ),
];

/// Landing story + first-trip setup. Used as the app's first screen and (with
/// `startAtSetup`) as the "New Trip / Setup Wizard" from Manage Group.
class OnboardingScreen extends ConsumerStatefulWidget {
  final VoidCallback onDone;
  final bool startAtSetup;

  const OnboardingScreen({
    super.key,
    required this.onDone,
    this.startAtSetup = false,
  });

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late final PageController _pages;
  late int _page;

  /// True while a finger / fling is moving the pages. Idle illustration and
  /// entrance tickers are paused for that time so the swipe only translates
  /// cached layers; they resume as soon as the page settles.
  final ValueNotifier<bool> _swiping = ValueNotifier<bool>(false);

  static final int _setupPage = _stories.length;

  /// Pages on each side that stay built: all of them.
  static const double _pageCount = 4;

  @override
  void initState() {
    super.initState();
    _page = widget.startAtSetup ? _setupPage : 0;
    _pages = PageController(initialPage: _page);
  }

  @override
  void dispose() {
    _swiping.dispose();
    _pages.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.horizontal || n.depth != 0) return false;
    if (n is ScrollStartNotification) {
      _swiping.value = true;
    } else if (n is ScrollEndNotification) {
      _swiping.value = false;
    }
    return false;
  }

  /// Every page is built up front, cached as its own raster layer and kept
  /// alive, with tickers running only for the settled, visible page.
  Widget _prewarm(int i, Widget child) => _PrewarmedPage(
    key: ValueKey('prewarm_page_$i'),
    active: _page == i,
    swiping: _swiping,
    child: child,
  );

  void _goTo(int page) {
    _pages.animateToPage(
      page,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  void _startTrip(TripSetupData data) {
    ref
        .read(tripControllerProvider.notifier)
        .startNewTrip(
          name: data.name,
          currency: data.tripCurrency,
          homeCurrency: data.homeCurrency,
          friends: data.friends,
        );
    widget.onDone();
  }

  void _tryDemo() {
    ref.read(tripControllerProvider.notifier).loadDemoTrip();
    widget.onDone();
  }

  Future<void> _joinGroup() async {
    final joined = await showJoinGroupSheet(context);
    if (joined == true && mounted) widget.onDone();
  }

  Widget _landingAction(
    Key key,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return TextButton.icon(
      key: key,
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: AppTheme.primaryEmeraldDark,
        minimumSize: const Size(0, 44),
        textStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final onSetup = _page == _setupPage;
    final media = MediaQuery.of(context);
    final compact = media.size.height < 640;
    // With the soft keyboard up the footer (dots + Next / Demo button) is hidden
    // instead of being pushed above the keyboard, so the form keeps the room.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      key: const ValueKey('onboarding_screen'),
      backgroundColor: AppTheme.canvasBackground,
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.mintToSkyGradient),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                    child: Row(
                      children: [
                        Text(
                          'Pocko',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.textDark,
                          ),
                        ),
                        const Spacer(),
                        if (!onSetup)
                          TextButton(
                            key: const ValueKey('skip_button'),
                            onPressed: () => _goTo(_setupPage),
                            child: Text(
                              'Skip',
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textSlate,
                              ),
                            ),
                          )
                        else if (!widget.startAtSetup)
                          TextButton(
                            key: const ValueKey('story_back_button'),
                            onPressed: () => _goTo(_setupPage - 1),
                            child: Text(
                              'Story',
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textSlate,
                              ),
                            ),
                          )
                        else
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.maybePop(context),
                            icon: const Icon(Icons.close_rounded),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _onScroll,
                      child: PageView(
                        key: const ValueKey('onboarding_pages'),
                        controller: _pages,
                        onPageChanged: (p) => setState(() => _page = p),
                        // Scenes 2 and 3 (and the setup form) are built, laid
                        // out and shader-compiled before the first swipe.
                        allowImplicitScrolling: true,
                        scrollCacheExtent: const ScrollCacheExtent.viewport(
                          _pageCount,
                        ),
                        children: [
                          for (var i = 0; i < _stories.length; i++)
                            _prewarm(
                              i,
                              _StoryPage(
                                key: ValueKey('story_$i'),
                                data: _stories[i],
                                compact: compact,
                              ),
                            ),
                          _prewarm(
                            _setupPage,
                            SingleChildScrollView(
                              key: const ValueKey('setup_page'),
                              // The Scaffold already shrinks the body above the keyboard.
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                              child: FirstTripSetupCard(onStart: _startTrip),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!keyboardOpen) ...[
                    _Dots(count: _stories.length + 1, index: _page),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
                      child: Column(
                        children: [
                          if (!onSetup)
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                key: const ValueKey('next_button'),
                                onPressed: () => _goTo(_page + 1),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primaryEmerald,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(0, 56),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: AppTheme.pillRadius,
                                  ),
                                  textStyle: GoogleFonts.plusJakartaSans(
                                    fontSize: 16.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                child: Text(
                                  _page == _stories.length - 1
                                      ? 'Set up my trip'
                                      : 'Next',
                                ),
                              ),
                            ),
                          Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 4,
                            children: [
                              if (!onSetup)
                                _landingAction(
                                  const ValueKey('create_trip_button'),
                                  Icons.flight_takeoff_rounded,
                                  'Get Started',
                                  () => _goTo(_setupPage),
                                ),
                              _landingAction(
                                const ValueKey('join_group_button'),
                                Icons.group_add_rounded,
                                'Join Group',
                                _joinGroup,
                              ),
                              _landingAction(
                                const ValueKey('demo_trip_button'),
                                Icons.rocket_launch_rounded,
                                'Try Tokyo Demo Trip',
                                _tryDemo,
                              ),
                              if (!widget.startAtSetup)
                                Builder(
                                  builder: (context) {
                                    final hasTrip = ref.watch(
                                      tripControllerProvider.select(
                                        (t) => t.hasTrip,
                                      ),
                                    );
                                    return _landingAction(
                                      ValueKey(
                                        hasTrip
                                            ? 'landing_back_to_trip'
                                            : 'landing_skip_button',
                                      ),
                                      Icons.arrow_back_rounded,
                                      hasTrip
                                          ? 'Back to my trip'
                                          : 'Skip for now',
                                      () => ref
                                          .read(
                                            onboardingCompleteProvider.notifier,
                                          )
                                          .complete(),
                                    );
                                  },
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One onboarding page: kept alive, painted into its own layer (a horizontal
/// swipe then moves a cached texture instead of repainting), and with tickers
/// muted unless it is the settled, visible page.
class _PrewarmedPage extends StatefulWidget {
  final bool active;
  final ValueListenable<bool> swiping;
  final Widget child;
  const _PrewarmedPage({
    super.key,
    required this.active,
    required this.swiping,
    required this.child,
  });

  @override
  State<_PrewarmedPage> createState() => _PrewarmedPageState();
}

class _PrewarmedPageState extends State<_PrewarmedPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RepaintBoundary(
      child: ValueListenableBuilder<bool>(
        valueListenable: widget.swiping,
        child: widget.child,
        builder: (context, swiping, child) =>
            TickerMode(enabled: widget.active && !swiping, child: child!),
      ),
    );
  }
}

class _StoryPage extends StatelessWidget {
  final _StoryData data;
  final bool compact;
  const _StoryPage({super.key, required this.data, required this.compact});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        // The illustration shrinks on short screens so text + buttons still fit.
        final sceneHeight = compact || box.maxHeight < 430 ? 190.0 : 250.0;
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight - 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                StoryIllustration(scene: data.scene, height: sceneHeight),
                const SizedBox(height: 22),
                Text(
                      data.title,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 27,
                        height: 1.15,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textDark,
                      ),
                    )
                    .animate()
                    .fadeIn(delay: 120.ms, duration: 360.ms)
                    .slideY(
                      begin: 0.15,
                      end: 0,
                      delay: 120.ms,
                      duration: 360.ms,
                      curve: Curves.easeOutCubic,
                    ),
                const SizedBox(height: 10),
                Text(
                  data.body,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textSlate,
                  ),
                ).animate().fadeIn(delay: 220.ms, duration: 360.ms),
                const SizedBox(height: 18),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < data.chips.length; i++)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.85),
                          borderRadius: AppTheme.pillRadius,
                        ),
                        child: Text(
                          data.chips[i],
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primaryEmeraldDark,
                          ),
                        ),
                      ).animate().fadeIn(
                        delay: Duration(milliseconds: 320 + 90 * i),
                        duration: 300.ms,
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Dots extends StatelessWidget {
  final int count;
  final int index;
  const _Dots({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('onboarding_dots'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == index
                  ? AppTheme.primaryEmerald
                  : AppTheme.primaryEmerald.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
      ],
    );
  }
}
