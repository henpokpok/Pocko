/// The audit trail of an AI-captured expense: the exact words the user spoke
/// or typed, stored verbatim at the start of `ExpenseItem.note` as
/// `Raw prompt: "…"`. Anything the user adds later follows on the next line.
class RawPromptNote {
  RawPromptNote._();

  static const String prefix = 'Raw prompt: "';

  /// `Raw prompt: "<raw>"` plus an optional extra note on a new line.
  static String compose(String raw, {String? extra}) {
    final head = '$prefix$raw"';
    final tail = extra?.trim() ?? '';
    return tail.isEmpty ? head : '$head\n$tail';
  }

  /// Splits a stored note into the verbatim prompt (if any) and the rest.
  static ({String? raw, String rest}) parse(String? note) {
    final n = note ?? '';
    if (!n.startsWith(prefix)) return (raw: null, rest: n);
    // The prompt ends at the first closing quote that ends the line.
    final m = RegExp(r'^Raw prompt: "([\s\S]*?)"(?=\n|$)').firstMatch(n);
    if (m == null) return (raw: null, rest: n);
    final rest = n.substring(m.end).replaceFirst(RegExp(r'^\n'), '');
    return (raw: m.group(1), rest: rest);
  }
}
