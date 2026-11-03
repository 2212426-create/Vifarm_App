import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/share_button.dart';
import '../../../shared/widgets/universal_share_bottom_sheet.dart';
import '../../products/repositories/product_repository.dart';
import '../repositories/store_repository.dart';

/// Màn hình Gian Hàng Công Khai (Khách hàng truy cập xem gian hàng)
class PublicStoreScreen extends ConsumerWidget {
  final String storeId;

  const PublicStoreScreen({
    super.key,
    required this.storeId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storeAsync = ref.watch(publicStoreStreamProvider(storeId));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return storeAsync.when(
      data: (store) {
        if (store == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Gian hàng')),
            body: const Center(child: Text('Gian hàng không tồn tại hoặc đã ngưng hoạt động!')),
          );
        }

        final productsAsync = ref.watch(sellerProductsStreamProvider(store.ownerId));

        return Scaffold(
          appBar: AppBar(
            title: Text(store.storeName),
            actions: [
              ShareButton(
                content: ShareContentModel.fromStore(store),
              ),
            ],
          ),
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Banner & Avatar
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      height: 120,
                      width: double.infinity,
                      color: AppColors.primary.withAlpha(40),
                      child: store.coverUrl.isNotEmpty
                          ? Image.network(store.coverUrl, fit: BoxFit.cover)
                          : const Icon(Icons.storefront, size: 48, color: AppColors.primary),
                    ),
                    Positioned(
                      left: 16,
                      bottom: -30,
                      child: CircleAvatar(
                        radius: 36,
                        backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
                        child: CircleAvatar(
                          radius: 33,
                          backgroundColor: AppColors.primary,
                          backgroundImage: store.avatarUrl.isNotEmpty ? NetworkImage(store.avatarUrl) : null,
                          child: store.avatarUrl.isEmpty ? const Icon(Icons.store, color: Colors.white) : null,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 36),

                // Store info
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              store.storeName,
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.success.withAlpha(30),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.verified, size: 14, color: AppColors.success),
                                SizedBox(width: 4),
                                Text('Đã xác minh', style: TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Khu vực: ${store.region} • Nhận hàng: ${store.address}',
                        style: const TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      if (store.description.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(store.description, style: const TextStyle(fontSize: 13, height: 1.4)),
                      ],
                      const SizedBox(height: 12),

                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.chat),
                          label: const Text('Nhắn Tin Cho Gian Hàng'),
                          onPressed: () {
                            context.push('/chat/${store.ownerId}?name=${Uri.encodeComponent(store.storeName)}');
                          },
                        ),
                      ),
                      const SizedBox(height: 20),

                      const Text('Sản phẩm công khai', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primary)),
                      const SizedBox(height: 10),

                      productsAsync.when(
                        data: (products) {
                          final publicProducts = products.where((p) => p.status == 'active' && p.moderationStatus == 'approved').toList();
                          if (publicProducts.isEmpty) {
                            return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Chưa có sản phẩm công khai nào.')));
                          }

                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 0.75,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                            itemCount: publicProducts.length,
                            itemBuilder: (context, index) {
                              final product = publicProducts[index];
                              return Card(
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () => context.push('/marketplace/products/${product.id}'),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Container(
                                          color: AppColors.primary.withAlpha(20),
                                          width: double.infinity,
                                          child: product.images.isNotEmpty
                                              ? Image.network(product.images.first, fit: BoxFit.cover)
                                              : const Icon(Icons.grass, color: AppColors.primary),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                            Text(
                                              product.saleType == 'fixed_price' ? '${product.listedPrice}đ / ${product.unit}' : 'Báo giá',
                                              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (err, stack) => Text('Lỗi: $err'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, stack) => Scaffold(body: Center(child: Text('Lỗi: $err'))),
    );
  }
}
