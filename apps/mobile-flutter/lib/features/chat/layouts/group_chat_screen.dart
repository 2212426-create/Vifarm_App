import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../video_upload/providers/upload_provider.dart';
import '../models/chat_message_model.dart';
import '../repositories/group_chat_repository.dart';
import '../providers/chat_provider.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/add_members_sheet.dart';
import '../widgets/member_management_sheet.dart';

/// Màn hình Chat Nhóm
class GroupChatScreen extends ConsumerStatefulWidget {
  final String groupId;
  final String groupName;

  const GroupChatScreen({
    super.key,
    required this.groupId,
    this.groupName = 'Nhóm',
  });

  @override
  ConsumerState<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends ConsumerState<GroupChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _sending = false;
  String? _myUid;
  bool _isSearching = false;

  bool get _canSend {
    final group = ref.read(groupDetailsProvider(widget.groupId));
    return !group.hasError &&
        group.valueOrNull != null &&
        group.valueOrNull!['closed'] != true &&
        (group.valueOrNull!['memberIds'] as List? ?? []).contains(_myUid);
  }

  @override
  void initState() {
    super.initState();
    _myUid = ref.read(authStateProvider).valueOrNull?.uid;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<bool> _sendMessage({
    String type = 'text',
    String? messageText,
    Map<String, dynamic>? metadata,
  }) async {
    final text = messageText ?? _messageController.text.trim();
    if (!_canSend || _sending || text.isEmpty || _myUid == null) return false;
    final draft = _messageController.text;
    setState(() => _sending = true);
    try {
      await GroupChatRepository(FirebaseFirestore.instance).send(
        groupId: widget.groupId,
        senderId: _myUid!,
        text: text,
        type: type,
        metadata: metadata,
      );
      if (mounted && type == 'text' && _messageController.text == draft) {
        _messageController.clear();
      }
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chưa gửi được. Nội dung vẫn được giữ để thử lại.'),
          ),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendImage() async {
    if (!_canSend || _sending) return;
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (picked == null || !mounted || !_canSend) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đang tải ảnh lên...'),
          duration: Duration(seconds: 30),
        ),
      );
    }

    try {
      final uploadRepo = ref.read(uploadRepositoryProvider);
      final url = await uploadRepo.uploadImageToCloudinary(file: picked);

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (!await _sendMessage(type: 'image', messageText: url)) return;

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Gửi ảnh thành công!')));
      }
    } catch (e) {
      debugPrint("Error sending image to Cloudinary: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi gửi ảnh: $e')));
      }
    }
  }

  void _showStickerPicker() {
    if (!_canSend) return;
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        height: 300,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'Chọn Sticker',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                ),
                itemCount: 8,
                itemBuilder: (context, index) {
                  final stickerUrl =
                      'https://api.dicebear.com/7.x/bottts/png?seed=$index';
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      _sendMessage(type: 'sticker', messageText: stickerUrl);
                    },
                    child: CachedNetworkImage(imageUrl: stickerUrl),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;
    final group = ref.watch(groupDetailsProvider(widget.groupId));
    final closed = group.valueOrNull?['closed'] == true;

    final bubbleInputBg = isDark
        ? const Color(0xFF2C2C2E)
        : const Color(0xFFF0F0F0);
    final inputBarBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final inputBarBorder = isDark
        ? AppTheme.dividerColor
        : const Color(0xFFE3E3E4);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            _isSearching ? Icons.close : Icons.arrow_back,
            color: cs.onSurface,
          ),
          onPressed: () {
            if (_isSearching) {
              setState(() {
                _isSearching = false;
                _searchController.clear();
              });
            } else {
              context.pop();
            }
          },
        ),
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(color: cs.onSurface, fontSize: 16),
                decoration: const InputDecoration(
                  hintText: 'Tìm kiếm tin nhắn...',
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() {}),
              )
            : StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('chats')
                    .doc(widget.groupId)
                    .snapshots(),
                builder: (context, snapshot) {
                  final data = snapshot.data?.data() as Map<String, dynamic>?;
                  final name = data?['groupName'] ?? widget.groupName;
                  final membersCount =
                      (data?['memberIds'] as List?)?.length ?? 0;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '$membersCount thành viên',
                        style: TextStyle(
                          color: AppTheme.textHint,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  );
                },
              ),
        actions: [
          IconButton(
            icon: Icon(
              _isSearching ? Icons.search : Icons.search,
              color: cs.onSurface,
            ),
            onPressed: () => setState(() => _isSearching = !_isSearching),
          ),
          IconButton(
            icon: Icon(Icons.more_horiz, color: cs.onSurface),
            onPressed: () => context.push('/group-settings/${widget.groupId}'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(widget.groupId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text(
                      'Không thể đọc tin nhắn. Nhóm có thể không còn quyền truy cập.',
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                var docs = snapshot.data!.docs;

                if (_isSearching && _searchController.text.isNotEmpty) {
                  final query = _searchController.text.toLowerCase();
                  docs = docs.where((doc) {
                    final msgData = doc.data() as Map<String, dynamic>;
                    final text = (msgData['message'] as String? ?? '')
                        .toLowerCase();
                    return text.contains(query);
                  }).toList();
                }

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  itemCount: docs.length + (_isSearching ? 0 : 1),
                  itemBuilder: (context, index) {
                    if (!_isSearching && index == docs.length) {
                      return _buildGroupHeader(context);
                    }
                    final data = docs[index].data() as Map<String, dynamic>;
                    final msg = ChatMessageModel.fromMap(
                      data,
                      id: docs[index].id,
                    );
                    final isMsgMe = msg.senderId == _myUid;

                    if (msg.type == 'system') {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            msg.message,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      );
                    }

                    return ChatBubble(
                      message: msg,
                      isMe: isMsgMe,
                      otherUserAvatar: '',
                      currentUid: _myUid,
                    );
                  },
                );
              },
            ),
          ),

          // Thanh nhập tin nhắn
          if (!_canSend)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  closed
                      ? 'Nhóm đã kết thúc. Bạn chỉ có thể xem lịch sử.'
                      : group.isLoading
                      ? 'Đang kiểm tra trạng thái nhóm...'
                      : 'Bạn không có quyền gửi tin trong nhóm này.',
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: inputBarBg,
                border: Border(
                  top: BorderSide(color: inputBarBorder, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.camera_alt_outlined,
                      color: AppTheme.textHint,
                    ),
                    onPressed: _sendImage,
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: bubbleInputBg,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: TextField(
                        controller: _messageController,
                        style: TextStyle(color: cs.onSurface, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Nhắn tin...',
                          hintStyle: TextStyle(
                            color: AppTheme.textHint,
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
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
                  IconButton(
                    icon: const Icon(
                      Icons.sentiment_satisfied_alt_outlined,
                      color: AppTheme.textHint,
                    ),
                    onPressed: _showStickerPicker,
                  ),
                  Material(
                    color: const Color(0xFFFE2C55),
                    borderRadius: BorderRadius.circular(22),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: _sending ? null : () => _sendMessage(),
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(
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
    );
  }

  Widget _buildGroupHeader(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.groupId)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final name = data?['groupName'] ?? widget.groupName;
        final avatarUrl = data?['avatarUrl'] as String?;
        final memberIds = List<String>.from(data?['memberIds'] ?? []);
        final canManage =
            !snapshot.hasError &&
            data?['closed'] != true &&
            data?['createdBy'] == _myUid;

        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: Colors.grey[300],
                backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                    ? CachedNetworkImageProvider(avatarUrl)
                    : null,
                child: avatarUrl == null || avatarUrl.isEmpty
                    ? const Icon(Icons.group, size: 40, color: Colors.white)
                    : null,
              ),
              const SizedBox(height: 16),
              Text(
                name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton(
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) => MemberManagementSheet(
                      groupId: widget.groupId,
                      memberIds: memberIds,
                      canManage: canManage,
                    ),
                  );
                },
                child: const Text(
                  'Xem thành viên nhóm',
                  style: TextStyle(color: Colors.blue),
                ),
              ),
              const SizedBox(height: 16),
              if (canManage)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildHeaderAction(
                      Icons.person_add_outlined,
                      'Thêm người',
                      () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (context) => AddMembersSheet(
                            groupId: widget.groupId,
                            existingMemberIds: memberIds,
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 32),
                    _buildHeaderAction(Icons.link, 'Liên kết mời', () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Mời bằng liên kết chưa được hỗ trợ. Chủ nhóm có thể thêm thành viên.',
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeaderAction(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.grey.withValues(alpha: 0.1),
            child: Icon(icon, color: Colors.black87),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
