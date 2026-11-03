import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toptop_flutter/features/farm_journal/models/journal_model.dart';

void main() {
  group('Journal Invalid Entries Classification & Expanded Toggle Tests', () {
    testWidgets('verify 2 invalid entries classification, counting, and toggle states', (WidgetTester tester) async {
      final now = DateTime(2026, 10, 28);
      final startDateMs = now.millisecondsSinceEpoch;

      final validEntry1 = JournalEntryModel(
        id: 'e1',
        journalId: 'j1',
        recordDate: DateTime(2026, 10, 28).millisecondsSinceEpoch,
        postDate: startDateMs,
        growthStage: 'Làm đất',
        title: 'Làm đất & chăm sóc đất',
        notes: '5 xe phân bò',
      );

      final invalidEntry1 = JournalEntryModel(
        id: 'e2',
        journalId: 'j1',
        recordDate: DateTime(2026, 2, 11).millisecondsSinceEpoch,
        postDate: startDateMs,
        growthStage: 'Tỉa lá',
        title: 'tỉa lá',
        notes: 'làm lá',
      );

      final invalidEntry2 = JournalEntryModel(
        id: 'e3',
        journalId: 'j1',
        recordDate: DateTime(2025, 12, 4).millisecondsSinceEpoch,
        postDate: startDateMs,
        growthStage: 'Thu hoạch',
        title: 'kkk',
        notes: 'thu hoạch',
      );

      final allEntries = [validEntry1, invalidEntry1, invalidEntry2];

      final validList = <JournalEntryModel>[];
      final invalidList = <JournalEntryModel>[];

      for (final e in allEntries) {
        final c = JournalModel.classifyEntry(e, startDateMs, now);
        if (c.isValid) {
          validList.add(e);
        } else {
          invalidList.add(e);
        }
      }

      // 1. Verify 2 items classified as invalid
      expect(validList.length, equals(1));
      expect(invalidList.length, equals(2));
      expect(invalidList[0].title, equals('tỉa lá'));
      expect(invalidList[1].title, equals('kkk'));

      // 2. Test widget rendering & toggle button state
      bool isExpanded = false;

      Widget buildTestWidget() {
        return MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return Column(
                  children: [
                    if (invalidList.isNotEmpty) ...[
                      Card(
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text('Có ${invalidList.length} mục ghi chép cần kiểm tra lại ngày thực hiện.'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      isExpanded = !isExpanded;
                                    });
                                  },
                                  child: Text(isExpanded ? 'Thu gọn' : 'Xem danh sách'),
                                ),
                              ],
                            ),
                            if (isExpanded) ...[
                              Column(
                                children: invalidList.map((invEntry) {
                                  final classification = JournalModel.classifyEntry(invEntry, startDateMs, now);
                                  return ListTile(
                                    title: Text(invEntry.title),
                                    subtitle: Text(classification.reasonMessage),
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        );
      }

      await tester.pumpWidget(buildTestWidget());

      // Initial state: collapsed, banner shows count 2, button shows 'Xem danh sách'
      expect(find.text('Có 2 mục ghi chép cần kiểm tra lại ngày thực hiện.'), findsOneWidget);
      expect(find.text('Xem danh sách'), findsOneWidget);
      expect(find.text('tỉa lá'), findsNothing);
      expect(find.text('kkk'), findsNothing);

      // Tap 'Xem danh sách' to expand
      await tester.tap(find.text('Xem danh sách'));
      await tester.pumpAndSettle();

      // Expanded state: button shows 'Thu gọn', both invalid items are visible with reasons
      expect(find.text('Thu gọn'), findsOneWidget);
      expect(find.text('tỉa lá'), findsOneWidget);
      expect(find.text('kkk'), findsOneWidget);
      expect(find.textContaining('trước ngày bắt đầu mùa vụ'), findsNWidgets(2));

      // Tap 'Thu gọn' to collapse again
      await tester.tap(find.text('Thu gọn'));
      await tester.pumpAndSettle();

      // Collapsed state again
      expect(find.text('Xem danh sách'), findsOneWidget);
      expect(find.text('tỉa lá'), findsNothing);

      // Simulate resolving 1 item -> remaining count becomes 1
      invalidList.removeAt(0);
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Có 1 mục ghi chép cần kiểm tra lại ngày thực hiện.'), findsOneWidget);

      // Simulate resolving all items -> warning banner disappears completely
      invalidList.clear();
      await tester.pumpWidget(buildTestWidget());

      expect(find.textContaining('cần kiểm tra lại ngày thực hiện'), findsNothing);
    });
  });
}
