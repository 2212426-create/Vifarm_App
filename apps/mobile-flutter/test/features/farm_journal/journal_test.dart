import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toptop_flutter/features/farm_journal/models/journal_model.dart';

void main() {
  group('3 Calendar Month Start Date Restriction Tests', () {
    test('calculates earliest allowed date lùi đúng 3 tháng theo lịch', () {
      // 1. Normal case: 28/10/2026 -> 28/07/2026
      final oct28 = DateTime(2026, 10, 28);
      final earliestOct = JournalModel.getEarliestAllowedStartDate(oct28);
      expect(earliestOct.year, equals(2026));
      expect(earliestOct.month, equals(7));
      expect(earliestOct.day, equals(28));

      // 2. Target month length truncation: 31/05/2026 -> 28/02/2026
      final may31 = DateTime(2026, 5, 31);
      final earliestMay = JournalModel.getEarliestAllowedStartDate(may31);
      expect(earliestMay.year, equals(2026));
      expect(earliestMay.month, equals(2));
      expect(earliestMay.day, equals(28));

      // 3. Leap year truncation: 31/05/2024 -> 29/02/2024
      final may31Leap = DateTime(2024, 5, 31);
      final earliestMayLeap = JournalModel.getEarliestAllowedStartDate(may31Leap);
      expect(earliestMayLeap.year, equals(2024));
      expect(earliestMayLeap.month, equals(2));
      expect(earliestMayLeap.day, equals(29));

      // 4. Year boundary transition: 15/02/2026 -> 15/11/2025
      final feb15 = DateTime(2026, 2, 15);
      final earliestFeb = JournalModel.getEarliestAllowedStartDate(feb15);
      expect(earliestFeb.year, equals(2025));
      expect(earliestFeb.month, equals(11));
      expect(earliestFeb.day, equals(15));
    });

    test('validates start date within [earliestAllowedDate .. today]', () {
      final today = DateUtils.dateOnly(DateTime(2026, 10, 28));

      // Today is valid
      expect(JournalModel.isValidStartDate(today, today), isTrue);

      // 28/07/2026 (exact 3 months ago) is valid
      expect(JournalModel.isValidStartDate(DateTime(2026, 7, 28), today), isTrue);

      // 27/07/2026 (1 day before earliest) is INVALID
      expect(JournalModel.isValidStartDate(DateTime(2026, 7, 27), today), isFalse);

      // 29/10/2026 (future date) is INVALID
      expect(JournalModel.isValidStartDate(DateTime(2026, 10, 29), today), isFalse);
    });
  });

  group('Entry Classification & Reason Tests', () {
    test('classifies entries as valid or invalid with clear Vietnamese reason messages', () {
      final startDateMs = DateTime(2026, 10, 28).millisecondsSinceEpoch;
      final today = DateTime(2026, 11, 15);

      final validEntry = JournalEntryModel(
        id: 'e1',
        journalId: 'j1',
        recordDate: DateTime(2026, 10, 28).millisecondsSinceEpoch,
        postDate: DateTime.now().millisecondsSinceEpoch,
        growthStage: 'Làm đất',
        title: 'Làm đất',
        notes: '',
      );

      final beforeStartEntry = JournalEntryModel(
        id: 'e2',
        journalId: 'j1',
        recordDate: DateTime(2025, 12, 4).millisecondsSinceEpoch,
        postDate: DateTime.now().millisecondsSinceEpoch,
        growthStage: 'Thu hoạch',
        title: 'kkk',
        notes: '',
      );

      final futureEntry = JournalEntryModel(
        id: 'e3',
        journalId: 'j1',
        recordDate: DateTime(2026, 11, 20).millisecondsSinceEpoch,
        postDate: DateTime.now().millisecondsSinceEpoch,
        growthStage: 'Tỉa lá',
        title: 'Tỉa lá tương lai',
        notes: '',
      );

      final corruptedEntry = JournalEntryModel(
        id: 'e4',
        journalId: 'j1',
        recordDate: 0,
        postDate: DateTime.now().millisecondsSinceEpoch,
        growthStage: 'Tỉa lá',
        title: 'Lỗi ngày',
        notes: '',
      );

      final c1 = JournalModel.classifyEntry(validEntry, startDateMs, today);
      expect(c1.isValid, isTrue);
      expect(c1.reason, equals(JournalEntryInvalidReason.none));

      final c2 = JournalModel.classifyEntry(beforeStartEntry, startDateMs, today);
      expect(c2.isValid, isFalse);
      expect(c2.reason, equals(JournalEntryInvalidReason.beforeStartDate));
      expect(c2.reasonMessage, contains('trước ngày bắt đầu mùa vụ'));

      final c3 = JournalModel.classifyEntry(futureEntry, startDateMs, today);
      expect(c3.isValid, isFalse);
      expect(c3.reason, equals(JournalEntryInvalidReason.afterToday));
      expect(c3.reasonMessage, contains('trong tương lai'));

      final c4 = JournalModel.classifyEntry(corruptedEntry, startDateMs, today);
      expect(c4.isValid, isFalse);
      expect(c4.reason, equals(JournalEntryInvalidReason.missingOrCorruptedDate));
      expect(c4.reasonMessage, contains('Chưa có ngày hợp lệ'));
    });
  });

  group('3-Tier Entry Timeline Comparator Tests', () {
    test('sorts entries by recordDate (1st), postDate/createdAt (2nd), and id (3rd)', () {
      final dateOct28 = DateTime(2026, 10, 28).millisecondsSinceEpoch;
      final dateOct29 = DateTime(2026, 10, 29).millisecondsSinceEpoch;

      // Entry A: "Làm đất" created first at 08:00 (postDate = 1000)
      final entryA = JournalEntryModel(
        id: 'e_lam_dat',
        journalId: 'j1',
        recordDate: dateOct28,
        postDate: 1000,
        growthStage: 'Làm đất',
        title: 'Làm đất và chăm sóc đất trước khi trồng',
        notes: '5 xe phân bò',
      );

      // Entry B: "Tỉa lá" created second at 09:00 (postDate = 2000), originally wrong date, edited to same date as A
      final entryB = JournalEntryModel(
        id: 'e_tia_la',
        journalId: 'j1',
        recordDate: dateOct28,
        postDate: 2000,
        growthStage: 'Tỉa lá',
        title: 'tỉa lá',
        notes: 'làm lá',
      );

      // Entry C: "Thu hoạch" created third at 10:00 (postDate = 3000), recordDate = Oct 29
      final entryC = JournalEntryModel(
        id: 'e_thu_hoach',
        journalId: 'j1',
        recordDate: dateOct29,
        postDate: 3000,
        growthStage: 'Thu hoạch',
        title: 'kkk',
        notes: 'thu hoạch',
      );

      // Shuffle order to test sorting
      final entries = [entryB, entryC, entryA];
      entries.sort(JournalModel.compareEntries);

      // Verify exact 3-tier sorted order: A ("Làm đất") -> B ("Tỉa lá") -> C ("Thu hoạch")
      expect(entries[0].title, equals('Làm đất và chăm sóc đất trước khi trồng'));
      expect(entries[1].title, equals('tỉa lá'));
      expect(entries[2].title, equals('kkk'));
    });

    test('maintains stable tie-breaker when recordDate and postDate are identical', () {
      final sameDate = DateTime(2026, 10, 28).millisecondsSinceEpoch;
      final samePostDate = 5000;

      final entryZ = JournalEntryModel(
        id: 'doc_z',
        journalId: 'j1',
        recordDate: sameDate,
        postDate: samePostDate,
        growthStage: 'Bón phân',
        title: 'Công việc Z',
        notes: '',
      );

      final entryA = JournalEntryModel(
        id: 'doc_a',
        journalId: 'j1',
        recordDate: sameDate,
        postDate: samePostDate,
        growthStage: 'Bón phân',
        title: 'Công việc A',
        notes: '',
      );

      final entries = [entryZ, entryA];
      entries.sort(JournalModel.compareEntries);

      expect(entries[0].id, equals('doc_a'));
      expect(entries[1].id, equals('doc_z'));
    });
  });

  group('Entry Date & Timeline Calculation Tests', () {
    test('calculates Ngày thứ N của mùa vụ correctly', () {
      final startDate = DateTime(2026, 10, 28);

      // Day 1 (same day as start date)
      expect(JournalModel.calculateDayNumber(DateTime(2026, 10, 28), startDate), equals(1));

      // Day 2 (next day)
      expect(JournalModel.calculateDayNumber(DateTime(2026, 10, 29), startDate), equals(2));

      // Day 14
      expect(JournalModel.calculateDayNumber(DateTime(2026, 11, 10), startDate), equals(14));
    });

    test('validates recordDate within [startDate .. today]', () {
      final startDate = DateTime(2026, 10, 28);
      final today = DateTime(2026, 11, 15);

      // Same as startDate -> valid
      expect(JournalModel.isValidRecordDate(DateTime(2026, 10, 28), startDate, today), isTrue);

      // Between startDate and today -> valid
      expect(JournalModel.isValidRecordDate(DateTime(2026, 11, 5), startDate, today), isTrue);

      // Same as today -> valid
      expect(JournalModel.isValidRecordDate(DateTime(2026, 11, 15), startDate, today), isTrue);

      // Before startDate -> INVALID
      expect(JournalModel.isValidRecordDate(DateTime(2026, 10, 27), startDate, today), isFalse);

      // Future date after today -> INVALID
      expect(JournalModel.isValidRecordDate(DateTime(2026, 11, 16), startDate, today), isFalse);
    });
  });

  group('JournalModel Serialization Tests', () {
    test('converts JournalModel toMap and fromMap correctly', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final journal = JournalModel(
        id: 'j123',
        ownerId: 'user1',
        ownerName: 'Nông hộ Nam',
        name: 'Nhật ký Sầu riêng Ri6',
        farmLocation: 'Vườn nhà, Thôn 3, Đức Trọng',
        crop: 'Sầu riêng',
        variety: 'Ri6',
        startDate: now,
        region: 'Lâm Đồng',
        description: 'Mùa vụ 2026',
        status: 'in_progress',
        privacy: 'public',
        createdAt: now,
      );

      final map = journal.toMap();
      final parsed = JournalModel.fromMap(map, 'j123');

      expect(parsed.id, equals('j123'));
      expect(parsed.ownerId, equals('user1'));
      expect(parsed.name, equals('Nhật ký Sầu riêng Ri6'));
      expect(parsed.farmLocation, equals('Vườn nhà, Thôn 3, Đức Trọng'));
      expect(parsed.crop, equals('Sầu riêng'));
      expect(parsed.variety, equals('Ri6'));
      expect(parsed.startDate, equals(now));
      expect(parsed.status, equals('in_progress'));
      expect(parsed.privacy, equals('public'));
    });
  });
}
