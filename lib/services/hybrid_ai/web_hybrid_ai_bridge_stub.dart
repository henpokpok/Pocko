/// Stub implementation of WebHybridAiBridge for native platforms and test VM
class WebHybridAiBridge {
  static bool get isSupported => false;

  static Future<bool> isAvailable() async => false;

  /// Fast path: nothing is reachable on the VM / native platforms.
  static Future<bool> quickProbe({
    Duration timeout = const Duration(milliseconds: 450),
  }) async => false;

  static Future<Map<String, dynamic>?> checkModelStatus() async => null;

  static Future<Map<String, dynamic>> generateContent({
    required String prompt,
    String mode = 'prefer_on_device',
    String cloudFallbackModel = 'gemini-3.1-flash-lite',
    int maxOutputTokens = 512,
    String? receiptBase64,
    String? audioBase64,
    String? mimeType,
  }) async {
    throw UnsupportedError('WebHybridAiBridge is only available on Web.');
  }
}
