import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../cart/providers/cart_provider.dart';
import '../../quote_requests/repositories/quote_repository.dart';
import '../models/product_model.dart';
import '../repositories/product_repository.dart';

/// Modal Bottom Sheet hiển thị sản phẩm gắn trên Video Feed
/// Mở trực tiếp mà KHÔNG làm reset, dừng hay tái khởi tạo Video Player!
class ProductBottomSheet extends ConsumerStatefulWidget {
  final String productId;

  const ProductBottomSheet({super.key, required this.productId});

  static Future<void> show(BuildContext context, {required String productId}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ProductBottomSheet(productId: productId),
    );
  }

  @override
  ConsumerState<ProductBottomSheet> createState() => _ProductBottomSheetState();
}

class _ProductBottomSheetState extends ConsumerState<ProductBottomSheet> {
  ProductVariantModel? _selectedVariant;
  double _quantity = 1.0;

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final productAsync = ref.watch(productDetailStreamProvider(widget.productId));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(16),
      child: SafeArea(
        child: productAsync.when(
          data: (product) {
            if (product == null) {
              return const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: 20),
                  Text('Sản phẩm đã bị xóa hoặc tạm ẩn!'),
                  SizedBox(height: 20),
                ],
              );
            }

            if (_selectedVariant == null && product.variants.isNotEmpty) {
              _selectedVariant = product.variants.first;
            }

            final isFixedPrice = product.saleType == 'fixed_price';
            final displayPrice = _selectedVariant != null
                ? _selectedVariant!.price
                : (isFixedPrice ? product.listedPrice : product.referencePrice);

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top handle & Close
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isFixedPrice ? AppColors.primary.withAlpha(40) : AppColors.accentBrown.withAlpha(40),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isFixedPrice ? 'Giá niêm yết' : 'Yêu cầu báo giá',
                        style: TextStyle(
                          color: isFixedPrice ? AppColors.primary : AppColors.accentBrown,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withAlpha(20),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: product.images.isNotEmpty
                          ? Image.network(
                              product.images.first,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(Icons.image, color: Colors.grey),
                            )
                          : const Icon(Icons.grass, color: AppColors.primary, size: 36),
                    ),
                    const SizedBox(width: 12),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatVND(displayPrice),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isFixedPrice ? AppColors.primary : AppColors.accentBrown,
                            ),
                          ),
                          Text(
                            'Khu vực: ${product.region}',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Variants if present
                if (product.variants.isNotEmpty) ...[
                  const Text('Chọn quy cách:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: product.variants.map((v) {
                      final isSelected = _selectedVariant?.variantId == v.variantId;
                      return ChoiceChip(
                        label: Text('${v.name} (${_formatVND(v.price)})'),
                        selected: isSelected,
                        selectedColor: AppColors.primary,
                        labelStyle: TextStyle(
                          fontSize: 11,
                          color: isSelected ? Colors.white : (isDark ? Colors.white : Colors.black87),
                        ),
                        onSelected: (selected) {
                          if (selected) setState(() => _selectedVariant = v);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                ],

                // Quantity & Buttons
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove, size: 16),
                            onPressed: _quantity > product.minOrderQuantity
                                ? () => setState(() => _quantity -= product.quantityStep)
                                : null,
                          ),
                          Text(
                            product.isDecimalAllowed ? _quantity.toStringAsFixed(1) : _quantity.toInt().toString(),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add, size: 16),
                            onPressed: () => setState(() => _quantity += product.quantityStep),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isFixedPrice ? AppColors.primary : AppColors.accentBrown,
                        ),
                        onPressed: () async {
                          if (currentUser == null) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Vui lòng đăng nhập để thao tác!')),
                            );
                            context.go('/auth');
                            return;
                          }

                          if (isFixedPrice) {
                            await ref.read(cartProvider.notifier).addToCart(
                                  userId: currentUser.uid,
                                  product: product,
                                  variant: _selectedVariant,
                                  quantity: _quantity,
                                );
                            if (mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Đã thêm ${product.name} vào giỏ!'),
                                  action: SnackBarAction(
                                    label: 'Xem giỏ',
                                    textColor: Colors.yellow,
                                    onPressed: () => context.push('/cart'),
                                  ),
                                ),
                              );
                            }
                          } else {
                            await ref.read(quoteRepositoryProvider).createQuoteRequest(
                                  buyerId: currentUser.uid,
                                  buyerName: currentUser.email?.split('@')[0] ?? 'Người mua',
                                  product: product,
                                  variant: _selectedVariant,
                                  quantity: _quantity,
                                );
                            if (mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Đã gửi yêu cầu báo giá!')),
                              );
                              context.push('/chat/${product.sellerId}?name=${Uri.encodeComponent(product.sellerName)}');
                            }
                          }
                        },
                        child: Text(
                          isFixedPrice ? 'Thêm vào giỏ' : 'Báo Giá',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Center(child: Text('Lỗi: $err')),
        ),
      ),
    );
  }

  String _formatVND(int price) {
    if (price <= 0) return 'Liên hệ';
    return '${price.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.')}đ';
  }
}
