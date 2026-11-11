import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../profile/providers/profile_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MemberManagementSheet extends ConsumerWidget {
  final String groupId;
  final List<String> memberIds;

  const MemberManagementSheet({
    super.key,
    required this.groupId,
    required this.memberIds,
  });

  Future<void> _removeMember(BuildContext context, String userId, String username) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa thành viên?'),
        content: Text('Bạn có chắc chắn muốn mời $username ra khỏi nhóm?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance.collection('chats').doc(groupId).update({
        'memberIds': FieldValue.arrayRemove([userId]),
      });

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(groupId)
          .collection('messages')
          .add({
        'senderId': 'system',
        'message': 'Thành viên $username đã bị mời ra khỏi nhóm.',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'type': 'system',
      });
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final theme = Theme.of(context);

    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2)),
          ),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Thành viên nhóm', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: memberIds.length,
              itemBuilder: (context, index) {
                final userId = memberIds[index];
                final profileAsync = ref.watch(userProfileStreamProvider(userId));

                return profileAsync.when(
                  data: (profile) {
                    if (profile == null) return const SizedBox.shrink();
                    final isMe = userId == currentUid;

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: profile.avatarUrl.isNotEmpty ? NetworkImage(profile.avatarUrl) : null,
                        child: profile.avatarUrl.isEmpty ? const Icon(Icons.person) : null,
                      ),
                      title: Text(profile.username + (isMe ? ' (Bạn)' : '')),
                      trailing: !isMe
                          ? IconButton(
                              icon: const Icon(Icons.person_remove_outlined, color: Colors.red),
                              onPressed: () => _removeMember(context, userId, profile.username),
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
    );
  }
}
