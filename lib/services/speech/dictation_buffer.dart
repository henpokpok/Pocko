/// Accumulates what the user says across recognition segments.
///
/// Android's `SpeechRecognizer` (and iOS) finalize a segment after a short
/// pause and then report **only the next words** from `recognizedWords`, so
/// assigning the result straight to a text field wipes what was said before the
/// pause. Chrome's continuous mode instead reports the **cumulative** transcript
/// every time. This buffer handles both without losing or duplicating a word:
///
/// * [committed]: every finalized segment so far (this capture session);
/// * [activeSegment]: the live partial / final words of the current listen
///   session, shown after the committed text;
/// * a result that already starts with [committed] (the Web case) *is* the full
///   text and replaces it, so nothing is repeated.
class DictationBuffer {
  String _committed = '';
  String _active = '';

  /// The segment most recently committed (to spot late duplicate echoes).
  String _lastSegment = '';

  String get committed => _committed;
  String get activeSegment => _active;

  /// Committed text followed by the live segment, single-spaced.
  String get fullText => _join(_committed, _active);

  bool get isEmpty => fullText.isEmpty;

  /// Collapses runs of whitespace and trims the ends.
  static String normalize(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

  static String _join(String a, String b) {
    if (a.isEmpty) return b;
    if (b.isEmpty) return a;
    return '$a $b';
  }

  /// Applies one recognizer callback and returns the text to show.
  /// A [isFinal] result promotes the combined text into [committed].
  ///
  /// The live segment keeps its **high-water mark**: an empty partial, or a
  /// shorter partial that is just a truncation of what is already showing (a
  /// confidence dip), never wipes longer words. Android often never sends
  /// `finalResult == true`, so the sheet also calls [commitActive] when the
  /// session ends.
  String onResult(String words, {required bool isFinal}) {
    final w = normalize(words);
    final cumulative = _committed.isNotEmpty && _isCumulativeOf(w, _committed);
    final candidate = cumulative ? w.substring(_committed.length).trim() : w;

    if (candidate.isEmpty) {
      // Empty partial / empty final: keep (and, if final, commit) what we have.
      if (isFinal) commitActive();
      return fullText;
    }
    // A late echo of the segment that was just committed (the recognizer
    // finishing its old session): never append it a second time.
    if (_active.isEmpty && _lastSegment.isNotEmpty) {
      final l = candidate.toLowerCase();
      final last = _lastSegment.toLowerCase();
      if (last == l || (!isFinal && last.startsWith(l))) return fullText;
    }

    final accepted = _resolve(candidate);
    final String full;
    if (cumulative && accepted == candidate && _committed.isNotEmpty) {
      full = w; // the engine already repeats the prefix (Web)
      _active = accepted;
    } else {
      _active = accepted;
      full = fullText;
    }
    if (isFinal) {
      final done = full;
      _committed = done;
      _lastSegment = _active;
      _active = '';
    }
    return full;
  }

  /// Decides what the live segment becomes after the new [candidate].
  String _resolve(String candidate) {
    final a = _active;
    if (a.isEmpty) return candidate;
    final c = candidate.toLowerCase();
    final cur = a.toLowerCase();
    // Confidence dip: a shorter partial that only truncates what we have.
    if (cur.startsWith(c) && _words(candidate) < _words(a)) return a;
    // Growth of the same segment.
    if (c.startsWith(cur)) return candidate;
    // Far fewer words and unrelated: the recognizer started a new utterance
    // without a final. Keep the old one, then continue with the new one.
    if (_words(candidate) * 2 < _words(a)) {
      _committed = _join(_committed, a);
      _lastSegment = a;
      return candidate;
    }
    // A revision of similar length: take the recognizer's newer hypothesis.
    return candidate;
  }

  static int _words(String s) => s.isEmpty ? 0 : s.split(' ').length;

  /// A listen session ended (pause / `done`): keep its words, start fresh.
  void commitActive() {
    if (_active.isNotEmpty) _lastSegment = _active;
    _committed = fullText;
    _active = '';
  }

  /// The user edited or cleared the text box: it is the new truth.
  void syncManual(String text) {
    _committed = normalize(text);
    _active = '';
    _lastSegment = '';
  }

  void clear() {
    _committed = '';
    _active = '';
    _lastSegment = '';
  }

  static bool _isCumulativeOf(String words, String prefix) {
    if (words.length < prefix.length) return false;
    if (words.substring(0, prefix.length).toLowerCase() !=
        prefix.toLowerCase()) {
      return false;
    }
    // Whole-word boundary: "coffee" must not match "coffeeshop".
    return words.length == prefix.length || words[prefix.length] == ' ';
  }
}
