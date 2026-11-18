import 'package:flutter_test/flutter_test.dart';
import 'package:travmate/features/capture/transcript_tokens.dart';

void main() {
  group('tokenizeTranscript', () {
    test('Highlights the title and price of a single expense inline', () {
      final r = tokenizeTranscript('Ichiran ramen 4800 split 4 ways', [
        (title: 'Ichiran Ramen', amount: 4800.0),
      ]);
      final kinds = r.tokens.map((t) => t.kind).toList();
      expect(kinds, [
        TranscriptTokenKind.title,
        TranscriptTokenKind.text,
        TranscriptTokenKind.amount,
        TranscriptTokenKind.text,
      ]);
      expect(r.tokens[0].text, 'Ichiran ramen');
      expect(r.tokens[2].text, '4800');
      expect(r.tokens[3].text, ' split 4 ways');
      expect(r.missingTitle, isEmpty);
      expect(r.missingAmount, isEmpty);
    });

    test('Maps several spoken expenses to the right items in order', () {
      final r = tokenizeTranscript(
        'Ramen 4800 split 4 ways, and Shinkansen tickets 18,200 for Alex, Maya, and me',
        [
          (title: 'Ramen', amount: 4800.0),
          (title: 'Shinkansen Tickets', amount: 18200.0),
        ],
      );
      final titles = r.tokens
          .where((t) => t.kind == TranscriptTokenKind.title)
          .toList();
      final amounts = r.tokens
          .where((t) => t.kind == TranscriptTokenKind.amount)
          .toList();
      expect(titles.map((t) => t.itemIndex), [0, 1]);
      expect(amounts.map((t) => t.itemIndex), [0, 1]);
      expect(amounts[1].text, '18,200');
      expect(r.tokens.last.text, ' for Alex, Maya, and me');
    });

    test('Includes a currency symbol and understands the k suffix', () {
      final r = tokenizeTranscript('Hotel ¥12k tonight', [
        (title: 'Hotel', amount: 12000.0),
      ]);
      final amount = r.tokens.firstWhere(
        (t) => t.kind == TranscriptTokenKind.amount,
      );
      expect(amount.text, '¥12k');
    });

    test('Ignores head-counts such as "4 ways" when locating the price', () {
      final r = tokenizeTranscript('Dinner 4 people 85 euro', [
        (title: 'Dinner', amount: 85.0),
      ]);
      final amount = r.tokens.firstWhere(
        (t) => t.kind == TranscriptTokenKind.amount,
      );
      expect(amount.text, '85');
    });

    test('Entities that are not in the transcript are reported as missing', () {
      final r = tokenizeTranscript('coffee 650', [
        (title: 'Meals', amount: 650.0),
      ]);
      expect(r.missingTitle, {0});
      expect(r.missingAmount, isEmpty);
      expect(r.hasInline(0), isTrue);

      final none = tokenizeTranscript('hello', [(title: 'Tea', amount: 5.0)]);
      expect(none.missingTitle, {0});
      expect(none.missingAmount, {0});
      expect(none.hasInline(0), isFalse);
      expect(none.tokens.single.kind, TranscriptTokenKind.text);
    });

    test('Falls back to the first meaningful title word', () {
      final r = tokenizeTranscript('matcha latte 650 for me', [
        (title: 'Matcha Latte Deluxe', amount: 650.0),
      ]);
      final title = r.tokens.firstWhere(
        (t) => t.kind == TranscriptTokenKind.title,
      );
      expect(title.text, 'matcha');
    });
  });

  group('Spoken multipliers and member names', () {
    test(
      '1 thousan / one thousand / 2.5k in the transcript match the item amount',
      () {
        for (final (text, amount, expected) in [
          ('Dinner 1 thousan yen', 1000.0, '1 thousan'),
          ('Dinner one thousand yen', 1000.0, 'one thousand'),
          ('Taxi 2.5k', 2500.0, '2.5k'),
          ('Villa 1 million', 1000000.0, '1 million'),
        ]) {
          final r = tokenizeTranscript(text, [
            (title: text.split(' ').first, amount: amount),
          ]);
          final amountToken = r.tokens.firstWhere(
            (t) => t.kind == TranscriptTokenKind.amount,
          );
          expect(amountToken.text, expected, reason: text);
          expect(r.missingAmount, isEmpty, reason: text);
        }
      },
    );

    test('member names become member tokens next to title and amount', () {
      final r = tokenizeTranscript(
        'Dinner 4800 split with Alex, Maya and Liam',
        [(title: 'Dinner', amount: 4800.0)],
        members: const [
          (id: 'you', name: 'You'),
          (id: 'alex', name: 'Alex'),
          (id: 'maya', name: 'Maya'),
          (id: 'liam', name: 'Liam'),
        ],
        selfId: 'you',
      );
      final members = r.tokens.where(
        (t) => t.kind == TranscriptTokenKind.member,
      );
      expect(members.map((t) => t.text), ['Alex', 'Maya', 'Liam']);
      expect(members.map((t) => t.memberId), ['alex', 'maya', 'liam']);
      expect(r.mentionedMembers, {'alex', 'maya', 'liam'});
      // Plain text between tokens is preserved verbatim.
      expect(
        r.tokens.map((t) => t.text).join(),
        'Dinner 4800 split with Alex, Maya and Liam',
      );
    });

    test('"me" and "myself" map to the current member; names only match whole words', () {
      final r = tokenizeTranscript(
        'Taxi 1200 for Alexandra and me',
        [(title: 'Taxi', amount: 1200.0)],
        members: const [(id: 'alex', name: 'Alex'), (id: 'you', name: 'You')],
        selfId: 'you',
      );
      expect(r.mentionedMembers, {'you'}, reason: 'Alexandra is not Alex');
      expect(
        r.tokens.firstWhere((t) => t.kind == TranscriptTokenKind.member).text,
        'me',
      );
    });

    test('a member name inside a title is left to the title', () {
      final r = tokenizeTranscript(
        "Alex's dinner 4800",
        [(title: "Alex's dinner", amount: 4800.0)],
        members: const [(id: 'alex', name: 'Alex')],
      );
      expect(r.mentionedMembers, isEmpty);
    });
  });
}
