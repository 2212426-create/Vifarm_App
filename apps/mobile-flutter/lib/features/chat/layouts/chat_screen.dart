import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../video_upload/providers/upload_provider.dart';
import '../providers/chat_provider.dart';
import '../repositories/chat_repository.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/typing_indicator.dart';
import '../widgets/chat_connection_banner.dart';

/// Màn hình Chat chi tiết giữa 2 người dùng
/// Đã tích hợp: VideoShareCard, Typing Indicator, Read Receipt
class ChatScreen extends ConsumerStatefulWidget {
  final String receiverId;
  final String receiverName;
  final String receiverAvatar;

  const ChatScreen({
    super.key,
    required this.receiverId,
    this.receiverName = '',
    this.receiverAvatar = '',
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _typingTimer;
  String? _roomId;
  late final ChatRepository _chatRepository;
  String? _myUid;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _chatRepository = ref.read(chatRepositoryProvider);
    _myUid = ref.read(authStateProvider).valueOrNull?.uid;
    _messageController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _stopTyping();
    _messageController.removeListener(_onTextChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    super.dispose();
  }

  /// Gọi khi text thay đổi → cập nhật typing indicator lên Firebase
  void _onTextChanged() {
    if (_roomId == null || _myUid == null) return;

    if (_messageController.text.trim().isNotEmpty) {
      _chatRepository.setTyping(
        roomId: _roomId!,
        userId: _myUid!,
        isTyping: true,
      );
      // Auto-reset sau 3 giây nếu không gõ thêm
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 3), _stopTyping);
    } else {
      _stopTyping();
    }
  }

  void _stopTyping() {
    if (_roomId == null || _myUid == null) return;
    try {
      _chatRepository.setTyping(
        roomId: _roomId!,
        userId: _myUid!,
        isTyping: false,
      );
    } catch (_) {}
  }

  Future<bool> _sendMessage({String type = 'text', String? messageText}) async {
    final text = messageText ?? _messageController.text.trim();
    if (_sending || text.isEmpty || _myUid == null) return false;
    final draft = _messageController.text;
    setState(() => _sending = true);

    // Dừng typing khi gửi
    _typingTimer?.cancel();
    _stopTyping();

    try {
      await _chatRepository.sendMessage(
        senderId: _myUid!,
        receiverId: widget.receiverId,
        message: text,
        type: type,
      );

      if (mounted && type == 'text' && _messageController.text == draft) {
        _messageController.clear();
      }
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Chưa gửi được tin nhắn. Kiểm tra kết nối và thử lại.',
            ),
          ),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (picked == null) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đang tải ảnh lên Cloudinary...'),
          duration: Duration(seconds: 30),
        ),
      );
    }

    try {
      final uploadRepo = ref.read(uploadRepositoryProvider);
      final url = await uploadRepo.uploadImageToCloudinary(file: picked);

      final sent = await _sendMessage(type: 'image', messageText: url);
      if (!sent) return;

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Gửi ảnh thành công!')));
      }
    } catch (e) {
      debugPrint("Error sending image to Cloudinary in ChatScreen: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi gửi ảnh: $e')));
      }
    }
  }

  /// Đánh dấu đã xem sau khi load tin nhắn
  void _markAsSeen(String roomId, String currentUid) {
    if (widget.receiverId == 'system_admin') return;
    _chatRepository.markMessagesAsSeen(
      roomId: roomId,
      viewerId: currentUid,
      otherUserId: widget.receiverId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = ref.watch(authStateProvider).valueOrNull?.uid;
    _myUid = currentUid;
    final isSystem = widget.receiverId == 'system_admin';

    // Theme-aware colors
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;
    final bubbleInputBg = isDark
        ? const Color(0xFF2C2C2E)
        : const Color(0xFFF0F0F0);
    final inputBarBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final inputBarBorder = isDark
        ? AppTheme.dividerColor
        : const Color(0xFFE3E3E4);

    // Xác định Room ID
    final roomId = currentUid != null
        ? _chatRepository.getRoomId(currentUid, widget.receiverId)
        : '';

    // Lưu roomId để dùng ở typing
    if (_roomId == null && roomId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _roomId = roomId;
      });
      _roomId = roomId;
    }

    // Theo dõi tin nhắn
    final messagesAsync = ref.watch(chatMessagesProvider(roomId));

    // Trạng thái đang nhập của đối phương
    final isOtherTyping =
        ref
            .watch(typingStatusProvider('$roomId|${widget.receiverId}'))
            .valueOrNull ??
        false;

    // Lấy thông tin thời gian thực của người nhận
    String displayUsername = widget.receiverName;
    String displayAvatar = widget.receiverAvatar;
    bool isOnline = false;

    if (!isSystem) {
      final profileAsync = ref.watch(chatProfileProvider(widget.receiverId));
      final onlineAsync = ref.watch(
        userOnlineStatusProvider(widget.receiverId),
      );
      isOnline = onlineAsync.valueOrNull ?? false;

      if (profileAsync.valueOrNull != null) {
        displayUsername = profileAsync.valueOrNull!.username;
        displayAvatar = profileAsync.valueOrNull!.avatarUrl;
      }
    } else {
      displayUsername = 'Hệ thống TopTop';
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: cs.onSurface),
          onPressed: () => context.pop(),
        ),
        title: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: isSystem
                      ? const Color(0xFFFE2C55).withValues(alpha: 0.1)
                      : cs.surface,
                  backgroundImage: displayAvatar.isNotEmpty
                      ? CachedNetworkImageProvider(displayAvatar, maxWidth: 80)
                      : null,
                  child: displayAvatar.isEmpty
                      ? Icon(
                          isSystem ? Icons.verified_user_rounded : Icons.person,
                          color: isSystem
                              ? const Color(0xFFFE2C55)
                              : cs.onSurface,
                          size: 20,
                        )
                      : null,
                ),
                if (isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.scaffoldBackgroundColor,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayUsername.isNotEmpty ? displayUsername : 'Người dùng',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (!isSystem)
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: isOtherTyping
                          ? const Text(
                              'Đang nhập...',
                              key: ValueKey('typing'),
                              style: TextStyle(
                                color: AppTheme.primaryColor,
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                              ),
                            )
                          : Text(
                              isOnline ? 'Đang hoạt động' : 'Ngoại tuyến',
                              key: const ValueKey('status'),
                              style: TextStyle(
                                color: isOnline
                                    ? Colors.green
                                    : AppTheme.textHint,
                                fontSize: 11,
                              ),
                            ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const ChatConnectionBanner(),
            // Danh sách tin nhắn
            Expanded(
              child: messagesAsync.when(
                data: (messages) {
                  // Đánh dấu seen khi nhận được tin nhắn
                  if (currentUid != null && roomId.isNotEmpty) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _markAsSeen(roomId, currentUid);
                    });
                  }

                  if (messages.isEmpty) {
                    return Center(
                      child: Text(
                        isSystem
                            ? 'Không có thông báo hệ thống nào.'
                            : 'Hãy gửi tin nhắn để bắt đầu cuộc trò chuyện.',
                        style: const TextStyle(
                          color: AppTheme.textHint,
                          fontSize: 13,
                        ),
                      ),
                    );
                  }

                  final reversedMessages = messages.reversed.toList();

                  // Tìm chỉ mục của tin nhắn đã xem mới nhất do mình gửi
                  int latestSeenMsgIndex = -1;
                  for (int i = 0; i < reversedMessages.length; i++) {
                    final msg = reversedMessages[i];
                    if (msg.senderId == currentUid &&
                        msg.isSeenBy(widget.receiverId)) {
                      latestSeenMsgIndex = i;
                      break;
                    }
                  }

                  return ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    itemCount:
                        reversedMessages.length + (isOtherTyping ? 1 : 0),
                    itemBuilder: (context, index) {
                      // Typing indicator ở đầu danh sách (index 0 khi reverse)
                      if (isOtherTyping && index == 0) {
                        return const Padding(
                          padding: EdgeInsets.only(bottom: 4),
                          child: TypingIndicator(),
                        );
                      }

                      final msgIndex = isOtherTyping ? index - 1 : index;
                      final msg = reversedMessages[msgIndex];
                      final isMsgMe = msg.senderId == currentUid;

                      return ChatBubble(
                        message: msg,
                        isMe: isMsgMe,
                        otherUserAvatar: displayAvatar,
                        showSeenAvatar: msgIndex == latestSeenMsgIndex,
                        currentUid: currentUid,
                      );
                    },
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFFFE2C55),
                    ),
                  ),
                ),
                error: (error, _) => _buildErrorWidget(context, error),
              ),
            ),

            // Thanh nhập tin nhắn
            if (isSystem)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: inputBarBg,
                  border: Border(
                    top: BorderSide(color: inputBarBorder, width: 0.5),
                  ),
                ),
                child: Text(
                  'Bạn không thể phản hồi tin nhắn hệ thống này.',
                  style: TextStyle(
                    color: isDark ? AppTheme.textHint : Colors.grey[600],
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: inputBarBg,
                  border: Border(
                    top: BorderSide(color: inputBarBorder, width: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    // Nút gửi ảnh
                    IconButton(
                      icon: const Icon(
                        Icons.camera_alt_outlined,
                        color: AppTheme.textHint,
                      ),
                      onPressed: _sendImage,
                    ),
                    // Input field
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: bubbleInputBg,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: TextField(
                          controller: _messageController,
                          style: TextStyle(color: cs.onSurface, fontSize: 14),
                          textCapitalization: TextCapitalization.sentences,
                          minLines: 1,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: 'Gửi tin nhắn...',
                            hintStyle: TextStyle(
                              color: isDark
                                  ? AppTheme.textHint
                                  : Colors.grey[500],
                              fontSize: 14,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            filled: false,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Nút gửi
                    Material(
                      color: const Color(0xFFFE2C55),
                      borderRadius: BorderRadius.circular(22),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: _sending ? null : () => _sendMessage(),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: _sending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.send_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget(BuildContext context, Object error) {
    final errStr = error.toString();
    final isPermissionDenied =
        errStr.contains('permission-denied') ||
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
                const Icon(
                  Icons.lock_person_rounded,
                  color: Color(0xFFFE2C55),
                  size: 44,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Quyền truy cập bị từ chối',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Không thể tải tin nhắn do Firebase Realtime Database Rules chưa cho phép.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFE2C55),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: const Color(0xFF1E1E1E),
                        title: const Text(
                          'Cách cấu hình Firebase Rules',
                          style: TextStyle(color: Colors.white),
                        ),
                        content: const SingleChildScrollView(
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
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text(
                              'Đã hiểu',
                              style: TextStyle(color: Color(0xFFFE2C55)),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                  child: const Text(
                    'Xem cách cấu hình',
                    style: TextStyle(fontSize: 12),
                  ),
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
          style: const TextStyle(color: Colors.red, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
