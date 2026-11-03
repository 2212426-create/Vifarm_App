import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../features/auth/providers/auth_provider.dart';

/// Shell widget cho 5 tab chính của Nông Video (Giao diện Thông Thường):
/// 1. Trang chủ (Feed video kỹ thuật)
/// 2. Quanh đây (Địa điểm, nhà vườn, thời tiết)
/// 3. Nút + ở giữa (Đăng video / Thêm nhật ký)
/// 4. Chợ (Sản phẩm & giỏ hàng)
/// 5. Cá nhân (Hồ sơ, nhật ký, đơn mua, báo giá đã gửi, trạng thái gian hàng)
class BottomNavShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const BottomNavShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final currentBranch = navigationShell.currentIndex;
    final uiIndex = currentBranch >= 2 ? currentBranch + 1 : currentBranch;

    return Scaffold(
      body: navigationShell,
      extendBody: false,
      bottomNavigationBar: Container(
        color: Theme.of(context).brightness == Brightness.dark
            ? AppColors.darkBg
            : AppColors.lightBg,
        child: SafeArea(
          top: false,
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? AppColors.darkBorder
                      : AppColors.lightBorder,
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _NavItem(
                    icon: Icons.home_outlined,
                    activeIcon: Icons.home,
                    label: 'Trang chủ',
                    isActive: uiIndex == 0,
                    onTap: () => _onTap(context, ref, 0),
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    icon: Icons.near_me_outlined,
                    activeIcon: Icons.near_me,
                    label: 'Quanh đây',
                    isActive: uiIndex == 1,
                    onTap: () => _onTap(context, ref, 1),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: _AddButton(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        if (currentUser == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Vui lòng đăng nhập để tạo nội dung!',
                              ),
                            ),
                          );
                          context.go('/auth');
                          return;
                        }
                        _showCreateOptionsSheet(context);
                      },
                    ),
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    icon: Icons.storefront_outlined,
                    activeIcon: Icons.storefront,
                    label: 'Chợ',
                    isActive: uiIndex == 3,
                    onTap: () => _onTap(context, ref, 3),
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    icon: Icons.person_outline,
                    activeIcon: Icons.person,
                    label: 'Cá nhân',
                    isActive: uiIndex == 4,
                    onTap: () => _onTap(context, ref, 4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onTap(BuildContext context, WidgetRef ref, int uiIndex) {
    if (uiIndex == 2) return;

    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null && uiIndex == 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng đăng nhập để truy cập trang Cá nhân!'),
        ),
      );
      context.go('/auth');
      return;
    }

    final branchIndex = uiIndex > 2 ? uiIndex - 1 : uiIndex;
    HapticFeedback.selectionClick();

    navigationShell.goBranch(
      branchIndex,
      initialLocation: branchIndex == navigationShell.currentIndex,
    );
  }

  void _showCreateOptionsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bạn muốn làm gì?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.lightTextPrimary,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                leading: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.videocam,
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),
                title: const Text(
                  'Đăng video',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                subtitle: const Text(
                  'Chia sẻ kinh nghiệm, giới thiệu vườn, sản phẩm hoặc chuyện nhà nông.',
                  style: TextStyle(fontSize: 13, height: 1.3),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/camera');
                },
              ),
              const Divider(height: 16),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                leading: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withAlpha(50),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.menu_book,
                    color: AppColors.accentBrown,
                    size: 24,
                  ),
                ),
                title: const Text(
                  'Ghi nhật ký mùa vụ',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                subtitle: const Text(
                  'Ghi lại việc làm và sự phát triển của cây theo từng ngày.',
                  style: TextStyle(fontSize: 13, height: 1.3),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/journal/create');
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = AppColors.primary;
    final inactiveColor = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 60,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              color: isActive ? activeColor : inactiveColor,
              size: 24,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isActive ? activeColor : inactiveColor,
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AddButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Đăng nội dung',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 32,
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withAlpha(80),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(Icons.add, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}
