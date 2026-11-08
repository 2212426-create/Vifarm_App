import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../orders/repositories/order_repository.dart';
import '../../products/repositories/product_repository.dart';
import '../../quote_requests/repositories/quote_repository.dart';
import '../repositories/store_repository.dart';

/// Màn hình Tổng quan Dành cho Người Bán (Seller Workspace)
class SellerOverviewScreen extends ConsumerWidget {
  const SellerOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    if (currentUser == null) {
      return const Scaffold(body: Center(child: Text('Vui lòng đăng nhập!')));
    }

    final storeAsync = ref.watch(userStoreStreamProvider(currentUser.uid));
    final ordersAsync = ref.watch(userOrdersStreamProvider(currentUser.uid));
    final quotesAsync = ref.watch(userQuotesStreamProvider(currentUser.uid));
    final productsAsync = ref.watch(sellerProductsStreamProvider(currentUser.uid));


    return Scaffold(
      appBar: AppBar(
        title: const Text('Tổng Quan Gian Hàng'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => context.push('/notifications'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Store Header Card & Status Banner
            storeAsync.when(
              data: (store) {
                if (store == null) return const SizedBox.shrink();

                Color bannerBg;
                IconData bannerIcon;
                String bannerText;

                if (store.status == 'pending') {
                  bannerBg = Colors.blue;
                  bannerIcon = Icons.hourglass_top;
                  bannerText = 'Hồ sơ đăng ký v${store.version} đang chờ Ban quản trị xét duyệt.';
                } else if (store.status == 'needs_changes') {
                  bannerBg = Colors.orange;
                  bannerIcon = Icons.warning_amber;
                  bannerText = 'Yêu cầu bổ sung hồ sơ v${store.version}: ${store.rejectionReason ?? "Vui lòng cập nhật lại thông tin."}';
                } else if (store.status == 'rejected') {
                  bannerBg = Colors.red;
                  bannerIcon = Icons.cancel;
                  bannerText = 'Hồ sơ v${store.version} bị từ chối: ${store.rejectionReason ?? "Không đạt tiêu chuẩn xác minh."}';
                } else {
                  bannerBg = Colors.green;
                  bannerIcon = Icons.verified;
                  bannerText = 'Gian hàng v${store.version} đã được Ban quản trị xác minh chính thức.';
                }

                return Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: bannerBg.withAlpha(30),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: bannerBg.withAlpha(100)),
                      ),
                      child: Row(
                        children: [
                          Icon(bannerIcon, color: bannerBg, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              bannerText,
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: bannerBg),
                            ),
                          ),
                          if (store.status == 'needs_changes' || store.status == 'rejected')
                            TextButton(
                              style: TextButton.styleFrom(padding: EdgeInsets.zero),
                              onPressed: () => context.push('/store/register'),
                              child: const Text('Cập nhật'),
                            ),
                        ],
                      ),
                    ),
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: AppColors.primary.withAlpha(30),
                              backgroundImage: store.avatarUrl.isNotEmpty ? NetworkImage(store.avatarUrl) : null,
                              child: store.avatarUrl.isEmpty ? const Icon(Icons.store, color: AppColors.primary) : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(store.storeName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  const SizedBox(height: 2),
                                  Text('${store.region} • ${store.storeType == "individual" ? "Cá nhân/Nhà vườn" : "Đơn vị kinh doanh"}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: store.canSell ? AppColors.success.withAlpha(30) : AppColors.warning.withAlpha(30),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                store.canSell ? 'Hoạt động' : 'Tạm ngưng',
                                style: TextStyle(
                                  color: store.canSell ? AppColors.success : AppColors.warning,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (e, s) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),

            // Quick Add Product Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.add_business, color: Colors.white),
                label: const Text('Đăng Sản Phẩm Mới', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                onPressed: () {
                  context.push('/marketplace/products/create');
                },
              ),
            ),
            const SizedBox(height: 20),

            // Metrics Section
            const Text('Chỉ số vận hành', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primary)),
            const SizedBox(height: 12),

            Row(
              children: [
                // Orders pending action
                Expanded(
                  child: ordersAsync.when(
                    data: (orders) {
                      final pendingCount = orders.where((o) => o.sellerId == currentUser.uid && (o.status == 'pending_seller_confirmation' || o.status == 'confirmed')).length;
                      return _MetricTile(
                        title: 'Đơn cần xử lý',
                        count: '$pendingCount',
                        icon: Icons.receipt_long,
                        color: AppColors.primary,
                        onTap: () => context.push('/seller/orders'),
                      );
                    },
                    loading: () => _MetricTile(title: 'Đơn cần xử lý', count: '...', icon: Icons.receipt_long, color: AppColors.primary),
                    error: (e, s) => _MetricTile(title: 'Đơn cần xử lý', count: '0', icon: Icons.receipt_long, color: AppColors.primary),
                  ),
                ),
                const SizedBox(width: 12),

                // Quotes pending action
                Expanded(
                  child: quotesAsync.when(
                    data: (quotes) {
                      final pendingCount = quotes.where((q) => q.sellerId == currentUser.uid && q.status == 'pending').length;
                      return _MetricTile(
                        title: 'Báo giá mới',
                        count: '$pendingCount',
                        icon: Icons.sell_outlined,
                        color: AppColors.accentBrown,
                        onTap: () => context.push('/seller/orders'),
                      );
                    },
                    loading: () => _MetricTile(title: 'Báo giá mới', count: '...', icon: Icons.sell_outlined, color: AppColors.accentBrown),
                    error: (e, s) => _MetricTile(title: 'Báo giá mới', count: '0', icon: Icons.sell_outlined, color: AppColors.accentBrown),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                // Low stock items
                Expanded(
                  child: productsAsync.when(
                    data: (products) {
                      final lowStockCount = products.where((p) => p.stock <= 5).length;
                      return _MetricTile(
                        title: 'Sắp hết hàng',
                        count: '$lowStockCount',
                        icon: Icons.warning_amber,
                        color: Colors.orange,
                        onTap: () => context.push('/seller/products'),
                      );
                    },
                    loading: () => _MetricTile(title: 'Sắp hết hàng', count: '...', icon: Icons.warning_amber, color: Colors.orange),
                    error: (e, s) => _MetricTile(title: 'Sắp hết hàng', count: '0', icon: Icons.warning_amber, color: Colors.orange),
                  ),
                ),
                const SizedBox(width: 12),

                // Total active products
                Expanded(
                  child: productsAsync.when(
                    data: (products) {
                      final activeCount = products.where((p) => p.status == 'active').length;
                      return _MetricTile(
                        title: 'SP đang bán',
                        count: '$activeCount',
                        icon: Icons.storefront,
                        color: Colors.blue,
                        onTap: () => context.push('/seller/products'),
                      );
                    },
                    loading: () => _MetricTile(title: 'SP đang bán', count: '...', icon: Icons.storefront, color: Colors.blue),
                    error: (e, s) => _MetricTile(title: 'SP đang bán', count: '0', icon: Icons.storefront, color: Colors.blue),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String title;
  final String count;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _MetricTile({
    required this.title,
    required this.count,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, color: color, size: 22),
                  Text(count, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
                ],
              ),
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}
