import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/core/enums/expense_category.dart';
import 'package:travmate/core/theme/app_theme.dart';
import 'package:travmate/features/expenses/expense_editor_sheet.dart';
import 'package:travmate/features/trip/trip_controller.dart';
import 'package:travmate/models/expense_item.dart';
import 'package:travmate/services/hybrid_ai/expense_normalizer.dart';
import 'package:travmate/services/hybrid_ai/hybrid_ai_service.dart';
import 'package:travmate/services/hybrid_ai/local_expense_parser.dart';

import 'test_helpers.dart';

const _members = ['You', 'Alex', 'Maya', 'Liam'];
const _sentence = 'Eat Ramen with Maya and Liam for 8 thousand yen';

Map<String, dynamic> _local(String text) => LocalExpenseParser.parseExpenses(
  text,
  tripCurrency: 'JPY',
  memberNames: _members,
  defaultPayer: 'You',
).single;

/// Pretends to be a real model so the editor's category assist can be checked.
class _FakeCategoryAi extends HybridAiService {
  final ExpenseCategory answer;
  final List<String> asked = [];
  _FakeCategoryAi(this.answer)
    : super(isMockEnabled: true, simulateLatency: false);

  @override
  Future<ExpenseCategory> suggestCategory(String title) async {
    asked.add(title);
    return answer;
  }
}

void main() {
  group('Natural sentences (offline parser)', () {
    test('"Eat Ramen with Maya and Liam for 8 thousand yen"', () {
      final item = _local(_sentence);
      expect(item['title'], 'Ramen');
      expect(item['amount'], 8000.0);
      expect(item['currency'], 'JPY');
      expect(item['category'], 'MEAL');
      expect(item['splitWith'], ['You', 'Maya', 'Liam']);
    });

    test('The name list is never split into a second expense', () {
      expect(
        LocalExpenseParser.parseExpenses(
          _sentence,
          tripCurrency: 'JPY',
          memberNames: _members,
          defaultPayer: 'You',
        ),
        hasLength(1),
      );
    });

    test('A member name is never the title', () {
      for (final text in [
        'Eat Ramen with Maya, Liam for 8 thousand yen',
        'Maya paid for sushi 4800',
        'Ramen with Liam 1500',
        'Dinner with Alex and Maya 9000 yen',
      ]) {
        final title = _local(text)['title'] as String;
        for (final name in _members) {
          expect(title.toLowerCase(), isNot(name.toLowerCase()), reason: text);
        }
      }
      expect(_local('Maya paid for sushi 4800')['title'], 'Sushi');
    });

    test('Leading verbs are dropped; "for Alex" stays a treat', () {
      expect(_local('Had a coffee 650 yen')['title'], 'Coffee');
      expect(_local('Bought souvenirs 3200')['title'], 'Souvenirs');
      final treat = _local('Sushi 4800 for Alex and Maya');
      expect(treat['splitWith'], ['Alex', 'Maya']);
    });
  });

  group('ExpenseNormalizer repairs real model answers', () {
    List<Map<String, dynamic>> fix(List<Map<String, dynamic>> live) =>
        ExpenseNormalizer.normalize(
          live,
          userInput: _sentence,
          tripCurrency: 'JPY',
          memberNames: _members,
          defaultPayer: 'You',
        );

    test('a member name as title becomes the item', () {
      final r = fix([
        {
          'title': 'Liam',
          'amount': 8000,
          'currency': 'JPY',
          'category': 'MEAL',
          'payer': 'You',
          'splitWith': ['Maya', 'Liam'],
        },
      ]).single;
      expect(r['title'], 'Ramen');
      expect(r['splitWith'], ['You', 'Maya', 'Liam']);
    });

    test('verbs are stripped and the multiplier is restored', () {
      final r = fix([
        {
          'title': 'Eat Ramen',
          'amount': 8,
          'currency': '',
          'category': 'MISC',
          'payer': 'You',
          'splitWith': [],
        },
      ]).single;
      expect(r['title'], 'Ramen');
      expect(r['amount'], 8000.0);
      expect(r['currency'], 'JPY');
      expect(r['category'], 'MEAL');
      expect(r['splitWith'], ['You', 'Maya', 'Liam']);
    });

    test('a correct answer passes through unchanged', () {
      final good = {
        'title': 'Ramen',
        'amount': 8000.0,
        'currency': 'JPY',
        'category': 'MEAL',
        'payer': 'You',
        'splitWith': ['You', 'Maya', 'Liam'],
      };
      final out = fix([good]).single;
      for (final e in good.entries) {
        expect(out[e.key], e.value, reason: e.key);
      }
      // The schema fields are filled in with their defaults.
      expect(out['unitAmount'], 8000.0);
      expect(out['amountMode'], 'TOTAL');
      expect(out['quantity'], 1);
      expect(out['extraPercent'], 0.0);
    });

    test('without named members the model\'s split is respected', () {
      final r = ExpenseNormalizer.normalize(
        [
          {
            'title': 'Taxi',
            'amount': 2000,
            'currency': 'JPY',
            'category': 'TRANSPORT',
            'payer': 'You',
            'splitWith': ['You', 'Alex'],
          },
        ],
        userInput: 'Taxi 2000',
        tripCurrency: 'JPY',
        memberNames: _members,
        defaultPayer: 'You',
      );
      expect(r.single['splitWith'], ['You', 'Alex']);
    });

    test('unknown payers fall back and empty lists pass through', () {
      expect(
        ExpenseNormalizer.normalize(
          [],
          userInput: 'x',
          tripCurrency: 'JPY',
          memberNames: _members,
          defaultPayer: 'You',
        ),
        isEmpty,
      );
      final r = fix([
        {'title': 'Ramen', 'amount': 8000, 'payer': 'Nobody'},
      ]).single;
      expect(r['payer'], 'You');
    });
  });

  group('Cloud model + thinking are aligned on every platform', () {
    String read(String path) => File(path).readAsStringSync();

    test('no retired gemini-2.5-flash anywhere in the runtime code', () {
      for (final dir in ['lib', 'web', 'android/app/src', 'ios/Runner']) {
        for (final f in Directory(dir).listSync(recursive: true)) {
          if (f is! File) continue;
          if (!RegExp(r'\.(dart|js|kt|swift|html)$').hasMatch(f.path)) continue;
          expect(
            f.readAsStringSync(),
            isNot(contains('gemini-2.5-flash')),
            reason: f.path,
          );
        }
      }
    });

    test('Android: gemini-3.1-flash-lite with thinking disabled', () {
      final kt = read(
        'android/app/src/main/kotlin/com/hybridtrip/ai/travmate/HybridAiPlugin.kt',
      );
      expect(kt, contains('CLOUD_FALLBACK_MODEL = "gemini-3.1-flash-lite"'));
      expect(kt, contains('thinkingBudget = 0'));
      // Fallback chain: fast model, slow model, short attempts, thinking-reject retry.
      expect(kt, contains('SLOW_CLOUD_MODEL = "gemini-3.8-flash"'));
      expect(kt, contains('CLOUD_ATTEMPT_TIMEOUT_MS = 12_000L'));
      expect(kt, contains('withTimeout'));
      expect(kt, contains('rejectsThinkingConfig'));
    });

    test('iOS: gemini-3.1-flash-lite, thinking off, model chain, no removed SDK API', () {
      final swift = read('ios/Runner/HybridAiPlugin.swift');
      // Comments may name the removed types; code must not use them.
      final code = swift
          .split('\n')
          .where(
            (l) =>
                !l.trimLeft().startsWith('//') &&
                !l.trimLeft().startsWith('*') &&
                !l.trimLeft().startsWith('/*'),
          )
          .join('\n');
      expect(swift, contains('fastCloudModel = "gemini-3.1-flash-lite"'));
      expect(swift, contains('slowCloudModel = "gemini-3.8-flash"'));
      expect(swift, contains('ThinkingConfig(thinkingBudget: 0)'));
      // On-device = Apple Foundation Models; cloud = the stable GenerativeModel API.
      expect(swift, contains('LanguageModelSession'));
      expect(swift, contains('SystemLanguageModel.default'));
      expect(swift, contains('generativeModel('));
      // firebase-ios-sdk 13 removed these interim types; they must not come back.
      for (final removed in [
        'HybridModel',
        'GenerativeModelSession',
        'FirebaseAI.SystemLanguageModel',
        'geminiModel(',
      ]) {
        expect(code, isNot(contains(removed)), reason: removed);
      }
    });

    test('iOS project compiles the plugin and links FirebaseAILogic', () {
      final pbx = read('ios/Runner.xcodeproj/project.pbxproj');
      // Without this entry the Runner target never compiled HybridAiPlugin.swift.
      expect(pbx, contains('HybridAiPlugin.swift in Sources'));
      expect(pbx, contains('productName = FirebaseAILogic'));
      expect(pbx, contains('https://github.com/firebase/firebase-ios-sdk'));
      final delegate = read('ios/Runner/AppDelegate.swift');
      expect(delegate, contains('HybridAiPlugin.register'));
      // registrar(forPlugin:) is optional in the current SDK.
      expect(
        delegate,
        contains('registry.registrar(forPlugin: "HybridAiPlugin")'),
      );
      // Registering the same key twice aborts the app at launch
      // ("Duplicate plugin key: HybridAiPlugin").
      expect(
        RegExp('registrar\\(forPlugin: "HybridAiPlugin"\\)')
            .allMatches(delegate)
            .length,
        1,
      );
      expect(delegate, contains('hybridAiRegistered'));
    });

    test('Web: fast default, thinking disabled, fallback chain, short attempts', () {
      final js = read('web/firebase_ai_web.js');
      expect(js, contains('FAST_CLOUD_MODEL = "gemini-3.1-flash-lite"'));
      expect(js, contains('SLOW_CLOUD_MODEL = "gemini-3.8-flash"'));
      expect(js, contains('thinkingBudget: 0'));
      // One 8 s attempt per model (not one 20 s hang), then the next model.
      expect(js, contains('CLOUD_ATTEMPT_TIMEOUT_MS = 12000'));
      expect(js, contains('trying next model'));
      // Models that reject thinkingConfig (generic 400) are retried without it.
      expect(js, contains('modelsRejectingThinking'));
      expect(js, contains('invalid argument'));
    });

    test('Dart policy default and Remote Config default agree', () {
      expect(
        HybridAiService(
          isMockEnabled: true,
          simulateLatency: false,
        ).policy.cloudModel,
        'gemini-3.1-flash-lite',
      );
    });
  });

  group('HybridAiService.suggestCategory', () {
    final service = HybridAiService(
      isMockEnabled: true,
      simulateLatency: false,
    );

    test('offline keyword fallback', () async {
      expect(
        await service.suggestCategory('Ramen at Ichiran'),
        ExpenseCategory.MEAL,
      );
      expect(
        await service.suggestCategory('Shinkansen ticket'),
        ExpenseCategory.TRANSPORT,
      );
      expect(await service.suggestCategory('   '), ExpenseCategory.MISC);
    });
  });

  group('Manual Expense asks HybridAiService after the 2.5 s pause', () {
    testWidgets('the model\'s answer becomes "Pocko suggested …"', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(420, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fake = _FakeCategoryAi(ExpenseCategory.TRANSPORT);
      final container = ProviderContainer(
        overrides: [hybridAiServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => Center(
                  child: ElevatedButton(
                    onPressed: () => showExpenseEditor(
                      context,
                      isNew: true,
                      tripState: ref.read(tripControllerProvider),
                      expense: ExpenseItem(
                        id: 'd',
                        title: '',
                        amount: 0,
                        currency: 'JPY',
                        payerId: 'you',
                        splitWithMemberIds: const ['you'],
                        createdAt: DateTime.now(),
                      ),
                    ),
                    child: const Text('Open editor'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open editor'));
      await settle(tester, 700);

      await tester.enterText(
        find.byType(TextField).first,
        'Night bus to Osaka',
      );
      await tester.pump(const Duration(milliseconds: 2000));
      expect(fake.asked, isEmpty, reason: 'not before the 2.5 s pause');
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
      expect(fake.asked, ['Night bus to Osaka']);
      expect(find.text('Pocko suggested Transport'), findsOneWidget);
    });
  });
}
