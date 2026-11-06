// ignore_for_file: prefer_initializing_formals

import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';

import '../../../core/constants/app_constants.dart';
import '../models/video_model.dart';
import '../models/ad_model.dart';
import '../services/recsys_service.dart';

/// Repository xử lý logic liên quan đến Video (feed, like, view count, sở thích)
/// Port từ VideoFragment.java, VideoAdapter.java, RecommendationHelper.java
class VideoRepository {
  final FirebaseFirestore _firestore;
  final FirebaseDatabase _database;
  final RecSysService? _recsysService;

  VideoRepository({
    required FirebaseFirestore firestore,
    required FirebaseDatabase database,
    RecSysService? recsysService,
  })  : _firestore = firestore,
        _database = database,
        _recsysService = recsysService;

  /// Lấy danh sách video được đề xuất (phân tích dựa trên tương tác, watch time và lịch sử tìm kiếm)
  Future<List<VideoModel>> getRecommendedVideos(String? currentUid) async {
    // 0. ƯU TIÊN 1: Lấy danh sách video từ Colab AI RecSys Server (nếu đang hoạt động)
    if (_recsysService != null) {
      final watchedIds = currentUid != null ? await getWatchedVideoIds(currentUid) : <String>[];
      final aiVideos = await _recsysService.getRecommendations(
        userId: currentUid,
        limit: AppConstants.videoFeedLimit,
        excludeVideoIds: watchedIds,
      );
      if (aiVideos != null && aiVideos.isNotEmpty) {
        return aiVideos;
      }
    }

    // 1. DỰ PHÒNG: Thuật toán Firestore truyền thống khi RecSys chưa bật hoặc lỗi mạng
    final snapshot = await _firestore
        .collection(AppConstants.videosCollection)
        .orderBy('timestamp', descending: true)
        .limit(500) // Tăng limit để đảm bảo có đủ video
        .get();

    final allVideos = snapshot.docs
        .map((doc) => VideoModel.fromMap(doc.data(), doc.id))
        .where((v) => v.moderationStatus.trim().toLowerCase() == 'approved')
        .toList();

    // 1. NGƯỜI DÙNG CHƯA ĐĂNG NHẬP: Trả về ngẫu nhiên để test và đa dạng
    if (currentUid == null) {
      allVideos.shuffle();
      return allVideos.take(AppConstants.videoFeedLimit).toList();
    }

    // 2. NGƯỜI DÙNG ĐÃ ĐĂNG NHẬP
    // 2.1. Lấy lịch sử video đã xem
    final watchedIds = await getWatchedVideoIds(currentUid);

    // 2.2. Lấy sở thích người dùng (top tags)
    final topInterests = await getTopInterests(currentUid, limit: 15);

    // 2.3. Lọc bỏ video đã xem (chỉ áp dụng cho For You để luôn mới mẻ)
    final unwatchedVideos = allVideos
        .where((v) => !watchedIds.contains(v.videoId))
        .toList();

    // TÀI KHOẢN MỚI (Chưa xem gì hoặc chưa có sở thích)
    if (watchedIds.isEmpty || topInterests.isEmpty) {
      allVideos.shuffle(); // Trộn ngẫu nhiên để đề xuất đa dạng ban đầu
      return allVideos.take(AppConstants.videoFeedLimit).toList();
    }

    // TÀI KHOẢN CÓ SỞ THÍCH: Rank theo thuật toán
    // Nếu hết video chưa xem, trộn ngẫu nhiên tất cả video cũ để lặp lại vô tận
    if (unwatchedVideos.isEmpty) {
      allVideos.shuffle();
      return allVideos.take(AppConstants.videoFeedLimit).toList();
    }

    // 4. Tính toán điểm số và sắp xếp
    return _rankVideos(unwatchedVideos, topInterests);
  }

  /// Lấy danh sách video thuộc Lâm Đồng bằng heuristic từ khóa trên caption, hashtag và
  /// trường location (không chạy OCR/ASR/nhận dạng ảnh; xem _calculateLamDongScore).
  Future<List<VideoModel>> getLamDongVideos(String? currentUid) async {
    final snapshot = await _firestore
        .collection(AppConstants.videosCollection)
        .orderBy('timestamp', descending: true)
        .limit(400) // Tăng limit cho mục Lâm Đồng
        .get();

    final allVideos = snapshot.docs
        .map((doc) => VideoModel.fromMap(doc.data(), doc.id))
        .where((v) => v.moderationStatus.trim().toLowerCase() == 'approved')
        .toList();

    // Chấm điểm từng video theo thuật toán 5 bước
    final lamDongVideos = allVideos.where((video) {
      return _calculateLamDongScore(video) >= 30; // Hạ thấp ngưỡng để dễ tìm thấy video hơn
    }).toList();

    // KHÔNG lọc bỏ video đã xem ở mục Lâm Đồng theo yêu cầu
    if (currentUid == null) {
      return _sortVideos(lamDongVideos);
    }

    final topInterests = await getTopInterests(currentUid, limit: 10);
    return _rankVideos(lamDongVideos, topInterests);
  }

  /// Chấm điểm video về Lâm Đồng bằng luật cộng điểm theo từ khóa (heuristic).
  /// Chỉ dùng văn bản có sẵn: description, hashtags, location. Không có OCR, ASR hay
  /// nhận dạng địa danh từ hình ảnh; các trường đó chưa tồn tại trong VideoModel.
  double _calculateLamDongScore(VideoModel video) {
    double score = 0;

    // Gom văn bản có sẵn của video (caption, hashtag, location).
    final String caption = video.description.toLowerCase();
    final List<String> hashtags = video.hashtags.map((h) => h.toLowerCase()).toList();

    final String combinedText = '$caption ${hashtags.join(' ')} ${video.location ?? ''}'.toLowerCase();

    // Tra từ điển địa danh trong văn bản (so khớp chuỗi con, không phải NER).
    const lamDongPlaces = [
      // Tỉnh & Thành phố
      'lâm đồng', 'lamdong', 'đà lạt', 'dalat', 'bảo lộc', 'baoloc',
      // Phường tại Đà Lạt
      'Xuân Hương','xuanhuong','Cam Ly','camly','Lâm Viên','lamvien','Xuân Trường','xuantruong','lang biang', 'langbiang',
      // Huyện & Xã (Đức Trọng)
      'đức trọng', 'ductrong', 'liên nghĩa', 'liennghia', 'hiệp an', 'hiepan',
      'hiệp thạnh', 'hiepthanh', 'liên hiệp', 'lienhiep', 'phú hội', 'phuhoi',
      'tân hội', 'tanhoi', 'tân thành', 'tanthanh', 'bình thạnh', 'binhthanh',
      'n’thôn hạ', 'nthonha', 'ninh gia', 'ninhgia', 'ninh loan', 'ninhloan',
      'đà loan', 'daloan', 'tà hine', 'tahine', 'tà năng', 'tanang', 'đa quyn', 'daquyn',
      // Đơn Dương
      'đơn dương', 'don duong', 'đonduong', 'ka đô', 'kado', 'quảng lập', 'quanglap',
      'd\'ran', 'dran', 'thạnh mỹ', 'thanhmy', 'đạ ròn', 'daron', 'tu tra', 'tutra',
      'lạc lâm', 'laclam', 'ka đơn', 'kadon', 'pró', 'pro', 'lạc xuân', 'lacxuan',
      // Lâm Hà
      'lâm hà', 'lam ha', 'nam ban', 'namban', 'đinh văn', 'dinhvan', 'phi tô', 'phito',
      'nam hà', 'namha', 'gia lâm', 'gialam', 'đông thanh', 'dongthanh',
      // Di Linh
      'di linh', 'dilinh', 'gia hiệp', 'giahiep', 'hòa ninh', 'hoaninh', 'đinh trang thượng',
      'bảo thuận', 'baothuan', 'sơn điền', 'sondien',
      // Đam Rông & các huyện khác
      'đam rông', 'damrong', 'đạ huoai', 'dahuoai', 'đạ tẻh', 'dateh', 'cát tiên', 'cattien', 'bảo lâm', 'baolam',
      // Địa danh nổi tiếng
      'hồ xuân hương','hoxuanhuong', 'prenn', 'mimosa', 'trại mát','traimat', 'cầu đất','caudat',
      'vạn thành','vanthanh', 'tà nung','tanung', 'phi nôm','phinom', 'ka đô','kado'
    ];

    bool hasPlaceMatch = false;
    for (final place in lamDongPlaces) {
      if (combinedText.contains(place)) {
        hasPlaceMatch = true;
        break;
      }
    }
    if (hasPlaceMatch) score += 50;

    // Các hashtag huyện lỵ đặc trưng (+40 điểm)
    final districtTags = [
      'ductrong', 'lienneghia', 'dalat', 'lamdong', 'dilinh', 'baoloc',
      'donduong', 'lacduong', 'damrong', 'cattien', 'baolam'
    ];
    if (hashtags.any((h) {
      final cleanH = h.replaceAll('#', '').toLowerCase();
      return districtTags.contains(cleanH);
    })) {
      score += 40;
    }

    // Cộng điểm theo từng luật từ khóa

    // 1. Caption có "Đà Lạt" hoặc "Đức Trọng" (+40)
    if (caption.contains('đà lạt') || caption.contains('đức trọng') || caption.contains('liên nghĩa')) {
      score += 40;
    }

    // 2. Hashtag #lamdong (+30)
    if (hashtags.any((h) => h.contains('lamdong') || h.contains('lam-dong'))) score += 30;

    // 2b. Hashtag #langbiang (+50)
    if (hashtags.any((h) => h.contains('langbiang') || h.contains('lang-biang'))) score += 50;

    // 3. Nhắc đến địa danh không dấu trong text (+35)
    if (combinedText.contains('duc trong') || combinedText.contains('lien nghia') || combinedText.contains('bao loc')) {
      score += 35;
    }

    // 4. Văn bản nhắc "da lat" không dấu (+40)
    if (combinedText.contains('welcome to da lat') || combinedText.contains('da lat')) score += 40;

    // 5. Văn bản nhắc địa danh nổi tiếng (+50)
    if (combinedText.contains('quảng trường lâm viên') ||
        combinedText.contains('hồ xuân hương') ||
        combinedText.contains('lang biang')) {
      score += 50;
    }

    // 6. Trường location do người đăng nhập chứa Đà Lạt/Lâm Đồng (+100; không phải GPS)
    if (video.location?.toLowerCase().contains('da lat') == true ||
        video.location?.toLowerCase().contains('lâm đồng') == true) {
      score += 100;
    }

    return score;
  }

  /// Lấy danh sách video từ những người đang theo dõi, xếp mới nhất lên đầu
  /// Không lọc bỏ video đã xem theo yêu cầu
  Future<List<VideoModel>> getFollowingVideos(String currentUid) async {
    if (currentUid.isEmpty) return [];

    try {
      // 1. Lấy danh sách UID đang follow
      final followingSnap = await _firestore
          .collection(AppConstants.profilesCollection)
          .doc(currentUid)
          .collection('following')
          .get();

      final followingIds = followingSnap.docs
          .map((doc) => doc.id)
          .where((id) => id != 'dump')
          .toList();

      if (followingIds.isEmpty) {
        print('DEBUG: No following IDs found for user $currentUid');
        return [];
      }
      print('DEBUG: Found following IDs: $followingIds');

      // 2. Lấy video từ những người này (Firestore whereIn giới hạn 30 items)
      // BỎ orderBy ĐỂ TRÁNH YÊU CẦU INDEX PHỨC TẠP
      final snapshot = await _firestore
          .collection(AppConstants.videosCollection)
          .where('authorId', whereIn: followingIds.take(30).toList())
          .limit(100)
          .get();

      print('DEBUG: Found ${snapshot.docs.length} videos from following');

      final videos = snapshot.docs
          .map((doc) => VideoModel.fromMap(doc.data(), doc.id))
          .where((v) => v.moderationStatus.trim().toLowerCase() == 'approved')
          .toList();

      // Sắp xếp thủ công in-memory theo thời gian giảm dần (mới nhất lên đầu)
      videos.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      return videos;
    } catch (e) {
      print('DEBUG: Error in getFollowingVideos: $e');
      return [];
    }
  }

  List<VideoModel> _sortVideos(List<VideoModel> list) {
    final sorted = List<VideoModel>.from(list);
    sorted.sort((a, b) {
      final aIsCampaign = a.location == 'Da Lat' ||
          a.hashtags.any((tag) => const ['dalat', 'dalatdulich', 'khamphadalat']
              .contains(tag.toLowerCase().replaceAll('#', '')));
      final bIsCampaign = b.location == 'Da Lat' ||
          b.hashtags.any((tag) => const ['dalat', 'dalatdulich', 'khamphadalat']
              .contains(tag.toLowerCase().replaceAll('#', '')));

      if (aIsCampaign && !bIsCampaign) return -1;
      if (!aIsCampaign && bIsCampaign) return 1;
      return b.timestamp.compareTo(a.timestamp);
    });
    return sorted;
  }

  List<VideoModel> _rankVideos(List<VideoModel> videos, List<String> topInterests) {
    final ranked = List<VideoModel>.from(videos);
    ranked.sort((a, b) {
      double scoreA = _calculateVideoScore(a, topInterests);
      double scoreB = _calculateVideoScore(b, topInterests);
      return scoreB.compareTo(scoreA);
    });
    return ranked.take(AppConstants.videoFeedLimit).toList();
  }

  double _calculateVideoScore(VideoModel video, List<String> topInterests) {
    double score = 0;

    // 1. Tag Match (Hợp sở thích)
    for (final tag in video.hashtags) {
      if (topInterests.contains(tag.toLowerCase().replaceAll('#', ''))) {
        score += 10.0;
      }
    }

    // 2. Recency (Độ mới) - Giảm dần theo thời gian (Max 5 điểm)
    final ageHours = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(video.timestamp)
    ).inHours;
    score += math.max(0, 5.0 - (ageHours / 24.0));

    // 3. Popularity (Độ hot)
    score += (video.watchCount / 1000.0).clamp(0.0, 5.0);
    score += (video.totalLikes / 100.0).clamp(0.0, 5.0);

    // 4. Campaign priority (Đà Lạt)
    final isCampaign = video.location == 'Da Lat' ||
        video.hashtags.any((tag) => const ['dalat', 'dalatdulich', 'khamphadalat']
            .contains(tag.toLowerCase().replaceAll('#', '')));
    if (isCampaign) score += 3.0;

    return score;
  }

  /// Bật/Tắt thích video (Like/Unlike)
  /// Port từ VideoAdapter.VideoViewHolder.toggleLikeLocal()
  Future<void> toggleLike({
    required String videoId,
    required String authorId,
    required String currentUid,
    required bool isLiked,
    required String currentUsername,
  }) async {
    final likeRef = _firestore.collection('likes').doc(videoId);
    final videoRef =
        _firestore.collection(AppConstants.videosCollection).doc(videoId);
    final profileRef =
        _firestore.collection(AppConstants.profilesCollection).doc(authorId);

    if (isLiked) {
      // 1. Cập nhật Firestore likes/{videoId}
      await likeRef.set({
        currentUid: true,
      }, SetOptions(merge: true));

      // 2. Tăng số like của video và profile tác giả
      await videoRef.update({
        'totalLikes': FieldValue.increment(1),
      });
      await profileRef.update({
        'likes': FieldValue.increment(1),
      });

      // 3. Ghi nhận sở thích (Like weight: 5)
      final videoDoc = await videoRef.get();
      if (videoDoc.exists) {
        final hashtags = (videoDoc.data()?['hashtags'] as List<dynamic>?)?.map((e) => e.toString()).toList();
        await recordInterest(
          tags: hashtags,
          currentUid: currentUid,
          weight: 5,
        );
      }

      // 4. Gửi thông báo Like qua RTDB
      final notifRef = _database
          .ref(AppConstants.notificationsPath)
          .child(authorId)
          .push();
      await notifRef.set({
        'fromUsername': currentUsername.isNotEmpty ? currentUsername : 'Ai đó',
        'action': AppConstants.actionLike,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'videoId': videoId,
      });
    } else {
      // 1. Xóa user khỏi Firestore likes/{videoId}
      await likeRef.update({
        currentUid: FieldValue.delete(),
      });

      // 2. Giảm số like của video và profile tác giả
      await videoRef.update({
        'totalLikes': FieldValue.increment(-1),
      });
      await profileRef.update({
        'likes': FieldValue.increment(-1),
      });
    }
  }

  /// Tăng lượt xem cho video (Watch Count)
  /// Port từ VideoAdapter.updateWatchCount()
  Future<void> incrementWatchCount({
    required String videoId,
    required String authorId,
  }) async {
    // 1. Tăng trong videos/{videoId}
    await _firestore
        .collection(AppConstants.videosCollection)
        .doc(videoId)
        .set({'watchCount': FieldValue.increment(1)}, SetOptions(merge: true));

    // 2. Tăng trong video_summaries/{videoId} (an toàn với set+merge để không crash nếu chưa tồn tại)
    await _firestore
        .collection('video_summaries')
        .doc(videoId)
        .set({'watchCount': FieldValue.increment(1)}, SetOptions(merge: true));

    // 3. Tăng trong profiles/{authorId}/public_videos/{videoId}
    await _firestore
        .collection(AppConstants.profilesCollection)
        .doc(authorId)
        .collection('public_videos')
        .doc(videoId)
        .set({'watchCount': FieldValue.increment(1)}, SetOptions(merge: true));
  }

  /// Ghi nhận sở thích xem video thông qua phân tách hashtag hoặc tags trực tiếp
  /// weight: trọng số ảnh hưởng (Like: 5, Comment: 3, Search: 2, Watch: 1)
  Future<void> recordInterest({
    String? description,
    List<String>? tags,
    required String currentUid,
    int weight = 1,
  }) async {
    if (currentUid.isEmpty) return;

    final Set<String> hashtags = {};
    if (description != null && description.isNotEmpty) {
      final regex = RegExp(r'#([A-Za-z0-9_\u00C0-\u1EF9-]+)');
      final matches = regex.allMatches(description);
      hashtags.addAll(matches.map((m) => m.group(1)!.toLowerCase()));
    }
    if (tags != null) {
      hashtags.addAll(tags.map((t) => t.toLowerCase().replaceAll('#', '')));
    }

    if (hashtags.isEmpty) return;

    final batch = _firestore.batch();
    for (final tag in hashtags) {
      final tagRef = _firestore
          .collection(AppConstants.userInterestsCollection)
          .doc(currentUid)
          .collection('tags')
          .doc(tag);

      batch.set(
        tagRef,
        {
          'count': FieldValue.increment(weight),
          'lastUpdated': DateTime.now().millisecondsSinceEpoch,
        },
        SetOptions(merge: true),
      );
    }

    await batch.commit();
  }

  /// Lấy danh sách tags người dùng quan tâm nhất
  Future<List<String>> getTopInterests(String currentUid, {int limit = 3}) async {
    if (currentUid.isEmpty) return [];

    final snapshot = await _firestore
        .collection(AppConstants.userInterestsCollection)
        .doc(currentUid)
        .collection('tags')
        .orderBy('count', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs.map((doc) => doc.id).toList();
  }

  /// Đánh dấu video đã xem
  Future<void> markVideoAsWatched(String userId, String videoId) async {
    if (userId.isEmpty || videoId.isEmpty) return;

    await _firestore
        .collection(AppConstants.profilesCollection)
        .doc(userId)
        .collection('watched_videos')
        .doc(videoId)
        .set({
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Lấy danh sách ID video đã xem
  Future<List<String>> getWatchedVideoIds(String userId) async {
    if (userId.isEmpty) return [];

    final snapshot = await _firestore
        .collection(AppConstants.profilesCollection)
        .doc(userId)
        .collection('watched_videos')
        .limit(500)
        .get();

    return snapshot.docs.map((doc) => doc.id).toList();
  }

  /// Stream số lượng like và trạng thái like của người dùng hiện tại
  Stream<Map<String, dynamic>> watchLikesState(String videoId) {
    return _firestore.collection('likes').doc(videoId).snapshots().map((doc) {
      if (!doc.exists) return {'count': 0, 'users': <String, bool>{}};
      final data = doc.data() ?? {};
      int count = 0;
      data.forEach((key, value) {
        if (value == true) count++;
      });
      return {
        'count': count,
        'users': Map<String, bool>.from(data),
      };
    });
  }

  /// Xóa video khỏi Firestore và các collection liên quan (likes, comments, summaries, public_videos)
  /// Port từ DeleteVideoSettingActivity.java
  Future<void> deleteVideo({
    required String videoId,
    required String authorId,
  }) async {
    final batch = _firestore.batch();

    // 1. Tìm và xóa các hashtag liên quan đến videoId này
    final hashtagsQuery = await _firestore
        .collection('hashtags')
        .where('videoId', isEqualTo: videoId)
        .get();
    for (final doc in hashtagsQuery.docs) {
      batch.delete(doc.reference);
    }

    // 2. Xóa các tài liệu chính của video
    batch.delete(_firestore.collection(AppConstants.videosCollection).doc(videoId));
    batch.delete(_firestore.collection('video_summaries').doc(videoId));
    batch.delete(_firestore
        .collection(AppConstants.profilesCollection)
        .doc(authorId)
        .collection('public_videos')
        .doc(videoId));

    // 3. Xóa likes và comments liên kết
    batch.delete(_firestore.collection('likes').doc(videoId));
    // NOTE: Comments được lưu theo videoId field nên phải query trước
    final commentsQuery = await _firestore
        .collection('comments')
        .where('videoId', isEqualTo: videoId)
        .get();
    for (final doc in commentsQuery.docs) {
      batch.delete(doc.reference);
    }

    // Thực hiện batch write
    await batch.commit();
  }

  /// Theo dõi danh sách video quảng cáo từ Firestore (chỉ lấy quảng cáo đang hoạt động)
  Stream<List<AdModel>> watchAds() {
    return _firestore.collection('ads').snapshots().map((snapshot) {
      final now = DateTime.now().millisecondsSinceEpoch;
      return snapshot.docs
          .map((doc) => AdModel.fromMap(doc.data(), doc.id))
          .where((ad) {
            return ad.status == 'active' &&
                ad.startDate <= now &&
                ad.endDate >= now;
          })
          .toList();
    });
  }

  /// Ghi nhận lượt xem cho chiến dịch quảng bá Đà Lạt
  Future<void> recordCampaignView(String videoId) async {
    final docRef = _firestore.collection('campaign_analytics').doc(videoId);
    await docRef.set({
      'videoId': videoId,
      'campaign': 'dalat',
      'views': FieldValue.increment(1),
    }, SetOptions(merge: true));
  }

  /// Ghi nhận lượt click vào badge/hashtag chiến dịch Đà Lạt
  Future<void> recordCampaignClick(String videoId) async {
    final docRef = _firestore.collection('campaign_analytics').doc(videoId);
    await docRef.set({
      'videoId': videoId,
      'campaign': 'dalat',
      'clicks': FieldValue.increment(1),
    }, SetOptions(merge: true));
  }

  /// Ghi nhận lượt hiển thị quảng cáo (Impression)
  Future<void> logAdImpression({required String adId, required String userId}) async {
    await _firestore.collection('ad_impressions').add({
      'adId': adId,
      'userId': userId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Ghi nhận lượt xem quảng cáo trên 2 giây (View)
  Future<void> logAdView({required String adId, required String userId, required int durationMs}) async {
    await _firestore.collection('ad_views').add({
      'adId': adId,
      'userId': userId,
      'durationMs': durationMs,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Ghi nhận lượt nhấp chuột quảng cáo (Click)
  Future<void> logAdClick({required String adId, required String userId}) async {
    await _firestore.collection('ad_clicks').add({
      'adId': adId,
      'userId': userId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Ghi nhận hành vi tương tác video ngắn (xem >= 3s hoặc like tim) lên máy chủ Colab RecSys
  void logRecSysInteraction({
    required String? userId,
    required String videoId,
    required int playTimeMs,
    required bool isLike,
  }) {
    _recsysService?.logInteraction(
      userId: userId,
      videoId: videoId,
      playTimeMs: playTimeMs,
      isLike: isLike,
    );
  }
}
