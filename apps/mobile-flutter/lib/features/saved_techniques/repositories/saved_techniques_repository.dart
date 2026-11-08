import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../video_feed/models/video_model.dart';

final savedTechniquesRepositoryProvider = Provider<SavedTechniquesRepository>((ref) {
  return SavedTechniquesRepository(
    firestore: ref.watch(firestoreProvider),
  );
});

final savedTechniquesStreamProvider = StreamProvider.family<List<VideoModel>, String>((ref, userId) {
  return ref.watch(savedTechniquesRepositoryProvider).watchSavedTechniques(userId);
});

final isTechniqueSavedProvider = StreamProvider.family<bool, ({String userId, String videoId})>((ref, arg) {
  return ref.watch(savedTechniquesRepositoryProvider).watchIsSaved(arg.userId, arg.videoId);
});

/// Repository quản lý Kho Kỹ Thuật (Lưu video bài học / kỹ thuật nông nghiệp)
class SavedTechniquesRepository {
  final FirebaseFirestore _firestore;

  SavedTechniquesRepository({required this._firestore});

  /// Stream danh sách ID kỹ thuật đã lưu
  Stream<List<VideoModel>> watchSavedTechniques(String userId) {
    if (userId.isEmpty) return Stream.value([]);
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('saved_techniques')
        .orderBy('savedAt', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
      final videoIds = snapshot.docs.map((doc) => doc.id).toList();
      if (videoIds.isEmpty) return [];

      final List<VideoModel> videos = [];
      for (final vId in videoIds) {
        final videoDoc = await _firestore.collection('videos').doc(vId).get();
        if (videoDoc.exists) {
          videos.add(VideoModel.fromMap(videoDoc.data()!, videoDoc.id));
        }
      }
      return videos;
    });
  }

  /// Check video đã được lưu hay chưa
  Stream<bool> watchIsSaved(String userId, String videoId) {
    if (userId.isEmpty || videoId.isEmpty) return Stream.value(false);
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('saved_techniques')
        .doc(videoId)
        .snapshots()
        .map((doc) => doc.exists);
  }

  /// Toggle lưu / bỏ lưu kỹ thuật (Lưu cả Firestore & SharedPreferences)
  Future<bool> toggleSaveTechnique({
    required String userId,
    required VideoModel video,
  }) async {
    if (userId.isEmpty) return false;

    final ref = _firestore
        .collection('users')
        .doc(userId)
        .collection('saved_techniques')
        .doc(video.videoId);

    final prefs = await SharedPreferences.getInstance();
    final localKey = 'saved_tech_${userId}_${video.videoId}';

    final doc = await ref.get();
    if (doc.exists) {
      await ref.delete();
      await prefs.setBool(localKey, false);
      return false; // đã bỏ lưu
    } else {
      await ref.set({
        'videoId': video.videoId,
        'title': video.description,
        'crop': video.crop,
        'growthStage': video.growthStage,
        'savedAt': DateTime.now().millisecondsSinceEpoch,
      });
      await prefs.setBool(localKey, true);
      return true; // đã lưu
    }
  }
}
