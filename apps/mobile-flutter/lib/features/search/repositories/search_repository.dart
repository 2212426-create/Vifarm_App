import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/text_utils.dart';
import '../../auth/models/profile_model.dart';
import '../../video_feed/models/video_model.dart';

/// Repository thực hiện các truy vấn tìm kiếm người dùng, video, hashtag và 7-day trending
class SearchRepository {
  final FirebaseFirestore _firestore;

  SearchRepository({
    required this._firestore,
  });

  /// Tìm kiếm người dùng theo username/fullname (Hỗ trợ tiếng Việt không dấu)
  Future<List<ProfileModel>> searchUsers(String key) async {
    final cleanKey = TextUtils.removeDiacritics(key);
    if (cleanKey.isEmpty) return [];

    final snapshot = await _firestore
        .collection(AppConstants.profilesCollection)
        .limit(30)
        .get();

    return snapshot.docs
        .map((doc) => ProfileModel.fromMap(doc.data()))
        .where((profile) {
          final normUsername = TextUtils.removeDiacritics(profile.username);
          final normFullname = TextUtils.removeDiacritics(profile.fullname);
          return normUsername.contains(cleanKey) || normFullname.contains(cleanKey);
        })
        .take(15)
        .toList();
  }

  /// Tìm kiếm video theo mô tả, hashtag, cây trồng, chủ đề kỹ thuật (Chuẩn hóa tiếng Việt không dấu)
  Future<List<VideoModel>> searchVideos(String key) async {
    final cleanKey = TextUtils.removeDiacritics(key);
    if (cleanKey.isEmpty) return [];

    final snapshot = await _firestore
        .collection(AppConstants.videosCollection)
        .limit(100)
        .get();

    final allApproved = snapshot.docs
        .map((doc) => VideoModel.fromMap(doc.data(), doc.id))
        .where((v) => v.moderationStatus == 'approved' || v.isPublic)
        .toList();

    final matched = allApproved.where((video) {
      final normDesc = TextUtils.removeDiacritics(video.description);
      final normCrop = TextUtils.removeDiacritics(video.crop ?? '');
      final normStage = TextUtils.removeDiacritics(video.growthStage ?? '');
      final normTopic = TextUtils.removeDiacritics(video.technicalTopic ?? '');
      final normUser = TextUtils.removeDiacritics(video.username);

      final matchesHashtag = video.hashtags.any((tag) {
        final normTag = TextUtils.normalizeHashtag(tag);
        return normTag.contains(cleanKey);
      });

      return normDesc.contains(cleanKey) ||
          normCrop.contains(cleanKey) ||
          normStage.contains(cleanKey) ||
          normTopic.contains(cleanKey) ||
          normUser.contains(cleanKey) ||
          matchesHashtag;
    }).toList();

    // Sắp xếp ưu tiên độ liên quan (tên cây trồng / hashtag khớp chính xác lên đầu)
    matched.sort((a, b) {
      final aCropExact = TextUtils.removeDiacritics(a.crop ?? '') == cleanKey ? 1 : 0;
      final bCropExact = TextUtils.removeDiacritics(b.crop ?? '') == cleanKey ? 1 : 0;
      if (aCropExact != bCropExact) return bCropExact.compareTo(aCropExact);
      return b.timestamp.compareTo(a.timestamp);
    });

    return matched.take(20).toList();
  }

  /// Tải các video THỊNH HÀNH 7 NGẦN NHẤT (dựa trên thời gian 7 ngày & tương tác thực tế)
  Future<List<VideoModel>> loadTrendingVideos() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final sevenDaysAgo = now - (7 * 86400 * 1000);

    final snapshot = await _firestore
        .collection(AppConstants.videosCollection)
        .limit(150)
        .get();

    final approved = snapshot.docs
        .map((doc) => VideoModel.fromMap(doc.data(), doc.id))
        .where((v) => v.moderationStatus == 'approved' || v.isPublic)
        .toList();

    // Lọc video trong cửa sổ 7 ngày
    final recentVideos = approved.where((v) => v.timestamp >= sevenDaysAgo).toList();

    final listToRank = recentVideos.isNotEmpty ? recentVideos : approved;

    // Tính điểm thịnh hành 7 ngày: watchCount + likes * 2 + comments * 3 + recency decay
    listToRank.sort((a, b) {
      final scoreA = a.watchCount + (a.totalLikes * 2) + (a.totalComments * 3);
      final scoreB = b.watchCount + (b.totalLikes * 2) + (b.totalComments * 3);
      return scoreB.compareTo(scoreA);
    });

    return listToRank.take(20).toList();
  }

  /// Thu thập các hashtag thịnh hành thực tế từ các video 7 ngày gần nhất
  Future<List<String>> loadTrendingTags() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final sevenDaysAgo = now - (7 * 86400 * 1000);

    final snapshot = await _firestore
        .collection(AppConstants.videosCollection)
        .limit(100)
        .get();

    final Map<String, int> tagCounts = {};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final ts = (data['timestamp'] as num?)?.toInt() ?? 0;
      if (ts < sevenDaysAgo) continue;

      final hashtags = data['hashtags'] as List<dynamic>?;
      if (hashtags != null) {
        final Set<String> seenInDoc = {};
        for (final tag in hashtags) {
          final normTag = TextUtils.normalizeHashtag(tag.toString());
          if (normTag.isNotEmpty && !seenInDoc.contains(normTag)) {
            seenInDoc.add(normTag);
            tagCounts[normTag] = (tagCounts[normTag] ?? 0) + 1;
          }
        }
      }
    }

    final sortedEntries = tagCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final result = sortedEntries.map((e) => '#${e.key}').take(10).toList();

    if (result.isEmpty) {
      return ['#saurien', '#lamdong', '#nongnghiep', '#caphe', '#phantron'];
    }

    return result;
  }
}
