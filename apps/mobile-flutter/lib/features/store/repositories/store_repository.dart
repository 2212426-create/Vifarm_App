import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/media/platform_media.dart';
import '../../../core/providers/firebase_providers.dart';
import '../models/store_model.dart';

final storeRepositoryProvider = Provider<StoreRepository>((ref) {
  return StoreRepository(
    firestore: ref.watch(firestoreProvider),
    storage: ref.watch(firebaseStorageProvider),
  );
});

final userStoreStreamProvider = StreamProvider.family<StoreModel?, String>((ref, ownerId) {
  return ref.watch(storeRepositoryProvider).watchUserStore(ownerId);
});

final publicStoreStreamProvider = StreamProvider.family<StoreModel?, String>((ref, storeId) {
  return ref.watch(storeRepositoryProvider).watchPublicStore(storeId);
});

final adminStoresStreamProvider = StreamProvider.family<List<StoreModel>, String?>((ref, filterStatus) {
  return ref.watch(storeRepositoryProvider).watchAdminStores(filterStatus);
});

class StoreRepository {
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  StoreRepository({
    required this._firestore,
    FirebaseStorage? storage,
  })  : _storage = storage ?? FirebaseStorage.instance;

  /// Stream thông tin gian hàng của user (Mỗi tài khoản tối đa 1 gian hàng)
  Stream<StoreModel?> watchUserStore(String ownerId) {
    if (ownerId.isEmpty) return Stream.value(null);
    return _firestore
        .collection('stores')
        .where('ownerId', isEqualTo: ownerId)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      final doc = snapshot.docs.first;
      return StoreModel.fromMap(doc.data(), doc.id);
    });
  }

  /// Lấy thông tin gian hàng theo ownerId bằng Future
  Future<StoreModel?> getStoreByOwner(String ownerId) async {
    if (ownerId.isEmpty) return null;
    final snapshot = await _firestore
        .collection('stores')
        .where('ownerId', isEqualTo: ownerId)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;
    final doc = snapshot.docs.first;
    return StoreModel.fromMap(doc.data(), doc.id);
  }

  /// Stream gian hàng công khai theo storeId
  Stream<StoreModel?> watchPublicStore(String storeId) {
    if (storeId.isEmpty) return Stream.value(null);
    return _firestore.collection('stores').doc(storeId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return StoreModel.fromMap(doc.data()!, doc.id);
    });
  }

  /// Stream danh sách gian hàng dành cho Admin xét duyệt
  Stream<List<StoreModel>> watchAdminStores([String? filterStatus]) {
    Query query = _firestore.collection('stores');
    if (filterStatus != null && filterStatus.isNotEmpty) {
      query = query.where('status', isEqualTo: filterStatus);
    }
    return query.snapshots().map((snapshot) {
      final list = snapshot.docs
          .map((doc) => StoreModel.fromMap(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
      list.sort((a, b) => (b.submittedAt ?? b.updatedAt).compareTo(a.submittedAt ?? a.updatedAt));
      return list;
    });
  }

  /// Tải tệp phương tiện (Avatar, Bìa, Giấy tờ) gian hàng lên Firebase Storage an toàn
  Future<String> uploadStoreMedia({
    required String ownerId,
    required XFile file,
    required String type, // 'avatar' | 'cover' | 'doc'
  }) async {
    final attemptId = DateTime.now().millisecondsSinceEpoch.toString().substring(7);
    final isAuthenticated = ownerId.isNotEmpty;

    debugPrint('[StorageDebug] Attempt #$attemptId - Stage 1: AuthCheck (isAuth=$isAuthenticated), Type=$type, FileName=${file.name}');

    if (!isAuthenticated) {
      throw Exception('Thông tin người dùng không hợp lệ hoặc chưa đăng nhập.');
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final sanitizedFileName = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');

    late final String path;
    if (type == 'avatar') {
      path = 'stores/$ownerId/avatar_$timestamp.jpg';
    } else if (type == 'cover') {
      path = 'stores/$ownerId/cover_$timestamp.jpg';
    } else {
      path = 'stores/$ownerId/docs/${timestamp}_$sanitizedFileName';
    }

    final bytes = await file.readAsBytes();
    final metadata = SettableMetadata(
      contentType: file.mimeType ?? (path.endsWith('.png') ? 'image/png' : 'image/jpeg'),
    );

    debugPrint('[StorageDebug] Attempt #$attemptId - Stage 2: TargetBucket="${_storage.bucket}", Path="$path", Size=${bytes.length} bytes, Mime=${metadata.contentType}');

    TaskSnapshot snapshot;
    try {
      final storageRef = _storage.ref().child(path);
      final uploadTask = PlatformMedia.uploadToFirebaseStorage(
        reference: storageRef,
        file: file,
        metadata: metadata,
      );
      snapshot = await uploadTask;
      debugPrint('[StorageDebug] Attempt #$attemptId - Stage 3: Primary bucket upload completed.');
    } catch (e) {
      debugPrint('[StorageDebug] Attempt #$attemptId - Stage 3: Primary bucket upload failed ($e). Trying fallback bucket gs://mytiktokclone-f9789.appspot.com...');
      try {
        final fallbackStorage = FirebaseStorage.instanceFor(bucket: 'gs://mytiktokclone-f9789.appspot.com');
        final fallbackRef = fallbackStorage.ref().child(path);
        final uploadTask = fallbackRef.putData(bytes, metadata);
        snapshot = await uploadTask;
        debugPrint('[StorageDebug] Attempt #$attemptId - Stage 3: Fallback bucket upload completed.');
      } catch (fallbackError) {
        if (fallbackError is FirebaseException) {
          debugPrint('[StorageDebug] Attempt #$attemptId - Stage 3: Fallback FirebaseException code=${fallbackError.code}, msg=${fallbackError.message}');
        } else {
          debugPrint('[StorageDebug] Attempt #$attemptId - Stage 3: Fallback general error: $fallbackError');
        }
        rethrow;
      }
    }

    debugPrint('[StorageDebug] Attempt #$attemptId - Stage 4: Querying getDownloadURL...');
    try {
      final downloadUrl = await snapshot.ref.getDownloadURL();
      debugPrint('[StorageDebug] Attempt #$attemptId - Stage 5: Success! Download URL retrieved.');
      return downloadUrl;
    } catch (urlError) {
      if (urlError is FirebaseException) {
        debugPrint('[StorageDebug] Attempt #$attemptId - Stage 5: getDownloadURL FirebaseException code=${urlError.code}, msg=${urlError.message}');
      } else {
        debugPrint('[StorageDebug] Attempt #$attemptId - Stage 5: getDownloadURL error: $urlError');
      }
      rethrow;
    }
  }

  /// Lưu bản nháp hồ sơ đăng ký gian hàng
  Future<String> saveStoreDraft(StoreModel store) async {
    final docRef = store.storeId.isNotEmpty
        ? _firestore.collection('stores').doc(store.storeId)
        : _firestore.collection('stores').doc();

    final now = DateTime.now().millisecondsSinceEpoch;
    final map = store.toMap();
    map['storeId'] = docRef.id;
    map['status'] = 'draft';
    map['updatedAt'] = now;
    if (store.createdAt == 0) map['createdAt'] = now;

    await docRef.set(map, SetOptions(merge: true));
    return docRef.id;
  }

  /// Gửi hồ sơ đăng ký gian hàng lên chờ xét duyệt (pending)
  Future<String> submitStoreRegistration(StoreModel store) async {
    final docRef = store.storeId.isNotEmpty
        ? _firestore.collection('stores').doc(store.storeId)
        : _firestore.collection('stores').doc();

    final docSnap = await docRef.get();
    int newVersion = 1;
    if (docSnap.exists) {
      final currentVer = (docSnap.data()?['version'] as num?)?.toInt() ?? 1;
      final currentStatus = docSnap.data()?['status'] as String? ?? 'draft';
      if (currentStatus == 'needs_changes' || currentStatus == 'rejected') {
        newVersion = currentVer + 1;
      } else {
        newVersion = currentVer;
      }
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final map = store.toMap();
    map['storeId'] = docRef.id;
    map['status'] = 'pending';
    map['version'] = newVersion;
    map['submittedAt'] = now;
    map['rejectionReason'] = null;
    map['updatedAt'] = now;
    if (store.createdAt == 0) map['createdAt'] = now;

    await docRef.set(map, SetOptions(merge: true));
    return docRef.id;
  }

  /// Admin xét duyệt hồ sơ gian hàng (Transaction với kiểm tra phiên bản & chống tự duyệt)
  Future<void> reviewStoreRegistration({
    required String storeId,
    required int expectedVersion,
    required String action, // 'approved' | 'needs_changes' | 'rejected'
    required String reviewerId,
    required String reviewerName,
    required String reason,
    String internalNote = '',
  }) async {
    if (storeId.isEmpty || reviewerId.isEmpty) {
      throw Exception('Thông tin không hợp lệ để thực hiện xét duyệt.');
    }

    final docRef = _firestore.collection('stores').doc(storeId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) {
        throw Exception('Hồ sơ gian hàng không tồn tại.');
      }

      final data = snapshot.data()!;
      final ownerId = data['ownerId'] as String? ?? '';
      final currentVersion = (data['version'] as num?)?.toInt() ?? 1;

      // 1. Chặn tự phê duyệt hồ sơ của chính mình
      if (reviewerId == ownerId) {
        throw Exception('Quản trị viên không thể tự phê duyệt hồ sơ gian hàng của chính mình.');
      }

      // 2. Kiểm tra xung đột phiên bản
      if (currentVersion != expectedVersion) {
        throw Exception('Phiên bản hồ sơ đã thay đổi (v$currentVersion). Không thể xét duyệt phiên bản cũ v$expectedVersion.');
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final existingAuditList = (data['auditHistory'] as List<dynamic>?)
              ?.map((e) => StoreAuditLog.fromMap(e as Map<String, dynamic>))
              .toList() ??
          <StoreAuditLog>[];

      final newAuditEntry = StoreAuditLog(
        version: currentVersion,
        status: action,
        reviewerId: reviewerId,
        reviewerName: reviewerName,
        reason: reason,
        internalNote: internalNote,
        timestamp: now,
      );

      existingAuditList.add(newAuditEntry);

      final updates = <String, dynamic>{
        'status': action,
        'rejectionReason': action == 'approved' ? null : reason,
        'reviewedBy': reviewerId,
        'reviewedByName': reviewerName,
        'reviewedAt': now,
        'updatedAt': now,
        'auditHistory': existingAuditList.map((a) => a.toMap()).toList(),
      };

      transaction.update(docRef, updates);
    });
  }

  /// Cập nhật thông tin gian hàng đã được duyệt
  Future<void> updateStoreSettings(String storeId, Map<String, dynamic> data) async {
    data['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    await _firestore.collection('stores').doc(storeId).update(data);
  }
}
