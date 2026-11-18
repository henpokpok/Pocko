import '../../services/hybrid_ai/spoken_numbers.dart';

/// Locates the parsed expense entities (item title, price and mentioned group
/// members) inside the user's own transcript so the overlay can render them as
/// tappable pills.
enum TranscriptTokenKind { text, title, amount, member }

class TranscriptToken {
  final TranscriptTokenKind kind;

  /// Original transcript text of this token.
  final String text;

  /// Index of the parsed item (for title/amount tokens).
  final int? itemIndex;

  /// Group member id (for member tokens).
  final String? memberId;

  const TranscriptToken(this.kind, this.text, [this.itemIndex, this.memberId]);
}

class TokenizeResult {
  final List<TranscriptToken> tokens;

  /// Items whose title phrase was not found in the transcript.
  final Set<int> missingTitle;

  /// Items whose price was not found in the transcript.
  final Set<int> missingAmount;

  const TokenizeResult(this.tokens, this.missingTitle, this.missingAmount);

  bool hasInline(int item) => tokens.any(
    (t) => t.itemIndex == item && t.kind != TranscriptTokenKind.text,
  );

  /// Ids of the members whose names appear in the transcript.
  Set<String> get mentionedMembers => {
    for (final t in tokens)
      if (t.kind == TranscriptTokenKind.member && t.memberId != null)
        t.memberId!,
  };
}

class _Range {
  final int start;
  final int end;
  final TranscriptTokenKind kind;
  final int item;
  final String? memberId;
  _Range(this.start, this.end, this.kind, this.item, [this.memberId]);
}

/// Splits [transcript] into plain text and highlighted title / amount / member
/// tokens for each `(title, amount)` in [items], in spoken order. Entities that
/// cannot be located are reported in `missingTitle` / `missingAmount` so the
/// UI can still show them (as trailing pills).
///
/// Amounts are located with [SpokenNumbers], so `"1 thousan"`, `"2.5k"` or
/// `"one thousand"` in the transcript match an item amount of 1000 / 2500.
///
/// [members] are `(id, name)` pairs; every whole-word mention of a name is
/// tokenized as a member token. [selfId] additionally maps "me" / "myself".
TokenizeResult tokenizeTranscript(
  String transcript,
  List<({String title, double amount})> items, {
  List<({String id, String name})> members = const [],
  String? selfId,
}) {
  final lower = transcript.toLowerCase();
  final ranges = <_Range>[];
  final missingTitle = <int>{};
  final missingAmount = <int>{};
  var cursor = 0;
  final numbers = SpokenNumbers.scan(transcript);

  for (var i = 0; i < items.length; i++) {
    final item = items[i];

    // --- title ---------------------------------------------------------
    int? ts;
    int? te;
    final full = item.title.trim().toLowerCase();
    if (full.isNotEmpty) {
      final idx = lower.indexOf(full, cursor);
      if (idx >= 0) {
        ts = idx;
        te = idx + full.length;
      } else {
        for (final w in full.split(RegExp(r'\s+'))) {
          if (w.length < 3) continue;
          final j = lower.indexOf(w, cursor);
          if (j >= 0) {
            ts = j;
            te = j + w.length;
            break;
          }
        }
      }
    }

    // --- amount --------------------------------------------------------
    int? aStart;
    int? aEnd;
    final from = ts ?? cursor;
    for (final n in numbers) {
      if (n.end <= from) continue;
      if ((n.value - item.amount).abs() > 0.01) continue;
      var start = n.start;
      if (start > 0 && '¥€\$₩£฿'.contains(transcript[start - 1])) start--;
      // Do not overlap the title range.
      if (ts != null && te != null && start < te && n.end > ts) continue;
      aStart = start;
      aEnd = n.end;
      break;
    }

    if (ts != null && te != null) {
      ranges.add(_Range(ts, te, TranscriptTokenKind.title, i));
    } else {
      missingTitle.add(i);
    }
    if (aStart != null && aEnd != null) {
      ranges.add(_Range(aStart, aEnd, TranscriptTokenKind.amount, i));
    } else {
      missingAmount.add(i);
    }
    final reached = [
      te ?? cursor,
      aEnd ?? cursor,
    ].reduce((a, b) => a > b ? a : b);
    if (reached > cursor) cursor = reached;
  }

  // --- members -----------------------------------------------------------
  final memberRanges = <_Range>[];
  for (final m in members) {
    final name = m.name.trim();
    if (name.isEmpty) continue;
    final re = RegExp(
      '(?<![A-Za-z])${RegExp.escape(name)}(?![A-Za-z])',
      caseSensitive: false,
    );
    for (final match in re.allMatches(transcript)) {
      memberRanges.add(
        _Range(match.start, match.end, TranscriptTokenKind.member, -1, m.id),
      );
    }
  }
  if (selfId != null) {
    for (final match in RegExp(
      r'(?<![A-Za-z])(me|myself)(?![A-Za-z])',
      caseSensitive: false,
    ).allMatches(transcript)) {
      memberRanges.add(
        _Range(match.start, match.end, TranscriptTokenKind.member, -1, selfId),
      );
    }
  }
  // Member mentions never steal text from a title or an amount.
  for (final r in memberRanges) {
    final clash = ranges.any(
      (o) =>
          o.kind != TranscriptTokenKind.member &&
          r.start < o.end &&
          r.end > o.start,
    );
    if (!clash) ranges.add(r);
  }

  ranges.sort((a, b) => a.start.compareTo(b.start));
  final tokens = <TranscriptToken>[];
  var pos = 0;
  for (final r in ranges) {
    if (r.start < pos) {
      // Overlapping range: the entity falls back to a trailing pill.
      if (r.kind == TranscriptTokenKind.title) missingTitle.add(r.item);
      if (r.kind == TranscriptTokenKind.amount) missingAmount.add(r.item);
      continue;
    }
    if (r.start > pos) {
      tokens.add(
        TranscriptToken(
          TranscriptTokenKind.text,
          transcript.substring(pos, r.start),
        ),
      );
    }
    tokens.add(
      TranscriptToken(
        r.kind,
        transcript.substring(r.start, r.end),
        r.kind == TranscriptTokenKind.member ? null : r.item,
        r.memberId,
      ),
    );
    pos = r.end;
  }
  if (pos < transcript.length) {
    tokens.add(
      TranscriptToken(TranscriptTokenKind.text, transcript.substring(pos)),
    );
  }
  return TokenizeResult(tokens, missingTitle, missingAmount);
}
