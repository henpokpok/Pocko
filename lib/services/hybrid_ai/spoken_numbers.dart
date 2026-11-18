/// A number found inside free text, with its position and numeric value.
class NumberSpan {
  /// Start (inclusive) and end (exclusive) offsets in the scanned text.
  final int start;
  final int end;

  /// Value after applying spoken multipliers ("2.5 thousand" -> 2500).
  final double value;

  /// `true` when the span carries a multiplier word or suffix (k, thousand...).
  final bool hasMultiplier;

  const NumberSpan(
    this.start,
    this.end,
    this.value, {
    this.hasMultiplier = false,
  });

  String text(String source) => source.substring(start, end);

  @override
  String toString() => 'NumberSpan($start, $end, $value)';
}

/// Finds numbers in typed or dictated text, including spoken multipliers and
/// their common typos, so every layer (AI prompt, offline parser, transcript
/// highlighter) agrees on the same value.
///
/// * `hundred` x100
/// * `thousand`, `thousan`, `thosand`, `k`, `grand` x1,000
/// * `million`, `milion`, `m` x1,000,000
///
/// Digits and words both work: `1 thousand`, `one thousand`, `2.5k`,
/// `15 thousand`, `1 million`, `two hundred fifty`.
class SpokenNumbers {
  SpokenNumbers._();

  static const Map<String, int> _units = {
    'zero': 0,
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'nine': 9,
    'ten': 10,
    'eleven': 11,
    'twelve': 12,
    'thirteen': 13,
    'fourteen': 14,
    'fifteen': 15,
    'sixteen': 16,
    'seventeen': 17,
    'eighteen': 18,
    'nineteen': 19,
  };

  static const Map<String, int> _tens = {
    'twenty': 20,
    'thirty': 30,
    'forty': 40,
    'fifty': 50,
    'sixty': 60,
    'seventy': 70,
    'eighty': 80,
    'ninety': 90,
  };

  /// Multiplier words including common dictation / typing typos.
  static const Map<String, double> _scaleWords = {
    'hundred': 100,
    'hundreds': 100,
    'hundrad': 100,
    'hunderd': 100,
    'thousand': 1000,
    'thousands': 1000,
    'thousan': 1000,
    'thousnd': 1000,
    'thosand': 1000,
    'thosan': 1000,
    'tousand': 1000,
    'thausand': 1000,
    'thoussand': 1000,
    'grand': 1000,
    'million': 1000000,
    'millions': 1000000,
    'milion': 1000000,
    'millon': 1000000,
    'milllion': 1000000,
  };

  /// Alternation for the regex that follows a digit number.
  static final String _suffixAlternation =
      '${(_scaleWords.keys.toList()..sort((a, b) => b.length.compareTo(a.length))).join('|')}|k|m';

  static final RegExp _digitNumber = RegExp(
    r'(?<![\w.])(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)'
    '(?:\\s*($_suffixAlternation)(?![A-Za-z]))?',
    caseSensitive: false,
  );

  static final RegExp _wordToken = RegExp(r"[A-Za-z]+");

  static double _scaleFor(String suffix) {
    final s = suffix.toLowerCase();
    if (s == 'k') return 1000;
    if (s == 'm') return 1000000;
    return _scaleWords[s] ?? 1;
  }

  /// All numbers in [text] in reading order, never overlapping.
  static List<NumberSpan> scan(String text) {
    final spans = <NumberSpan>[];

    for (final m in _digitNumber.allMatches(text)) {
      var value = double.tryParse(m.group(1)!.replaceAll(',', ''));
      if (value == null) continue;
      final suffix = m.group(2);
      if (suffix != null) value *= _scaleFor(suffix);
      spans.add(
        NumberSpan(m.start, m.end, value, hasMultiplier: suffix != null),
      );
    }

    spans.addAll(_scanWordNumbers(text, spans));
    spans.sort((a, b) => a.start.compareTo(b.start));
    return spans;
  }

  /// `"one thousand"`, `"two hundred and fifty"`, `"a million"` ...
  /// Only phrases that contain a multiplier word are accepted so ordinary
  /// words such as "one" or "two" never become amounts by accident.
  static List<NumberSpan> _scanWordNumbers(
    String text,
    List<NumberSpan> taken,
  ) {
    final result = <NumberSpan>[];
    final tokens = _wordToken.allMatches(text).toList();
    var i = 0;
    while (i < tokens.length) {
      final startToken = tokens[i];
      var total = 0.0;
      var current = 0.0;
      var sawScale = false;
      var sawAny = false;
      var lastEnd = startToken.start;
      var j = i;
      var consumed = i;

      while (j < tokens.length) {
        final t = tokens[j];
        // Only whitespace, hyphens or "and" may sit between number words.
        if (j > i) {
          final gap = text.substring(lastEnd, t.start);
          if (!RegExp(r'^[\s\-]+$').hasMatch(gap)) break;
        }
        final w = t.group(0)!.toLowerCase();

        if (w == 'and' && sawAny) {
          // "one hundred and fifty": only if a number word follows.
          if (j + 1 < tokens.length &&
              _isNumberWord(tokens[j + 1].group(0)!.toLowerCase())) {
            lastEnd = t.end;
            j++;
            continue;
          }
          break;
        }

        if (_units.containsKey(w)) {
          current += _units[w]!;
        } else if (_tens.containsKey(w)) {
          current += _tens[w]!;
        } else if ((w == 'a' || w == 'an') &&
            !sawAny &&
            j + 1 < tokens.length &&
            _scaleWords.containsKey(tokens[j + 1].group(0)!.toLowerCase())) {
          current += 1;
        } else if (_scaleWords.containsKey(w)) {
          final scale = _scaleWords[w]!;
          if (scale == 100) {
            current = (current == 0 ? 1 : current) * 100;
          } else {
            total += (current == 0 ? 1 : current) * scale;
            current = 0;
          }
          sawScale = true;
        } else {
          break;
        }
        sawAny = true;
        lastEnd = t.end;
        consumed = j + 1;
        j++;
      }

      if (sawAny && sawScale) {
        final start = startToken.start;
        final end = tokens[consumed - 1].end;
        final overlaps = taken.any((s) => start < s.end && end > s.start);
        if (!overlaps) {
          result.add(
            NumberSpan(start, end, total + current, hasMultiplier: true),
          );
        }
        i = consumed;
      } else {
        i++;
      }
    }
    return result;
  }

  static bool _isNumberWord(String w) =>
      _units.containsKey(w) ||
      _tens.containsKey(w) ||
      _scaleWords.containsKey(w);

  /// Rewrites every spoken or suffixed number in [text] as plain digits so a
  /// language model sees `1000` instead of `1 thousan` or `2.5k`.
  static String normalize(String text) {
    final spans = scan(text).where((s) => s.hasMultiplier).toList();
    if (spans.isEmpty) return text;
    final buf = StringBuffer();
    var pos = 0;
    for (final s in spans) {
      if (s.start < pos) continue;
      buf.write(text.substring(pos, s.start));
      final v = s.value;
      buf.write(v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString());
      pos = s.end;
    }
    buf.write(text.substring(pos));
    return buf.toString();
  }
}
