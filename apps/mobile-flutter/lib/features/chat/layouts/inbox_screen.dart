import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/shimmer_loading.dart';
import '../../profile/providers/profile_provider.dart';
import '../models/chat_preview_model.dart';
import '../providers/chat_provider.dart';
import '../widgets/active_users_row.dart';
import '../widgets/chat_list_tile.dart';
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
    final dividerColor = isDark ? const Color(0xFF222224) : const Color(0xFFE8E8E8);

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
              final notifications = ref.watch(notificationsProvider).valueOrNull ?? [];
              final lastRead = ref.watch(lastReadNotificationTimestampProvider);
              final newCount = notifications.where((n) => n.timestamp > lastRead).length;

              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: Icon(Icons.notifications_outlined, color: cs.onSurface, size: 26),
                    onPressed: () {
                      // Đánh dấu đã xem toàn bộ thông báo hiện tại
                      ref.read(lastReadNotificationTimestampProvider.notifier).updateTimestamp();
                      context.push('/notifications');
                    },
                  ),
                  if (newCount > 0)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
                            color: isDark ? AppTheme.textHint : Colors.grey[600],
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
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    indent: 76,
                    color: dividerColor,
                  ),
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
                          lastMessageAt: DateTime.fromMillisecondsSinceEpoch(conv['timestamp'] as int? ?? 0),
                        ),
                      );
                    }

                    final otherUserId = conv['userId'] as String;
                    final lastMsg = conv['lastMessage'] as String? ?? 'Chưa có tin nhắn';
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final errStr = error.toString();
    final isPermissionDenied = errStr.contains('permission-denied') || 
                               errStr.contains('Permission denied') ||
                               errStr.contains('PERMISSION_DENIED');

    if (isPermissionDenied) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_person_rounded, color: Color(0xFFFE2C55), size: 48),
                const SizedBox(height: 16),
                Text(
                  'Quyền truy cập bị từ chối',
                  style: TextStyle(color: cs.onSurface, fontSize: 16, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Realtime Database Rules của dự án đang bị khóa hoặc chưa được cấp quyền đọc/ghi.',
                  style: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black54, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFE2C55),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: cs.surface,
                        title: Text('Cách cấu hình Firebase Rules', style: TextStyle(color: cs.onSurface)),
                        content: SingleChildScrollView(
                          child: Text(
                            'Vui lòng truy cập Firebase Console -> Realtime Database -> Rules, và dán cấu hình sau:\n\n'
                            '{\n'
                            '  "rules": {\n'
                            '    ".read": "auth != null",\n'
                            '    ".write": "auth != null"\n'
                            '  }\n'
                            '}\n\n'
                            'Sau đó nhấn "Publish" để áp dụng.',
                            style: TextStyle(
                              color: isDark ? AppTheme.textSecondary : Colors.black87,
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Đã hiểu', style: TextStyle(color: Color(0xFFFE2C55))),
                          ),
                        ],
                      ),
                    );
                  },
                  icon: const Icon(Icons.help_outline_rounded, size: 18),
                  label: const Text('Xem cách cấu hình', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          'Lỗi tải tin nhắn: $error',
          style: const TextStyle(color: Colors.red, fontSize: 14),
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

    final profileAsync = ref.watch(userProfileStreamProvider(otherUserId));
    final isOnlineAsync = ref.watch(userOnlineStatusProvider(otherUserId));
    final isOnline = isOnlineAsync.valueOrNull ?? false;

    return profileAsync.when(
      data: (profile) {
        if (profile == null) return const SizedBox.shrink();

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
      error: (error, stack) => const SizedBox.shrink(),
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
      id: currentUid != null ? ref.read(chatRepositoryProvider).getRoomId(currentUid, otherUserId) : otherUserId,
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
