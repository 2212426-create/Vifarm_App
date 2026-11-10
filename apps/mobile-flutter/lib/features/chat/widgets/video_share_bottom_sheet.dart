import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../../video_feed/models/video_model.dart';
import '../providers/chat_provider.dart';
import '../../profile/providers/profile_provider.dart';

/// Bottom sheet nâng cao cho việc chia sẻ video kiểu TikTok
class VideoShareBottomSheet extends ConsumerStatefulWidget {
  final VideoModel video;

  const VideoShareBottomSheet({super.key, required this.video});

  @override
  ConsumerState<VideoShareBottomSheet> createState() =>
      _VideoShareBottomSheetState();
}

class _VideoShareBottomSheetState extends ConsumerState<VideoShareBottomSheet> {
  final TextEditingController _captionController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedRecipients = {};
  final Map<String, bool> _isGroupMap = {};
  String _searchQuery = '';

  @override
  void dispose() {
    _captionController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _handleSend({
    String? singleRecipientId,
    bool isSingleGroup = false,
  }) async {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;

    final repo = ref.read(chatRepositoryProvider);
    final caption = _captionController.text.trim();

    if (singleRecipientId != null) {
      await repo.sendVideoShare(
        senderId: currentUser.uid,
        receiverId: singleRecipientId,
        videoId: widget.video.videoId,
        isGroup: isSingleGroup,
        caption: caption,
      );
      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã gửi video!')));
      }
      return;
    }

    if (_selectedRecipients.isEmpty) return;

    for (final recipientId in _selectedRecipients) {
      final isGroup = _isGroupMap[recipientId] ?? false;
      await repo.sendVideoShare(
        senderId: currentUser.uid,
        receiverId: recipientId,
        videoId: widget.video.videoId,
        isGroup: isGroup,
        caption: caption,
      );
    }

    if (mounted) {
      context.pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đã chia sẻ cho ${_selectedRecipients.length} cuộc hội thoại!',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final conversationsAsync = ref.watch(chatConversationsProvider);
    final shareUrl = "${AppConstants.shareBaseUrl}${widget.video.videoId}";

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161722) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          _buildHandle(),
          Text(
            'Gửi tới',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 12),

          _buildActionRow(shareUrl, isDark),
          const Divider(height: 1, color: Colors.black12),

          _buildSearchAndCaption(isDark),

          Expanded(
            child: conversationsAsync.when(
              data: (allConversations) {
                final convs = allConversations
                    .where((c) => c['closed'] != true)
                    .toList();
                if (convs.isEmpty) {
                  return const Center(
                    child: Text('Chưa có cuộc trò chuyện nào.'),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 20),
                  itemCount: convs.length,
                  itemBuilder: (context, index) {
                    final c = convs[index];
                    final isGroup = c['isGroup'] == true;
                    final id = (isGroup ? c['chatId'] : c['userId']) as String;
                    final isSelected = _selectedRecipients.contains(id);
                    _isGroupMap[id] = isGroup;

                    return _RecipientTile(
                      id: id,
                      isGroup: isGroup,
                      title: isGroup ? (c['title'] ?? 'Nhóm') : null,
                      avatar: isGroup ? (c['avatarUrl'] ?? '') : null,
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
                      onQuickSend: () => _handleSend(
                        singleRecipientId: id,
                        isSingleGroup: isGroup,
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Lỗi: $e')),
            ),
          ),

          if (_selectedRecipients.isNotEmpty) _buildSendButton(isDark),
        ],
      ),
    );
  }

  Widget _buildHandle() {
    return Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildActionRow(String shareUrl, bool isDark) {
    return Container(
      height: 90,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildOption(Icons.copy, 'Sao chép', isDark, () {
            Clipboard.setData(ClipboardData(text: shareUrl));
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Đã sao chép link!')));
          }),
          _buildOption(Icons.download_rounded, 'Tải về', isDark, () {}),
          _buildOption(Icons.qr_code_scanner_rounded, 'Mã QR', isDark, () {}),
          _buildOption(Icons.sms_rounded, 'Tin nhắn', isDark, () {}),
          _buildOption(Icons.more_horiz, 'Thêm', isDark, () {}),
        ],
      ),
    );
  }

  Widget _buildOption(
    IconData icon,
    String label,
    bool isDark,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 80,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: isDark ? Colors.white12 : Colors.grey[200],
              child: Icon(
                icon,
                color: isDark ? Colors.white : Colors.black87,
                size: 24,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndCaption(bool isDark) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final hintColor = isDark ? AppTheme.textHint : Colors.grey[600];

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: isDark ? Colors.white12 : Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: TextField(
              controller: _searchController,
              cursorColor: AppColors.primary,
              style: TextStyle(color: textColor, fontSize: 14),
              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Tìm kiếm bạn bè...',
                hintStyle: TextStyle(fontSize: 13, color: hintColor),
                prefixIcon: Icon(Icons.search, size: 20, color: hintColor),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _captionController,
            cursorColor: AppColors.primary,
            style: TextStyle(color: textColor, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Thêm tin nhắn...',
              hintStyle: TextStyle(fontSize: 14, color: hintColor),
              filled: false,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: isDark ? Colors.white24 : Colors.grey[400]!,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: AppColors.primary,
                  width: 1.5,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSendButton(bool isDark) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16),
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: () => _handleSend(),
          child: Text(
            'Gửi (${_selectedRecipients.length})',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ),
      ),
    );
  }
}

class _RecipientTile extends ConsumerWidget {
  final String id;
  final bool isGroup;
  final String? title;
  final String? avatar;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onQuickSend;

  const _RecipientTile({
    required this.id,
    required this.isGroup,
    this.title,
    this.avatar,
    required this.isSelected,
    required this.onTap,
    required this.onQuickSend,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FutureBuilder(
      future: isGroup
          ? Future.value(null)
          : ref.read(userProfileStreamProvider(id).future),
      builder: (context, snap) {
        final profile = snap.data;
        final displayTitle = isGroup
            ? (title ?? 'Nhóm')
            : (profile?.username ?? id.substring(0, 8));
        final displayAvatar = isGroup
            ? (avatar ?? '')
            : (profile?.avatarUrl ?? '');

        return ListTile(
          onTap: onTap,
          leading: Stack(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: Colors.grey[200],
                backgroundImage: displayAvatar.isNotEmpty
                    ? NetworkImage(displayAvatar)
                    : null,
                child: displayAvatar.isEmpty
                    ? Icon(
                        isGroup ? Icons.group : Icons.person,
                        color: Colors.grey,
                        size: 22,
                      )
                    : null,
              ),
              if (isSelected)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(2),
                    child: const Icon(
                      Icons.check_circle,
                      color: AppTheme.primaryColor,
                      size: 18,
                    ),
                  ),
                ),
            ],
          ),
          title: Text(
            isGroup ? displayTitle : '@$displayTitle',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 14,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          trailing: isSelected
              ? null
              : ElevatedButton(
                  onPressed: onQuickSend,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(60, 32),
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: const Text(
                    'Gửi',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
        );
      },
    );
  }
}
