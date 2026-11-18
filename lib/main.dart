import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/shell/pocko_main_shell.dart';
import 'firebase_options.dart';
import 'services/remote_config/remote_config_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase with App Check, Anonymous Auth, Offline Persistence, and Remote Config
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // 1. Enable Firebase App Check with Debug Provider for development builds
    const recaptchaV3SiteKey = String.fromEnvironment(
      'RECAPTCHA_V3_SITE_KEY',
      defaultValue: '6LeIxAcTAAAAAJcZVRqyHh71UMIEGNQ_MXjiZKhI',
    );

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
      providerWeb: debugAppCheck
          ? ReCaptchaV3Provider('debug-token-local-development')
          : ReCaptchaV3Provider(recaptchaV3SiteKey),
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

  runApp(const ProviderScope(child: TravMateApp()));
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
