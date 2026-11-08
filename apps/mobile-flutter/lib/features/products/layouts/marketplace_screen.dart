import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../cart/providers/cart_provider.dart';
import '../models/product_model.dart';
import '../repositories/product_repository.dart';

/// Màn hình Chợ Nông Sản & Vật Tư Nông Nghiệp
class MarketplaceScreen extends ConsumerStatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  ConsumerState<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends ConsumerState<MarketplaceScreen> {
  String _selectedCategory = 'Tất cả';
  String _selectedRegion = 'Tất cả';
  String _selectedSaleType = 'Tất cả';
  final _searchController = TextEditingController();

  final List<String> _categories = [
    'Tất cả',
    'Nông sản',
    'Vật tư nông nghiệp',
    'Phân bón & Thuốc BVTV',
    'Cây giống & Hạt giống',
    'Thiết bị & Máy nông nghiệp',
  ];

  final List<String> _regions = [
    'Tất cả',
    'Lâm Đồng',
    'Đắk Lắk',
    'Gia Lai',
    'Đồng Nai',
    'Cần Thơ',
    'TP.HCM',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cartCount = ref.watch(cartItemCountProvider);

    final productsAsync = ref.watch(marketplaceProductsStreamProvider((
      category: _selectedCategory,
      region: _selectedRegion,
      saleType: _selectedSaleType,
      query: _searchController.text,
    )));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chợ Nông Nghiệp'),
        actions: [
          // Cart button with badge
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_cart_outlined),
                tooltip: 'Giỏ hàng',
                onPressed: () {
                  context.push('/cart');
                },
              ),
              if (cartCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Text(
                      '$cartCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.add_business),
            tooltip: 'Đăng bán sản phẩm',
            onPressed: () {
              context.push('/marketplace/products/create');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Filters Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
            child: Column(
              children: [
                // Search Input
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Tìm kiếm nông sản, phân bón, vật tư...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onChanged: (val) => setState(() {}),
                ),
                const SizedBox(height: 8),

                // Category Chips
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _categories.length,
                    separatorBuilder: (context, index) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final cat = _categories[index];
                      final isSelected = _selectedCategory == cat;
                      return ChoiceChip(
                        label: Text(
                          cat,
                          style: TextStyle(
                            fontSize: 12,
                            color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                          ),
                        ),
                        selected: isSelected,
                        selectedColor: AppColors.primary,
                        onSelected: (selected) {
                          if (selected) setState(() => _selectedCategory = cat);
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 6),

                // Filter row for Region & SaleType
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 16, color: AppColors.primary),
                    const SizedBox(width: 4),
                    DropdownButton<String>(
                      value: _selectedRegion,
                      underline: const SizedBox.shrink(),
                      isDense: true,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                      ),
                      items: _regions.map((r) {
                        return DropdownMenuItem(value: r, child: Text(r));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedRegion = val);
                      },
                    ),
                    const Spacer(),
                    const Icon(Icons.sell_outlined, size: 16, color: AppColors.accentBrown),
                    const SizedBox(width: 4),
                    DropdownButton<String>(
                      value: _selectedSaleType,
                      underline: const SizedBox.shrink(),
                      isDense: true,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Tất cả', child: Text('Tất cả hình thức')),
                        DropdownMenuItem(value: 'fixed_price', child: Text('Giá niêm yết')),
                        DropdownMenuItem(value: 'quote_required', child: Text('Cần báo giá')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedSaleType = val);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Product Grid View
          Expanded(
            child: productsAsync.when(
              data: (products) {
                if (products.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.storefront_outlined,
                          size: 64,
                          color: isDark ? AppColors.darkTextHint : AppColors.lightTextHint,
                        ),
                        const SizedBox(height: 12),
                        const Text('Không tìm thấy sản phẩm phù hợp.'),
                      ],
                    ),
                  );
                }

                return GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.72,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final product = products[index];
                    return _ProductCard(product: product);
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
}

class _ProductCard extends StatelessWidget {
  final ProductModel product;

  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context) {

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      child: InkWell(
        onTap: () {
          context.push('/marketplace/products/${product.id}');
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image area
            Expanded(
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    color: AppColors.primary.withAlpha(20),
                    child: product.images.isNotEmpty
                        ? Image.network(
                            product.images.first,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.image, size: 48, color: Colors.grey),
                          )
                        : const Icon(Icons.grass, size: 48, color: AppColors.primary),
                  ),
                  // SaleType Badge
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: product.saleType == 'fixed_price'
                            ? AppColors.primary
                            : AppColors.accentBrown,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        product.saleType == 'fixed_price' ? 'Giá niêm yết' : 'Báo giá',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 4),

                  // Price
                  if (product.saleType == 'fixed_price')
                    Text(
                      '${_formatVND(product.listedPrice)} / ${product.unit}',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    )
                  else
                    Text(
                      'Giá tham khảo: ${_formatVND(product.referencePrice)}',
                      style: const TextStyle(
                        color: AppColors.accentBrown,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),

                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 12, color: Colors.grey),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          product.region.isNotEmpty ? product.region : 'Toàn quốc',
                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatVND(int price) {
    if (price <= 0) return 'Liên hệ';
    return '${price.toString().replaceAllRegExp(RegExp(r'\B(?=(\d{3})+(?!\d))'), '.')}đ';
  }
}

extension StringFormatX on String {
  String replaceAllRegExp(RegExp regex, String replacement) {
    return replaceAllMapped(regex, (match) => replacement);
  }
}
