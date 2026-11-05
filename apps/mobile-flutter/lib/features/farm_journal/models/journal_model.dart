import 'package:flutter/material.dart';

enum JournalEntryInvalidReason {
  none,
  beforeStartDate,
  afterToday,
  missingOrCorruptedDate,
}

class JournalEntryClassification {
  final bool isValid;
  final JournalEntryInvalidReason reason;
  final String reasonMessage;

  JournalEntryClassification({
    required this.isValid,
    required this.reason,
    required this.reasonMessage,
  });
}

/// Model Nhật ký mùa vụ / vườn trồng
class JournalModel {
  final String id;
  final String ownerId;
  final String ownerName;
  final String name;
  final String farmLocation;
  final String crop;
  final String? variety;
  final int startDate;
  final String region;
  final String description;
  final String status;  // 'in_progress' | 'finished'
  final String privacy; // 'public' | 'private'
  final int createdAt;

  JournalModel({
    required this.id,
    required this.ownerId,
    this.ownerName = '',
    required this.name,
    required this.farmLocation,
    required this.crop,
    this.variety,
    required this.startDate,
    required this.region,
    this.description = '',
    this.status = 'in_progress',
    this.privacy = 'public',
    required this.createdAt,
  });

  /// Tính ngày sớm nhất được phép chọn làm ngày bắt đầu (Lùi đúng 3 tháng theo lịch)
  static DateTime getEarliestAllowedStartDate([DateTime? now]) {
    final current = DateUtils.dateOnly(now ?? DateTime.now());
    int year = current.year;
    int month = current.month - 3;
    if (month <= 0) {
      month += 12;
      year -= 1;
    }
    int day = current.day;
    final daysInTargetMonth = DateUtils.getDaysInMonth(year, month);
    if (day > daysInTargetMonth) {
      day = daysInTargetMonth;
    }
    return DateTime(year, month, day);
  }

  /// Kiểm tra ngày bắt đầu có nằm trong khoảng hợp lệ [3 tháng trước .. hôm nay]
  static bool isValidStartDate(DateTime startDate, [DateTime? now]) {
    final today = DateUtils.dateOnly(now ?? DateTime.now());
    final earliest = getEarliestAllowedStartDate(today);
    final target = DateUtils.dateOnly(startDate);

    return !target.isBefore(earliest) && !target.isAfter(today);
  }

  /// Tính "Ngày thứ N của mùa vụ" (Ngày 1 là ngày bắt đầu mùa vụ)
  static int calculateDayNumber(DateTime recordDate, DateTime startDate) {
    final start = DateUtils.dateOnly(startDate);
    final record = DateUtils.dateOnly(recordDate);
    final diff = record.difference(start).inDays;
    return diff + 1;
  }

  /// Kiểm tra ngày thực hiện có hợp lệ trong mùa vụ [startDate .. today]
  static bool isValidRecordDate(DateTime recordDate, DateTime startDate, [DateTime? now]) {
    final today = DateUtils.dateOnly(now ?? DateTime.now());
    final start = DateUtils.dateOnly(startDate);
    final target = DateUtils.dateOnly(recordDate);

    return !target.isBefore(start) && !target.isAfter(today);
  }

  /// Comparator sắp xếp mốc thời gian dòng thời gian theo 3 cấp chuẩn nghiệp vụ:
  /// 1. Ngày thực hiện (recordDate theo ngày lịch)
  /// 2. Trong cùng ngày thực hiện: Thời điểm tạo ban đầu (postDate / createdAt) tăng dần
  /// 3. Nếu postDate bằng nhau: ID document (docId) để kết quả luôn ổn định
  static int compareEntries(JournalEntryModel a, JournalEntryModel b) {
    final aDateOnly = DateUtils.dateOnly(DateTime.fromMillisecondsSinceEpoch(a.recordDate)).millisecondsSinceEpoch;
    final bDateOnly = DateUtils.dateOnly(DateTime.fromMillisecondsSinceEpoch(b.recordDate)).millisecondsSinceEpoch;

    final recordCmp = aDateOnly.compareTo(bDateOnly);
    if (recordCmp != 0) return recordCmp;

    final postCmp = a.postDate.compareTo(b.postDate);
    if (postCmp != 0) return postCmp;

    return a.id.compareTo(b.id);
  }

  /// Phân loại mục ghi chép hợp lệ hay cần kiểm tra kèm lý do cụ thể
  static JournalEntryClassification classifyEntry(
    JournalEntryModel entry,
    int journalStartDateMs, [
    DateTime? now,
  ]) {
    if (entry.recordDate <= 0) {
      return JournalEntryClassification(
        isValid: false,
        reason: JournalEntryInvalidReason.missingOrCorruptedDate,
        reasonMessage: 'Chưa có ngày hợp lệ hoặc dữ liệu bị lỗi.',
      );
    }

    final today = DateUtils.dateOnly(now ?? DateTime.now());
    final startDateOnly = DateUtils.dateOnly(DateTime.fromMillisecondsSinceEpoch(journalStartDateMs));
    final recordDateOnly = DateUtils.dateOnly(DateTime.fromMillisecondsSinceEpoch(entry.recordDate));

    final startDateStr = '${startDateOnly.day.toString().padLeft(2, '0')}/${startDateOnly.month.toString().padLeft(2, '0')}/${startDateOnly.year}';
    final todayStr = '${today.day.toString().padLeft(2, '0')}/${today.month.toString().padLeft(2, '0')}/${today.year}';

    if (recordDateOnly.isBefore(startDateOnly)) {
      return JournalEntryClassification(
        isValid: false,
        reason: JournalEntryInvalidReason.beforeStartDate,
        reasonMessage: 'Ngày này trước ngày bắt đầu mùa vụ $startDateStr.',
      );
    }

    if (recordDateOnly.isAfter(today)) {
      return JournalEntryClassification(
        isValid: false,
        reason: JournalEntryInvalidReason.afterToday,
        reasonMessage: 'Ngày này trong tương lai sau hôm nay ($todayStr).',
      );
    }

    return JournalEntryClassification(
      isValid: true,
      reason: JournalEntryInvalidReason.none,
      reasonMessage: '',
    );
  }

  factory JournalModel.fromMap(Map<String, dynamic> map, [String? docId]) {
    return JournalModel(
      id: docId ?? map['id'] as String? ?? '',
      ownerId: map['ownerId'] as String? ?? '',
      ownerName: map['ownerName'] as String? ?? '',
      name: map['name'] as String? ?? '',
      farmLocation: map['farmLocation'] as String? ?? '',
      crop: map['crop'] as String? ?? '',
      variety: map['variety'] as String?,
      startDate: (map['startDate'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      region: map['region'] as String? ?? '',
      description: map['description'] as String? ?? '',
      status: map['status'] as String? ?? 'in_progress',
      privacy: map['privacy'] as String? ?? 'public',
      createdAt: (map['createdAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'ownerId': ownerId,
        'ownerName': ownerName,
        'name': name,
        'farmLocation': farmLocation,
        'crop': crop,
        'variety': variety,
        'startDate': startDate,
        'region': region,
        'description': description,
        'status': status,
        'privacy': privacy,
        'createdAt': createdAt,
      };
}

/// Model Mục nhật ký (Entry) trong mùa vụ
class JournalEntryModel {
  final String id;
  final String journalId;
  final int recordDate; // Ngày thực tế ghi nhận
  final int postDate;   // Ngày tạo mục trên ứng dụng
  final String growthStage;
  final String title;
  final String notes;
  final String? attachedVideoUrl;
  final List<String> attachedImageUrls;
  final String privacy; // 'public' | 'private'

  JournalEntryModel({
    required this.id,
    required this.journalId,
    required this.recordDate,
    required this.postDate,
    required this.growthStage,
    required this.title,
    required this.notes,
    this.attachedVideoUrl,
    this.attachedImageUrls = const [],
    this.privacy = 'public',
  });

  factory JournalEntryModel.fromMap(Map<String, dynamic> map, [String? docId]) {
    return JournalEntryModel(
      id: docId ?? map['id'] as String? ?? '',
      journalId: map['journalId'] as String? ?? '',
      recordDate: (map['recordDate'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      postDate: (map['postDate'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      growthStage: map['growthStage'] as String? ?? '',
      title: map['title'] as String? ?? '',
      notes: map['notes'] as String? ?? '',
      attachedVideoUrl: map['attachedVideoUrl'] as String?,
      attachedImageUrls: (map['attachedImageUrls'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      privacy: map['privacy'] as String? ?? 'public',
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'journalId': journalId,
        'recordDate': recordDate,
        'postDate': postDate,
        'growthStage': growthStage,
        'title': title,
        'notes': notes,
        'attachedVideoUrl': attachedVideoUrl,
        'attachedImageUrls': attachedImageUrls,
        'privacy': privacy,
      };
}
