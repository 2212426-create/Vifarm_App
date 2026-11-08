import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/share_button.dart';
import '../../../shared/widgets/universal_share_bottom_sheet.dart';
import '../../../shared/widgets/shimmer_loading.dart';
import '../../auth/providers/auth_provider.dart';
import '../../farm_journal/repositories/journal_repository.dart';
import '../../saved_techniques/repositories/saved_techniques_repository.dart';
import '../../store/providers/app_mode_provider.dart';
import '../../store/repositories/store_repository.dart';
import '../providers/profile_provider.dart';
import '../widgets/avatar_preview_dialog.dart';

/// Màn hình Hồ Sơ "Cá Nhân" & Người Dùng Khác
/// Thiết kế chuẩn mực 7 phần: TopBar, Avatar/Username, Bio, Stats, Action Buttons, Linked Store Card, Content Tabs
class ProfileScreen extends ConsumerStatefulWidget {
  final String? userId;

  const ProfileScreen({
    super.key,
    this.userId,
  });

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _bioController = TextEditingController();
  final bool _isEditingBio = false;
  bool _isFollowLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _showSettingsBottomSheet(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              ListTile(
                leading: Icon(Icons.settings, color: onSurface),
                title: Text('Cài đặt & Quyền riêng tư', style: TextStyle(color: onSurface)),
                onTap: () {
                  Navigator.pop(context);
                  context.push('/settings');
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: AppTheme.primaryColor),
                title: const Text('Đăng xuất', style: TextStyle(color: AppTheme.primaryColor)),
                onTap: () async {
                  Navigator.pop(context);
                  await ref.read(authNotifierProvider.notifier).signOut();
                  if (context.mounted) {
                    context.go('/auth');
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final profileId = widget.userId ?? currentUser?.uid ?? '';
    final isMe = profileId == currentUser?.uid;

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;
    final bgColor = theme.scaffoldBackgroundColor;
    final onSurface = cs.onSurface;
    final divColor = isDark ? const Color(0xFF333333) : const Color(0xFFE3E3E4);
    final btnBgColor = isDark ? const Color(0xFF242428) : const Color(0xFFF1F1F3);

    if (profileId.isEmpty) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(
          child: Text('Vui lòng đăng nhập để xem trang cá nhân', style: TextStyle(color: onSurface.withValues(alpha: 0.5))),
        ),
      );
    }

    final profileState = ref.watch(userProfileStreamProvider(profileId));
    final videosState = ref.watch(userVideosStreamProvider(profileId));
    final storeState = ref.watch(userStoreStreamProvider(profileId));

    final followCompositeKey = "${currentUser?.uid}_$profileId";
    final isFollowing = ref.watch(followStatusStreamProvider(followCompositeKey)).valueOrNull ?? false;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        centerTitle: true,
        leading: !isMe
            ? IconButton(
                icon: Icon(Icons.arrow_back, color: onSurface),
                onPressed: () => context.pop(),
              )
            : null,
        title: profileState.when(
          data: (profile) => Text(
            isMe ? 'Cá Nhân' : (profile?.fullname.isNotEmpty == true ? profile!.fullname : 'Hồ sơ'),
            style: TextStyle(color: onSurface, fontWeight: FontWeight.bold, fontSize: 18),
          ),
          loading: () => const SizedBox(),
          error: (error, _) => const SizedBox(),
        ),
        actions: [
          if (profileState.valueOrNull != null)
            ShareButton(
              content: ShareContentModel.fromProfile(profileState.valueOrNull!),
            ),
          if (isMe)
            IconButton(
              icon: Icon(Icons.menu, color: onSurface),
              onPressed: () => _showSettingsBottomSheet(context),
            ),
        ],
      ),
      body: profileState.when(
        data: (profile) {
          if (profile == null) {
            return Center(
              child: Text('Hồ sơ không tồn tại hoặc đã bị xóa.', style: TextStyle(color: onSurface.withValues(alpha: 0.7))),
            );
          }

          if (!_isEditingBio && _bioController.text != profile.bio) {
            _bioController.text = profile.bio;
          }

          return RefreshIndicator(
            onRefresh: () async {
              await ref.read(profileRepositoryProvider).syncFollowCounts(profileId);
            },
            color: AppColors.primary,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 12),

                  // 1. Avatar
                  GestureDetector(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => AvatarPreviewDialog(avatarUrl: profile.avatarUrl),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppColors.brandGradient,
                      ),
                      child: CircleAvatar(
                        radius: 42,
                        backgroundColor: bgColor,
                        child: CircleAvatar(
                          radius: 39,
                          backgroundColor: isDark ? Colors.grey[900] : Colors.grey[200],
                          backgroundImage: profile.avatarUrl.isNotEmpty
                              ? CachedNetworkImageProvider(profile.avatarUrl, maxWidth: 120)
                              : const AssetImage('assets/images/default_avatar.png') as ImageProvider,
                          child: profile.avatarUrl.isEmpty
                              ? Icon(Icons.person, size: 40, color: onSurface.withValues(alpha: 0.5))
                              : null,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // 2. Full Name & Username
                  if (profile.fullname.isNotEmpty)
                    Text(
                      profile.fullname,
                      style: TextStyle(color: onSurface, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  Text(
                    '@${profile.username}',
                    style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 13),
                  ),
                  const SizedBox(height: 12),

                  // 3. Bio
                  if (profile.bio.isNotEmpty || isMe)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        profile.bio.isNotEmpty ? profile.bio : 'Chưa có tiểu sử.',
                        style: TextStyle(color: onSurface.withValues(alpha: 0.8), fontSize: 13, height: 1.3),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  const SizedBox(height: 16),

                  // 4. Stats Row
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildMetricItem(
                            label: 'Đang theo dõi',
                            value: profile.following.toString(),
                            onTap: () => context.push('/user/$profileId/following'),
                          ),
                        ),
                        _buildDivider(),
                        Expanded(
                          child: _buildMetricItem(
                            label: 'Người theo dõi',
                            value: profile.followers.toString(),
                            onTap: () => context.push('/user/$profileId/followers'),
                          ),
                        ),
                        _buildDivider(),
                        Expanded(
                          child: _buildMetricItem(
                            label: 'Lượt thích',
                            value: profile.likes.toString(),
                            onTap: null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 5. Main Action Buttons
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: isMe
                        ? Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => context.push('/profile/edit'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: onSurface,
                                    side: BorderSide.none,
                                    backgroundColor: btnBgColor,
                                  ),
                                  child: const Text('Sửa hồ sơ', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => context.push('/settings'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: onSurface,
                                    side: BorderSide.none,
                                    backgroundColor: btnBgColor,
                                  ),
                                  child: const Text('Cài đặt', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                ),
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              // Follow / Unfollow Button with Single-Tap Lock & Loading State
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _isFollowLoading
                                      ? null
                                      : () async {
                                          if (currentUser == null) {
                                            context.go('/auth');
                                            return;
                                          }

                                          setState(() => _isFollowLoading = true);
                                          final repo = ref.read(profileRepositoryProvider);

                                          try {
                                            if (isFollowing) {
                                              await repo.unfollowUser(
                                                currentUid: currentUser.uid,
                                                targetUid: profileId,
                                              );
                                            } else {
                                              final myProfile = ref.read(currentUserProfileProvider).valueOrNull;
                                              final myUsername = myProfile?.username ?? currentUser.email?.split('@')[0] ?? '';
                                              await repo.followUser(
                                                currentUid: currentUser.uid,
                                                targetUid: profileId,
                                                currentUsername: myUsername,
                                              );
                                            }
                                          } finally {
                                            if (mounted) setState(() => _isFollowLoading = false);
                                          }
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isFollowing ? (isDark ? Colors.grey[850] : Colors.grey[300]) : AppColors.primary,
                                    foregroundColor: isFollowing ? (isDark ? Colors.white : Colors.black87) : Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  child: _isFollowLoading
                                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                      : Text(
                                          isFollowing ? 'Đang theo dõi' : 'Theo dõi',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 8),

                              // Message Button
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () {
                                    if (currentUser == null) {
                                      context.go('/auth');
                                      return;
                                    }
                                    context.push('/chat/$profileId?name=${Uri.encodeComponent(profile.username)}');
                                  },
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: onSurface,
                                    side: BorderSide.none,
                                    backgroundColor: btnBgColor,
                                  ),
                                  child: const Text('Nhắn tin', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                ),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 16),

                  // 6. Linked Store Card
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: storeState.when(
                      data: (store) {
                        if (store == null && isMe) {
                          return _buildStoreCardTile(
                            title: 'Đăng ký bán hàng',
                            subtitle: 'Mở gian hàng nông sản, vật tư',
                            buttonText: 'Đăng ký ngay',
                            color: AppColors.primary,
                            onPressed: () => context.push('/store/register'),
                          );
                        }

                        if (store != null) {
                          if (isMe) {
                            if (store.status == 'draft') {
                              return _buildStoreCardTile(
                                title: 'Hồ sơ gian hàng dở dang',
                                subtitle: 'Bạn có bản nháp chưa gửi',
                                buttonText: 'Tiếp tục',
                                color: AppColors.warning,
                                onPressed: () => context.push('/store/register'),
                              );
                            }

                            if (store.status == 'pending') {
                              return _buildStoreCardTile(
                                title: 'Hồ sơ gian hàng đang chờ xét duyệt',
                                subtitle: store.storeName,
                                buttonText: 'Xem hồ sơ',
                                color: Colors.orange,
                                onPressed: () => context.push('/store/register'),
                              );
                            }

                            if (store.status == 'needs_changes') {
                              return _buildStoreCardTile(
                                title: 'Cần bổ sung thông tin hồ sơ',
                                subtitle: store.rejectionReason ?? 'Vui lòng kiểm tra lại thông tin',
                                buttonText: 'Cập nhật',
                                color: Colors.redAccent,
                                onPressed: () => context.push('/store/register'),
                              );
                            }

                            if (store.isApproved) {
                              return _buildStoreCardTile(
                                title: 'Gian hàng: ${store.storeName}',
                                subtitle: store.storeType == 'individual' ? 'Cá nhân / Nhà vườn' : 'Đơn vị kinh doanh',
                                buttonText: 'Vào Gian Hàng',
                                color: AppColors.primary,
                                onPressed: () async {
                                  final success = await ref.read(appModeProvider.notifier).switchToSellerMode();
                                  if (success && mounted) {
                                    context.go('/seller/overview');
                                  }
                                },
                              );
                            }
                          } else if (store.isApproved) {
                            // Other user's approved public store
                            return _buildStoreCardTile(
                              title: store.storeName,
                              subtitle: store.storeType == 'individual' ? 'Cá nhân / Nhà vườn' : 'Đơn vị kinh doanh',
                              buttonText: 'Xem Gian Hàng',
                              color: AppColors.primary,
                              onPressed: () => context.push('/store/${store.storeId}'),
                            );
                          }
                        }

                        return const SizedBox.shrink();
                      },
                      loading: () => const SizedBox.shrink(),
                      error: (e, s) => const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 7. Content Tabs (Video / Nhật ký / Kho kỹ thuật)
                  Divider(color: divColor, height: 1),
                  TabBar(
                    controller: _tabController,
                    labelColor: AppColors.primary,
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: AppColors.primary,
                    tabs: [
                      const Tab(text: 'Videos'),
                      const Tab(text: 'Nhật ký'),
                      if (isMe) const Tab(text: 'Kho Kỹ Thuật'),
                    ],
                  ),

                  SizedBox(
                    height: 380,
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        // Tab 1: Video Grid
                        videosState.when(
                          data: (videos) {
                            if (videos.isEmpty) {
                              return const Center(child: Text('Chưa có video nào.', style: TextStyle(color: Colors.grey)));
                            }
                            return GridView.builder(
                              padding: const EdgeInsets.all(8),
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
                                      CachedNetworkImage(
                                        imageUrl: video.thumbnailUri,
                                        fit: BoxFit.cover,
                                        placeholder: (ctx, url) => Container(color: Colors.grey[900]),
                                        errorWidget: (ctx, url, err) => Container(color: Colors.grey[900]),
                                      ),
                                      Positioned(
                                        left: 6,
                                        bottom: 6,
                                        child: Row(
                                          children: [
                                            const Icon(Icons.play_arrow, color: Colors.white, size: 14),
                                            Text('${video.watchCount}', style: const TextStyle(color: Colors.white, fontSize: 11)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                          loading: () => const ShimmerVideoGrid(),
                          error: (err, stack) => Center(child: Text('Lỗi: $err')),
                        ),

                        // Tab 2: Farm Journals
                        Consumer(
                          builder: (context, ref, child) {
                            final journalsAsync = isMe
                                ? ref.watch(userJournalsStreamProvider(profileId))
                                : ref.watch(publicJournalsStreamProvider);

                            return journalsAsync.when(
                              data: (journals) {
                                final list = isMe
                                    ? journals
                                    : journals.where((j) => j.ownerId == profileId && j.privacy == 'public').toList();

                                if (list.isEmpty) {
                                  return const Center(child: Text('Chưa có nhật ký mùa vụ công khai nào.', style: TextStyle(color: Colors.grey)));
                                }

                                return ListView.builder(
                                  padding: const EdgeInsets.all(8),
                                  itemCount: list.length,
                                  itemBuilder: (context, index) {
                                    final j = list[index];
                                    return Card(
                                      child: ListTile(
                                        title: Text(j.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                        subtitle: Text('🌱 ${j.crop} • ${j.region}'),
                                        trailing: const Icon(Icons.chevron_right),
                                        onTap: () => context.push('/journal/${j.id}'),
                                      ),
                                    );
                                  },
                                );
                              },
                              loading: () => const Center(child: CircularProgressIndicator()),
                              error: (e, s) => Center(child: Text('Lỗi: $e')),
                            );
                          },
                        ),

                        // Tab 3: Saved Techniques (Private area ONLY for own profile)
                        if (isMe)
                          Consumer(
                            builder: (context, ref, child) {
                              final savedAsync = ref.watch(savedTechniquesStreamProvider(profileId));

                              return savedAsync.when(
                                data: (videos) {
                                  if (videos.isEmpty) {
                                    return const Center(child: Text('Chưa có kỹ thuật nào được lưu trong kho.', style: TextStyle(color: Colors.grey)));
                                  }

                                  return ListView.builder(
                                    padding: const EdgeInsets.all(8),
                                    itemCount: videos.length,
                                    itemBuilder: (context, index) {
                                      final v = videos[index];
                                      return Card(
                                        child: ListTile(
                                          leading: const Icon(Icons.bookmark, color: AppColors.primary),
                                          title: Text(v.description.isNotEmpty ? v.description : 'Kỹ thuật canh tác', maxLines: 1, overflow: TextOverflow.ellipsis),
                                          subtitle: Text('🌱 ${v.crop ?? "Nông nghiệp"} • @${v.username}'),
                                          onTap: () => context.push('/video/${v.videoId}'),
                                        ),
                                      );
                                    },
                                  );
                                },
                                loading: () => const Center(child: CircularProgressIndicator()),
                                error: (e, s) => Center(child: Text('Lỗi: $e')),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Lỗi: $err')),
      ),
    );
  }

  Widget _buildStoreCardTile({
    required String title,
    required String subtitle,
    required String buttonText,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        children: [
          Icon(Icons.storefront, color: color, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 6),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              minimumSize: Size.zero,
            ),
            onPressed: onPressed,
            child: Text(buttonText, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(width: 1, height: 16, color: Colors.grey.shade400);
  }

  Widget _buildMetricItem({
    required String label,
    required String value,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }
}
