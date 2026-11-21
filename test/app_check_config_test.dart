import 'dart:io';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/services/firebase/app_check_config.dart';

String _providerKey(WebProvider p) =>
    (p as ReCaptchaEnterpriseProvider).siteKey;

void main() {
  group('web App Check provider selection', () {
    test(
      'localhost and 127.0.0.1 use the debug provider, never the real key',
      () {
        for (final host in ['localhost', '127.0.0.1', '[::1]']) {
          final p = webAppCheckProvider(host, key: 'REAL_KEY_123456');
          expect(p, isA<ReCaptchaEnterpriseProvider>());
          expect(_providerKey(p), kWebDebugTokenPlaceholder, reason: host);
        }
      },
    );

    test('Firebase Hosting hosts use reCAPTCHA Enterprise with the key', () {
      for (final host in [
        'pocko-hybrid-ai.web.app',
        'pocko-hybrid-ai.firebaseapp.com',
        'preview--pocko-hybrid-ai.web.app',
      ]) {
        expect(isProductionWebHost(host), isTrue, reason: host);
        final p = webAppCheckProvider(host, key: 'REAL_KEY_123456');
        expect(_providerKey(p), 'REAL_KEY_123456', reason: host);
      }
    });

    test('unknown hosts never get the debug provider', () {
      final p = webAppCheckProvider('example.com', key: 'REAL_KEY_123456');
      expect(_providerKey(p), 'REAL_KEY_123456');
      expect(isLocalWebHost('localhost.evil.com'), isFalse);
    });

    test('placeholder key is not a real key', () {
      expect(hasRealRecaptchaKey('PASTE_YOUR_ENTERPRISE_KEY_ID_HERE'), isFalse);
      expect(hasRealRecaptchaKey('6Lc_abcdefghijk'), isTrue);
    });
  });

  group('both web entry points stay in sync', () {
    final js = File('web/firebase_ai_web.js').readAsStringSync();

    test('the AI bridge uses ReCaptchaEnterpriseProvider, not v3', () {
      expect(js, contains('ReCaptchaEnterpriseProvider'));
      expect(js, isNot(contains('ReCaptchaV3Provider')));
    });

    test('the AI bridge keeps debug mode on localhost only', () {
      expect(js, contains('FIREBASE_APPCHECK_DEBUG_TOKEN'));
      expect(js, contains('"localhost"'));
      expect(js, contains('"127.0.0.1"'));
    });

    test('Dart and JS carry the same Enterprise key ID', () {
      final m = RegExp('RECAPTCHA_ENTERPRISE_KEY_ID = "([^"]+)"')
          .firstMatch(js);
      expect(m, isNotNull);
      expect(m!.group(1), kRecaptchaEnterpriseKeyId);
    });
  });

  test('firebase.json serves the Flutter build as a single-page app', () {
    final text = File('firebase.json').readAsStringSync();
    expect(text, contains('"public": "build/web"'));
    expect(text, contains('"destination": "/index.html"'));
  });
}
