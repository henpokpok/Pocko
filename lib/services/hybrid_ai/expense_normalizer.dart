import '../../core/enums/expense_category.dart';
import '../../core/utils/travel_gazetteer.dart';
import 'local_expense_parser.dart';
import 'parsed_expense_draft.dart';
import 'spoken_numbers.dart';

/// Safety net applied to every real (on-device or cloud) model answer so a
/// hallucinated or sloppy reply can never reach the UI as-is.
///
/// The deterministic [LocalExpenseParser] is used as a cross-check for the
/// same sentence:
/// * a title is the thing bought, never a person (`Liam`) and never starts
///   with a verb (`Eat Ramen` becomes `Ramen`);
/// * **pricing cues come from the text, not from the model's arithmetic**:
///   `each` / `per person`, `4 x price` and `plus 10%` decide
///   `amountMode`, `quantity` and `extraPercent`, and the stated number is
///   restored if the model multiplied it or dropped a spoken multiplier;
/// * a `MISC` category on a known travel venue or brand (`Disneyland`,
///   `Teamlab`, `Cosmo Land`...) is rescued by the [TravelGazetteer] (and only
///   a `MISC` answer is ever overridden);
/// * members the user explicitly named win over the model's guess, and
///   `with Maya and Liam` includes the payer while `for Maya` does not.
class ExpenseNormalizer {
  ExpenseNormalizer._();

  static List<Map<String, dynamic>> normalize(
    List<Map<String, dynamic>> liveItems, {
    required String userInput,
    required String tripCurrency,
    required List<String> memberNames,
    required String defaultPayer,
  }) {
    if (liveItems.isEmpty) return liveItems;
    // The words after "oh wait, no..." replace the corrected-away number, and
    // a spaced "2 200" is 2200, before any deterministic cross-check.
    userInput = SpokenCorrections.resolve(
      SpokenNumbers.collapseSpacedThousands(userInput),
    );

    final segments = LocalExpenseParser.segment(
      userInput,
      memberNames: memberNames,
      defaultPayer: defaultPayer,
    );
    final local = LocalExpenseParser.parseExpenses(
      userInput,
      tripCurrency: tripCurrency,
      memberNames: memberNames,
      defaultPayer: defaultPayer,
    );
    // A shared bill with per-person prices is ONE expense: when the sentence
    // is clearly itemized, the deterministic reading replaces a model answer
    // that split it into several items.
    if (local.length == 1 &&
        ParsedExpenseDraft.fromMap(local.first).isItemized &&
        liveItems.length != 1) {
      return [local.first];
    }
    final paired = local.length == liveItems.length;
    final lowerNames = {for (final n in memberNames) n.toLowerCase(): n};

    final result = <Map<String, dynamic>>[];
    for (var i = 0; i < liveItems.length; i++) {
      final live = ParsedExpenseDraft.fromMap(
        liveItems[i],
        defaultCurrency: tripCurrency,
        defaultPayer: defaultPayer,
      );
      final ref = paired
          ? ParsedExpenseDraft.fromMap(
              local[i],
              defaultCurrency: tripCurrency,
              defaultPayer: defaultPayer,
            )
          : null;
      final segment = paired ? segments[i] : userInput;

      // ---- category ----------------------------------------------------------
      var category = live.category;
      if (category == ExpenseCategory.MISC) {
        // Rescue: a model that says MISC for a known venue / brand is wrong.
        final rescued =
            TravelGazetteer.classify('${live.title} $segment') ??
            (ref != null && ref.category != ExpenseCategory.MISC
                ? ref.category
                : null);
        if (rescued != null) category = rescued;
      }

      // ---- title -------------------------------------------------------------
      final title = _cleanTitle(
        live.title,
        memberNames: memberNames,
        fallback: ref?.title,
        category: category,
      );

      // ---- unit amount + pricing modifiers ------------------------------------
      var unit = live.unitAmount;
      var mode = live.amountMode;
      var quantity = live.quantity;
      var percent = live.extraPercent;
      if (ref != null) {
        // The text decides the modifiers; the model only reads intent.
        mode = ref.amountMode;
        quantity = ref.quantity;
        percent = ref.extraPercent;
        if (ref.unitAmount > 0) {
          if (unit <= 0 || ref.hasModifiers) {
            // The model may have multiplied it itself ("1500" for "500 each").
            unit = ref.unitAmount;
          } else if (unit < ref.unitAmount) {
            // "8 thousand" answered as 8: the model dropped the multiplier.
            final ratio = ref.unitAmount / unit;
            const scales = [100.0, 1000.0, 1000000.0];
            if (scales.any((s) => (ratio - s).abs() < 0.5)) {
              unit = ref.unitAmount;
            }
          }
        }
      } else {
        // Unpaired: keep the model's reading, but never invent a percentage.
        if (!RegExp(
          r'%|per\s?cent|percent|\bpct\b',
          caseSensitive: false,
        ).hasMatch(segment)) {
          percent = 0;
        }
        if (mode == AmountMode.perPerson &&
            !LocalExpenseParser.hasPerPersonCue(segment)) {
          mode = AmountMode.total;
        }
      }

      // ---- payer ---------------------------------------------------------------
      final payerRaw = live.payer.trim();
      final payer =
          (payerRaw.isEmpty || !lowerNames.containsKey(payerRaw.toLowerCase()))
          ? (ref?.payer ?? defaultPayer)
          : lowerNames[payerRaw.toLowerCase()]!;

      // ---- currency ------------------------------------------------------------
      final currency = live.currency.isEmpty
          ? (ref?.currency ?? tripCurrency)
          : live.currency;

      // ---- split ---------------------------------------------------------------
      final named = <String>[
        for (final n in memberNames)
          if (RegExp(
            '\\b${RegExp.escape(n)}\\b',
            caseSensitive: false,
          ).hasMatch(segment))
            n,
      ];
      final solo = RegExp(
        r'\b(solo|just me|only me|for myself|by myself)\b',
        caseSensitive: false,
      ).hasMatch(segment);
      final explicit = named.isNotEmpty || solo;
      List<String> split;
      if (explicit && ref != null) {
        split = List<String>.from(ref.splitWith);
      } else {
        final liveSplit = live.splitWith
            .map((e) => lowerNames[e.toLowerCase()])
            .whereType<String>()
            .toSet()
            .toList();
        split = liveSplit.isEmpty ? List<String>.from(memberNames) : liveSplit;
      }

      // Itemized bills come from the text: every named price, by person.
      Map<String, double>? custom = live.customSplits;
      if (ref != null && ref.isItemized) {
        custom = ref.customSplits;
        unit = ref.unitAmount;
      } else if (ref != null && !ref.isItemized) {
        custom = null; // never invent exact shares the text does not give
      }

      final draft = ParsedExpenseDraft(
        title: title,
        unitAmount: unit,
        amountMode: mode,
        quantity: quantity,
        extraPercent: percent,
        currency: currency.toUpperCase(),
        category: category,
        payer: payer,
        splitWith: custom != null && custom.length >= 2
            ? custom.keys.toList()
            : split,
        customSplits: (custom != null && custom.length >= 2) ? custom : null,
      );
      result.add(draft.toMap(split.length));
    }
    return result;
  }

  /// Strips verbs and member names; falls back to the offline title (or the
  /// category name) when nothing sensible is left.
  static String _cleanTitle(
    String raw, {
    required List<String> memberNames,
    required String? fallback,
    required ExpenseCategory category,
  }) {
    final names = {for (final n in memberNames) n.trim().toLowerCase()};
    var t = LocalExpenseParser.stripLeadingVerb(raw, memberNames);
    t = t
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && !names.contains(w.toLowerCase()))
        .join(' ')
        .trim();
    // A dangling connector ("Ramen with") left behind by removing a name.
    t = t.replaceFirst(
      RegExp(r'\s+(with|for|and|&|by|to)$', caseSensitive: false),
      '',
    );
    if (t.length < 2) {
      final f = fallback?.trim() ?? '';
      if (f.length >= 2 && !names.contains(f.toLowerCase())) return f;
      return category.displayName;
    }
    return '${t[0].toUpperCase()}${t.substring(1)}';
  }
}
