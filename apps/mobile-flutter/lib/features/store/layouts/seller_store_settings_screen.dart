import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/app_mode_provider.dart';
import '../repositories/store_repository.dart';

/// Màn hình Cài Đặt Gian Hàng & Nút Chuyển Về Chế Độ Mua Sắm
class SellerStoreSettingsScreen extends ConsumerWidget {
  const SellerStoreSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    if (currentUser == null) return const Scaffold(body: Center(child: Text('Vui lòng đăng nhập!')));

    final storeAsync = ref.watch(userStoreStreamProvider(currentUser.uid));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản Lý Gian Hàng'),
      ),
      body: storeAsync.when(
        data: (store) {
          if (store == null) {
            return const Center(child: Text('Chưa khởi tạo gian hàng.'));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Switch to Normal Mode Button Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primary.withAlpha(50)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shopping_bag_outlined, color: AppColors.primary, size: 28),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Chế độ Bán Hàng', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            Text('Đang quản lý gian hàng của bạn', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                        onPressed: () async {
                          await ref.read(appModeProvider.notifier).switchToNormalMode();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Đã chuyển sang chế độ Mua sắm thông thường!')),
                            );
                            context.go('/home');
                          }
                        },
                        child: const Text('Sang Mua Sắm', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Public Storefront Preview Link
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.storefront, color: AppColors.primary),
                    title: const Text('Xem Trang Gian Hàng Công Khai'),
                    subtitle: const Text('Trang hiển thị sản phẩm và thông tin cho khách mua'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      context.push('/store/${store.storeId}');
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // Store Details & Verification Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('Hồ sơ xác minh gian hàng', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primary)),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.success.withAlpha(30),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('Đã xác minh', style: TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const Divider(),
                        Text('Tên gian hàng: ${store.storeName}'),
                        Text('Loại hình: ${store.storeType == "individual" ? "Cá nhân / Nhà vườn" : "Đơn vị kinh doanh"}'),
                        Text('Người liên hệ: ${store.contactName}'),
                        Text('Số điện thoại: ${store.phone}'),
                        Text('Địa chỉ: ${store.address}, ${store.region}'),
                        if (store.taxCode != null) Text('Mã số thuế: ${store.taxCode}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Operating status toggle
                Card(
                  child: SwitchListTile(
                    title: const Text('Trạng thái hoạt động gian hàng'),
                    subtitle: Text(store.operatingStatus == 'active' ? 'Đang mở cửa kinh doanh' : 'Đang tạm ngưng nhận đơn'),
                    value: store.operatingStatus == 'active',
                    activeThumbColor: AppColors.primary,
                    onChanged: (val) async {
                      final newStatus = val ? 'active' : 'suspended';
                      await ref.read(storeRepositoryProvider).updateStoreSettings(store.storeId, {
                        'operatingStatus': newStatus,
                      });
                    },
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Lỗi: $err')),
      ),
    );
  }
}
