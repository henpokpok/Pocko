import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/core/theme/app_theme.dart';
import 'package:travmate/core/utils/currency_helper.dart';
import 'package:travmate/features/expenses/expense_editor_sheet.dart';
import 'package:travmate/features/onboarding/onboarding_screen.dart';
import 'package:travmate/features/onboarding/trip_destinations.dart';
import 'package:travmate/features/settle/visual_settle_screen.dart';
import 'package:travmate/features/shell/pocko_main_shell.dart';
import 'package:travmate/features/trip/trip_controller.dart';
import 'package:travmate/models/expense_item.dart';
import 'package:travmate/models/raw_prompt_note.dart';
import 'package:travmate/services/media/receipt_photo_service.dart';

import 'test_helpers.dart';

const _tinyPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

Finder _k(String key) => find.byKey(ValueKey(key));

ExpenseItem _expense({
  Map<String, double>? custom,
  String? receipt,
  double amount = 3000,
}) => ExpenseItem(
  id: 'e1',
  title: 'Sushiro Dinner',
  amount: amount,
  currency: 'JPY',
  payerId: 'you',
  splitWithMemberIds: const ['you', 'maya', 'liam'],
  customSplits: custom,
  receiptImageBase64: receipt,
  createdAt: DateTime(2026, 11, 16, 20, 30),
);

Future<void> _show(
  WidgetTester tester,
  ExpenseItem expense,
  List<ExpenseItem?> results,
) async {
  await pumpPocko(
    tester,
    Consumer(
      builder: (context, ref, _) => Center(
        child: ElevatedButton(
          onPressed: () async {
            final r = await showExpenseEditor(
              context,
              expense: expense,
              tripState: ref.read(tripControllerProvider),
            );
            results.add(r);
          },
          child: const Text('Open editor'),
        ),
      ),
    ),
    size: const Size(420, 1800),
  );
  await tester.tap(find.text('Open editor'));
  await settle(tester, 700);
}

Future<void> _save(WidgetTester tester) async {
  final save = find.text('Save Changes');
  await tester.ensureVisible(save);
  await tester.tap(save);
  await settle(tester, 500);
}

void main() {
  group('Expense sheet redesign', () {
    testWidgets('the currency is a pill inside the Amount field', (
      tester,
    ) async {
      await _show(tester, _expense(), []);
      expect(
        find.descendant(
          of: _k('editor_amount'),
          matching: _k('editor_currency'),
        ),
        findsOneWidget,
      );
      expect(find.text('JPY'), findsWidgets);
      // The old "Amount (JPY)" label and the separate currency column are gone.
      expect(find.widgetWithText(TextField, 'Amount'), findsOneWidget);
    });

    testWidgets('date and time are Pocko pills that open themed pickers', (
      tester,
    ) async {
      await _show(tester, _expense(), []);
      expect(find.text('Mon, Nov 16, 2026'), findsOneWidget);
      expect(find.text('20:30'), findsOneWidget);

      await tester.tap(_k('editor_date'));
      await settle(tester, 600);
      final dialog = find.byType(DatePickerDialog);
      expect(dialog, findsOneWidget);
      expect(
        Theme.of(tester.element(dialog)).colorScheme.primary,
        AppTheme.primaryEmerald,
      );
      await tester.tap(find.text('Cancel'));
      await settle(tester, 400);

      await tester.tap(_k('editor_time'));
      await settle(tester, 600);
      expect(find.byType(TimePickerDialog), findsOneWidget);
    });

    testWidgets('category is a searchable dropdown and Paid By a selector', (
      tester,
    ) async {
      final results = <ExpenseItem?>[];
      await _show(tester, _expense(), results);
      expect(find.byType(ChoiceChip), findsNothing);

      await tester.ensureVisible(_k('editor_category'));
      await tester.tap(_k('editor_category'));
      await settle(tester, 400);
      expect(_k('selector_search'), findsOneWidget);
      await tester.enterText(_k('selector_search'), 'Souv');
      await tester.pump();
      await tester.tap(_k('selector_row_Souvenirs'));
      await settle(tester, 400);

      await tester.ensureVisible(_k('editor_payer'));
      await tester.tap(_k('editor_payer'));
      await settle(tester, 400);
      await tester.tap(_k('selector_row_Maya'));
      await settle(tester, 400);

      await _save(tester);
      expect(results.single!.category.displayName, 'Souvenirs');
      expect(results.single!.payerId, 'maya');
    });

    testWidgets('Equal Split is the default and shows the per-person share', (
      tester,
    ) async {
      await _show(tester, _expense(), []);
      expect(_k('custom_split_rows'), findsNothing);
      expect(find.textContaining('¥1,000 each'), findsOneWidget);
      expect(tester.widget<TextField>(_k('editor_amount')).readOnly, isFalse);
    });

    testWidgets(
      'Custom Amounts pre-fills the equal share and the total is their sum',
      (tester) async {
        final results = <ExpenseItem?>[];
        await _show(tester, _expense(), results);

        await tester.ensureVisible(_k('split_mode_custom'));
        await tester.tap(_k('split_mode_custom'));
        await settle(tester, 400);

        String valueOf(String id) =>
            tester.widget<TextField>(_k('custom_amount_$id')).controller!.text;
        expect(
          [valueOf('you'), valueOf('maya'), valueOf('liam')],
          ['1000', '1000', '1000'],
        );
        expect(tester.widget<TextField>(_k('editor_amount')).readOnly, isTrue);

        await tester.enterText(_k('custom_amount_you'), '1200');
        await tester.enterText(_k('custom_amount_maya'), '1800');
        await tester.enterText(_k('custom_amount_liam'), '950');
        await settle(tester, 300);
        expect(
          tester.widget<TextField>(_k('editor_amount')).controller!.text,
          anyOf('3000', '3950'),
        );
        expect(find.textContaining('Total ¥3,950'), findsOneWidget);

        await _save(tester);
        final saved = results.single!;
        expect(saved.amount, 3950);
        expect(saved.customSplits, {
          'you': 1200.0,
          'maya': 1800.0,
          'liam': 950.0,
        });
        expect(saved.isItemized, isTrue);
      },
    );

    testWidgets('an itemized expense opens in Custom Amounts mode', (
      tester,
    ) async {
      await _show(
        tester,
        _expense(
          amount: 3950,
          custom: {'you': 1200, 'maya': 1800, 'liam': 950},
        ),
        [],
      );
      expect(_k('custom_split_rows'), findsOneWidget);
      expect(
        tester.widget<TextField>(_k('custom_amount_maya')).controller!.text,
        '1800',
      );
    });

    testWidgets('every custom row needs an amount', (tester) async {
      final results = <ExpenseItem?>[];
      await _show(tester, _expense(), results);
      await tester.ensureVisible(_k('split_mode_custom'));
      await tester.tap(_k('split_mode_custom'));
      await settle(tester, 400);
      await tester.enterText(_k('custom_amount_liam'), '');
      await tester.pump();
      await _save(tester);
      expect(find.text('Enter an amount for every person.'), findsOneWidget);
      expect(results, isEmpty);
    });

    testWidgets('switching back to Equal Split clears the custom amounts', (
      tester,
    ) async {
      final results = <ExpenseItem?>[];
      await _show(
        tester,
        _expense(
          amount: 3950,
          custom: {'you': 1200, 'maya': 1800, 'liam': 950},
        ),
        results,
      );
      await tester.ensureVisible(_k('split_mode_equal'));
      await tester.tap(_k('split_mode_equal'));
      await settle(tester, 400);
      await _save(tester);
      expect(results.single!.customSplits, isNull);
      expect(results.single!.amount, 3950);
    });
  });

  group('Section order and pill styling', () {
    testWidgets('sections run top to bottom in the exact priority order', (
      tester,
    ) async {
      final withPrompt = _expense().copyWith(
        note: RawPromptNote.compose('Sushiro dinner mine 1200 Maya 1800'),
      );
      await _show(tester, withPrompt, []);

      final sections = <String, Finder>{
        '1 Title': find.widgetWithText(TextField, 'Expense Title'),
        '2 Amount': _k('editor_amount'),
        '3 Date & Time': _k('editor_date'),
        '4 Category': _k('editor_category'),
        '5 Paid By': _k('editor_payer'),
        '6 Receipt Photo': _k('receipt_section'),
        '7 Split': _k('split_mode_toggle'),
        '8 Note': find.widgetWithText(TextField, 'Note (optional)'),
        '9 Original Voice Prompt': _k('raw_prompt_card'),
      };
      double? previous;
      String? previousName;
      for (final entry in sections.entries) {
        expect(entry.value, findsOneWidget, reason: entry.key);
        final y = tester.getTopLeft(entry.value).dy;
        if (previous != null) {
          expect(
            y,
            greaterThan(previous),
            reason: '${entry.key} must sit below $previousName',
          );
        }
        previous = y;
        previousName = entry.key;
      }
      // Time sits beside the date, not below it.
      expect(
        tester.getTopLeft(_k('editor_time')).dy,
        closeTo(tester.getTopLeft(_k('editor_date')).dy, 1),
      );
      // The member pills belong to the split section, above its toggle.
      expect(
        tester.getTopLeft(_k('split_member_you')).dy,
        lessThan(tester.getTopLeft(_k('split_mode_toggle')).dy),
      );
      expect(
        tester.getTopLeft(_k('split_member_you')).dy,
        greaterThan(tester.getTopLeft(_k('receipt_section')).dy),
      );
    });

    testWidgets('the original voice prompt is last, and absent when empty', (
      tester,
    ) async {
      await _show(tester, _expense(), []);
      expect(_k('raw_prompt_card'), findsNothing);
      expect(find.widgetWithText(TextField, 'Note (optional)'), findsOneWidget);
    });

    testWidgets('Split with members are fully rounded stadium pills', (
      tester,
    ) async {
      await _show(tester, _expense(), []);
      for (final id in ['you', 'maya', 'liam']) {
        final chip = tester.widget<FilterChip>(_k('split_member_$id'));
        expect(chip.shape, isA<StadiumBorder>(), reason: id);
      }
      // Selected and unselected pills share the same shape language.
      await tester.ensureVisible(_k('split_member_liam'));
      await tester.tap(_k('split_member_liam'));
      await settle(tester, 300);
      expect(
        tester.widget<FilterChip>(_k('split_member_liam')).selected,
        isFalse,
      );
      expect(
        tester.widget<FilterChip>(_k('split_member_liam')).shape,
        isA<StadiumBorder>(),
      );
    });

    testWidgets('the Equal Split / Custom toggle is a stadium pill', (
      tester,
    ) async {
      await _show(tester, _expense(), []);
      final track =
          tester.widget<Container>(_k('split_mode_toggle')).decoration!
              as ShapeDecoration;
      expect(track.shape, isA<StadiumBorder>());
      for (final key in ['split_mode_equal', 'split_mode_custom']) {
        final inner = tester.widget<AnimatedContainer>(
          find.descendant(
            of: _k(key),
            matching: find.byType(AnimatedContainer),
          ),
        );
        expect(
          (inner.decoration! as ShapeDecoration).shape,
          isA<StadiumBorder>(),
          reason: key,
        );
      }
      // Date, time, category and paid-by pills are stadiums too.
      for (final key in ['editor_date', 'editor_time']) {
        final shape = tester
            .widget<Material>(
              find.ancestor(of: _k(key), matching: find.byType(Material)).first,
            )
            .shape;
        expect(shape, isA<StadiumBorder>(), reason: key);
      }
    });
  });

  group('Receipt / slip photo', () {
    late Future<ReceiptPhotoResult> Function(ReceiptSource) original;
    setUp(() => original = ReceiptPhotoService.pick);
    tearDown(() => ReceiptPhotoService.pick = original);

    testWidgets('Take Photo and Choose from Gallery are offered', (
      tester,
    ) async {
      await _show(tester, _expense(), []);
      expect(find.text('Receipt / Slip Photo'), findsOneWidget);
      expect(find.text('Take Photo'), findsOneWidget);
      expect(find.text('Choose from Gallery'), findsOneWidget);
    });

    testWidgets('a picked photo is previewed, saved, and each source is used', (
      tester,
    ) async {
      final sources = <ReceiptSource>[];
      ReceiptPhotoService.pick = (s) async {
        sources.add(s);
        return const ReceiptPhotoResult.ok(_tinyPng);
      };
      final results = <ExpenseItem?>[];
      await _show(tester, _expense(), results);

      await tester.ensureVisible(_k('receipt_camera'));
      await tester.tap(_k('receipt_camera'));
      await settle(tester, 400);
      expect(_k('receipt_preview'), findsOneWidget);
      expect(sources, [ReceiptSource.camera]);

      await _save(tester);
      expect(results.single!.receiptImageBase64, _tinyPng);
    });

    testWidgets('tapping the preview opens it full screen; Remove deletes it', (
      tester,
    ) async {
      final results = <ExpenseItem?>[];
      await _show(tester, _expense(receipt: _tinyPng), results);
      expect(_k('receipt_preview'), findsOneWidget);

      await tester.ensureVisible(_k('receipt_preview'));
      await tester.tap(_k('receipt_preview'));
      await settle(tester, 500);
      expect(_k('receipt_fullscreen'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await tester.tap(_k('receipt_fullscreen_close'));
      await settle(tester, 400);
      expect(_k('receipt_fullscreen'), findsNothing);

      await tester.ensureVisible(_k('receipt_remove'));
      await tester.tap(_k('receipt_remove'));
      await settle(tester, 300);
      expect(_k('receipt_preview'), findsNothing);
      await _save(tester);
      expect(results.single!.receiptImageBase64, isNull);
    });

    testWidgets(
      'a refused permission shows a friendly message, never a crash',
      (tester) async {
        ReceiptPhotoService.pick = (_) async => const ReceiptPhotoResult.error(
          'Could not open the camera. Check the camera permission.',
        );
        await _show(tester, _expense(), []);
        await tester.ensureVisible(_k('receipt_camera'));
        await tester.tap(_k('receipt_camera'));
        await settle(tester, 400);
        expect(_k('receipt_error'), findsOneWidget);
        expect(_k('receipt_preview'), findsNothing);
      },
    );

    testWidgets('cancelling the picker changes nothing', (tester) async {
      ReceiptPhotoService.pick = (_) async =>
          const ReceiptPhotoResult.cancelled();
      await _show(tester, _expense(), []);
      await tester.ensureVisible(_k('receipt_gallery'));
      await tester.tap(_k('receipt_gallery'));
      await settle(tester, 400);
      expect(_k('receipt_preview'), findsNothing);
      expect(_k('receipt_error'), findsNothing);
    });

    test('the picker settings keep photos small enough to sync', () {
      expect(ReceiptPhotoService.maxSide, lessThanOrEqualTo(1024));
      expect(ReceiptPhotoService.jpegQuality, lessThanOrEqualTo(60));
      expect(ReceiptPhotoService.maxBase64Chars, lessThan(512 * 1024));
    });
  });

  group('Landing screen on a real phone keyboard', () {
    testWidgets('the footer is shown with the keyboard closed', (tester) async {
      await pumpPocko(
        tester,
        OnboardingScreen(startAtSetup: true, onDone: () {}),
        scaffold: false,
      );
      await settle(tester, 400);
      expect(_k('onboarding_dots'), findsOneWidget);
      expect(_k('demo_trip_button'), findsOneWidget);
    });

    testWidgets('the footer hides while the keyboard is open', (tester) async {
      await pumpPocko(
        tester,
        OnboardingScreen(startAtSetup: true, onDone: () {}),
        size: const Size(390, 700),
        bottomInset: 320,
        scaffold: false,
      );
      await settle(tester, 400);
      expect(_k('onboarding_dots'), findsNothing);
      expect(_k('demo_trip_button'), findsNothing);
      expect(_k('next_button'), findsNothing);
      expect(_k('setup_page'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'no overflow stripes');
    });

    testWidgets('story pages also drop the Next button under the keyboard', (
      tester,
    ) async {
      await pumpPocko(
        tester,
        OnboardingScreen(onDone: () {}),
        size: const Size(390, 700),
        bottomInset: 320,
        scaffold: false,
      );
      await settle(tester, 400);
      expect(_k('next_button'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Destination picker shows country flags', () {
    test('every destination has a flag and a labelled picker row', () {
      for (final d in TripDestination.all) {
        expect(d.flag.isNotEmpty, isTrue, reason: d.name);
        expect(
          d.pickerLabel(CurrencyHelper.symbol(d.currency)),
          startsWith(d.flag),
        );
      }
      final byName = {for (final d in TripDestination.all) d.name: d};
      expect(byName['Japan']!.pickerLabel('¥'), '🇯🇵 Japan (¥ JPY)');
      // The dropdown row shows the flag once (in its circle), not in the text.
      expect(byName['Japan']!.rowLabel('¥'), 'Japan (¥ JPY)');
      expect(byName['Switzerland']!.rowLabel('CHF'), 'Switzerland (CHF)');
      for (final d in TripDestination.all) {
        expect(d.rowLabel('x').contains(d.flag), isFalse, reason: d.name);
      }
      expect(byName['Taiwan']!.currency, 'TWD');
      expect(byName['Hong Kong']!.currency, 'HKD');
    });
  });

  group('Hidden tabs do not run animations', () {
    testWidgets('only the visible tab keeps its tickers enabled', (
      tester,
    ) async {
      await pumpPocko(tester, const PockoMainShell(), scaffold: false);
      await settle(tester, 400);

      bool ticking(Finder f) =>
          TickerMode.valuesOf(tester.element(f.first)).enabled;

      final settleTab = find.byType(VisualSettleScreen, skipOffstage: false);
      expect(settleTab, findsOneWidget);
      expect(ticking(settleTab), isFalse, reason: 'Settle is hidden on Home');

      await tester.tap(find.text('Settle'));
      await settle(tester, 700);
      expect(ticking(settleTab), isTrue);
    });
  });
}
