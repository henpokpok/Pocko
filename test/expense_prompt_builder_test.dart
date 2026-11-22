import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/services/hybrid_ai/expense_prompt_builder.dart';

void main() {
  group('ExpensePromptBuilder Tests', () {
    test('Builds a compact prompt (category anchors + rules, < 560 words)', () {
      final prompt = ExpensePromptBuilder.buildPrompt(
        userInput: 'Grilled pork 1500 Boss paid, split May and Kong',
        tripCurrency: 'THB',
        memberNames: ['Boss', 'May', 'Kong'],
        defaultPayer: 'Boss',
      );

      final wordCount = prompt.split(RegExp(r'\s+')).length;
      // ~500 words is ~800 tokens: comfortably inside Gemini Nano's window.
      expect(wordCount, lessThan(560));
      expect(prompt.contains('MEAL'), isTrue);
      expect(prompt.contains('Boss, May, Kong'), isTrue);
      expect(
        prompt.contains('Grilled pork 1500 Boss paid, split May and Kong'),
        isTrue,
      );
    });

    test(
      'Remote Config prompt_template_override replaces the default template',
      () {
        final prompt = ExpensePromptBuilder.buildPrompt(
          userInput: 'coffee 450',
          memberNames: ['You', 'Alex'],
          templateOverride: 'Parse {{userInput}} in {{tripCurrency}} for [{{members}}] paid by {{defaultPayer}}',
        );
        expect(prompt, 'Parse coffee 450 in JPY for [You, Alex] paid by You');
      },
    );

    test('Default prompt is 100% English and mentions the 12 categories', () {
      final prompt = ExpensePromptBuilder.buildPrompt(userInput: 'ramen 4800');
      expect(prompt.runes.any((r) => r >= 0x0E00 && r <= 0x0E7F), isFalse);
      expect(prompt, contains('SNACK_CAFE'));
      expect(prompt, contains('INSURANCE'));
    });

    test('Receipt prompt keeps account masking and requests itemized JSON', () {
      final prompt = ExpensePromptBuilder.buildReceiptPrompt(
        maskedText: 'Cafe •••• 4455 total 12.50',
      );
      expect(prompt, contains('lineItems'));
      expect(prompt, contains('•••• 4455'));
    });

    test('cleanJsonOutput removes markdown fences', () {
      const fenced = '```json\n{"title": "test", "amount": 100}\n```';
      final cleaned = ExpensePromptBuilder.cleanJsonOutput(fenced);
      expect(cleaned, '{"title": "test", "amount": 100}');

      final parsed = ExpensePromptBuilder.parseJson(fenced);
      expect(parsed, isNotNull);
      expect(parsed!['amount'], 100);
    });

    test('parseJson extracts embedded JSON from conversational text', () {
      const conversational =
          'Here is the parsed expense: {"title": "Grilled pork", "amount": 1500.0} Hope that helps!';
      final parsed = ExpensePromptBuilder.parseJson(conversational);
      expect(parsed, isNotNull);
      expect(parsed!['title'], 'Grilled pork');
      expect(parsed['amount'], 1500.0);
    });

    test('parseJson handles multi-item array payload seamlessly', () {
      const multiJson =
          '{"items": [{"title": "Ramen", "amount": 4800.0}, {"title": "Train", "amount": 18200.0}]}';
      final parsed = ExpensePromptBuilder.parseJson(multiJson);
      expect(parsed, isNotNull);
      expect(parsed!['items'], isA<List>());
      expect((parsed['items'] as List).length, 2);
      expect(
        parsed['title'],
        'Ramen',
      ); // Backwards-compatible first item mirror
      expect(parsed['amount'], 4800.0);
    });
  });
}
