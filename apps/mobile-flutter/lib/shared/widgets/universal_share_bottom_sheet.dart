import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../features/auth/models/profile_model.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/chat/providers/chat_provider.dart';
import '../../core/providers/firebase_providers.dart' show firestoreProvider;
import '../../features/chat/repositories/group_chat_repository.dart';
import '../../features/farm_journal/models/journal_model.dart';
import '../../features/products/models/product_model.dart';
import '../../features/store/models/store_model.dart';
import '../../features/video_feed/models/video_model.dart';

enum ShareContentType { video, product, store, profile, journal }

/// Model tổng quát đại diện cho nội dung được chia sẻ
class ShareContentModel {
  final ShareContentType type;
  final String id;
  final String title;
  final String subtitle;
  final String? imageUrl;
  final String shareUrl;
  final bool isPrivate;
  final Map<String, dynamic>? extraData;

  ShareContentModel({
    required this.type,
    required this.id,
    required this.title,
    this.subtitle = '',
    this.imageUrl,
    required this.shareUrl,
    this.isPrivate = false,
    this.extraData,
  });

  factory ShareContentModel.fromVideo(VideoModel video) {
    return ShareContentModel(
      type: ShareContentType.video,
      id: video.videoId,
      title: video.description.isNotEmpty ? video.description : 'Video ViFarm',
      subtitle: '@${video.username}',
      shareUrl: '${AppConstants.shareBaseUrl}${video.videoId}',
      extraData: video.toMap(),
    );
  }

  factory ShareContentModel.fromProduct(ProductModel product) {
    final priceStr = product.saleType == 'fixed_price'
        ? '${product.listedPrice}đ / ${product.unit}'
        : 'Báo giá • ${product.unit}';

    return ShareContentModel(
      type: ShareContentType.product,
      id: product.id,
      title: product.name,
      subtitle: '$priceStr • ${product.sellerName}',
      imageUrl: product.images.isNotEmpty ? product.images.first : null,
      shareUrl: '${AppConstants.shareBaseUrl}product_${product.id}',
      extraData: product.toMap(),
    );
  }

  factory ShareContentModel.fromStore(StoreModel store) {
    return ShareContentModel(
      type: ShareContentType.store,
      id: store.storeId,
      title: store.storeName,
      subtitle:
          '${store.region} • ${store.storeType == "individual" ? "Cá nhân/Nhà vườn" : "Đơn vị kinh doanh"}',
      imageUrl: store.avatarUrl,
      shareUrl: '${AppConstants.shareBaseUrl}store_${store.storeId}',
      extraData: store.toMap(),
    );
  }

  factory ShareContentModel.fromProfile(ProfileModel profile) {
    return ShareContentModel(
      type: ShareContentType.profile,
      id: profile.userId,
      title: profile.fullname.isNotEmpty ? profile.fullname : profile.username,
      subtitle: '@${profile.username}',
      imageUrl: profile.avatarUrl,
      shareUrl: '${AppConstants.shareBaseUrl}profile_${profile.userId}',
      extraData: profile.toMap(),
    );
  }

  factory ShareContentModel.fromJournal(JournalModel journal) {
    return ShareContentModel(
      type: ShareContentType.journal,
      id: journal.id,
      title: journal.name,
      subtitle:
          '🌱 ${journal.crop} (${journal.farmLocation}) • ${journal.ownerName}',
      shareUrl: '${AppConstants.shareBaseUrl}journal_${journal.id}',
      isPrivate: journal.privacy == 'private',
      extraData: journal.toMap(),
    );
  }
}

/// Bottom Sheet nâng cao dùng chung cho tất cả các loại nội dung chia sẻ
class UniversalShareBottomSheet extends ConsumerStatefulWidget {
  final ShareContentModel content;

  const UniversalShareBottomSheet({super.key, required this.content});

  static void show(BuildContext context, ShareContentModel content) {
    if (content.isPrivate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nội dung này đang ở chế độ riêng tư, không thể chia sẻ công khai.',
          ),
          backgroundColor: Colors.amber,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => UniversalShareBottomSheet(content: content),
    );
  }

  @override
  ConsumerState<UniversalShareBottomSheet> createState() =>
      _UniversalShareBottomSheetState();
}

class _UniversalShareBottomSheetState
    extends ConsumerState<UniversalShareBottomSheet> {
  final TextEditingController _captionController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedRecipients = {};
  String _searchQuery = '';
  bool _isSending = false;

  @override
  void dispose() {
    _captionController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _handleSend() async {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null || _selectedRecipients.isEmpty) return;

    setState(() => _isSending = true);

    try {
      final repo = ref.read(chatRepositoryProvider);
      final caption = _captionController.text.trim();

      for (final recipientId in _selectedRecipients) {
        final conversations =
            ref.read(chatConversationsProvider).valueOrNull ?? [];
        final recipient = conversations.firstWhere(
          (c) =>
              (c['isGroup'] == true ? c['chatId'] : c['userId']) == recipientId,
        );
        final isGroup = recipient['isGroup'] == true;
        if (isGroup && recipient['closed'] == true) {
          throw StateError('Nhóm đã kết thúc. Vui lòng chọn lại người nhận.');
        }
        if (widget.content.type == ShareContentType.video) {
          await repo.sendVideoShare(
            senderId: currentUser.uid,
            receiverId: recipientId,
            videoId: widget.content.id,
            caption: caption,
            isGroup: isGroup,
          );
        } else {
          final messageText = caption.isNotEmpty
              ? '$caption\n\n[${widget.content.title}](${widget.content.shareUrl})'
              : 'Tôi muốn chia sẻ ${widget.content.title}: ${widget.content.shareUrl}';

          if (isGroup) {
            await GroupChatRepository(ref.read(firestoreProvider)).send(
              groupId: recipientId,
              senderId: currentUser.uid,
              text: messageText,
              metadata: widget.content.extraData,
            );
          } else {
            await repo.sendMessage(
              senderId: currentUser.uid,
              receiverId: recipientId,
              message: messageText,
              type: 'text',
              metadata: widget.content.extraData,
            );
          }
        }
      }

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        context.pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Đã chia sẻ cho ${_selectedRecipients.length} cuộc hội thoại!',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gửi chia sẻ thất bại: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUser = ref.watch(currentUserProvider);
    final conversationsAsync = ref.watch(chatConversationsProvider);

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF181A20) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.withAlpha(80),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Chia sẻ',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => context.pop(),
                ),
              ],
            ),
          ),

          // Content Preview Card
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withAlpha(15) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withAlpha(40)),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 44,
                    height: 44,
                    color: AppColors.primary.withAlpha(40),
                    child:
                        widget.content.imageUrl != null &&
                            widget.content.imageUrl!.isNotEmpty
                        ? Image.network(
                            widget.content.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _getFallbackIcon(),
                          )
                        : _getFallbackIcon(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.content.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.content.subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.content.subtitle,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // External Actions Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text(
                      'Sao chép liên kết',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: widget.content.shareUrl),
                      );
                      context.pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Đã sao chép liên kết')),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.share, size: 16),
                    label: const Text(
                      'Chia sẻ qua...',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: widget.content.shareUrl),
                      );
                      context.pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Đã sao chép liên kết chia sẻ!'),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1),
          ),

          // Internal Sharing Section
          Expanded(
            child: currentUser == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.chat_bubble_outline,
                            size: 48,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Đăng nhập để gửi trực tiếp cho bạn bè trong ViFarm',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              context.pop();
                              context.push('/login');
                            },
                            child: const Text('Đăng nhập'),
                          ),
                        ],
                      ),
                    ),
                  )
                : Column(
                    children: [
                      // Search and Caption
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: [
                            SizedBox(
                              height: 38,
                              child: TextField(
                                controller: _searchController,
                                style: const TextStyle(fontSize: 13),
                                onChanged: (v) => setState(
                                  () => _searchQuery = v.toLowerCase().trim(),
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Tìm người nhận trong ViFarm...',
                                  hintStyle: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.search,
                                    size: 18,
                                  ),
                                  contentPadding: EdgeInsets.zero,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide.none,
                                  ),
                                  filled: true,
                                  fillColor: isDark
                                      ? Colors.white10
                                      : Colors.grey.shade200,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 38,
                              child: TextField(
                                controller: _captionController,
                                style: const TextStyle(fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: 'Thêm lời nhắn (không bắt buộc)...',
                                  hintStyle: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),

                      // List of Conversations
                      Expanded(
                        child: conversationsAsync.when(
                          data: (convs) {
                            final filteredConvs = convs.where((c) {
                              if (c['isGroup'] == true && c['closed'] == true)
                                return false;
                              if (_searchQuery.isEmpty) return true;
                              final title = (c['title'] ?? c['userId'] ?? '')
                                  .toString()
                                  .toLowerCase();
                              return title.contains(_searchQuery);
                            }).toList();

                            if (filteredConvs.isEmpty) {
                              return const Center(
                                child: Text(
                                  'Không tìm thấy cuộc hội thoại nào.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey,
                                  ),
                                ),
                              );
                            }

                            return ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              itemCount: filteredConvs.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final c = filteredConvs[index];
                                final isGroup = c['isGroup'] == true;
                                final id =
                                    (isGroup ? c['chatId'] : c['userId'])
                                        as String;
                                final isSelected = _selectedRecipients.contains(
                                  id,
                                );

                                return _RecipientTile(
                                  id: id,
                                  isGroup: isGroup,
                                  title: isGroup
                                      ? (c['title'] ?? 'Nhóm')
                                      : null,
                                  avatar: isGroup
                                      ? (c['avatarUrl'] ?? '')
                                      : null,
                                  isSelected: isSelected,
                                  onTap: () {
                                    setState(() {
                                      if (isSelected) {
                                        _selectedRecipients.remove(id);
                                      } else {
                                        _selectedRecipients.add(id);
                                      }
                                    });
                                  },
                                );
                              },
                            );
                          },
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (e, s) => Center(child: Text('Lỗi: $e')),
                        ),
                      ),

                      // Send Button
                      if (_selectedRecipients.isNotEmpty)
                        SafeArea(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                              onPressed: _isSending ? null : _handleSend,
                              child: _isSending
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      'Gửi (${_selectedRecipients.length})',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _getFallbackIcon() {
    switch (widget.content.type) {
      case ShareContentType.video:
        return const Icon(
          Icons.play_circle_fill,
          color: AppColors.primary,
          size: 24,
        );
      case ShareContentType.product:
        return const Icon(
          Icons.shopping_bag,
          color: AppColors.primary,
          size: 24,
        );
      case ShareContentType.store:
        return const Icon(Icons.storefront, color: AppColors.primary, size: 24);
      case ShareContentType.profile:
        return const Icon(Icons.person, color: AppColors.primary, size: 24);
      case ShareContentType.journal:
        return const Icon(Icons.menu_book, color: AppColors.primary, size: 24);
    }
  }
}

class _RecipientTile extends ConsumerWidget {
  final String id;
  final bool isGroup;
  final String? title;
  final String? avatar;
  final bool isSelected;
  final VoidCallback onTap;

  const _RecipientTile({
    required this.id,
    required this.isGroup,
    this.title,
    this.avatar,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FutureBuilder(
      future: isGroup
          ? Future.value(null)
          : ref.read(chatProfileProvider(id).future),
      builder: (context, snap) {
        final profile = snap.data;
        final displayTitle = isGroup
            ? (title ?? 'Nhóm')
            : (profile?.username ?? id.substring(0, 8));
        final displayAvatar = isGroup
            ? (avatar ?? '')
            : (profile?.avatarUrl ?? '');

        return Material(
          color: Colors.transparent,
          child: ListTile(
            onTap: onTap,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 2,
            ),
            leading: Stack(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.grey.shade200,
                  backgroundImage: displayAvatar.isNotEmpty
                      ? NetworkImage(displayAvatar)
                      : null,
                  child: displayAvatar.isEmpty
                      ? Icon(
                          isGroup ? Icons.group : Icons.person,
                          color: Colors.grey,
                          size: 20,
                        )
                      : null,
                ),
                if (isSelected)
                  const Positioned(
                    right: 0,
                    bottom: 0,
                    child: Icon(
                      Icons.check_circle,
                      color: AppColors.primary,
                      size: 16,
                    ),
                  ),
              ],
            ),
            title: Text(
              isGroup ? displayTitle : '@$displayTitle',
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            trailing: Checkbox(
              value: isSelected,
              activeColor: AppColors.primary,
              onChanged: (_) => onTap(),
            ),
          ),
        );
      },
    );
  }
}
