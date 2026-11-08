import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/share_button.dart';
import '../../../shared/widgets/universal_share_bottom_sheet.dart';
import '../../auth/providers/auth_provider.dart';
import '../../cart/providers/cart_provider.dart';
import '../../quote_requests/repositories/quote_repository.dart';
import '../models/product_model.dart';
import '../repositories/product_repository.dart';

/// Màn hình Chi tiết Sản phẩm Nông Nghiệp
class ProductDetailScreen extends ConsumerStatefulWidget {
  final String productId;

  const ProductDetailScreen({
    super.key,
    required this.productId,
  });

  @override
  ConsumerState<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  ProductVariantModel? _selectedVariant;
  double _quantity = 1.0;

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final productAsync = ref.watch(productDetailStreamProvider(widget.productId));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return productAsync.when(
      data: (product) {
        if (product == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Chi tiết sản phẩm')),
            body: const Center(child: Text('Không tìm thấy sản phẩm!')),
          );
        }

        // Default variant
        if (_selectedVariant == null && product.variants.isNotEmpty) {
          _selectedVariant = product.variants.first;
        }

        final isFixedPrice = product.saleType == 'fixed_price';
        final displayPrice = _selectedVariant != null
            ? _selectedVariant!.price
            : (isFixedPrice ? product.listedPrice : product.referencePrice);

        return Scaffold(
          appBar: AppBar(
            title: Text(product.name),
            actions: [
              ShareButton(
                content: ShareContentModel.fromProduct(product),
              ),
              IconButton(
                icon: const Icon(Icons.shopping_cart_outlined),
                onPressed: () => context.push('/cart'),
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Product Image Header
                      Container(
                        height: 250,
                        width: double.infinity,
                        color: AppColors.primary.withAlpha(20),
                        child: product.images.isNotEmpty
                            ? Image.network(
                                product.images.first,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(Icons.image, size: 64, color: Colors.grey),
                              )
                            : const Icon(Icons.grass, size: 64, color: AppColors.primary),
                      ),

                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Title & Category Badge
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withAlpha(30),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    product.category,
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isFixedPrice ? AppColors.primary : AppColors.accentBrown,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    isFixedPrice ? 'Giá niêm yết' : 'Yêu cầu báo giá',
                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            Text(
                              product.name,
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),

                            // Price display
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  _formatVND(displayPrice),
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: isFixedPrice ? AppColors.primary : AppColors.accentBrown,
                                  ),
                                ),
                                Text(
                                  ' / ${product.unit}',
                                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                                ),
                                if (!isFixedPrice)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 8),
                                    child: Text(
                                      '(Giá tham khảo)',
                                      style: TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Region & Seller Info Card
                            Card(
                              child: ListTile(
                                leading: const CircleAvatar(
                                  backgroundColor: AppColors.primary,
                                  child: Icon(Icons.store, color: Colors.white),
                                ),
                                title: Text(product.sellerName.isNotEmpty ? product.sellerName : 'Nhà vườn uy tín'),
                                subtitle: Text('Khu vực: ${product.region} • Nhận hàng: ${product.deliveryScope}'),
                                trailing: OutlinedButton(
                                  onPressed: () {
                                    if (currentUser == null) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Vui lòng đăng nhập để chát với người bán!')),
                                      );
                                      context.go('/auth');
                                      return;
                                    }
                                    context.push('/chat/${product.sellerId}?name=${Uri.encodeComponent(product.sellerName)}');
                                  },
                                  child: const Text('Hỏi người bán'),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Variants / Specifications Selector (if any)
                            if (product.variants.isNotEmpty) ...[
                              const Text('Quy cách / Biến thể:', style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: product.variants.map((v) {
                                  final isSelected = _selectedVariant?.variantId == v.variantId;
                                  return ChoiceChip(
                                    label: Text('${v.name} (${_formatVND(v.price)})'),
                                    selected: isSelected,
                                    selectedColor: AppColors.primary,
                                    labelStyle: TextStyle(
                                      color: isSelected ? Colors.white : (isDark ? Colors.white : Colors.black87),
                                    ),
                                    onSelected: (selected) {
                                      if (selected) setState(() => _selectedVariant = v);
                                    },
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 16),
                            ],

                            // Description
                            const Text('Mô tả sản phẩm:', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            Text(
                              product.description,
                              style: const TextStyle(height: 1.4, fontSize: 14),
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom Action Bar
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -2)),
                  ],
                ),
                child: Row(
                  children: [
                    // Quantity selector
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove, size: 18),
                            onPressed: _quantity > product.minOrderQuantity
                                ? () {
                                    setState(() => _quantity -= product.quantityStep);
                                  }
                                : null,
                          ),
                          Text(
                            product.isDecimalAllowed ? _quantity.toStringAsFixed(1) : _quantity.toInt().toString(),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add, size: 18),
                            onPressed: () {
                              setState(() => _quantity += product.quantityStep);
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Add to Cart / Request Quote Button
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isFixedPrice ? AppColors.primary : AppColors.accentBrown,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () async {
                          if (currentUser == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Vui lòng đăng nhập để thao tác!')),
                            );
                            context.go('/auth');
                            return;
                          }

                          if (isFixedPrice) {
                            // Thêm vào giỏ hàng
                            await ref.read(cartProvider.notifier).addToCart(
                                  userId: currentUser.uid,
                                  product: product,
                                  variant: _selectedVariant,
                                  quantity: _quantity,
                                );
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Đã thêm ${product.name} vào giỏ hàng!'),
                                  action: SnackBarAction(
                                    label: 'Xem giỏ',
                                    textColor: Colors.yellow,
                                    onPressed: () => context.push('/cart'),
                                  ),
                                ),
                              );
                            }
                          } else {
                            // Yêu cầu báo giá -> Tạo yêu cầu & mở chat
                            await ref.read(quoteRepositoryProvider).createQuoteRequest(
                                  buyerId: currentUser.uid,
                                  buyerName: currentUser.email?.split('@')[0] ?? 'Người mua',
                                  product: product,
                                  variant: _selectedVariant,
                                  quantity: _quantity,
                                );
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Đã gửi yêu cầu báo giá tới người bán!')),
                              );
                              context.push('/chat/${product.sellerId}?name=${Uri.encodeComponent(product.sellerName)}');
                            }
                          }
                        },
                        child: Text(
                          isFixedPrice ? 'Thêm vào giỏ' : 'Gửi Yêu Cầu Báo Giá',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, stack) => Scaffold(body: Center(child: Text('Lỗi: $err'))),
    );
  }

  String _formatVND(int price) {
    if (price <= 0) return 'Liên hệ';
    return '${price.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.')}đ';
  }
}
