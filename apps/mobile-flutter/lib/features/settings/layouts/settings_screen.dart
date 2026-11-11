import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';

/// Màn hình Cài đặt & Quyền riêng tư (Settings Screen)
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = theme.scaffoldBackgroundColor;
    final cardColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final textColor = theme.colorScheme.onSurface;
    final hintColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('Cài đặt & Quyền riêng tư'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          _buildSectionHeader('Tài khoản'),
          _buildSettingsTile(
            context,
            icon: Icons.person_outline,
            title: 'Cài đặt tài khoản',
            subtitle: 'Thông tin cá nhân & quản lý tài khoản',
            cardColor: cardColor,
            textColor: textColor,
            hintColor: hintColor,
            onTap: () => context.push('/settings/account'),
          ),

          const SizedBox(height: 16),

          _buildSectionHeader('Cài đặt ứng dụng'),
          _buildSettingsTile(
            context,
            icon: Icons.palette_outlined,
            title: 'Giao diện hiển thị',
            subtitle: 'Chế độ Sáng / Tối',
            cardColor: cardColor,
            textColor: textColor,
            hintColor: hintColor,
            onTap: () => context.push('/settings/appearance'),
          ),

          const SizedBox(height: 16),

          _buildSectionHeader('Thông tin & Hỗ trợ'),
          _buildSettingsTile(
            context,
            icon: Icons.info_outline,
            title: 'Về ViFarm',
            subtitle: 'Phiên bản ${AppConstants.appVersion}',
            cardColor: cardColor,
            textColor: textColor,
            hintColor: hintColor,
            showChevron: false,
            onTap: () {},
          ),

          const SizedBox(height: 32),

          // Nút Đăng xuất
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? const Color(0xFF242428) : const Color(0xFFF1F1F3),
              foregroundColor: AppTheme.primaryColor,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => _showLogoutDialog(context, ref, isDark),
            child: const Text(
              'Đăng xuất',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildSettingsTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color cardColor,
    required Color textColor,
    required Color hintColor,
    required VoidCallback onTap,
    bool showChevron = true,
  }) {
    return Card(
      color: cardColor,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: Icon(icon, color: textColor, size: 22),
        title: Text(
          title,
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: hintColor, fontSize: 12),
        ),
        trailing: showChevron ? Icon(Icons.chevron_right, color: hintColor, size: 20) : null,
        onTap: onTap,
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, WidgetRef ref, bool isDark) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đăng xuất'),
        content: Text(
          'Bạn có chắc chắn muốn đăng xuất khỏi ViFarm?',
          style: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
            ),
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(authNotifierProvider.notifier).signOut();
              if (context.mounted) {
                context.go('/auth');
              }
            },
            child: const Text('Đăng xuất', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
