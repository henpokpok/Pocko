import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../core/enums/inference_source.dart';
import '../../models/bank_slip.dart';
import '../../models/expense_item.dart';
import '../hybrid_ai/hybrid_ai_service.dart';
import 'pii_masker.dart';
import 'slip_matcher.dart';

class SlipAnalysis {
  final BankSlip slip;
  final HybridAiResult ai;
  final MaskedText masked;

  const SlipAnalysis({
    required this.slip,
    required this.ai,
    required this.masked,
  });
}

/// End-to-end Smart Slip pipeline:
///
/// 1. 🛡️ Mask account numbers / e-mails / names on-device ([PiiMasker]).
/// 2. 🧠 Parse with the hybrid runtime. Plain bank notifications stay on-device;
///    itemized or foreign-currency receipts and photos use the cloud fallback.
///    Only *masked* text can ever leave the device.
/// 3. 🔗 Correlate with unverified expenses ([SlipMatcher]).
class SlipAnalyzer {
  final HybridAiService _ai;

  SlipAnalyzer(this._ai);

  static final RegExp _timePattern = RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)\b');

  static const List<String> _banks = [
    'Wise',
    'Chase',
    'Apple Pay',
    'PayPay',
    'Revolut',
    'Monzo',
    'KBank',
    'Visa',
    'Mastercard',
    'Amex',
  ];

  /// Whether the slip needs the cloud model (itemized lines, a foreign
  /// currency, or a photo).
  static bool needsCloud(String maskedText, String baseCurrency) {
    final lineItems = maskedText
        .split('\n')
        .where(
          (l) =>
              RegExp(r'[A-Za-z].*\s\d[\d.,]*\s*$').hasMatch(l.trim()) &&
              !RegExp(
                r'\b(total|subtotal|vat|tax|time|amount|card|account|table)\b',
                caseSensitive: false,
              ).hasMatch(l),
        )
        .length;
    if (lineItems >= 3) return true;
    final upper = maskedText.toUpperCase();
    final foreign = RegExp(r'\b(EUR|USD|GBP|KRW|THB|JPY|CNY|AUD|CAD|CHF|SGD)\b')
        .allMatches(upper)
        .map((m) => m.group(1)!)
        .where((c) => c != baseCurrency.toUpperCase());
    return foreign.isNotEmpty && lineItems >= 1;
  }

  Future<SlipAnalysis> analyzeText({
    required String rawText,
    required String baseCurrency,
    required List<ExpenseItem> expenses,
    Set<String> takenExpenseIds = const {},
    SlipOrigin origin = SlipOrigin.sample,
  }) async {
    final masked = PiiMasker.mask(rawText);
    final cloud = needsCloud(masked.text, baseCurrency);

    final result = await _ai.parseReceipt(
      maskedText: masked.text,
      tripCurrency: baseCurrency,
      forceCloud: cloud,
    );
    return _buildAnalysis(
      result: result,
      masked: masked,
      origin: origin,
      baseCurrency: baseCurrency,
      expenses: expenses,
      takenExpenseIds: takenExpenseIds,
      header: rawText,
    );
  }

  /// Real photo upload. Without a camera-grade OCR on-device, photos are sent
  /// to the multimodal cloud model; if no runtime is reachable a clearly
  /// labelled simulated extraction is used so the flow stays testable.
  Future<SlipAnalysis> analyzeImage({
    required Uint8List bytes,
    required String name,
    String? mimeType,
    required String baseCurrency,
    required List<ExpenseItem> expenses,
    Set<String> takenExpenseIds = const {},
  }) async {
    final fallbackText = _demoTextForImage(bytes.length);
    final masked = PiiMasker.mask(fallbackText);

    final result = await _ai.parseReceipt(
      maskedText: masked.text,
      tripCurrency: baseCurrency,
      forceCloud: true,
      receiptBase64: base64Encode(bytes),
      mimeType: mimeType ?? 'image/jpeg',
    );
    return _buildAnalysis(
      result: result,
      masked: masked,
      origin: SlipOrigin.upload,
      baseCurrency: baseCurrency,
      expenses: expenses,
      takenExpenseIds: takenExpenseIds,
      header: name,
      previewBytes: bytes,
    );
  }

  // Deterministic stand-in text when a photo cannot be OCR'd without a cloud model.
  static String _demoTextForImage(int seed) {
    const variants = [
      '''Cafe Kitsune - Aoyama
Matcha latte           720
Cheesecake             880
Iced coffee            650
TOTAL JPY            2,250
Time: 15:10''',
      '''Ramen Nagi - Golden Gai
Special ramen        1,450
Gyoza                  480
Draft beer             650
TOTAL JPY            2,580
Time: 21:40''',
    ];
    return variants[seed % variants.length];
  }

  SlipAnalysis _buildAnalysis({
    required HybridAiResult result,
    required MaskedText masked,
    required SlipOrigin origin,
    required String baseCurrency,
    required List<ExpenseItem> expenses,
    required Set<String> takenExpenseIds,
    required String header,
    Uint8List? previewBytes,
  }) {
    final receipt = result.receipt;
    final amount = receipt?.total ?? 0.0;
    final currency = (receipt != null && receipt.currency.isNotEmpty)
        ? receipt.currency
        : baseCurrency;
    final merchant = receipt?.merchant ?? '';

    final timeMatch = _timePattern.firstMatch(masked.text);
    final now = DateTime.now();
    DateTime slipTime = now;
    String timeLabel = DateFormat('HH:mm').format(now);
    if (timeMatch != null) {
      final h = int.parse(timeMatch.group(1)!);
      final m = int.parse(timeMatch.group(2)!);
      slipTime = DateTime(now.year, now.month, now.day, h, m);
      if (slipTime.isAfter(now)) {
        slipTime = slipTime.subtract(const Duration(days: 1));
      }
      timeLabel = '${h.toString().padLeft(2, '0')}:${timeMatch.group(2)}';
    }

    final descriptor =
        '$merchant ${receipt?.lineItems.map((l) => l.name).join(' ') ?? ''}';
    final match = SlipMatcher.match(
      amount: amount,
      currency: currency,
      descriptor: descriptor,
      slipTime: slipTime,
      expenses: expenses,
      baseCurrency: baseCurrency,
      excludeExpenseIds: takenExpenseIds,
    );

    final bank = _banks.firstWhere(
      (b) => header.toLowerCase().contains(b.toLowerCase()),
      orElse: () =>
          origin == SlipOrigin.upload ? 'Photo receipt' : 'Paper receipt',
    );

    final slip = BankSlip(
      id: 'slip_${DateTime.now().microsecondsSinceEpoch}',
      bankName: bank,
      maskedAccount: masked.accountLast4 != null
          ? '•••• ${masked.accountLast4}'
          : 'No account on slip',
      amount: amount,
      currency: currency,
      time: timeLabel,
      merchant: merchant,
      targetExpenseId: match.expense?.id,
      matchPercentage: match.percent,
      origin: origin,
      inferenceSource: result.inferenceSource,
      latencyMs: result.latencyMs,
      modelInfo: result.modelInfo,
      isSimulated: result.isSimulated,
      maskedText: masked.text,
      maskedFieldCount: masked.count,
      lineItems:
          receipt?.lineItems
              .map((l) => SlipLineItem(name: l.name, amount: l.amount))
              .toList() ??
          const [],
      createdAt: slipTime,
      previewBytes: previewBytes,
    );

    return SlipAnalysis(slip: slip, ai: result, masked: masked);
  }

  /// Convenience for UI: telemetry source of the slip.
  static InferenceSource sourceOf(BankSlip slip) => slip.inferenceSource;
}
