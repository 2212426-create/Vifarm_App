import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/firebase_providers.dart';
import '../models/journal_model.dart';

final journalRepositoryProvider = Provider<JournalRepository>((ref) {
  return JournalRepository(firestore: ref.watch(firestoreProvider));
});

final userJournalsStreamProvider = StreamProvider.family<List<JournalModel>, String>((ref, userId) {
  return ref.watch(journalRepositoryProvider).watchUserJournals(userId);
});

final publicJournalsStreamProvider = StreamProvider<List<JournalModel>>((ref) {
  return ref.watch(journalRepositoryProvider).watchPublicJournals();
});

final journalDetailStreamProvider = StreamProvider.family<JournalModel?, String>((ref, journalId) {
  return ref.watch(journalRepositoryProvider).watchJournalDetail(journalId);
});

final journalEntriesStreamProvider = StreamProvider.family<List<JournalEntryModel>, String>((ref, journalId) {
  return ref.watch(journalRepositoryProvider).watchJournalEntries(journalId);
});

class JournalRepository {
  final FirebaseFirestore _firestore;

  JournalRepository({required this._firestore});

  /// Stream danh sách nhật ký của người dùng
  Stream<List<JournalModel>> watchUserJournals(String userId) {
    if (userId.isEmpty) return Stream.value([]);
    return _firestore
        .collection('journals')
        .where('ownerId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs
          .map((doc) => JournalModel.fromMap(doc.data(), doc.id))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// Stream nhật ký công khai
  Stream<List<JournalModel>> watchPublicJournals() {
    return _firestore
        .collection('journals')
        .where('privacy', isEqualTo: 'public')
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs
          .map((doc) => JournalModel.fromMap(doc.data(), doc.id))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// Stream thông tin chi tiết 1 nhật ký
  Stream<JournalModel?> watchJournalDetail(String journalId) {
    if (journalId.isEmpty) return Stream.value(null);
    return _firestore.collection('journals').doc(journalId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return JournalModel.fromMap(doc.data()!, doc.id);
    });
  }

  /// Stream các mục nhật ký (sắp xếp theo recordDate tăng dần - từ cũ đến mới, từ trên xuống)
  Stream<List<JournalEntryModel>> watchJournalEntries(String journalId) {
    if (journalId.isEmpty) return Stream.value([]);
    return _firestore
        .collection('journals')
        .doc(journalId)
        .collection('entries')
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs
          .map((doc) => JournalEntryModel.fromMap(doc.data(), doc.id))
          .toList();
      list.sort(JournalModel.compareEntries);
      return list;
    });
  }

  /// Tạo hồ sơ nhật ký mới
  Future<String> createJournal(JournalModel journal) async {
    final docRef = _firestore.collection('journals').doc();
    final newJournal = JournalModel(
      id: docRef.id,
      ownerId: journal.ownerId,
      ownerName: journal.ownerName,
      name: journal.name,
      farmLocation: journal.farmLocation,
      crop: journal.crop,
      variety: journal.variety,
      startDate: journal.startDate,
      region: journal.region,
      description: journal.description,
      status: journal.status,
      privacy: journal.privacy,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await docRef.set(newJournal.toMap());
    return docRef.id;
  }

  /// Cập nhật thông tin nhật ký
  Future<void> updateJournal(JournalModel journal, String currentUserId) async {
    final docRef = _firestore.collection('journals').doc(journal.id);
    final docSnap = await docRef.get();

    if (!docSnap.exists) {
      throw Exception('Nhật ký không tồn tại.');
    }

    final data = docSnap.data();
    if (data == null || data['ownerId'] != currentUserId) {
      throw Exception('Bạn không có quyền chỉnh sửa nhật ký này.');
    }

    await docRef.update(journal.toMap());
  }

  /// Xóa vĩnh viễn nhật ký và tất cả các mục ghi chép thuộc nhật ký đó
  Future<void> deleteJournal(String journalId, String currentUserId) async {
    if (journalId.isEmpty || currentUserId.isEmpty) {
      throw Exception('Thông tin không hợp lệ để thực hiện xóa.');
    }

    final journalDocRef = _firestore.collection('journals').doc(journalId);
    final journalSnapshot = await journalDocRef.get();

    if (!journalSnapshot.exists) {
      throw Exception('Nhật ký không tồn tại hoặc đã bị xóa.');
    }

    final data = journalSnapshot.data();
    if (data == null || data['ownerId'] != currentUserId) {
      throw Exception('Bạn không có quyền xóa nhật ký này.');
    }

    // 1. Read all entries in subcollection `journals/{journalId}/entries`
    final entriesSnapshot = await journalDocRef.collection('entries').get();

    // 2. Use WriteBatch for atomic deletion
    final batch = _firestore.batch();

    for (final doc in entriesSnapshot.docs) {
      batch.delete(doc.reference);
    }

    batch.delete(journalDocRef);

    // 3. Unbind linked videos in `videos` collection if any
    try {
      final linkedVideosSnapshot = await _firestore
          .collection('videos')
          .where('journalId', isEqualTo: journalId)
          .get();

      for (final doc in linkedVideosSnapshot.docs) {
        batch.update(doc.reference, {'journalId': FieldValue.delete()});
      }
    } catch (_) {
      // Ignore if videos query fails
    }

    await batch.commit();
  }

  /// Tạo mục nhật ký mới (hỗ trợ chọn recordDate để đăng bù)
  Future<void> addJournalEntry(JournalEntryModel entry) async {
    final docRef = _firestore
        .collection('journals')
        .doc(entry.journalId)
        .collection('entries')
        .doc();

    final newEntry = JournalEntryModel(
      id: docRef.id,
      journalId: entry.journalId,
      recordDate: entry.recordDate,
      postDate: DateTime.now().millisecondsSinceEpoch,
      growthStage: entry.growthStage,
      title: entry.title,
      notes: entry.notes,
      attachedVideoUrl: entry.attachedVideoUrl,
      attachedImageUrls: entry.attachedImageUrls,
      privacy: entry.privacy,
    );

    await docRef.set(newEntry.toMap());
  }

  /// Cập nhật mục nhật ký
  Future<void> updateJournalEntry(JournalEntryModel entry) async {
    final docRef = _firestore
        .collection('journals')
        .doc(entry.journalId)
        .collection('entries')
        .doc(entry.id);

    await docRef.update(entry.toMap());
  }

  /// Xóa mục nhật ký
  Future<void> deleteJournalEntry(String journalId, String entryId) async {
    final docRef = _firestore
        .collection('journals')
        .doc(journalId)
        .collection('entries')
        .doc(entryId);

    await docRef.delete();
  }
}
