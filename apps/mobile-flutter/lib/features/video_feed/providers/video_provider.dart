import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../core/constants/app_constants.dart';
import '../../auth/models/profile_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/video_model.dart';
import '../models/ad_model.dart';
import '../models/feed_item.dart';
import '../repositories/video_repository.dart';
import '../services/recsys_service.dart';

/// Provider cho RecSysService kết nối tới Google Colab
final recsysServiceProvider = Provider<RecSysService>((ref) {
  return RecSysService(
    database: ref.watch(realtimeDbProvider),
  );
});

/// Provider cho VideoRepository
final videoRepositoryProvider = Provider<VideoRepository>((ref) {
  return VideoRepository(
    firestore: ref.watch(firestoreProvider),
    database: ref.watch(realtimeDbProvider),
    recsysService: ref.watch(recsysServiceProvider),
  );
});

/// FutureProvider cung cấp danh sách video đề xuất
final videoFeedProvider = FutureProvider<List<VideoModel>>((ref) {
  final user = ref.watch(currentUserProvider);
  return ref.watch(videoRepositoryProvider).getRecommendedVideos(user?.uid);
});

/// FutureProvider cung cấp danh sách video Lâm Đồng
final lamDongVideoFeedProvider = FutureProvider<List<VideoModel>>((ref) {
  final user = ref.watch(currentUserProvider);
  return ref.watch(videoRepositoryProvider).getLamDongVideos(user?.uid);
});

/// FutureProvider cung cấp danh sách video từ những người đang follow
final followingVideoFeedProvider = FutureProvider<List<VideoModel>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  return ref.watch(videoRepositoryProvider).getFollowingVideos(user.uid);
});

/// Enum cho các tab ở trang chủ
enum HomeTab { following, forYou, lamDong }

/// StateProvider quản lý tab đang chọn ở trang chủ
final homeTabProvider = StateProvider<HomeTab>((ref) => HomeTab.forYou);

/// Provider tải thông tin tác giả video
final videoAuthorProfileProvider =
    FutureProvider.family<ProfileModel?, String>((ref, authorId) async {
  return ref.watch(authRepositoryProvider).getProfile(authorId);
});

/// StateProvider lưu trữ trạng thái tắt âm toàn cục
final videoMuteProvider = StateProvider<bool>((ref) => false);

/// StreamProvider theo dõi lượng like và trạng thái like của người dùng đối với một video cụ thể
final videoLikesStateProvider =
    StreamProvider.family<Map<String, dynamic>, String>((ref, videoId) {
  return ref.watch(videoRepositoryProvider).watchLikesState(videoId);
});

/// StreamProvider theo dõi số lượng bình luận thực tế của video (tối ưu hóa chỉ đọc trường totalComments)
final videoCommentsCountProvider =
    StreamProvider.family<int, String>((ref, videoId) {
  return ref.watch(firestoreProvider)
      .collection(AppConstants.videosCollection)
      .doc(videoId)
      .snapshots()
      .map((snapshot) => (snapshot.data()?['totalComments'] as num?)?.toInt() ?? 0);
});

/// StreamProvider theo dõi danh sách quảng cáo
final adsStreamProvider = StreamProvider<List<AdModel>>((ref) {
  return ref.watch(videoRepositoryProvider).watchAds();
});

/// Provider kết hợp video thường và quảng cáo tự động
final homeFeedProvider = Provider<AsyncValue<List<FeedItem>>>((ref) {
  final selectedTab = ref.watch(homeTabProvider);

  AsyncValue<List<VideoModel>> videosAsync;

  switch (selectedTab) {
    case HomeTab.lamDong:
      videosAsync = ref.watch(lamDongVideoFeedProvider);
      break;
    case HomeTab.following:
      videosAsync = ref.watch(followingVideoFeedProvider);
      break;
    case HomeTab.forYou:
      videosAsync = ref.watch(videoFeedProvider);
      break;
  }

  final adsAsync = ref.watch(adsStreamProvider);

  return videosAsync.when(
    data: (videos) {
      // Lấy danh sách quảng cáo nếu tải thành công, ngược lại sử dụng danh sách trống
      final ads = adsAsync.value ?? <AdModel>[];
      
      final feedItems = <FeedItem>[];
      int videoCounter = 0;
      int adIndex = 0;

      for (final video in videos) {
        feedItems.add(VideoItem(video));
        videoCounter++;

        if (videoCounter % 5 == 0 && ads.isNotEmpty) {
          final selectedAd = ads[adIndex % ads.length];
          feedItems.add(AdItem(selectedAd));
          adIndex++;
        }
      }
      return AsyncValue.data(feedItems);
    },
    loading: () => const AsyncValue.loading(),
    error: (err, stack) => AsyncValue.error(err, stack),
  );
});

