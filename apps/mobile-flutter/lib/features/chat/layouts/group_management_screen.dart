import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../video_upload/providers/upload_provider.dart';
import '../widgets/member_management_sheet.dart';

class GroupManagementScreen extends ConsumerWidget {
  final String groupId;

  const GroupManagementScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .doc(groupId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Scaffold(
            body: Center(child: Text('Không có quyền quản lý nhóm.')),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snapshot.data!.data() as Map<String, dynamic>?;
        if (data == null ||
            data['createdBy'] != FirebaseAuth.instance.currentUser?.uid ||
            data['closed'] == true) {
          return const Scaffold(
            body: Center(
              child: Text('Nhóm đã kết thúc hoặc bạn không phải chủ nhóm.'),
            ),
          );
        }
        final memberIds = List<String>.from(data['memberIds'] ?? []);
        final groupName = data['groupName'] ?? 'Nhóm';
        final avatarUrl = data['avatarUrl'] ?? '';

        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'Quản lý nhóm',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: 10),
            children: [
              _buildHeader(context, ref, groupName, avatarUrl),
              const SizedBox(height: 20),
              const ListTile(
                title: Text('Mời bằng liên kết và phân quyền quản trị viên'),
                subtitle: Text('Chưa hỗ trợ trong phiên bản này.'),
              ),
              _buildNavigationTile('Xóa thành viên', () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => MemberManagementSheet(
                    groupId: groupId,
                    memberIds: memberIds,
                  ),
                );
              }),
              const SizedBox(height: 20),
              const ListTile(
                title: Text('Chuyển quyền sở hữu'),
                subtitle: Text(
                  'Chưa hỗ trợ; chủ nhóm không thể rời khi nhóm còn hoạt động.',
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                title: const Center(
                  child: Text(
                    'Kết thúc nhóm',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                onTap: () => _endGroup(context),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref,
    String name,
    String avatar,
  ) {
    return Column(
      children: [
        GestureDetector(
          onTap: () => _updateGroupAvatar(context, ref),
          child: Stack(
            children: [
              CircleAvatar(
                radius: 40,
                backgroundImage: avatar.isNotEmpty
                    ? NetworkImage(avatar)
                    : null,
                child: avatar.isEmpty
                    ? const Icon(Icons.group, size: 40)
                    : null,
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: CircleAvatar(
                  radius: 12,
                  backgroundColor: AppTheme.primaryColor,
                  child: const Icon(
                    Icons.camera_alt,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: () => _editGroupName(context, name),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.edit, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _updateGroupAvatar(BuildContext context, WidgetRef ref) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
    );
    if (picked != null) {
      try {
        final uploadRepo = ref.read(uploadRepositoryProvider);
        final url = await uploadRepo.uploadImageToCloudinary(file: picked);

        await FirebaseFirestore.instance
            .collection('chats')
            .doc(groupId)
            .update({'avatarUrl': url});
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Lỗi cập nhật ảnh: $e')));
        }
      }
    }
  }

  Future<void> _editGroupName(BuildContext context, String currentName) async {
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đổi tên nhóm'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nhập tên nhóm mới'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != currentName) {
      try {
        await FirebaseFirestore.instance
            .collection('chats')
            .doc(groupId)
            .update({'groupName': newName});
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Không thể đổi tên nhóm (tối đa 80 ký tự).'),
            ),
          );
        }
      }
    }
  }

  Widget _buildNavigationTile(String title, VoidCallback onTap) {
    return ListTile(
      title: Text(
        title,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  Future<void> _endGroup(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kết thúc nhóm?'),
        content: const Text(
          'Nhóm sẽ ngừng nhận tin mới. Lịch sử được giữ cho các thành viên hiện tại.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kết thúc', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection('chats')
            .doc(groupId)
            .update({'closed': true});
        if (context.mounted) context.go('/inbox');
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không thể kết thúc nhóm.')),
          );
        }
      }
    }
  }
}
