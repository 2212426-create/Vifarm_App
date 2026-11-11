import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:toptop_flutter/core/theme/app_theme.dart';
import 'package:toptop_flutter/features/profile/providers/profile_provider.dart';
import 'package:toptop_flutter/features/chat/widgets/add_members_sheet.dart';

class GroupSettingsScreen extends ConsumerStatefulWidget {
  final String groupId;

  const GroupSettingsScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends ConsumerState<GroupSettingsScreen> with SingleTickerProviderStateMixin {
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
      stream: FirebaseFirestore.instance.collection('chats').doc(widget.groupId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        
        final data = snapshot.data!.data() as Map<String, dynamic>;
        final name = data['groupName'] ?? 'Nhóm';
        final memberIds = List<String>.from(data['memberIds'] ?? []);
        final isPinned = data['isPinned'] ?? false;
        final isMuted = data['isMuted'] ?? false;
        final creatorId = data['createdBy'] ?? '';
        final currentUid = FirebaseAuth.instance.currentUser?.uid;
        final isAdmin = creatorId == currentUid;

        return Scaffold(
          appBar: AppBar(
            elevation: 0,
            leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
            title: Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          body: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    _buildQuickActions(context, memberIds),
                    const SizedBox(height: 20),
                    _buildSettingsList(context, isPinned, isMuted, isAdmin, memberIds),
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

  Widget _buildQuickActions(BuildContext context, List<String> memberIds) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildActionItem(Icons.person_add_outlined, 'Thêm người', () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => AddMembersSheet(groupId: widget.groupId, existingMemberIds: memberIds),
          );
        }),
        _buildActionItem(Icons.link, 'Liên kết mời', () {
           // Copy link logic
        }),
        _buildActionItem(Icons.search, 'Tìm kiếm', () {}),
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

  Widget _buildSettingsList(BuildContext context, bool isPinned, bool isMuted, bool isAdmin, List<String> memberIds) {
    return Column(
      children: [
        _buildListTile(Icons.bubble_chart_outlined, 'Bong bóng trò chuyện', trailing: const Icon(Icons.chevron_right)),
        _buildListTile(Icons.music_note_outlined, 'Âm báo', trailing: const Icon(Icons.chevron_right)),
        _buildListTile(
          Icons.push_pin_outlined, 
          'Ghim lên đầu', 
          trailing: Switch(
            value: isPinned, 
            onChanged: (v) => FirebaseFirestore.instance.collection('chats').doc(widget.groupId).update({'isPinned': v}),
            activeColor: AppTheme.primaryColor,
          ),
        ),
        _buildListTile(Icons.notifications_none, 'Thông báo', trailing: Text(isMuted ? 'Tắt' : 'Tất cả', style: const TextStyle(color: Colors.grey))),
        _buildListTile(Icons.flag_outlined, 'Báo cáo', trailing: const Icon(Icons.chevron_right)),
        _buildListTile(
          Icons.settings_outlined, 
          'Quản lý nhóm', 
          trailing: const Icon(Icons.chevron_right),
          onTap: isAdmin ? () => context.push('/group-management/${widget.groupId}') : null,
        ),
        _buildListTile(Icons.logout, 'Rời nhóm', textColor: Colors.red, onTap: () => _leaveGroup(context)),
      ],
    );
  }

  Widget _buildListTile(IconData icon, String title, {Widget? trailing, Color? textColor, VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: textColor ?? Colors.black87),
      title: Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.w500)),
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
        final profileAsync = ref.watch(userProfileStreamProvider(userId));
        return profileAsync.when(
          data: (profile) => profile == null ? const SizedBox.shrink() : ListTile(
            leading: CircleAvatar(backgroundImage: profile.avatarUrl.isNotEmpty ? NetworkImage(profile.avatarUrl) : null),
            title: Text(profile.username),
            subtitle: userId == creatorId ? const Text('Chủ nhóm', style: TextStyle(color: Colors.grey, fontSize: 12)) : null,
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
          .where('type', whereIn: ['image', 'video'])
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.photo_library_outlined, size: 64, color: Colors.grey[300]),
                const SizedBox(height: 16),
                const Text('Ảnh và video sẽ hiển thị tại đây', style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(2),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            return Image.network(data['message'], fit: BoxFit.cover);
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Rời nhóm', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance.collection('chats').doc(widget.groupId).update({
        'memberIds': FieldValue.arrayRemove([currentUid]),
      });
      if (context.mounted) {
        context.go('/inbox');
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
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(color: Colors.white, child: _tabBar);
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) => false;
}
