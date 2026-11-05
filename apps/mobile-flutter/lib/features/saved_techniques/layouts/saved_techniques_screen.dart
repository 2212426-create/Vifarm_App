import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../repositories/saved_techniques_repository.dart';

/// Màn hình Kho Kỹ Thuật (Danh sách các video kỹ thuật nông nghiệp đã lưu)
class SavedTechniquesScreen extends ConsumerWidget {
  const SavedTechniquesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Video đã lưu')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.bookmark_outline,
                size: 64,
                color: AppColors.primary,
              ),
              const SizedBox(height: 16),
              const Text('Vui lòng đăng nhập để xem các video đã lưu!'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.go('/auth'),
                child: const Text('Đăng nhập'),
              ),
            ],
          ),
        ),
      );
    }

    final savedVideosAsync = ref.watch(
      savedTechniquesStreamProvider(currentUser.uid),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Video đã lưu')),
      body: savedVideosAsync.when(
        data: (videos) {
          if (videos.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.bookmark_border,
                    size: 72,
                    color: isDark
                        ? AppColors.darkTextHint
                        : AppColors.lightTextHint,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Chưa có video nào được lưu',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Bấm biểu tượng "Lưu" ở video bất kỳ để xem lại tại đây!',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: videos.length,
            separatorBuilder: (context, index) => const Divider(height: 16),
            itemBuilder: (context, index) {
              final video = videos[index];
              return Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  contentPadding: const EdgeInsets.all(8),
                  leading: Container(
                    width: 70,
                    height: 90,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.play_circle_fill,
                      color: AppColors.primary,
                      size: 36,
                    ),
                  ),
                  title: Text(
                    video.description.isNotEmpty
                        ? video.description
                        : 'Kỹ thuật canh tác #${video.videoId}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (video.crop != null && video.crop!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withAlpha(40),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                video.crop!,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          if (video.growthStage != null &&
                              video.growthStage!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.accentBrown.withAlpha(40),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                video.growthStage!,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.accentBrown,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '@${video.username}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    context.push('/video/${video.videoId}');
                  },
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Lỗi: $err')),
      ),
    );
  }
}
