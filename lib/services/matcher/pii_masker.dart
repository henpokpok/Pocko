/// Result of masking sensitive fields on-device.
class MaskedText {
  /// Text that is safe to hand to a model (or to a cloud fallback).
  final String text;

  /// Number of sensitive fields that were masked.
  final int count;

  /// Last four digits of the first card / account number found, if any.
  final String? accountLast4;

  /// Kinds of fields found, e.g. `card/account number`, `email`.
  final List<String> kinds;

  const MaskedText({
    required this.text,
    required this.count,
    this.accountLast4,
    this.kinds = const [],
  });
}

/// Privacy Shield: strips bank account numbers, IBANs, e-mails, phone numbers
/// and holder names *before* any text reaches an AI model. Runs entirely
/// on-device in plain Dart.
class PiiMasker {
  PiiMasker._();

  static final RegExp _iban = RegExp(
    r'\b[A-Z]{2}\d{2}(?:\s?[A-Z0-9]{4}){3,7}(?:\s?[A-Z0-9]{1,4})?\b',
  );
  static final RegExp _cardOrAccount = RegExp(
    r'\b(?:\d{3,4}[ -]){2,4}\d{2,4}\b|\b\d{8,19}\b',
  );
  static final RegExp _email = RegExp(r'[\w.+\-]+@[\w\-]+(?:\.[\w\-]+)+');
  static final RegExp _phone = RegExp(r'\+\d[\d ()\-]{7,}\d');
  static final RegExp _labelledName = RegExp(
    r'^(\s*(?:account holder|card ?holder|customer|payer|sender|recipient|beneficiary|name)\s*[:\-]\s*)(.+)$',
    caseSensitive: false,
    multiLine: true,
  );

  static MaskedText mask(String input) {
    var text = input;
    var count = 0;
    String? last4;
    final kinds = <String>{};

    String digitsOf(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');

    text = text.replaceAllMapped(_iban, (m) {
      final compact = digitsOf(m.group(0)!);
      count++;
      kinds.add('IBAN');
      last4 ??= compact.substring(compact.length - 4);
      return '•••• ${compact.substring(compact.length - 4)}';
    });

    text = text.replaceAllMapped(_cardOrAccount, (m) {
      final digits = m.group(0)!.replaceAll(RegExp(r'\D'), '');
      count++;
      kinds.add('card/account number');
      final tail = digits.substring(digits.length - 4);
      last4 ??= tail;
      return '•••• $tail';
    });

    text = text.replaceAllMapped(_email, (m) {
      count++;
      kinds.add('email');
      return '•••@•••';
    });

    text = text.replaceAllMapped(_phone, (m) {
      count++;
      kinds.add('phone number');
      return '•••• phone';
    });

    text = text.replaceAllMapped(_labelledName, (m) {
      count++;
      kinds.add('holder name');
      return '${m.group(1)}••••';
    });

    return MaskedText(
      text: text,
      count: count,
      accountLast4: last4,
      kinds: kinds.toList(),
    );
  }
}
