import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/chat_preview_model.dart';
import '../providers/chat_provider.dart';
import 'chat_options_popup.dart';
import 'create_group_bottom_sheet.dart';
import '../../profile/providers/profile_provider.dart';

/// ==== 1. Ví dụ 1 dòng trong danh sách Inbox có gắn onLongPress ====
class ChatListTile extends ConsumerStatefulWidget {
  final ChatPreview chat;
  const ChatListTile({super.key, required this.chat});

  @override
  ConsumerState<ChatListTile> createState() => _ChatListTileState();
}

class _ChatListTileState extends ConsumerState<ChatListTile> {
  Offset _tapPosition = Offset.zero;

  void _getTapPosition(TapDownDetails details) {
    _tapPosition = details.globalPosition;
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    return GestureDetector(
      onTapDown: _getTapPosition,
      onLongPress: () => widget.chat.isGroup
          ? context.push('/group-settings/${widget.chat.id}')
          : showChatOptionsPopup(
              context,
              tapPosition: _tapPosition,
              chat: widget.chat,
              onMarkUnread: () {
                FirebaseFirestore.instance
                    .collection('chats')
                    .doc(widget.chat.id)
                    .update({'isRead': !widget.chat.isRead});
              },
              onArchive: () {
                FirebaseFirestore.instance
                    .collection('chats')
                    .doc(widget.chat.id)
                    .update({'isArchived': !widget.chat.isArchived});
              },
              onTogglePin: () {
                final otherUid = widget.chat.isGroup
                    ? null
                    : widget.chat.memberIds.firstWhere(
                        (id) => id != currentUid,
                        orElse: () => '',
                      );

                ref
                    .read(chatRepositoryProvider)
                    .togglePin(
                      chatId: widget.chat.id,
                      isPinned: !widget.chat.isPinned,
                      isGroup: widget.chat.isGroup,
                      currentUid: currentUid,
                      otherUid: otherUid,
                    );
              },
              onToggleMute: () {
                FirebaseFirestore.instance
                    .collection('chats')
                    .doc(widget.chat.id)
                    .update({'isMuted': !widget.chat.isMuted});
              },
              onToggleStar: () {
                FirebaseFirestore.instance
                    .collection('chats')
                    .doc(widget.chat.id)
                    .update({'isStarred': !widget.chat.isStarred});
              },
              onDelete: () async {
                final currentUid = FirebaseAuth.instance.currentUser?.uid;
                if (currentUid == null) return;

                if (widget.chat.isGroup) {
                  // Đối với nhóm, ta có thể rời nhóm hoặc xóa cho bản thân.
                  // Ở đây ta thực hiện xóa record của user trong memberIds (Rời nhóm)
                  // HOẶC nếu bạn muốn xóa hẳn document (chỉ admin mới có quyền này thường)
                  // Tạm thời ta set isDeleted cho user này hoặc xóa hẳn chat document nếu là người tạo
                  await FirebaseFirestore.instance
                      .collection('chats')
                      .doc(widget.chat.id)
                      .delete();
                } else {
                  // Đối với 1-1, xóa record trong RTDB ChatList của mình
                  final database = FirebaseDatabase.instance;
                  final otherUid = widget.chat.memberIds.firstWhere(
                    (id) => id != currentUid,
                    orElse: () => '',
                  );
                  if (otherUid.isNotEmpty) {
                    await database
                        .ref('ChatList')
                        .child(currentUid)
                        .child(otherUid)
                        .remove();
                  }
                }

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Đã xóa cuộc trò chuyện')),
                  );
                }
              },
              onBlock: () async {
                if (currentUid == null) return;

                final otherUid = widget.chat.memberIds.firstWhere(
                  (id) => id != currentUid,
                  orElse: () => '',
                );

                if (otherUid.isNotEmpty) {
                  await FirebaseFirestore.instance
                      .collection('profiles')
                      .doc(currentUid)
                      .update({
                        'blockedUsers': FieldValue.arrayUnion([otherUid]),
                      });
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Đã chặn người dùng này')),
                    );
                  }
                }
              },
              onCreateGroup: (chat) async {
                final otherUid = chat.memberIds.firstWhere(
                  (id) => id != currentUid,
                  orElse: () => '',
                );
                if (otherUid.isEmpty) return;

                // Fetch profile of the person we long-pressed
                final profile = await ref
                    .read(profileRepositoryProvider)
                    .getProfile(otherUid);
                if (profile != null && context.mounted) {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) =>
                        CreateGroupBottomSheet(initialFriend: profile),
                  );
                }
              },
            ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        onTap: () {
          if (widget.chat.isGroup) {
            context.push(
              '/groupchat/${widget.chat.id}?name=${Uri.encodeComponent(widget.chat.title)}',
            );
          } else {
            final otherUid = widget.chat.memberIds.firstWhere(
              (id) => id != currentUid,
              orElse: () => '',
            );
            if (otherUid.isNotEmpty) {
              context.push(
                '/chat/$otherUid?name=${Uri.encodeComponent(widget.chat.title)}&avatar=${Uri.encodeComponent(widget.chat.avatarUrl ?? '')}',
              );
            }
          }
        },
        leading: CircleAvatar(
          radius: 26,
          backgroundColor: Colors.grey[800],
          backgroundImage:
              widget.chat.avatarUrl != null && widget.chat.avatarUrl!.isNotEmpty
              ? CachedNetworkImageProvider(widget.chat.avatarUrl!)
              : null,
          child: widget.chat.avatarUrl == null || widget.chat.avatarUrl!.isEmpty
              ? const Icon(Icons.person, size: 28, color: Colors.white)
              : null,
        ),
        title: Text(
          widget.chat.title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: widget.chat.lastMessage != null
            ? Text(
                widget.chat.lastMessage!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              )
            : null,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (widget.chat.lastMessageAt != null)
              Text(
                _formatTime(widget.chat.lastMessageAt!),
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            if (widget.chat.isPinned)
              const Padding(
                padding: EdgeInsets.only(top: 4.0),
                child: Icon(Icons.push_pin, size: 14, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final difference = DateTime.now().difference(time);
    if (difference.inMinutes < 60) return '${difference.inMinutes}m';
    if (difference.inHours < 24) return '${difference.inHours}h';
    return '${difference.inDays}d';
  }
}

/// ==== 2. Hành động "Tạo nhóm với người này" (Legacy function, better use CreateGroupBottomSheet) ====
Future<void> createGroupWith(BuildContext context, ChatPreview chat) async {
  final nameController = TextEditingController(text: '${chat.title} & bạn');

  final groupName = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Tạo nhóm mới'),
      content: TextField(
        controller: nameController,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Đặt tên nhóm'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, nameController.text.trim()),
          child: const Text('Tạo nhóm'),
        ),
      ],
    ),
  );

  if (groupName == null || groupName.isEmpty) return;

  final currentUid = FirebaseAuth.instance.currentUser?.uid;
  if (currentUid == null) return;

  final memberIds = <String>{currentUid, ...chat.memberIds}.toList();

  final docRef = await FirebaseFirestore.instance.collection('chats').add({
    'isGroup': true,
    'groupName': groupName,
    'memberIds': memberIds,
    'createdBy': currentUid,
    'createdAt': FieldValue.serverTimestamp(),
    'lastMessage': 'Bạn đã tạo nhóm.',
    'lastMessageAt': FieldValue.serverTimestamp(),
    'isPinned': false,
    'isMuted': false,
    'isStarred': false,
    'isArchived': false,
    'isRead': true,
  });

  if (context.mounted) {
    debugPrint('Đã tạo nhóm: ${docRef.id}');
    context.push(
      '/groupchat/${docRef.id}?name=${Uri.encodeComponent(groupName)}',
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Đã tạo nhóm: $groupName')));
  }
}
