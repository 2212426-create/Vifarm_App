import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/text_utils.dart';
import '../../../shared/widgets/shimmer_loading.dart';
import '../../video_feed/models/video_model.dart';

final hashtagVideosProvider = StreamProvider.family<List<VideoModel>, ({String tag, String sort})>((ref, arg) {
  final cleanTag = TextUtils.normalizeHashtag(arg.tag);

  return FirebaseFirestore.instance
      .collection('videos')
      .where('hashtags', arrayContains: cleanTag)
      .snapshots()
      .map((snapshot) {
    var list = snapshot.docs
        .map((doc) => VideoModel.fromMap(doc.data(), doc.id))
        .where((v) => v.moderationStatus == 'approved' || v.isPublic)
        .toList();

    if (arg.sort == 'Mới nhất') {
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } else if (arg.sort == 'Thịnh hành') {
      list.sort((a, b) => b.watchCount.compareTo(a.watchCount));
    }

    return list;
  });
});

/// Màn hình Hashtag Thống Nhất (/hashtag/:tag)
class HashtagScreen extends ConsumerStatefulWidget {
  final String tag;

  const HashtagScreen({super.key, required this.tag});

  @override
  ConsumerState<HashtagScreen> createState() => _HashtagScreenState();
}

class _HashtagScreenState extends ConsumerState<HashtagScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _sortOptions = ['Mới nhất', 'Thịnh hành'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _sortOptions.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cleanTag = TextUtils.normalizeHashtag(widget.tag);
    final displayTag = widget.tag.startsWith('#') ? widget.tag : '#${widget.tag}';

    return Scaffold(
      appBar: AppBar(
        title: Text(displayTag),
        bottom: TabBar(
          controller: _tabController,
          tabs: _sortOptions.map((s) => Tab(text: s)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _sortOptions.map((sortOption) {
          final videosAsync = ref.watch(hashtagVideosProvider((tag: cleanTag, sort: sortOption)));

          return videosAsync.when(
            data: (videos) {
              if (videos.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.tag, size: 64, color: Colors.grey),
                      const SizedBox(height: 12),
                      Text('Chưa có video nào với hashtag $displayTag'),
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    color: AppColors.primary.withAlpha(20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.video_collection, color: AppColors.primary, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          'Tổng số: ${videos.length} video $displayTag',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 3 / 4,
                        crossAxisSpacing: 4,
                        mainAxisSpacing: 4,
                      ),
                      itemCount: videos.length,
                      itemBuilder: (context, index) {
                        final video = videos[index];
                        return GestureDetector(
                          onTap: () => context.push('/video/${video.videoId}'),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Container(
                                color: Colors.grey[900],
                                child: video.videoUri.contains('cloudinary.com')
                                    ? Image.network(
                                        video.videoUri.replaceAll('.mp4', '.jpg'),
                                        fit: BoxFit.cover,
                                        cacheWidth: 360,
                                        errorBuilder: (context, error, stackTrace) =>
                                            const Icon(Icons.play_circle_outline, color: Colors.white30),
                                      )
                                    : const Icon(Icons.play_circle_outline, color: Colors.white30),
                              ),
                              Positioned(
                                left: 4,
                                bottom: 4,
                                child: Row(
                                  children: [
                                    const Icon(Icons.play_arrow, color: Colors.white, size: 12),
                                    Text('${video.watchCount}', style: const TextStyle(color: Colors.white, fontSize: 10)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
            loading: () => const ShimmerVideoGrid(),
            error: (err, stack) => Center(child: Text('Lỗi: $err')),
          );
        }).toList(),
      ),
    );
  }
}
