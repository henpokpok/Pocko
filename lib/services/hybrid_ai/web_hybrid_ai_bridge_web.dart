import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('window.firebaseAiWeb')
external JSObject? get _firebaseAiWeb;

/// Web implementation of WebHybridAiBridge using Dart 3 JS Interop.
///
/// The JS side (`web/firebase_ai_web.js`) talks to the Firebase AI Logic JS SDK
/// (`getGenerativeModel(ai, { mode: InferenceMode.PREFER_ON_DEVICE })`) and
/// falls back to Chrome's built-in W3C Prompt API (`LanguageModel`).
class WebHybridAiBridge {
  static bool get isSupported => _firebaseAiWeb != null;

  static Future<bool> isAvailable() async {
    final ai = _firebaseAiWeb;
    if (ai == null) return false;
    try {
      final isAvailFn = ai['isAvailable'];
      if (isAvailFn == null || !isAvailFn.isA<JSFunction>()) return false;
      final promise = (isAvailFn as JSFunction).callAsFunction(ai) as JSPromise;
      final result = await promise.toDart;
      return (result as JSBoolean).toDart;
    } catch (_) {
      return false;
    }
  }

  /// Instant "is a real runtime reachable?" check used before every request.
  ///
  /// 1. No bridge object -> `false` immediately (CDN module not loaded).
  /// 2. A real `window.firebaseConfig` -> `true` without any await: Firebase AI
  ///    Logic executes directly.
  /// 3. Otherwise only an *already downloaded* Chrome on-device model counts, and
  ///    the check is capped by [timeout] so a stuck probe can never stall the UI.
  static Future<bool> quickProbe({
    Duration timeout = const Duration(milliseconds: 450),
  }) async {
    final ai = _firebaseAiWeb;
    if (ai == null) return false;
    try {
      final quick = ai['quickStatus'];
      if (quick != null && quick.isA<JSFunction>()) {
        final status = (quick as JSFunction).callAsFunction(ai) as JSObject?;
        if (status != null) {
          if ((status['firebaseConfigured'] as JSBoolean?)?.toDart ?? false) {
            return true;
          }
          if (!((status['promptApiPresent'] as JSBoolean?)?.toDart ?? false)) {
            return false;
          }
        }
      }
      final ready = ai['isOnDeviceReady'];
      if (ready == null || !ready.isA<JSFunction>()) return false;
      final promise = (ready as JSFunction).callAsFunction(ai) as JSPromise;
      final result = await promise.toDart.timeout(timeout);
      return (result as JSBoolean).toDart;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>?> checkModelStatus() async {
    final ai = _firebaseAiWeb;
    if (ai == null) return null;
    try {
      final fn = ai['checkModelStatus'];
      if (fn == null || !fn.isA<JSFunction>()) return null;
      final promise = (fn as JSFunction).callAsFunction(ai) as JSPromise;
      final result = await promise.toDart;
      if (result == null) return null;
      final jsObj = result as JSObject;
      return {
        'isAvailable': (jsObj['isAvailable'] as JSBoolean?)?.toDart ?? false,
        'status': (jsObj['status'] as JSString?)?.toDart ?? 'UNKNOWN',
        'modelInfo':
            (jsObj['modelInfo'] as JSString?)?.toDart ??
            'Firebase AI Logic Web',
        'runtime': (jsObj['runtime'] as JSString?)?.toDart ?? 'web',
      };
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> generateContent({
    required String prompt,
    String mode = 'prefer_on_device',
    String cloudFallbackModel = 'gemini-3.1-flash-lite',
    int maxOutputTokens = 512,
    String? receiptBase64,
    String? audioBase64,
    String? mimeType,
  }) async {
    final ai = _firebaseAiWeb;
    if (ai == null) {
      throw StateError('firebaseAiWeb is not available on window');
    }

    final fn = ai['generateContent'];
    if (fn == null || !fn.isA<JSFunction>()) {
      throw StateError('generateContent function missing on firebaseAiWeb');
    }

    final options = JSObject();
    options['prompt'] = prompt.toJS;
    options['mode'] = mode.toJS;
    options['cloudFallbackModel'] = cloudFallbackModel.toJS;
    options['maxOutputTokens'] = maxOutputTokens.toJS;
    if (receiptBase64 != null) {
      options['receiptBase64'] = receiptBase64.toJS;
      options['mimeType'] = (mimeType ?? 'image/jpeg').toJS;
    }
    if (audioBase64 != null) {
      options['audioBase64'] = audioBase64.toJS;
      options['mimeType'] = (mimeType ?? 'audio/wav').toJS;
    }

    final promise = (fn as JSFunction).callAsFunction(ai, options) as JSPromise;
    final jsResult = (await promise.toDart) as JSObject;

    return {
      'rawJson': (jsResult['rawJson'] as JSString?)?.toDart ?? '{}',
      'inferenceSource':
          (jsResult['inferenceSource'] as JSString?)?.toDart ?? 'in_cloud',
      'latencyMs': (jsResult['latencyMs'] as JSNumber?)?.toDartInt ?? 0,
      'modelInfo':
          (jsResult['modelInfo'] as JSString?)?.toDart ??
          'Firebase AI Logic Web',
      'isSimulated': false,
    };
  }
}
