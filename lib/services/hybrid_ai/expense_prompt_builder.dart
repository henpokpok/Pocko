import 'dart:convert';

import '../../core/enums/expense_category.dart';
import 'spoken_numbers.dart';

class ExpensePromptBuilder {
  /// Builds a compact, single-turn instruction prompt tailored for on-device inference
  /// (Gemini Nano / Apple FM) and cloud fallback to parse single or multiple travel expense
  /// descriptions into strict JSON.
  ///
  /// When [templateOverride] (Firebase Remote Config `prompt_template_override`)
  /// is non-empty it replaces the default template. Supported placeholders:
  /// `{{userInput}}`, `{{tripCurrency}}`, `{{members}}`, `{{defaultPayer}}`,
  /// `{{categories}}`.
  static String buildPrompt({
    required String userInput,
    String tripCurrency = 'JPY',
    List<String> memberNames = const ['You', 'Alex', 'Maya', 'Liam'],
    String defaultPayer = 'You',
    String templateOverride = '',
    bool fromSpeech = false,
  }) {
    final categoriesStr = ExpenseCategory.values.map((c) => c.name).join(', ');
    final membersStr = memberNames.join(', ');
    // Before any model sees it: a spaced "2 200" is 2200, the words after
    // "oh wait, no" replace the corrected-away number, and spoken / typo'd
    // multipliers become plain digits.
    final normalizedInput = SpokenNumbers.normalize(
      SpokenCorrections.resolve(
        SpokenNumbers.collapseSpacedThousands(userInput),
      ),
    );

    if (templateOverride.trim().isNotEmpty) {
      return templateOverride
          .replaceAll('{{userInput}}', normalizedInput)
          .replaceAll('{{tripCurrency}}', tripCurrency)
          .replaceAll('{{members}}', membersStr)
          .replaceAll('{{defaultPayer}}', defaultPayer)
          .replaceAll('{{categories}}', categoriesStr);
    }

    return '''Parse travel expenses into strict JSON. You extract intent; the app does the math.

Currency: $tripCurrency
Members: [$membersStr]
Default Payer: $defaultPayer

$categoryGuide

Rules:
1. One "items" object per expense ("Matcha 600 for me, and gyoza 1200 with Alex" = 2 items).
2. "title": the thing bought ("Ramen", "Taxi"): short, no verb, never a person's name.
3. "unitAmount": the number as stated, NEVER multiplied by you. Expand spoken multipliers and typos: hundred x100; thousand, thousan, k x1000; million, m x1000000 ("2.5k"=2500, "five hundred"=500, "8 thousand"=8000).
4. "amountMode": "PER_PERSON" for each / per person / apiece / per head, else "TOTAL".
5. "quantity": item count in "N things at price" ("4 coffees at 5 dollars a cup": unitAmount 5, quantity 4). Default 1.
6. "extraPercent": tip, tax or service percent: "plus 10 percent", "10% tip" = 10. unitAmount stays the base price ("5,000 yen plus 10 percent": unitAmount 5000, extraPercent 10; the app adds it up to 5500). Default 0.
7. "currency": ISO code (bucks, dollars = USD; yen = JPY; baht = THB; won = KRW; euros = EUR; pounds, quid = GBP). Default $tripCurrency.
8. "payer": who paid ("Maya paid", "Alex covered", "paid by Liam"); else $defaultPayer.
9. "splitWith": EVERY member named. "with Maya and Liam" = payer + Maya + Liam; "for Maya" or "bought Maya a ticket" = Maya only; "for me" or "solo" = payer only; "everyone", "all", "the group" or nobody named = all members.
10. Corrections: if the speaker corrects themselves ("4200, oh wait no, 4800", "I mean", "actually"), use only the last value and ignore the corrected-away number. Spaced or comma thousands are one number: "2 200 yen" = "2,200" = 2200.
11. "customSplits": only for ONE shared bill where each person names their own price ("Sushiro, I paid: mine 1200, Maya salmon 1800, Liam udon 950"): {"You":1200,"Maya":1800,"Liam":950}, unitAmount = their sum, splitWith = those people, title = the venue. Otherwise omit it.

${fromSpeech ? speechHints : ''}Examples:
"Ramen with Maya and Liam 500 yen each" -> {"items":[{"title":"Ramen","unitAmount":500,"amountMode":"PER_PERSON","quantity":1,"extraPercent":0,"currency":"JPY","category":"MEAL","payer":"$defaultPayer","splitWith":["$defaultPayer","Maya","Liam"]}]}
"Maya paid 6k yen for taxi" -> {"items":[{"title":"Taxi","unitAmount":6000,"amountMode":"TOTAL","quantity":1,"extraPercent":0,"currency":"JPY","category":"TRANSPORT","payer":"Maya","splitWith":[all members]}]}

User Input: "$normalizedInput"

Respond ONLY with JSON, no markdown:
{"items": [{"title": "short description", "unitAmount": 0.0, "amountMode": "TOTAL", "quantity": 1, "extraPercent": 0, "currency": "$tripCurrency", "category": "CATEGORY", "payer": "Name", "splitWith": ["Name1", "Name2"], "customSplits": null}]}''';
  }

  /// Speech-to-text often mishears travel and food words; passed to the model
  /// when the sentence came from dictation.
  static const String speechHints = '''Speech-to-text may have misheard food and places: "Michelle"/"Michelle latte" = Matcha (latte), "Ramming" = Ramen, "she in kansen" = Shinkansen, "you cut sue" = Gyukatsu, "yaki tori" = Yakitori. Correct such words.
''';

  /// Prompt for a **recorded voice clip** sent to Gemini as inline audio. The
  /// model first writes the exact words spoken (English, verbatim, no cleanup)
  /// and then extracts the same `items` as the text prompt, in one call.
  static String buildAudioPrompt({
    String tripCurrency = 'JPY',
    List<String> memberNames = const ['You', 'Alex', 'Maya', 'Liam'],
    String defaultPayer = 'You',
  }) {
    final base = buildPrompt(
      userInput: '(see audio)',
      tripCurrency: tripCurrency,
      memberNames: memberNames,
      defaultPayer: defaultPayer,
    );
    return base
        .replaceFirst(
          'User Input: "(see audio)"',
          'Input: the attached audio clip, a traveler speaking English about '
              'what they spent. First write "transcript": the exact words '
              'spoken, verbatim (keep numbers, names and slang as said, no '
              'cleanup, no translation). Spell travel and food words correctly '
              '(Matcha, Ramen, Shinkansen, Gyukatsu, Yakitori, Okonomiyaki). '
              'Then parse that transcript into items. Member names above are '
              'the only people mentioned.',
        )
        .replaceFirst(
          '{"items": [{"title"',
          '{"transcript": "exact words spoken", "items": [{"title"',
        );
  }

  /// Tiny transcription-only prompt (fast, a few output tokens). It runs next
  /// to [buildAudioPrompt] so the capture sheet can show the words while the
  /// full analysis is still in flight.
  static String buildTranscribePrompt({
    List<String> memberNames = const ['You', 'Alex', 'Maya', 'Liam'],
  }) {
    return 'Transcribe the attached audio clip verbatim: a traveler speaking '
        'English about what they spent. Keep numbers, names and slang as '
        'said; no cleanup, no translation. Names that may appear: '
        '${memberNames.join(', ')}.\n'
        'Respond ONLY with JSON, no markdown: {"transcript": "exact words spoken"}';
  }

  /// Ultra-compact semantic anchors: proper-noun venues and brands per
  /// category, suffix cues, and the venue-vs-item priority rule, so a small
  /// on-device model never files "Disneyland" or "Teamlab" under MISC.
  static const String categoryGuide =
      '''Categories (never MISC for a known venue or brand):
ATTRACTION: theme parks (Disneyland, DisneySea, Universal Studios/USJ, Legoland, Cosmo Land, Lotte World, Everland), teamLab, museums, galleries, National Center, Art Center, Science Center, palaces, temples, shrines, Shibuya Sky, Skytree, towers, aquariums, zoos; names ending -land, -world, Studio(s), Museum, Gallery, Aquarium, Observatory, Park.
TRANSPORT: Suica, Pasmo, ICOCA, T-money, Octopus, EZ-Link, Shinkansen, JR, Narita Express, MRT, BTS, Uber, Grab, taxi, flights.
MEAL: restaurants and food (Ichiran, sushi, ramen). SNACK_CAFE: Starbucks, 7-Eleven, Lawson, FamilyMart, coffee, drinks, desserts.
SOUVENIR: shopping and gifts (Don Quijote/Donki, Olive Young, Pop Mart, Daiso, Duty Free). APPAREL: Uniqlo, GU, clothes.
LODGING: APA, Toyoko Inn, Airbnb, Agoda, Booking.com, hostel, ryokan.
Also MEDICAL, CONNECTIVITY, INSURANCE, SERVICE; MISC only if nothing fits.
Venue rule: a bare venue or ticket ("Disneyland 9400") is ATTRACTION; with a merchandise or food noun the item wins ("Disneyland headband" = SOUVENIR, "Universal popcorn" = MEAL, "Museum gift shop" = SOUVENIR).''';

  /// Tiny single-purpose prompt for the Manual Expense auto-category assist.
  static String buildCategoryPrompt(String title) {
    return '''Classify one travel expense title into exactly one category.
$categoryGuide
Title: "${title.replaceAll('"', "'")}"
Respond ONLY with JSON: {"category": "CATEGORY"}''';
  }

  /// Prompt used by the Smart Slip Matcher. The text it receives has already
  /// been PII-masked on-device, so bank account numbers never reach the model.
  static String buildReceiptPrompt({
    required String maskedText,
    String tripCurrency = 'JPY',
  }) {
    final categoriesStr = ExpenseCategory.values.map((c) => c.name).join(', ');
    return '''You are a privacy-first receipt and bank-notification parser. Account numbers are already masked; never ask for them.

Trip Currency: $tripCurrency
Allowed Categories: [$categoriesStr]

Rules:
1. "total": the final amount charged, numerical value only.
2. "currency": ISO code of the amount actually charged (e.g. EUR, USD, JPY).
3. "lineItems": every itemized line as {"name", "amount"}; empty array for bank notifications.
4. "merchant": the shop or service name.
5. "category": the single best Allowed Category.

Receipt text:
"""
$maskedText
"""

Respond ONLY with valid JSON (no markdown fences, no preamble):
{"merchant": "Name", "total": 0.0, "currency": "ISO", "category": "CATEGORY", "lineItems": [{"name": "item", "amount": 0.0}]}''';
  }

  /// Cleans raw model output by removing markdown code fences or surrounding whitespace
  static String cleanJsonOutput(String rawOutput) {
    var trimmed = rawOutput.trim();
    if (trimmed.startsWith('```json')) {
      trimmed = trimmed.substring(7);
    } else if (trimmed.startsWith('```')) {
      trimmed = trimmed.substring(3);
    }
    if (trimmed.endsWith('```')) {
      trimmed = trimmed.substring(0, trimmed.length - 3);
    }
    return trimmed.trim();
  }

  /// Safely parses the model output into a `Map<String, dynamic>` supporting both
  /// multi-item schema ({"items": [...]}) and legacy single-object schema ({"title": ...}).
  static Map<String, dynamic>? parseJson(String rawOutput) {
    Map<String, dynamic>? result;
    try {
      final cleaned = cleanJsonOutput(rawOutput);
      final decoded = jsonDecode(cleaned);
      if (decoded is Map<String, dynamic>) {
        result = decoded;
      } else if (decoded is List) {
        result = {'items': decoded};
      }
    } catch (_) {
      // Fallback: search for outermost JSON object or array
      try {
        final startObj = rawOutput.indexOf('{');
        final endObj = rawOutput.lastIndexOf('}');
        if (startObj != -1 && endObj != -1 && endObj > startObj) {
          final substring = rawOutput.substring(startObj, endObj + 1);
          final decoded = jsonDecode(substring);
          if (decoded is Map<String, dynamic>) {
            result = decoded;
          }
        }
      } catch (_) {}

      if (result == null) {
        try {
          final startArr = rawOutput.indexOf('[');
          final endArr = rawOutput.lastIndexOf(']');
          if (startArr != -1 && endArr != -1 && endArr > startArr) {
            final substring = rawOutput.substring(startArr, endArr + 1);
            final decoded = jsonDecode(substring);
            if (decoded is List) {
              result = {'items': decoded};
            }
          }
        } catch (_) {}
      }
    }

    if (result != null) {
      // Ensure backwards compatibility: if items exists and is non-empty, mirror first item keys at root
      if (result.containsKey('items') &&
          result['items'] is List &&
          (result['items'] as List).isNotEmpty) {
        final first = (result['items'] as List).first;
        if (first is Map<String, dynamic>) {
          for (final entry in first.entries) {
            if (!result.containsKey(entry.key)) {
              result[entry.key] = entry.value;
            }
          }
        }
      } else if (!result.containsKey('items') &&
          (result.containsKey('amount') || result.containsKey('title'))) {
        result['items'] = [Map<String, dynamic>.from(result)];
      }
    }

    return result;
  }
}
