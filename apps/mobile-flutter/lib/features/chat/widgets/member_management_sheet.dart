import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/chat_provider.dart';
import '../repositories/group_chat_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MemberManagementSheet extends ConsumerWidget {
  final String groupId;
  final List<String> memberIds;
  final bool canManage;

  const MemberManagementSheet({
    super.key,
    required this.groupId,
    required this.memberIds,
    this.canManage = true,
  });

  Future<void> _removeMember(
    BuildContext context,
    String userId,
    String username,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa thành viên?'),
        content: Text('Bạn có chắc chắn muốn mời $username ra khỏi nhóm?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await GroupChatRepository(
          FirebaseFirestore.instance,
        ).changeMembers(groupId, [userId], add: false);
        if (context.mounted) Navigator.pop(context);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Không thể xóa thành viên. Chỉ chủ nhóm có quyền này.',
              ),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final theme = Theme.of(context);

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: Material(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Thành viên nhóm',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: memberIds.length,
                itemBuilder: (context, index) {
                  final userId = memberIds[index];
                  final profileAsync = ref.watch(chatProfileProvider(userId));

                  return profileAsync.when(
                    data: (profile) {
                      final isMe = userId == currentUid;

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: profile.avatarUrl.isNotEmpty
                              ? NetworkImage(profile.avatarUrl)
                              : null,
                          child: profile.avatarUrl.isEmpty
                              ? const Icon(Icons.person)
                              : null,
                        ),
                        title: Text(profile.username + (isMe ? ' (Bạn)' : '')),
                        trailing: canManage && !isMe
                            ? IconButton(
                                icon: const Icon(
                                  Icons.person_remove_outlined,
                                  color: Colors.red,
                                ),
                                onPressed: () => _removeMember(
                                  context,
                                  userId,
                                  profile.username,
                                ),
                              )
                            : null,
                      );
                    },
                    loading: () => const ListTile(title: Text('Đang tải...')),
                    error: (_, _) => const SizedBox.shrink(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
