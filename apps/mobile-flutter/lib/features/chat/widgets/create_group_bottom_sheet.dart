import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/models/profile_model.dart';
import '../providers/chat_provider.dart';

class CreateGroupBottomSheet extends ConsumerStatefulWidget {
  final ProfileModel? initialFriend;

  const CreateGroupBottomSheet({super.key, this.initialFriend});

  @override
  ConsumerState<CreateGroupBottomSheet> createState() =>
      _CreateGroupBottomSheetState();
}

class _CreateGroupBottomSheetState
    extends ConsumerState<CreateGroupBottomSheet> {
  final TextEditingController _nameController = TextEditingController();
  final List<String> _selectedUserIds = [];
  File? _groupAvatar;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialFriend != null &&
        widget.initialFriend!.userId.isNotEmpty) {
      _selectedUserIds.add(widget.initialFriend!.userId);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
    );
    if (picked != null && mounted) {
      setState(() => _groupAvatar = File(picked.path));
    }
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (_isCreating) return;
    if (name.isEmpty ||
        name.length > 80 ||
        _selectedUserIds.isEmpty ||
        _selectedUserIds.length > 49) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nhập tên 1–80 ký tự và chọn 1–49 thành viên.'),
        ),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (currentUid == null) return;

      final allMemberIds = {currentUid, ..._selectedUserIds}.toList();
      String? avatarUrl;

      // Upload avatar if picked
      if (_groupAvatar != null) {
        final ref = FirebaseStorage.instance
            .ref()
            .child('group_avatars')
            .child('${DateTime.now().millisecondsSinceEpoch}.jpg');
        await ref.putFile(_groupAvatar!);
        avatarUrl = await ref.getDownloadURL();
      }

      final docRef = await FirebaseFirestore.instance.collection('chats').add({
        'isGroup': true,
        'groupName': name,
        'avatarUrl': avatarUrl,
        'memberIds': allMemberIds,
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

      if (mounted) {
        final router = GoRouter.of(context);
        router.pop();
        router.push(
          '/groupchat/${docRef.id}?name=${Uri.encodeComponent(name)}',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi tạo nhóm: $e')));
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final friendsAsync = ref.watch(selectableFriendsProvider);
    final theme = Theme.of(context);

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Material(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: Column(
          children: [
            _buildHandle(),
            _buildHeader(),
            _buildAvatarPicker(),
            _buildNameInput(),
            const Divider(),
            _buildFriendsList(friendsAsync),
            _buildCreateButton(),
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

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(onPressed: () => context.pop(), child: const Text('Hủy')),
          const Text(
            'Nhóm mới',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          TextButton(
            onPressed: (_isCreating || _nameController.text.isEmpty)
                ? null
                : _createGroup,
            child: _isCreating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Tạo',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarPicker() {
    return GestureDetector(
      onTap: _pickAvatar,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 20),
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          shape: BoxShape.circle,
          image: _groupAvatar != null
              ? DecorationImage(
                  image: FileImage(_groupAvatar!),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: _groupAvatar == null
            ? const Icon(Icons.camera_alt, size: 30, color: Colors.grey)
            : null,
      ),
    );
  }

  Widget _buildNameInput() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: _nameController,
        decoration: const InputDecoration(
          hintText: 'Tên nhóm (bắt buộc)',
          border: InputBorder.none,
        ),
        onChanged: (v) => setState(() {}),
      ),
    );
  }

  Widget _buildFriendsList(AsyncValue<List<ProfileModel>> friendsAsync) {
    return Expanded(
      child: friendsAsync.when(
        data: (friends) {
          if (friends.isEmpty) {
            return const Center(child: Text('Không có bạn bè nào để thêm.'));
          }
          return ListView.builder(
            itemCount: friends.length,
            itemBuilder: (context, index) {
              final user = friends[index];
              final isSelected = _selectedUserIds.contains(user.userId);
              return CheckboxListTile(
                value: isSelected,
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
    );
  }

  Widget _buildCreateButton() {
    return Container(
      padding: const EdgeInsets.all(16),
      width: double.infinity,
      child: ElevatedButton(
        onPressed: (_isCreating || _nameController.text.isEmpty)
            ? null
            : _createGroup,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryColor,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const Text(
          'Tạo nhóm',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
