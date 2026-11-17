import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/shimmer_loading.dart';
import '../providers/video_provider.dart';
import '../widgets/video_action_bar.dart';
import '../widgets/video_overlay.dart';
import '../widgets/video_player_widget.dart';
import '../widgets/ad_player_widget.dart';
import '../models/feed_item.dart';
import '../services/volume_sync_service.dart';

/// Màn hình chính phát video cuộn dọc (Video Feed)
class VideoFeedScreen extends ConsumerWidget {
  const VideoFeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(volumeSyncServiceProvider);
    final feedState = ref.watch(homeFeedProvider);
    final selectedTab = ref.watch(homeTabProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (_) {
          // Chặn các thao tác vuốt ngang vô tình lôi sang trang cá nhân khi dùng tay trái
        },
        child: Stack(
          children: [
          // 1. Màn hình Feed chính
          feedState.when(
            data: (items) {
              if (items.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.video_library_outlined,
                        color: Colors.white54,
                        size: 64,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        selectedTab == HomeTab.lamDong
                            ? 'Chưa có video nào về Lâm Đồng.'
                            : 'Không có video nào được đăng.',
                        style: const TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () async {
                  if (selectedTab == HomeTab.lamDong) {
                    ref.invalidate(lamDongVideoFeedProvider);
                    await ref.read(lamDongVideoFeedProvider.future);
                  } else if (selectedTab == HomeTab.following) {
                    ref.invalidate(followingVideoFeedProvider);
                    await ref.read(followingVideoFeedProvider.future);
                  } else {
                    ref.invalidate(videoFeedProvider);
                    await ref.read(videoFeedProvider.future);
                  }
                },
                color: Colors.white,
                backgroundColor: Colors.black,
                child: PageView.builder(
                  key: ValueKey(selectedTab),
                  scrollDirection: Axis.vertical,
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];

                    // Key theo id: khi quảng cáo được chèn vào sau, các trang dịch chỉ số;
                    // không có key thì State (và VideoPlayerController) của video cũ bị gán cho video khác.
                    if (item is AdItem) {
                      return AdPlayerWidget(
                        key: ValueKey('ad_${item.id}_$index'),
                        ad: item.ad,
                      );
                    } else if (item is VideoItem) {
                      final video = item.video;

                      return Stack(
                        key: ValueKey('video_${video.videoId}_$index'),
                        fit: StackFit.expand,
                        children: [
                          VideoPlayerWidget(video: video),
                          VideoOverlay(
                            video: video,
                            onCampaignBadgeTap: () {
                              ref.read(videoRepositoryProvider).recordCampaignClick(video.videoId);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Cảm ơn bạn đã tham gia chiến dịch nông nghiệp Lâm Đồng! 🌲'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                          ),
                          VideoActionBar(video: video),
                        ],
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              );
            },
            loading: () => const ShimmerVideoFeed(),
            error: (error, stackTrace) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.redAccent,
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Lỗi tải danh sách video: ${error.toString()}',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),

          // 2. Header Shortcuts: Dùng Stack + Positioned + FittedBox để tuyệt đối không bao giờ tràn lề (overflow)
          SafeArea(
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Stack(
                children: [
                  // Nút Tìm kiếm ở góc trái
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        icon: const Icon(Icons.search, color: Colors.white, size: 24),
                        tooltip: 'Tìm kiếm',
                        onPressed: () => context.push('/search'),
                      ),
                    ),
                  ),

                  // Cụm 3 Tab ở chính giữa - dùng FittedBox scaleDown tự động co giãn vừa khít màn hình
                  Align(
                    alignment: Alignment.center,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 72),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildTopTab(ref, 'Follow', HomeTab.following, selectedTab == HomeTab.following),
                            _buildDivider(),
                            _buildTopTab(ref, 'Lâm Đồng', HomeTab.lamDong, selectedTab == HomeTab.lamDong),
                            _buildDivider(),
                            _buildTopTab(ref, 'Dành cho bạn', HomeTab.forYou, selectedTab == HomeTab.forYou),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Nút Tin nhắn & Thông báo ở góc phải
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            icon: const Icon(Icons.chat_bubble_outline, color: Colors.white, size: 22),
                            tooltip: 'Tin nhắn',
                            onPressed: () => context.push('/inbox'),
                          ),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            icon: const Icon(Icons.notifications_outlined, color: Colors.white, size: 22),
                            tooltip: 'Thông báo',
                            onPressed: () => context.push('/notifications'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        '|',
        style: TextStyle(
          color: Colors.white.withAlpha(80),
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildTopTab(WidgetRef ref, String title, HomeTab tab, bool isActive) {
    return GestureDetector(
      onTap: () {
        ref.read(homeTabProvider.notifier).state = tab;
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.white60,
              fontSize: 13,
              fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
              shadows: const [
                Shadow(blurRadius: 8, color: Colors.black54, offset: Offset(0, 1)),
              ],
            ),
          ),
          if (isActive)
            Container(
              margin: const EdgeInsets.only(top: 2),
              height: 2,
              width: 20,
              color: Colors.white,
            ),
        ],
      ),
    );
  }
}
