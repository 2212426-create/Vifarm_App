import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../repositories/group_chat_repository.dart';
import '../providers/chat_provider.dart';

class AddMembersSheet extends ConsumerStatefulWidget {
  final String groupId;
  final List<String> existingMemberIds;

  const AddMembersSheet({
    super.key,
    required this.groupId,
    required this.existingMemberIds,
  });

  @override
  ConsumerState<AddMembersSheet> createState() => _AddMembersSheetState();
}

class _AddMembersSheetState extends ConsumerState<AddMembersSheet> {
  final List<String> _selectedUserIds = [];
  bool _isUpdating = false;

  Future<void> _addMembers() async {
    if (_selectedUserIds.isEmpty) return;
    setState(() => _isUpdating = true);

    try {
      await GroupChatRepository(
        FirebaseFirestore.instance,
      ).changeMembers(widget.groupId, _selectedUserIds, add: true);

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi thêm thành viên: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final friendsAsync = ref.watch(selectableFriendsProvider);
    final theme = Theme.of(context);

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Material(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: Column(
          children: [
            _buildHandle(),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Thêm thành viên',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${_selectedUserIds.length} đã chọn',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
            Expanded(
              child: friendsAsync.when(
                data: (friends) {
                  final notInGroup = friends
                      .where(
                        (f) => !widget.existingMemberIds.contains(f.userId),
                      )
                      .toList();
                  if (notInGroup.isEmpty) {
                    return const Center(
                      child: Text('Tất cả bạn bè đã có trong nhóm.'),
                    );
                  }
                  return ListView.builder(
                    itemCount: notInGroup.length,
                    itemBuilder: (context, index) {
                      final user = notInGroup[index];
                      final isSelected = _selectedUserIds.contains(user.userId);
                      return CheckboxListTile(
                        value: isSelected,
                        activeColor: AppTheme.primaryColor,
                        title: Text(user.username),
                        secondary: CircleAvatar(
                          backgroundImage: user.avatarUrl.isNotEmpty
                              ? NetworkImage(user.avatarUrl)
                              : null,
                          child: user.avatarUrl.isEmpty
                              ? const Icon(Icons.person)
                              : null,
                        ),
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedUserIds.add(user.userId);
                            } else {
                              _selectedUserIds.remove(user.userId);
                            }
                          });
                        },
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, s) => Center(child: Text('Lỗi: $e')),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_isUpdating || _selectedUserIds.isEmpty)
                    ? null
                    : _addMembers,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isUpdating
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'Thêm vào nhóm',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHandle() {
    return Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[600],
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
