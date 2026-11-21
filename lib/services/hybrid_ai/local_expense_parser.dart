import '../../core/enums/expense_category.dart';
import 'parsed_expense_draft.dart';
import 'spoken_numbers.dart';

/// Deterministic English heuristic engine used only when no real on-device or
/// cloud model is reachable (headless `flutter test`, unconfigured simulators,
/// mock mode). Results from this engine are always flagged `isSimulated`.
class LocalExpenseParser {
  LocalExpenseParser._();

  static const Map<String, List<String>> _currencyWords = {
    'JPY': ['¥', 'yen', 'jpy'],
    'USD': ['\$', 'usd', 'dollar', 'dollars', 'bucks'],
    'EUR': ['€', 'eur', 'euro', 'euros'],
    'THB': ['฿', 'thb', 'baht'],
    'KRW': ['₩', 'krw', 'won'],
    'GBP': ['£', 'gbp', 'pound', 'pounds', 'quid', 'sterling'],
  };

  // ---------------------------------------------------------------------------
  // Expense sentences
  // ---------------------------------------------------------------------------

  /// Splits "A 4800 …, and B 18200 …" into independent expense segments.
  static List<String> segment(
    String rawText, {
    List<String> memberNames = const [],
    String defaultPayer = 'You',
  }) {
    // One shared bill with per-person prices is ONE expense, not many.
    if (memberNames.isNotEmpty &&
        _tryItemized(
              rawText,
              tripCurrency: 'JPY',
              memberNames: memberNames,
              defaultPayer: defaultPayer,
            ) !=
            null) {
      return [rawText.trim()];
    }
    final chunks = rawText
        .split(RegExp(r'[\n;]+|\s*,\s+and\s+|\s+and\s+|,\s+(?=[A-Za-z])'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final merged = <String>[];
    for (final chunk in chunks) {
      if (merged.isEmpty) {
        merged.add(chunk);
      } else if (_findAmount(merged.last) == null) {
        // "Eat Ramen with Maya and Liam for 8000": the part before "and" has no
        // price yet, so the name list continues the same expense.
        merged[merged.length - 1] = '${merged.last} and $chunk';
      } else if (_findAmount(chunk) != null) {
        merged.add(chunk);
      } else {
        // Name lists such as "for Alex, Maya, and me" belong to the previous expense.
        merged[merged.length - 1] = '${merged.last}, $chunk';
      }
    }
    return merged.isEmpty ? [rawText.trim()] : merged;
  }

  static List<Map<String, dynamic>> parseExpenses(
    String rawText, {
    required String tripCurrency,
    required List<String> memberNames,
    required String defaultPayer,
  }) {
    final itemized = _tryItemized(
      rawText,
      tripCurrency: tripCurrency,
      memberNames: memberNames,
      defaultPayer: defaultPayer,
    );
    if (itemized != null) return [itemized];

    return segment(rawText)
        .map(
          (seg) => _parseSegment(
            seg,
            tripCurrency: tripCurrency,
            memberNames: memberNames,
            defaultPayer: defaultPayer,
          ),
        )
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Itemized shared bills: "Dinner at Sushiro, I paid: mine 1200 yen, Maya
  // ordered salmon 1800 yen, Liam had udon 950 yen"
  // ---------------------------------------------------------------------------

  static final RegExp _itemizedCue = RegExp(
    r'\b(mine|my own|ordered|order|had|got|ate)\b|:',
    caseSensitive: false,
  );
  static final RegExp _payerVerb = RegExp(
    r'\b(paid|pays|covered|treated|bought|treat)\b',
    caseSensitive: false,
  );

  /// Returns ONE combined expense with `customSplits` when the sentence lists
  /// each person's own price, otherwise `null`.
  static Map<String, dynamic>? _tryItemized(
    String raw, {
    required String tripCurrency,
    required List<String> memberNames,
    required String defaultPayer,
  }) {
    if (memberNames.length < 2 || !_itemizedCue.hasMatch(raw)) return null;
    final spans = SpokenNumbers.scan(raw);
    if (spans.length < 2) return null;

    final alias = RegExp(
      '\\b(${[for (final n in memberNames) RegExp.escape(n)].join('|')}|mine|my|me)\\b',
      caseSensitive: false,
    );

    final shares = <String, double>{};
    var prevEnd = 0;
    for (final span in spans) {
      final window = raw.substring(prevEnd, span.start);
      RegExpMatch? last;
      for (final m in alias.allMatches(window)) {
        last = m;
      }
      if (last == null) return null; // every price must belong to somebody
      // "Maya paid 6k": a payer verb between the name and the price is not an order.
      if (_payerVerb.hasMatch(window.substring(last.end))) return null;
      final who = last.group(0)!.toLowerCase();
      final name = (who == 'mine' || who == 'my' || who == 'me')
          ? defaultPayer
          : memberNames.firstWhere(
              (n) => n.toLowerCase() == who,
              orElse: () => defaultPayer,
            );
      shares[name] = (shares[name] ?? 0) + span.value;
      prevEnd = span.end;
    }
    if (shares.length < 2) return null;

    // Title: the venue clause before the first comma / colon / "paid".
    final cut = RegExp(
      r'[,:]|\bi paid\b|\bpaid\b|\bmine\b',
      caseSensitive: false,
    ).firstMatch(raw);
    final clause = (cut == null ? raw : raw.substring(0, cut.start)).trim();
    String title;
    final venue = RegExp(
      r'^(.*?)\s+(?:at|in|@)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(clause);
    if (venue != null) {
      title = _cleanTitle('${venue.group(2)} ${venue.group(1)}', memberNames);
      if (title.isEmpty) title = clause;
    } else {
      title = _cleanTitle(clause, memberNames);
    }
    var category = ExpenseCategory.fromString(clause);
    if (category == ExpenseCategory.MISC) {
      category = ExpenseCategory.fromString(raw);
    }
    if (title.isEmpty) title = category.displayName;

    // Who paid the shared bill: the speaker unless "Maya paid ...".
    var payer = defaultPayer;
    for (final n in memberNames) {
      if (RegExp(
        '\\b${RegExp.escape(n)}\\s+(paid|covered|pays)\\b',
        caseSensitive: false,
      ).hasMatch(raw)) {
        payer = n;
        break;
      }
    }

    final draft = ParsedExpenseDraft(
      title: title,
      unitAmount: shares.values.fold<double>(0, (a, b) => a + b),
      currency: _detectCurrency(raw) ?? tripCurrency,
      category: category == ExpenseCategory.MISC
          ? ExpenseCategory.MEAL
          : category,
      payer: payer,
      splitWith: shares.keys.toList(),
      customSplits: shares,
    );
    return draft.toMap(shares.length);
  }

  static Map<String, dynamic> _parseSegment(
    String seg, {
    required String tripCurrency,
    required List<String> memberNames,
    required String defaultPayer,
  }) {
    final lower = seg.toLowerCase();
    final span = _findAmountSpan(seg);
    final unit = span?.value ?? 0.0;
    final mods = _modifiers(seg, span);
    final currency = _detectCurrency(seg) ?? tripCurrency;
    final category = ExpenseCategory.fromString(seg);

    // ---- payer -------------------------------------------------------------
    var payer = defaultPayer;
    String? payerClause;
    for (final name in memberNames) {
      final escaped = RegExp.escape(name);
      final m = RegExp(
        '\\b$escaped\\b\\s+(?:paid|pays|covered|treated|bought|got|picked up)|paid by\\s+$escaped\\b',
        caseSensitive: false,
      ).firstMatch(seg);
      if (m != null) {
        payer = name;
        payerClause = m.group(0);
        break;
      }
    }
    if (payerClause == null &&
        RegExp(r"\b(i paid|i bought|i covered|i got|paid by me|my treat)\b")
            .hasMatch(lower)) {
      payer = defaultPayer;
    }

    // ---- split -------------------------------------------------------------
    final scan = payerClause == null ? seg : seg.replaceFirst(payerClause, ' ');
    final scanLower = scan.toLowerCase();
    List<String> splitWith;
    final solo = RegExp(
      r'\b(solo|just me|only me|for myself|for himself|for herself|for themself|by myself)\b',
    ).hasMatch(lower);
    final everyone = RegExp(
      r'\b(everyone|everybody|every one|all of (?:us|them|you)|the (?:whole |entire )?group|the whole crew|split all|(?:for|with|among|between|split)\s+(?:the\s+)?all|split (?:\d+|evenly|equally|it)(?: ways)?|between us)\b|\ball\s*$',
    ).hasMatch(lower);

    if (solo) {
      splitWith = [payer];
    } else {
      final mentioned = <String>[];
      for (final name in memberNames) {
        if (RegExp(
          '\\b${RegExp.escape(name)}\\b',
          caseSensitive: false,
        ).hasMatch(scan)) {
          mentioned.add(name);
        }
      }
      if (RegExp(r'\b(me|myself|us)\b').hasMatch(scanLower) &&
          !mentioned.contains(defaultPayer)) {
        mentioned.add(defaultPayer);
      }
      final treat = RegExp(r'\b(treat|treated|on behalf|paid for)\b')
          .hasMatch(lower);
      if (everyone || mentioned.isEmpty) {
        splitWith = List<String>.from(memberNames);
      } else {
        // "split with Alex" and "ramen with Maya and Liam" include the payer;
        // "for Alex & Maya" (a treat) does not.
        final together =
            lower.contains('split') || RegExp(r'\bwith\b').hasMatch(scanLower);
        if (!treat && together && !mentioned.contains(payer)) {
          mentioned.insert(0, payer);
        }
        splitWith = mentioned;
      }
    }

    final draft = ParsedExpenseDraft(
      title: _extractTitle(seg, category, memberNames),
      unitAmount: unit,
      amountMode: mods.mode,
      quantity: mods.quantity,
      extraPercent: mods.percent,
      currency: currency,
      category: category,
      payer: payer,
      splitWith: splitWith,
    );
    // `amount` is the exact total (unit x quantity x people x (1 + percent)).
    return draft.toMap(splitWith.length);
  }

  // ---------------------------------------------------------------------------
  // Pricing modifiers: "500 yen each", "4 coffees at 5 dollars a cup",
  // "10k plus 10% service charge"
  // ---------------------------------------------------------------------------

  static final RegExp _percent = RegExp(
    r'(plus|\+|incl\.?|including|add|and|with)?\s*(\d+(?:\.\d+)?)\s*(?:%|per\s?cent|percent|pct)\s*(service charge|service|tip|tax|vat|surcharge|fee|gratuity|charge)?',
    caseSensitive: false,
  );

  static const Map<String, int> _qtyWords = {
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
  };

  static final RegExp _qtyBeforePrice = RegExp(
    r'(?:^|\s)(\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten)\s*(?:(x|×)\s*)?((?:[a-z][a-z\-]*\s+){0,2}?)(?:(at|@)\s*)?[¥€\$₩£฿]?\s*$',
    caseSensitive: false,
  );

  static final RegExp _eachAfterPrice = RegExp(
    r'^\s*(?:yen|jpy|usd|eur|euros?|thb|baht|krw|won|gbp|pounds?|quid|dollars?|bucks)?\s*(?:a|an|per|each|apiece|ea|every)\b',
    caseSensitive: false,
  );

  static final RegExp _perPerson = RegExp(
    r'\b(per person|per head|a head|per pax|apiece|each|pp)\b',
    caseSensitive: false,
  );

  static final RegExp _perPersonExplicit = RegExp(
    r'\b(per person|per head|a head|per pax|pp)\b',
    caseSensitive: false,
  );

  /// Whether [text] says the price is per person (each, per head, apiece...).
  static bool hasPerPersonCue(String text) => _perPerson.hasMatch(text);

  static ({AmountMode mode, int quantity, double percent}) _modifiers(
    String seg,
    NumberSpan? span,
  ) {
    // ---- percent (tip / tax / service charge) ----------------------------
    var percent = 0.0;
    final pm = _percent.firstMatch(seg);
    if (pm != null) {
      final rest = seg.substring(pm.end);
      final isDiscount = RegExp(
        r'^\s*(off|discount)\b',
        caseSensitive: false,
      ).hasMatch(rest);
      final connected = pm.group(1) != null || pm.group(3) != null;
      if (!isDiscount && connected) percent = double.parse(pm.group(2)!);
    }

    // ---- quantity: "4 coffees at 5 dollars a cup", "2 x 500", ------------
    //      "3 tickets 1200 yen each"
    var quantity = 1;
    var eachBelongsToQuantity = false;
    if (span != null) {
      final before = seg.substring(0, span.start);
      final after = seg.substring(span.end);
      final q = _qtyBeforePrice.firstMatch(before);
      if (q != null) {
        final raw = q.group(1)!.toLowerCase();
        final n = int.tryParse(raw) ?? _qtyWords[raw] ?? 1;
        final noun = (q.group(3) ?? '').toLowerCase();
        final pre = before.substring(0, q.start);
        final headCount =
            RegExp(
              r'\b(ways?|people|persons?|pax|guests?|nights?|days?|hours?|hrs?)\b',
            ).hasMatch(noun) ||
            RegExp(
              r'(for|with|split|among|between|of)\s*$',
              caseSensitive: false,
            ).hasMatch(pre);
        final marker = q.group(2) != null || q.group(4) != null;
        final each = _eachAfterPrice.hasMatch(after);
        if (n >= 2 && !headCount && (marker || each)) {
          quantity = n;
          eachBelongsToQuantity = each && !marker;
        }
      }
    }

    // ---- per person -------------------------------------------------------
    final perPerson = eachBelongsToQuantity
        ? _perPersonExplicit.hasMatch(seg)
        : _perPerson.hasMatch(seg);

    return (
      mode: perPerson ? AmountMode.perPerson : AmountMode.total,
      quantity: quantity,
      percent: percent,
    );
  }

  static final RegExp _leadingVerb = RegExp(
    r'^(?:(?:i|we)\s+)?(?:eat|ate|eating|had|have|having|grab|grabbed|bought|buy|got|get|ordered|order|paid\s+for|pay\s+for|spent\s+on|booked|book|took|take|treated\s+to)\s+(?:the\s+|a\s+|an\s+|some\s+|my\s+|our\s+)?',
    caseSensitive: false,
  );

  /// "Eat Ramen" -> "Ramen", "Maya paid for sushi" -> "sushi". Shared with the
  /// model-answer normalizer so real LLM titles get the same clean-up.
  static String stripLeadingVerb(String text, List<String> memberNames) {
    var t = text.trim();
    for (final name in memberNames) {
      final m = RegExp(
        '^${RegExp.escape(name)}\\s+(?:paid|pays|covered|treated|bought|got)\\s+(?:for\\s+)?',
        caseSensitive: false,
      ).firstMatch(t);
      if (m != null) {
        t = t.substring(m.end);
        break;
      }
    }
    return t.replaceFirst(_leadingVerb, '').trim();
  }

  static String _extractTitle(
    String seg,
    ExpenseCategory category,
    List<String> memberNames,
  ) {
    final matches = SpokenNumbers.scan(seg);
    final first = matches.isEmpty ? null : matches.first;
    final before = first == null ? seg : seg.substring(0, first.start);
    final after = first == null ? '' : seg.substring(first.end);

    // The words before the price; if there are none (or they were only a
    // payer / verb), the words after it ("Maya paid 6k yen for taxi").
    final tries = <String>[
      if (RegExp(r'[A-Za-z]{3,}').hasMatch(before)) before,
      if (first != null) after,
      seg,
    ];
    for (final raw in tries) {
      final t = _cleanTitle(raw, memberNames);
      if (t.length >= 2) return t;
    }
    return category.displayName;
  }

  static String _cleanTitle(String raw, List<String> memberNames) {
    var candidate = stripLeadingVerb(raw, memberNames);

    // Remove currency words / symbols.
    candidate = candidate.replaceAll(RegExp(r'[¥€\$₩£฿]'), ' ');
    candidate = candidate.replaceAll(
      RegExp(
        r'\b(yen|jpy|usd|eur|euros?|thb|baht|krw|won|gbp|pounds?|quid|dollars?|bucks)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    // Stand-alone numbers ("1200", "2.5k") are the price, not the item; names
    // such as "7-Eleven" keep theirs.
    candidate = candidate.replaceAll(
      RegExp(r'(?<![\w-])\d[\d,.]*(?:k|m)?(?![\w-])', caseSensitive: false),
      ' ',
    );
    candidate = candidate.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Leading connectors ("for taxi", "on sushi", "at Ichiran").
    final lead = RegExp(
      r'^(for|on|at|to|of|from|a|an|the)\s+',
      caseSensitive: false,
    );
    while (lead.hasMatch(candidate)) {
      candidate = candidate.replaceFirst(lead, '');
    }

    // Cut at the first connector keyword.
    final cut = RegExp(
      r'\b(paid|pays|split|for|with|between|among|each|per|by|and|on|at|from|to|plus|incl|including)\b',
      caseSensitive: false,
    ).firstMatch(candidate);
    if (cut != null && cut.start > 0) {
      candidate = candidate.substring(0, cut.start);
    }
    candidate = candidate
        .replaceAll(RegExp(r'[^\p{L}\p{N}_ &\-\x27]+', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // A title is the thing bought, never a person: drop member names.
    final names = {for (final n in memberNames) n.trim().toLowerCase()};
    candidate = candidate
        .split(' ')
        .where((w) => !names.contains(w.toLowerCase()))
        .join(' ')
        .trim();
    candidate = candidate
        .replaceFirst(RegExp(r'^(a|an|the)\s+', caseSensitive: false), '')
        .trim();

    if (candidate.length < 2) return '';
    return candidate
        .split(' ')
        .map((w) {
          if (w.isEmpty) return w;
          final hasUpper = w.substring(1).contains(RegExp(r'[A-Z]'));
          return hasUpper ? w : '${w[0].toUpperCase()}${w.substring(1)}';
        })
        .join(' ');
  }

  // ---------------------------------------------------------------------------
  // Amounts & currencies
  // ---------------------------------------------------------------------------

  static String? _detectCurrency(String text) {
    final lower = text.toLowerCase();
    int bestIndex = 1 << 30;
    String? best;
    _currencyWords.forEach((code, words) {
      for (final w in words) {
        final idx = lower.indexOf(w);
        if (idx < 0) continue;
        // Word currencies must be standalone words ("won" inside "won't" is ignored).
        if (RegExp(r'^[a-z]+$').hasMatch(w)) {
          if (!RegExp('\\b${RegExp.escape(w)}\\b').hasMatch(lower)) continue;
        }
        if (idx < bestIndex) {
          bestIndex = idx;
          best = code;
        }
      }
    });
    return best;
  }

  /// Finds the most plausible expense amount: a number next to a currency
  /// marker wins, otherwise the largest number that is not a head-count.
  static double? _findAmount(String seg) => _findAmountSpan(seg)?.value;

  static NumberSpan? _findAmountSpan(String seg) {
    NumberSpan? withCurrency;
    NumberSpan? largest;
    for (final m in SpokenNumbers.scan(seg)) {
      final after = seg.substring(m.end);
      final before = seg.substring(0, m.start);
      if (RegExp(
        r'^\s*(ways?|people|persons?|pax|guests?|nights?|days?|x\b|%|per\s?cent|percent|pct|hrs?\b|hours?)',
        caseSensitive: false,
      ).hasMatch(after)) {
        continue;
      }
      if (RegExp(
        r'(split|among|between)\s*$',
        caseSensitive: false,
      ).hasMatch(before)) {
        continue;
      }

      final nearCurrency =
          RegExp(r'[¥€\$₩£฿]\s*$').hasMatch(before) ||
          RegExp(
            r'^\s*(yen|jpy|usd|eur|euros?|thb|baht|krw|won|gbp|pounds?|quid|dollars?|bucks)\b',
            caseSensitive: false,
          ).hasMatch(after);
      if (nearCurrency) withCurrency ??= m;
      if (largest == null || m.value > largest.value) largest = m;
    }
    return withCurrency ?? largest;
  }

  /// Parses "1,234.50", "18,50" (EU decimal) and "1.234,50".
  static double? parseNumber(String raw) {
    var s = raw.trim().replaceAll(RegExp(r'[^\d.,]'), '');
    if (s.isEmpty) return null;
    final lastComma = s.lastIndexOf(',');
    final lastDot = s.lastIndexOf('.');
    if (lastComma >= 0 && lastDot >= 0) {
      if (lastComma > lastDot) {
        s = s.replaceAll('.', '').replaceAll(',', '.');
      } else {
        s = s.replaceAll(',', '');
      }
    } else if (lastComma >= 0) {
      final decimals = s.length - lastComma - 1;
      s = decimals == 2 ? s.replaceAll(',', '.') : s.replaceAll(',', '');
    }
    return double.tryParse(s);
  }

  // ---------------------------------------------------------------------------
  // Receipts
  // ---------------------------------------------------------------------------

  static final RegExp _skipLine = RegExp(
    r'\b(total|subtotal|sub-total|tax|vat|tip|service|card|date|time|account|email|amount|merchant|paid|change|cash|balance|receipt|invoice|table|server|order)\b',
    caseSensitive: false,
  );

  static Map<String, dynamic> parseReceipt(
    String text, {
    required String tripCurrency,
  }) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    // Currency
    final currency =
        _detectCurrency(text) ??
        RegExp(r'\b(EUR|USD|JPY|KRW|GBP|THB)\b').firstMatch(text)?.group(1) ??
        tripCurrency;

    // Merchant
    String merchant = '';
    for (final l in lines) {
      final m = RegExp(
        r'^(?:merchant|shop|store|restaurant)\s*[:\-]\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(l);
      if (m != null) {
        merchant = m.group(1)!.trim();
        break;
      }
    }
    if (merchant.isEmpty && lines.isNotEmpty) {
      merchant = lines.first
          .replaceAll(RegExp(r'[•|]+'), '-')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }

    // Line items
    final items = <Map<String, dynamic>>[];
    for (final l in lines) {
      if (_skipLine.hasMatch(l) || l.contains(':')) continue;
      final m = RegExp(
        r'^(.*?[A-Za-z].*?)\s+[^\d\n]{0,3}(\d[\d.,]*)\s*(?:[A-Za-z€\$¥₩£฿]{0,3})$',
      ).firstMatch(l);
      if (m == null) continue;
      final value = parseNumber(m.group(2)!);
      final name = m.group(1)!.replaceAll(RegExp(r'[\s.\-•]+$'), '').trim();
      if (value == null || value <= 0 || name.length < 2) continue;
      items.add({'name': name, 'amount': value});
    }

    // Total
    double? total;
    for (final l in lines.reversed) {
      if (RegExp(
        r'\b(sub-?total|tax|vat|tip)\b',
        caseSensitive: false,
      ).hasMatch(l)) {
        continue;
      }
      final m = RegExp(
        r'\b(?:grand total|total|amount|paid|charged|you spent|balance due)\b[^\d\n]*([\d][\d.,]*)',
        caseSensitive: false,
      ).firstMatch(l);
      if (m != null) {
        total = parseNumber(m.group(1)!);
        if (total != null) break;
      }
    }
    if (total == null && items.isNotEmpty) {
      total = items.fold<double>(0.0, (s, i) => s + (i['amount'] as double));
    }
    total ??= _findAmount(text) ?? 0.0;

    final category = ExpenseCategory.fromString(
      '$merchant ${items.map((i) => i['name']).join(' ')}',
    );

    return {
      'merchant': merchant.isEmpty ? 'Receipt' : merchant,
      'total': total,
      'currency': currency,
      'category': category.name,
      'lineItems': items,
      'items': [
        {
          'title': merchant.isEmpty ? 'Receipt' : merchant,
          'amount': total,
          'currency': currency,
          'category': category.name,
          'payer': '',
          'splitWith': <String>[],
        },
      ],
    };
  }
}
