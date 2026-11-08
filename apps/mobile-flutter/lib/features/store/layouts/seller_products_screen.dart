import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../products/repositories/product_repository.dart';

/// Màn hình Quản Lý Sản Phẩm của Gian hàng (Seller Workspace)
class SellerProductsScreen extends ConsumerStatefulWidget {
  const SellerProductsScreen({super.key});

  @override
  ConsumerState<SellerProductsScreen> createState() => _SellerProductsScreenState();
}

class _SellerProductsScreenState extends ConsumerState<SellerProductsScreen> {
  final _searchController = TextEditingController();
  String _filterStatus = 'Tất cả';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    if (currentUser == null) return const Scaffold(body: Center(child: Text('Vui lòng đăng nhập!')));

    final productsAsync = ref.watch(sellerProductsStreamProvider(currentUser.uid));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản Lý Sản Phẩm'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => context.push('/marketplace/products/create'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter & Search Header
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'Tìm kiếm sản phẩm gian hàng...',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (val) => setState(() {}),
                ),
                const SizedBox(height: 8),

                Row(
                  children: ['Tất cả', 'active', 'hidden'].map((status) {
                    final isSelected = _filterStatus == status;
                    String label = 'Tất cả';
                    if (status == 'active') label = 'Đang bán';
                    if (status == 'hidden') label = 'Tạm ẩn';

                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: isSelected,
                        selectedColor: AppColors.primary,
                        onSelected: (selected) {
                          if (selected) setState(() => _filterStatus = status);
                        },
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          // Products List
          Expanded(
            child: productsAsync.when(
              data: (products) {
                var list = products;
                if (_filterStatus != 'Tất cả') {
                  list = list.where((p) => p.status == _filterStatus).toList();
                }
                if (_searchController.text.trim().isNotEmpty) {
                  final q = _searchController.text.trim().toLowerCase();
                  list = list.where((p) => p.name.toLowerCase().contains(q)).toList();
                }

                if (list.isEmpty) {
                  return const Center(child: Text('Không có sản phẩm nào.'));
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final product = list[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withAlpha(20),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: product.images.isNotEmpty
                              ? Image.network(product.images.first, fit: BoxFit.cover)
                              : const Icon(Icons.grass, color: AppColors.primary),
                        ),
                        title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Text(
                          'Tồn: ${product.stock} ${product.unit} • ${product.saleType == "fixed_price" ? _formatVND(product.listedPrice) : "Báo giá tham khảo"}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                product.status == 'active' ? Icons.visibility : Icons.visibility_off,
                                color: product.status == 'active' ? AppColors.primary : Colors.grey,
                              ),
                              onPressed: () async {
                                final nextStatus = product.status == 'active' ? 'hidden' : 'active';
                                await ref.read(productRepositoryProvider).toggleProductStatus(product.id, nextStatus);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_note, color: AppColors.accentBrown),
                              onPressed: () {
                                context.push('/marketplace/products/edit/${product.id}');
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Lỗi: $err')),
            ),
          ),
        ],
      ),
    );
  }

  String _formatVND(int price) {
    if (price <= 0) return '0đ';
    return '${price.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.')}đ';
  }
}
