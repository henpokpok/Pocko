import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/shell/pocko_main_shell.dart';
import 'firebase_options.dart';
import 'services/firebase/app_check_config.dart';
import 'services/remote_config/remote_config_service.dart';
import 'services/session/session_store.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase with App Check, Anonymous Auth, Offline Persistence, and Remote Config
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // 1. Enable Firebase App Check. Native debug builds use the debug
    // providers; on the web the debug provider is only ever used on
    // localhost / 127.0.0.1, production hosts (*.web.app, *.firebaseapp.com)
    // use reCAPTCHA Enterprise.
    // Profile / release builds installed straight from a Mac (so they open from
    // the home screen) can keep the debug provider with
    // `--dart-define=APP_CHECK_DEBUG=true`; its token is then registered once
    // in the Firebase console. Store builds use the production providers.
    const forceDebugAppCheck = bool.fromEnvironment('APP_CHECK_DEBUG');
    const debugAppCheck = kDebugMode || forceDebugAppCheck;

    await FirebaseAppCheck.instance.activate(
      providerAndroid: debugAppCheck
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
      providerApple: debugAppCheck
          ? const AppleDebugProvider()
          : const AppleDeviceCheckProvider(),
      providerWeb: webAppCheckProvider(Uri.base.host),
    );

    // 2. Enable Cloud Firestore offline persistence
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );

    // 3. Frictionless Anonymous Auth (Assigns secure device UID)
    try {
      final userCred = await FirebaseAuth.instance.signInAnonymously();
      debugPrint(
        '[FirebaseAuth] Anonymous user signed in: ${userCred.user?.uid}',
      );
    } catch (authErr) {
      debugPrint('[FirebaseAuth] Anonymous auth note: $authErr');
    }

    // 4. Initialize & Fetch Firebase Remote Config
    await RemoteConfigService.instance.initializeAndFetch();

    debugPrint(
      '[Firebase] All services initialized (AppCheck, Auth, Firestore Offline, RemoteConfig).',
    );
  } catch (e) {
    debugPrint('[Firebase] Running in Standalone / Offline mode: $e');
    debugPrint(
      '[Firebase] (Tip: Run `flutterfire configure` when linking production cloud project)',
    );
  }

  // Local session: the landing is shown only on the first launch and the trip
  // survives restarts. If storage is unavailable the app still runs (it just
  // behaves like a first launch every time).
  SessionStore? store;
  try {
    store = SessionStore(await SharedPreferences.getInstance());
  } catch (e) {
    debugPrint('[SessionStore] Local storage unavailable: $e');
  }

  runApp(
    ProviderScope(
      overrides: [sessionStoreProvider.overrideWithValue(store)],
      child: const TravMateApp(),
    ),
  );
}

class TravMateApp extends StatelessWidget {
  const TravMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pocko',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const OnboardingGate(app: PockoMainShell()),
    );
  }
}
