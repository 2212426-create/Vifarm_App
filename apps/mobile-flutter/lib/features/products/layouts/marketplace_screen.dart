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
  String _selectedProvince = 'Tất cả';
  String _selectedDistrict = 'Tất cả';
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

  final List<String> _provinces = [
    'Tất cả',
    'Lâm Đồng',
    'Đắk Lắk',
    'Gia Lai',
    'Đồng Nai',
    'Cần Thơ',
    'TP.HCM',
  ];

  static const Map<String, List<String>> _provinceDistricts = {
    'Lâm Đồng': [
      'Tất cả',
      'Đà Lạt',
      'Bảo Lộc',
      'Đức Trọng',
      'Đơn Dương',
      'Di Linh',
      'Lạc Dương',
      'Lâm Hà',
      'Bảo Lâm',
      'Đạ Huoai',
      'Đạ Tẻh',
      'Cát Tiên',
    ],
    'Đắk Lắk': [
      'Tất cả',
      'Buôn Ma Thuột',
      'Buôn Hồ',
      'Krông Pắc',
      'Cư M\'gar',
      'Ea Kar',
      'Krông Năng',
      'Krông Búk',
    ],
    'Gia Lai': [
      'Tất cả',
      'Pleiku',
      'An Khê',
      'Ayun Pa',
      'Chư Sê',
      'Đak Đoa',
      'Ia Grai',
    ],
    'Đồng Nai': [
      'Tất cả',
      'Biên Hòa',
      'Long Khánh',
      'Long Thành',
      'Nhơn Trạch',
      'Định Quán',
      'Xuân Lộc',
    ],
    'Cần Thơ': [
      'Tất cả',
      'Ninh Kiều',
      'Cái Răng',
      'Bình Thủy',
      'Ô Môn',
      'Thốt Nốt',
      'Phong Điền',
    ],
    'TP.HCM': [
      'Tất cả',
      'Củ Chi',
      'Hóc Môn',
      'Bình Chánh',
      'Cần Giờ',
      'Thủ Đức',
    ],
  };

  static const List<String> _popularSuggestions = [
    'Lúa',
    'Lúa giống',
    'Lan hồ điệp',
    'Lạc',
    'Lê',
    'Sầu riêng',
    'Sầu riêng Ri6',
    'Su su',
    'Sâm ngọc linh',
    'Phân bón',
    'Phân NPK',
    'Phân hữu cơ',
    'Cà phê',
    'Cà chua',
    'Cây giống',
    'Tiêu',
    'Trà / Chè',
    'Bơ 034',
    'Bưởi da xanh',
    'Rau củ sạch',
    'Dưa lưới',
    'Khoai lang',
    'Ngô / Bắp',
    'Thuốc BVTV',
  ];

  static String _removeAccents(String str) {
    const withAccents = 'áàảãạăắằẳẵặâấầẩẫậéèẻẽẹêếềểễệíìỉĩịóòỏõọôốồổỗộơớờởỡợúùủũụưứừửữựýỳỷỹỵđ';
    const withoutAccents = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
    var out = str;
    for (var i = 0; i < withAccents.length; i++) {
      out = out.replaceAll(withAccents[i], withoutAccents[i]);
    }
    return out;
  }

  List<String> get _matchingSuggestions {
    final text = _searchController.text.trim().toLowerCase();
    if (text.isEmpty) return const [];
    final unaccentedText = _removeAccents(text);

    return _popularSuggestions.where((item) {
      final itemLower = item.toLowerCase();
      final itemUnaccented = _removeAccents(itemLower);
      return itemLower.startsWith(text) ||
          itemUnaccented.startsWith(unaccentedText) ||
          itemLower.contains(text) ||
          itemUnaccented.contains(unaccentedText);
    }).take(6).toList();
  }

  String get _effectiveRegionFilter {
    if (_selectedDistrict != 'Tất cả') {
      return _selectedDistrict;
    }
    return _selectedProvince;
  }

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
      region: _effectiveRegionFilter,
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

                // Gợi ý tìm kiếm tức thì theo chữ cái đầu (VD: L -> Lúa, S -> Sầu riêng)
                if (_matchingSuggestions.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 28,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _matchingSuggestions.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (context, index) {
                        final suggestion = _matchingSuggestions[index];
                        return InkWell(
                          onTap: () {
                            _searchController.text = suggestion;
                            setState(() {});
                          },
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withAlpha(25),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.primary.withAlpha(80), width: 0.8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.search, size: 12, color: AppColors.primary),
                                const SizedBox(width: 4),
                                Text(
                                  suggestion,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
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

                // Filter row for Region (Province) & SaleType
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 16, color: AppColors.primary),
                    const SizedBox(width: 4),
                    DropdownButton<String>(
                      value: _selectedProvince,
                      underline: const SizedBox.shrink(),
                      isDense: true,
                      menuMaxHeight: 250,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                      ),
                      items: _provinces.map((r) {
                        return DropdownMenuItem(value: r, child: Text(r));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedProvince = val;
                            _selectedDistrict = 'Tất cả';
                          });
                        }
                      },
                    ),
                    const Spacer(),
                    const Icon(Icons.sell_outlined, size: 16, color: AppColors.accentBrown),
                    const SizedBox(width: 4),
                    DropdownButton<String>(
                      value: _selectedSaleType,
                      underline: const SizedBox.shrink(),
                      isDense: true,
                      menuMaxHeight: 250,
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
                // Thanh chọn thành phố / thị xã / thị trấn trong tỉnh
                if (_selectedProvince != 'Tất cả' && _provinceDistricts.containsKey(_selectedProvince)) ...[
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 28,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _provinceDistricts[_selectedProvince]!.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (context, idx) {
                        final d = _provinceDistricts[_selectedProvince]![idx];
                        final isSel = _selectedDistrict == d;
                        final label = d == 'Tất cả' ? 'Toàn tỉnh' : d;
                        return InkWell(
                          onTap: () => setState(() => _selectedDistrict = d),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: isSel ? AppColors.primary : AppColors.primary.withAlpha(20),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isSel ? AppColors.primary : AppColors.primary.withAlpha(60),
                                width: 0.8,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                  color: isSel ? Colors.white : (isDark ? Colors.white70 : AppColors.primary),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
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
