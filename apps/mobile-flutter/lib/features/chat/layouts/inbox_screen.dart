import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/shimmer_loading.dart';
import '../models/chat_preview_model.dart';
import '../providers/chat_provider.dart';
import '../widgets/active_users_row.dart';
import '../widgets/chat_list_tile.dart';
import '../widgets/chat_connection_banner.dart';
import '../widgets/create_group_bottom_sheet.dart';
import '../../auth/models/profile_model.dart';
import '../../auth/providers/auth_provider.dart';

/// Màn hình Hộp thư (Danh sách Chat & Active Users)
/// Port từ InboxFragment.java trong Android project
class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  /// Tính toán thời gian tương đối
  String _formatTime(int timestamp) {
    if (timestamp <= 0) return '';
    final difference = DateTime.now().millisecondsSinceEpoch - timestamp;
    final diffMinutes = difference ~/ (1000 * 60);
    final diffHours = difference ~/ (1000 * 60 * 60);
    final diffDays = difference ~/ (1000 * 60 * 60 * 24);

    if (diffMinutes <= 60) {
      return '${diffMinutes}m';
    } else if (diffHours <= 24) {
      return '${diffHours}h';
    } else {
      return '${diffDays}d';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversationsAsync = ref.watch(chatConversationsProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;
    final dividerColor = isDark
        ? const Color(0xFF222224)
        : const Color(0xFFE8E8E8);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        title: Text(
          'Hộp thư',
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          // Nút tạo nhóm mới
          IconButton(
            icon: Icon(Icons.group_add_outlined, color: cs.onSurface, size: 26),
            onPressed: () {
              final currentUid = ref.read(authStateProvider).valueOrNull?.uid;
              if (currentUid != null) {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => CreateGroupBottomSheet(
                    initialFriend: ProfileModel(
                      userId: '',
                      username: 'Nhóm mới',
                    ),
                  ),
                );
              }
            },
          ),
          // Nút xem thông báo tương tác với Badge số lượng thông báo mới đè lên chuông
          Consumer(
            builder: (context, ref, child) {
              final notifications =
                  ref.watch(notificationsProvider).valueOrNull ?? [];
              final lastRead = ref.watch(lastReadNotificationTimestampProvider);
              final newCount = notifications
                  .where((n) => n.timestamp > lastRead)
                  .length;

              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.notifications_outlined,
                      color: cs.onSurface,
                      size: 26,
                    ),
                    onPressed: () {
                      // Đánh dấu đã xem toàn bộ thông báo hiện tại
                      ref
                          .read(lastReadNotificationTimestampProvider.notifier)
                          .updateTimestamp();
                      context.push('/notifications');
                    },
                  ),
                  if (newCount > 0)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        decoration: const BoxDecoration(
                          color: AppTheme.primaryColor,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Center(
                          child: Text(
                            newCount > 99 ? '99+' : '$newCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thanh danh sách người dùng Online ngang
          const ActiveUsersRow(),
          const ChatConnectionBanner(),

          // Danh sách các cuộc hội thoại dọc
          Expanded(
            child: conversationsAsync.when(
              data: (conversations) {
                if (conversations.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.mail_outline_rounded,
                          size: 64,
                          color: isDark ? AppTheme.textHint : Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Hộp thư trống',
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Bắt đầu nhắn tin với bạn bè của bạn',
                          style: TextStyle(
                            color: isDark
                                ? AppTheme.textHint
                                : Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: conversations.length,
                  separatorBuilder: (context, index) =>
                      Divider(height: 1, indent: 76, color: dividerColor),
                  itemBuilder: (context, index) {
                    final conv = conversations[index];
                    final isGroup = conv['isGroup'] == true;

                    if (isGroup) {
                      return ChatListTile(
                        chat: ChatPreview(
                          id: conv['chatId'] as String? ?? '',
                          title: conv['title'] as String? ?? 'Nhóm',
                          avatarUrl: conv['avatarUrl'] as String? ?? '',
                          memberIds: List<String>.from(conv['memberIds'] ?? []),
                          isGroup: true,
                          isPinned: conv['isPinned'] == true,
                          lastMessage: conv['lastMessage'] as String? ?? '',
                          lastMessageAt: DateTime.fromMillisecondsSinceEpoch(
                            conv['timestamp'] as int? ?? 0,
                          ),
                        ),
                      );
                    }

                    final otherUserId = conv['userId'] as String;
                    final lastMsg =
                        conv['lastMessage'] as String? ?? 'Chưa có tin nhắn';
                    final timestamp = conv['timestamp'] as int;
                    final isPinned = conv['isPinned'] == true;

                    return _ConversationTile(
                      otherUserId: otherUserId,
                      lastMessage: lastMsg,
                      timestamp: timestamp,
                      formatTime: _formatTime(timestamp),
                      isPinned: isPinned,
                    );
                  },
                );
              },
              loading: () => const ShimmerInboxList(),
              error: (error, _) => _buildErrorWidget(context, error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget(BuildContext context, Object error) {
    final denied = error.toString().toLowerCase().contains('permission');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          denied
              ? 'Không thể truy cập hộp thư. Vui lòng thử đăng nhập lại hoặc liên hệ hỗ trợ.'
              : 'Chưa tải được hộp thư. Kiểm tra kết nối và thử lại.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _ConversationTile extends ConsumerWidget {
  final String otherUserId;
  final String lastMessage;
  final int timestamp;
  final String formatTime;
  final bool isPinned;

  const _ConversationTile({
    required this.otherUserId,
    required this.lastMessage,
    required this.timestamp,
    required this.formatTime,
    this.isPinned = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSystem = otherUserId == 'system_admin';

    if (isSystem) {
      return _buildTile(
        context,
        ref,
        username: 'Hệ thống TopTop',
        avatarUrl: '',
        isOnline: false,
        isSystem: true,
      );
    }

    final profileAsync = ref.watch(chatProfileProvider(otherUserId));
    final isOnlineAsync = ref.watch(userOnlineStatusProvider(otherUserId));
    final isOnline = isOnlineAsync.valueOrNull ?? false;

    return profileAsync.when(
      data: (profile) {
        return _buildTile(
          context,
          ref,
          username: profile.username.isNotEmpty ? profile.username : 'User',
          avatarUrl: profile.avatarUrl,
          isOnline: isOnline,
          isSystem: false,
        );
      },
      loading: () => const SizedBox(height: 72),
      error: (error, stack) => _buildTile(
        context,
        ref,
        username: 'Người dùng',
        avatarUrl: '',
        isOnline: false,
        isSystem: false,
      ),
    );
  }

  Widget _buildTile(
    BuildContext context,
    WidgetRef ref, {
    required String username,
    required String avatarUrl,
    required bool isOnline,
    required bool isSystem,
  }) {
    final currentUid = ref.read(authStateProvider).valueOrNull?.uid;

    final chatPreview = ChatPreview(
      id: currentUid != null
          ? ref.read(chatRepositoryProvider).getRoomId(currentUid, otherUserId)
          : otherUserId,
      title: username,
      avatarUrl: avatarUrl,
      memberIds: currentUid != null ? [currentUid, otherUserId] : [otherUserId],
      lastMessage: lastMessage,
      lastMessageAt: DateTime.fromMillisecondsSinceEpoch(timestamp),
      isPinned: isPinned,
    );

    return ChatListTile(chat: chatPreview);
  }
}
