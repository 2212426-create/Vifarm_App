import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/media/platform_media.dart';
import '../../auth/models/profile_model.dart';
import '../../video_feed/models/video_summary_model.dart';

/// Repository xử lý thông tin hồ sơ, chỉnh sửa avatar/bio/username, theo dõi (follow/unfollow)
class ProfileRepository {
  final FirebaseFirestore _firestore;
  final FirebaseDatabase _database;
  final FirebaseStorage _storage;

  // In-memory set để khóa các thao tác follow đang chờ xử lý (chống spam / double tap)
  final Set<String> _pendingFollowLocks = {};

  ProfileRepository({
    required this._firestore,
    required this._database,
    required this._storage,
  });

  Future<ProfileModel?> getProfile(String uid) async {
    final doc = await _firestore
        .collection(AppConstants.profilesCollection)
        .doc(uid)
        .get();

    if (!doc.exists || doc.data() == null) return null;
    return ProfileModel.fromMap(doc.data()!);
  }

  Stream<ProfileModel?> watchProfile(String uid) {
    return _firestore
        .collection(AppConstants.profilesCollection)
        .doc(uid)
        .snapshots()
        .map((doc) {
          if (!doc.exists || doc.data() == null) return null;
          return ProfileModel.fromMap(doc.data()!);
        });
  }

  Future<void> updateBio(String uid, String bio) async {
    await _firestore
        .collection(AppConstants.profilesCollection)
        .doc(uid)
        .update({'bio': bio});
  }

  Future<String> updateAvatar(String uid, XFile file) async {
    final storageRef = _storage.ref().child('avatars').child('$uid.jpg');

    final uploadTask = await PlatformMedia.uploadToFirebaseStorage(
      reference: storageRef,
      file: file,
      metadata: SettableMetadata(contentType: file.mimeType ?? 'image/jpeg'),
    );
    final downloadUrl = await uploadTask.ref.getDownloadURL();

    await _firestore
        .collection(AppConstants.profilesCollection)
        .doc(uid)
        .update({
          'avatar': downloadUrl,
          'avatarUrl': downloadUrl,
        });

    await _firestore.collection(AppConstants.usersCollection).doc(uid).update({
      'avatar': downloadUrl,
      'avatarUrl': downloadUrl,
    });

    return downloadUrl;
  }

  Future<bool> updateUsername({
    required String uid,
    required String newUsername,
  }) async {
    final checkQuery = await _firestore
        .collection(AppConstants.usersCollection)
        .where('username', isEqualTo: newUsername)
        .get();

    for (final doc in checkQuery.docs) {
      if (doc.id != uid) {
        return false;
      }
    }

    await _firestore.collection(AppConstants.usersCollection).doc(uid).update({
      'username': newUsername,
    });

    await _firestore
        .collection(AppConstants.profilesCollection)
        .doc(uid)
        .update({'username': newUsername});

    final videosQuery = await _firestore
        .collection(AppConstants.videosCollection)
        .where('authorId', isEqualTo: uid)
        .get();

    if (videosQuery.docs.isNotEmpty) {
      final batch = _firestore.batch();
      for (final doc in videosQuery.docs) {
        batch.update(doc.reference, {'username': newUsername});
      }
      await batch.commit();
    }

    return true;
  }

  Future<void> updateBirthdate({
    required String uid,
    required String birthdate,
  }) async {
    await _firestore.collection(AppConstants.usersCollection).doc(uid).update({
      'birthdate': birthdate,
    });

    await _firestore
        .collection(AppConstants.profilesCollection)
        .doc(uid)
        .update({'birthdate': birthdate});
  }

  Stream<List<VideoSummaryModel>> watchUserVideos(String uid) {
    return _firestore
        .collection(AppConstants.videosCollection)
        .where('authorId', isEqualTo: uid)
        .snapshots()
        .map((snapshot) {
          final docs = snapshot.docs.toList();
          docs.sort((a, b) {
            final aTime = (a.data()['timestamp'] as num?)?.toInt() ?? 0;
            final bTime = (b.data()['timestamp'] as num?)?.toInt() ?? 0;
            return bTime.compareTo(aTime);
          });

          final list = <VideoSummaryModel>[];
          final limitedDocs = docs.take(50);

          for (final doc in limitedDocs) {
            final data = doc.data();
            final modStatus = data['moderationStatus'] as String?;
            if (modStatus == 'rejected') continue;

            String thumb = data['thumbnailUri'] as String? ?? '';
            if (thumb.isEmpty) {
              thumb = data['thumbnailUrl'] as String? ?? '';
            }
            if (thumb.isEmpty) {
              final videoUri = data['videoUri'] as String? ?? '';
              if (videoUri.contains('cloudinary.com')) {
                thumb = videoUri.replaceAll('.mp4', '.jpg');
                if (thumb.contains('/upload/')) {
                  thumb = thumb.replaceAll('/upload/', '/upload/so_0/');
                }
              } else {
                thumb = 'https://picsum.photos/200/300';
              }
            }

            final vId = data['videoId'] as String? ?? '';
            list.add(
              VideoSummaryModel(
                videoId: vId.isNotEmpty ? vId : doc.id,
                thumbnailUri: thumb,
                watchCount: (data['watchCount'] as num?)?.toInt() ?? 0,
              ),
            );
          }
          return list;
        });
  }

  Stream<bool> watchFollowStatus({
    required String currentUid,
    required String targetUid,
  }) {
    if (currentUid.isEmpty || targetUid.isEmpty) return Stream.value(false);
    return _firestore
        .collection(AppConstants.profilesCollection)
        .doc(currentUid)
        .collection('following')
        .doc(targetUid)
        .snapshots()
        .map((doc) => doc.exists);
  }

  /// Theo dõi người dùng (Khóa chống double tap & rollback khi lỗi)
  Future<bool> followUser({
    required String currentUid,
    required String targetUid,
    required String currentUsername,
  }) async {
    if (currentUid.isEmpty || targetUid.isEmpty || currentUid == targetUid) return false;

    final lockKey = '${currentUid}_$targetUid';
    if (_pendingFollowLocks.contains(lockKey)) return false; // Khóa chống bấm liên tục
    _pendingFollowLocks.add(lockKey);

    try {
      await _firestore
          .collection(AppConstants.profilesCollection)
          .doc(currentUid)
          .collection('following')
          .doc(targetUid)
          .set({'userID': targetUid});

      await _firestore
          .collection(AppConstants.profilesCollection)
          .doc(targetUid)
          .collection('followers')
          .doc(currentUid)
          .set({'userID': currentUid});

      await syncFollowCounts(currentUid);
      await syncFollowCounts(targetUid);

      final notifRef = _database
          .ref(AppConstants.notificationsPath)
          .child(targetUid)
          .push();
      await notifRef.set({
        'fromUsername': currentUsername.isNotEmpty ? currentUsername : 'Ai đó',
        'action': AppConstants.actionFollow,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      return true;
    } catch (e) {
      // Rollback nếu lỗi server
      await unfollowUser(currentUid: currentUid, targetUid: targetUid);
      rethrow;
    } finally {
      _pendingFollowLocks.remove(lockKey);
    }
  }

  /// Bỏ theo dõi người dùng (Khóa chống double tap & rollback)
  Future<bool> unfollowUser({
    required String currentUid,
    required String targetUid,
  }) async {
    if (currentUid.isEmpty || targetUid.isEmpty) return false;

    final lockKey = '${currentUid}_$targetUid';
    if (_pendingFollowLocks.contains(lockKey)) return false;
    _pendingFollowLocks.add(lockKey);

    try {
      await _firestore
          .collection(AppConstants.profilesCollection)
          .doc(currentUid)
          .collection('following')
          .doc(targetUid)
          .delete();

      await _firestore
          .collection(AppConstants.profilesCollection)
          .doc(targetUid)
          .collection('followers')
          .doc(currentUid)
          .delete();

      await syncFollowCounts(currentUid);
      await syncFollowCounts(targetUid);

      return true;
    } finally {
      _pendingFollowLocks.remove(lockKey);
    }
  }

  /// Đồng bộ số lượng follow (đảm bảo số đếm không âm)
  Future<void> syncFollowCounts(String uid) async {
    if (uid.isEmpty) return;

    final followersSnap = await _firestore
        .collection(AppConstants.profilesCollection)
        .doc(uid)
        .collection('followers')
        .where(FieldPath.documentId, isNotEqualTo: 'dump')
        .count()
        .get();

    final followingSnap = await _firestore
        .collection(AppConstants.profilesCollection)
        .doc(uid)
        .collection('following')
        .where(FieldPath.documentId, isNotEqualTo: 'dump')
        .count()
        .get();

    final followersCount = (followersSnap.count ?? 0).clamp(0, 99999999);
    final followingCount = (followingSnap.count ?? 0).clamp(0, 99999999);

    await _firestore
        .collection(AppConstants.profilesCollection)
        .doc(uid)
        .update({'followers': followersCount, 'following': followingCount});
  }

  Future<List<ProfileModel>> getFollowers(String uid) async {
    final snap = await _firestore
        .collection(AppConstants.profilesCollection)
        .doc(uid)
        .collection('followers')
        .get();

    final ids = snap.docs
        .map((doc) => doc.id)
        .where((id) => id != 'dump')
        .toList();
    if (ids.isEmpty) return [];

    final profiles = <ProfileModel>[];
    for (var i = 0; i < ids.length; i += 10) {
      final chunk = ids.sublist(i, i + 10 > ids.length ? ids.length : i + 10);
      final querySnap = await _firestore
          .collection(AppConstants.profilesCollection)
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      profiles.addAll(
        querySnap.docs.map((doc) => ProfileModel.fromMap(doc.data())),
      );
    }
    return profiles;
  }

  Future<List<ProfileModel>> getFollowing(String uid) async {
    final snap = await _firestore
        .collection(AppConstants.profilesCollection)
        .doc(uid)
        .collection('following')
        .get();

    final ids = snap.docs
        .map((doc) => doc.id)
        .where((id) => id != 'dump')
        .toList();
    if (ids.isEmpty) return [];

    final profiles = <ProfileModel>[];
    for (var i = 0; i < ids.length; i += 10) {
      final chunk = ids.sublist(i, i + 10 > ids.length ? ids.length : i + 10);
      final querySnap = await _firestore
          .collection(AppConstants.profilesCollection)
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      profiles.addAll(
        querySnap.docs.map((doc) => ProfileModel.fromMap(doc.data())),
      );
    }
    return profiles;
  }
}
