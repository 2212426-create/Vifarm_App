import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:toptop_flutter/core/theme/app_theme.dart';
import '../repositories/group_chat_repository.dart';
import 'package:toptop_flutter/features/chat/providers/chat_provider.dart';
import 'package:toptop_flutter/features/chat/widgets/add_members_sheet.dart';

class GroupSettingsScreen extends ConsumerStatefulWidget {
  final String groupId;

  const GroupSettingsScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupSettingsScreen> createState() =>
      _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends ConsumerState<GroupSettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.groupId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Scaffold(
            body: Center(child: Text('Không thể truy cập nhóm.')),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snapshot.data!.data() as Map<String, dynamic>?;
        if (data == null) {
          return const Scaffold(
            body: Center(child: Text('Nhóm không còn tồn tại.')),
          );
        }
        final name = data['groupName'] ?? 'Nhóm';
        final memberIds = List<String>.from(data['memberIds'] ?? []);
        final isPinned =
            (data['pinnedBy']
                as Map?)?[FirebaseAuth.instance.currentUser?.uid] ==
            true;
        final isMuted = data['isMuted'] ?? false;
        final creatorId = data['createdBy'] ?? '';
        final currentUid = FirebaseAuth.instance.currentUser?.uid;
        final isAdmin = creatorId == currentUid;
        final closed = data['closed'] == true;

        return Scaffold(
          appBar: AppBar(
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            ),
            title: Text(
              name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          body: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    if (closed)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Nhóm đã kết thúc. Bạn chỉ có thể xem lịch sử.',
                        ),
                      ),
                    _buildQuickActions(context, memberIds, isAdmin && !closed),
                    const SizedBox(height: 20),
                    _buildSettingsList(
                      context,
                      isPinned,
                      isMuted,
                      isAdmin,
                      memberIds,
                      closed,
                    ),
                  ],
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _SliverAppBarDelegate(
                  TabBar(
                    controller: _tabController,
                    indicatorColor: AppTheme.primaryColor,
                    labelColor: Colors.black,
                    unselectedLabelColor: Colors.grey,
                    tabs: const [
                      Tab(icon: Icon(Icons.people_outline)),
                      Tab(icon: Icon(Icons.link_outlined)),
                      Tab(icon: Icon(Icons.photo_library_outlined)),
                    ],
                  ),
                ),
              ),
            ],
            body: TabBarView(
              controller: _tabController,
              children: [
                _buildMembersTab(memberIds, creatorId),
                const Center(child: Text('Liên kết đã chia sẻ sẽ hiện ở đây')),
                _buildAlbumTab(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuickActions(
    BuildContext context,
    List<String> memberIds,
    bool canManage,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        if (canManage)
          _buildActionItem(Icons.person_add_outlined, 'Thêm người', () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (context) => AddMembersSheet(
                groupId: widget.groupId,
                existingMemberIds: memberIds,
              ),
            );
          }),
        if (canManage)
          _buildActionItem(Icons.link, 'Liên kết mời', () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Mời bằng liên kết chưa được hỗ trợ.'),
              ),
            );
          }),
        _buildActionItem(Icons.search, 'Tìm kiếm', () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Dùng nút kính lúp trong màn trò chuyện để tìm tin nhắn.',
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildActionItem(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.grey[100],
            child: Icon(icon, color: Colors.black87),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildSettingsList(
    BuildContext context,
    bool isPinned,
    bool isMuted,
    bool isAdmin,
    List<String> memberIds,
    bool closed,
  ) {
    return Column(
      children: [
        _buildListTile(
          Icons.bubble_chart_outlined,
          'Bong bóng trò chuyện (chưa hỗ trợ)',
          trailing: const Icon(Icons.chevron_right),
        ),
        _buildListTile(
          Icons.music_note_outlined,
          'Âm báo (chưa hỗ trợ)',
          trailing: const Icon(Icons.chevron_right),
        ),
        _buildListTile(
          Icons.push_pin_outlined,
          'Ghim lên đầu',
          trailing: Switch(
            value: isPinned,
            onChanged: closed
                ? null
                : (v) => FirebaseFirestore.instance
                      .collection('chats')
                      .doc(widget.groupId)
                      .update({
                        'pinnedBy.${FirebaseAuth.instance.currentUser!.uid}': v,
                      })
                      .catchError((Object _) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Không thể cập nhật ghim.'),
                            ),
                          );
                        }
                      }),
            activeThumbColor: AppTheme.primaryColor,
          ),
        ),
        _buildListTile(
          Icons.notifications_none,
          'Thông báo nền (chưa hỗ trợ)',
          trailing: Text(
            isMuted ? 'Tắt' : 'Tất cả',
            style: const TextStyle(color: Colors.grey),
          ),
        ),
        _buildListTile(
          Icons.flag_outlined,
          'Báo cáo nhóm (chưa hỗ trợ)',
          trailing: const Icon(Icons.chevron_right),
        ),
        if (!closed && isAdmin)
          _buildListTile(
            Icons.settings_outlined,
            'Quản lý nhóm',
            trailing: const Icon(Icons.chevron_right),
            onTap: isAdmin
                ? () => context.push('/group-management/${widget.groupId}')
                : null,
          ),
        if (!closed && !isAdmin)
          _buildListTile(
            Icons.logout,
            'Rời nhóm',
            textColor: Colors.red,
            onTap: () => _leaveGroup(context),
          ),
      ],
    );
  }

  Widget _buildListTile(
    IconData icon,
    String title, {
    Widget? trailing,
    Color? textColor,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: textColor ?? Colors.black87),
      title: Text(
        title,
        style: TextStyle(color: textColor, fontWeight: FontWeight.w500),
      ),
      trailing: trailing,
      onTap: onTap,
    );
  }

  Widget _buildMembersTab(List<String> memberIds, String creatorId) {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 16),
      itemCount: memberIds.length,
      itemBuilder: (context, index) {
        final userId = memberIds[index];
        final profileAsync = ref.watch(chatProfileProvider(userId));
        return profileAsync.when(
          data: (profile) => ListTile(
            leading: CircleAvatar(
              backgroundImage: profile.avatarUrl.isNotEmpty
                  ? NetworkImage(profile.avatarUrl)
                  : null,
            ),
            title: Text(profile.username),
            subtitle: userId == creatorId
                ? const Text(
                    'Chủ nhóm',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  )
                : null,
          ),
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
        );
      },
    );
  }

  Widget _buildAlbumTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.groupId)
          .collection('messages')
          .where('type', isEqualTo: 'image')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Không thể tải ảnh của nhóm.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.photo_library_outlined,
                  size: 64,
                  color: Colors.grey[300],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Ảnh đã chia sẻ sẽ hiển thị tại đây',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(2),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
          ),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            return Image.network(
              data['message'],
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
            );
          },
        );
      },
    );
  }

  Future<void> _leaveGroup(BuildContext context) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rời khỏi nhóm?'),
        content: const Text('Bạn sẽ không còn nhận được tin nhắn từ nhóm này.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rời nhóm', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await GroupChatRepository(
          FirebaseFirestore.instance,
        ).changeMembers(widget.groupId, [currentUid], add: false);
        if (context.mounted) context.go('/inbox');
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Không thể rời nhóm. Chủ nhóm cần kết thúc nhóm trước.',
              ),
            ),
          );
        }
      }
    }
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar);

  final TabBar _tabBar;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: Colors.white, child: _tabBar);
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) => false;
}
