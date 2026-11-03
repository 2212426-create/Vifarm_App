import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/text_utils.dart';
import '../../../core/utils/time_utils.dart';
import '../../profile/providers/profile_provider.dart';
import '../models/video_model.dart';
import '../providers/video_provider.dart';
import '../../products/widgets/product_bottom_sheet.dart';

/// Widget hiển thị thông tin nông nghiệp đè lên Video
class VideoOverlay extends ConsumerStatefulWidget {
  final VideoModel video;
  final VoidCallback? onCampaignBadgeTap;

  const VideoOverlay({super.key, required this.video, this.onCampaignBadgeTap});

  @override
  ConsumerState<VideoOverlay> createState() => _VideoOverlayState();
}

class _VideoOverlayState extends ConsumerState<VideoOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _marqueeController;

  @override
  void initState() {
    super.initState();
    _marqueeController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _marqueeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authorProfile = ref
        .watch(userProfileStreamProvider(widget.video.authorId))
        .valueOrNull;
    final username = authorProfile?.username ?? widget.video.username;

    return Positioned(
      left: 0,
      bottom: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Color(0xE6000000), Colors.black54, Colors.transparent],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        padding: const EdgeInsets.only(
          left: 16,
          right: 90,
          bottom: 20,
          top: 60,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Thẻ sản phẩm gắn kèm video
            if (widget.video.taggedProductIds.isNotEmpty) ...[
              GestureDetector(
                onTap: () {
                  final productId = widget.video.taggedProductIds.first;
                  ProductBottomSheet.show(context, productId: productId);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.secondary, Color(0xFFFFA000)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.shopping_bag_outlined,
                        size: 14,
                        color: Colors.black87,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Xem sản phẩm (${widget.video.taggedProductIds.length})',
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.chevron_right,
                        size: 14,
                        color: Colors.black87,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],

            // 2. Thẻ Nhật ký mùa vụ liên quan
            if (widget.video.relatedJournalId != null &&
                widget.video.relatedJournalId!.isNotEmpty) ...[
              GestureDetector(
                onTap: () {
                  context.push('/journal/${widget.video.relatedJournalId}');
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(200),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white30, width: 0.5),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.menu_book, size: 13, color: Colors.white),
                      SizedBox(width: 5),
                      Text(
                        'Xem nhật ký liên quan',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],

            // 3. Các thẻ nông nghiệp & Chủ đề video (Cây trồng, Chủ đề, Giai đoạn, Khu vực)
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (widget.video.topic != null &&
                    widget.video.topic!.isNotEmpty)
                  _buildTagBadge(
                    VideoModel.getTopicDisplayName(widget.video.topic),
                    AppColors.primary,
                  ),
                if (widget.video.isSponsored)
                  _buildTagBadge('📢 Được tài trợ', Colors.amber.shade800),
                if (widget.video.crop != null && widget.video.crop!.isNotEmpty)
                  _buildTagBadge('🌱 ${widget.video.crop}', AppColors.primary),
                if (widget.video.growthStage != null &&
                    widget.video.growthStage!.isNotEmpty)
                  _buildTagBadge(
                    '🌸 ${widget.video.growthStage}',
                    AppColors.accentBrown,
                  ),
                if (widget.video.region != null &&
                    widget.video.region!.isNotEmpty)
                  _buildTagBadge('📍 ${widget.video.region}', Colors.blueGrey),
                if (widget.video.technicalTopic != null &&
                    widget.video.technicalTopic!.isNotEmpty)
                  _buildTagBadge(
                    '🔬 ${widget.video.technicalTopic}',
                    Colors.teal,
                  ),
              ],
            ),
            if (widget.video.crop != null ||
                widget.video.growthStage != null ||
                widget.video.region != null)
              const SizedBox(height: 8),

            // 4. Tên tác giả & Thời gian
            Row(
              children: [
                Text(
                  username.isNotEmpty ? '@$username' : '@NhaVuon',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    letterSpacing: 0.3,
                    shadows: [
                      Shadow(
                        blurRadius: 6,
                        color: Colors.black87,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
                if (ref.watch(homeTabProvider) == HomeTab.following) ...[
                  const SizedBox(width: 8),
                  Text(
                    '• ${TimeUtils.formatRelativeTime(widget.video.timestamp)}',
                    style: TextStyle(
                      color: Colors.white.withAlpha(160),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),

            // 5. Mô tả video
            if (widget.video.description.isNotEmpty)
              Text(
                widget.video.description,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  height: 1.4,
                  shadows: [
                    Shadow(
                      blurRadius: 4,
                      color: Colors.black54,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

            // 6. Hashtags (Chạm mở Màn hình Hashtag tập trung)
            if (widget.video.hashtags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: widget.video.hashtags
                    .map((tag) => tag.trim())
                    .where((tag) => tag.isNotEmpty)
                    .map((tag) => tag.startsWith('#') ? tag.substring(1) : tag)
                    .toSet()
                    .take(5)
                    .map((tag) {
                      final cleanTag = TextUtils.normalizeHashtag(tag);

                      return GestureDetector(
                        onTap: () {
                          context.push('/hashtag/$cleanTag');
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(40),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '#$tag',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      );
                    })
                    .toList(),
              ),
            ],

            // 7. Nhạc marquee
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.agriculture, color: Colors.white, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: SizedBox(
                    height: 16,
                    child: RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _marqueeController,
                        builder: (context, child) {
                          return ClipRect(
                            child: FractionalTranslation(
                              translation: Offset(
                                1.0 - 2.0 * _marqueeController.value,
                                0,
                              ),
                              child: Text(
                                '♪ Kỹ thuật nông nghiệp — ${username.isNotEmpty ? username : "Nông Video"}',
                                style: TextStyle(
                                  color: Colors.white.withAlpha(200),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.visible,
                                softWrap: false,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
