import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/product_model.dart';
import '../repositories/product_repository.dart';

/// Màn hình Đăng / Sửa Sản phẩm Nông Nghiệp (Tích hợp ImagePicker, BottomSheet Danh mục & Khu vực)
class EditProductScreen extends ConsumerStatefulWidget {
  final String? productId;

  const EditProductScreen({
    super.key,
    this.productId,
  });

  @override
  ConsumerState<EditProductScreen> createState() => _EditProductScreenState();
}

class _EditProductScreenState extends ConsumerState<EditProductScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _regionController = TextEditingController(text: 'Đà Lạt, Lâm Đồng');
  final _unitController = TextEditingController(text: 'kg');
  final _stockController = TextEditingController(text: '100');

  String _category = 'Nông sản';
  String _saleType = 'fixed_price';
  String _selectedProvince = 'Lâm Đồng';
  String _selectedDistrict = 'Đà Lạt';

  bool _isLoading = false;
  bool _isUploadingImage = false;

  final List<String> _productImages = [];
  final ImagePicker _picker = ImagePicker();

  static const List<String> _categories = [
    'Nông sản',
    'Vật tư nông nghiệp',
    'Phân bón & Thuốc BVTV',
    'Cây giống & Hạt giống',
    'Thiết bị & Máy nông nghiệp',
  ];

  static const List<String> _provinces = [
    'Lâm Đồng',
    'Đắk Lắk',
    'Gia Lai',
    'Đồng Nai',
    'Cần Thơ',
    'TP.HCM',
  ];

  static const Map<String, List<String>> _provinceDistricts = {
    'Lâm Đồng': [
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
      'Buôn Ma Thuột',
      'Buôn Hồ',
      'Krông Pắc',
      'Cư M\'gar',
      'Ea Kar',
      'Krông Năng',
      'Krông Búk',
    ],
    'Gia Lai': [
      'Pleiku',
      'An Khê',
      'Ayun Pa',
      'Chư Sê',
      'Đak Đoa',
      'Ia Grai',
    ],
    'Đồng Nai': [
      'Biên Hòa',
      'Long Khánh',
      'Long Thành',
      'Nhơn Trạch',
      'Định Quán',
      'Xuân Lộc',
    ],
    'Cần Thơ': [
      'Ninh Kiều',
      'Cái Răng',
      'Bình Thủy',
      'Ô Môn',
      'Thốt Nốt',
      'Phong Điền',
    ],
    'TP.HCM': [
      'Củ Chi',
      'Hóc Môn',
      'Bình Chánh',
      'Cần Giờ',
      'Thủ Đức',
    ],
  };

  @override
  void initState() {
    super.initState();
    if (widget.productId != null && widget.productId!.isNotEmpty) {
      _loadProductData();
    }
  }

  Future<void> _loadProductData() async {
    final product = await ref.read(productRepositoryProvider).getProductOnce(widget.productId!);
    if (product != null && mounted) {
      _nameController.text = product.name;
      _descriptionController.text = product.description;
      _priceController.text = product.saleType == 'fixed_price'
          ? product.listedPrice.toString()
          : product.referencePrice.toString();
      _productImages.clear();
      _productImages.addAll(product.images);
      _regionController.text = product.region;
      _unitController.text = product.unit;
      _stockController.text = product.stock.toString();

      // Phân tích tỉnh / huyện nếu có
      for (final prov in _provinces) {
        if (product.region.contains(prov)) {
          _selectedProvince = prov;
          final districts = _provinceDistricts[prov] ?? [];
          for (final d in districts) {
            if (product.region.contains(d)) {
              _selectedDistrict = d;
              break;
            }
          }
          break;
        }
      }

      setState(() {
        _category = product.category;
        _saleType = product.saleType;
      });
    }
  }

  Future<void> _pickProductImages() async {
    final List<XFile> selected = await _picker.pickMultiImage(imageQuality: 85);
    if (selected.isEmpty) return;

    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;

    setState(() => _isUploadingImage = true);

    try {
      for (final file in selected) {
        final url = await ref.read(productRepositoryProvider).uploadProductMedia(
          sellerId: currentUser.uid,
          file: file,
        );
        setState(() {
          _productImages.add(url);
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã tải lên ${selected.length} hình ảnh sản phẩm!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải ảnh: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  void _showCategoryPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Chọn Danh Mục Sản Phẩm',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                  ),
                ),
              ),
              const Divider(height: 1),
              ..._categories.map((c) => ListTile(
                title: Text(
                  c,
                  style: TextStyle(
                    fontWeight: _category == c ? FontWeight.bold : FontWeight.normal,
                    color: _category == c ? AppColors.primary : null,
                  ),
                ),
                trailing: _category == c ? const Icon(Icons.check_circle, color: AppColors.primary) : null,
                onTap: () {
                  setState(() => _category = c);
                  Navigator.pop(ctx);
                },
              )),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _showProvincePicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Chọn Tỉnh / Khu Vực',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(height: 1),
              ..._provinces.map((p) => ListTile(
                title: Text(
                  p,
                  style: TextStyle(
                    fontWeight: _selectedProvince == p ? FontWeight.bold : FontWeight.normal,
                    color: _selectedProvince == p ? AppColors.primary : null,
                  ),
                ),
                trailing: _selectedProvince == p ? const Icon(Icons.check_circle, color: AppColors.primary) : null,
                onTap: () {
                  setState(() {
                    _selectedProvince = p;
                    final districts = _provinceDistricts[p] ?? [];
                    _selectedDistrict = districts.isNotEmpty ? districts.first : '';
                    _regionController.text = '$_selectedDistrict, $_selectedProvince';
                  });
                  Navigator.pop(ctx);
                },
              )),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _showDistrictPicker() {
    final districts = _provinceDistricts[_selectedProvince] ?? [];
    if (districts.isEmpty) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Chọn Thành Phố / Thị Trấn ($_selectedProvince)',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  children: districts.map((d) => ListTile(
                    title: Text(
                      d,
                      style: TextStyle(
                        fontWeight: _selectedDistrict == d ? FontWeight.bold : FontWeight.normal,
                        color: _selectedDistrict == d ? AppColors.primary : null,
                      ),
                    ),
                    trailing: _selectedDistrict == d ? const Icon(Icons.check_circle, color: AppColors.primary) : null,
                    onTap: () {
                      setState(() {
                        _selectedDistrict = d;
                        _regionController.text = '$_selectedDistrict, $_selectedProvince';
                      });
                      Navigator.pop(ctx);
                    },
                  )).toList(),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _regionController.dispose();
    _unitController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng đăng nhập để thao tác!')),
      );
      return;
    }

    final userProfile = ref.read(currentUserProfileProvider).valueOrNull;
    final sellerName = userProfile?.username ?? currentUser.email?.split('@')[0] ?? '';

    setState(() => _isLoading = true);

    try {
      final priceVal = int.tryParse(_priceController.text.trim()) ?? 0;
      final stockVal = int.tryParse(_stockController.text.trim()) ?? 0;

      final product = ProductModel(
        id: widget.productId ?? '',
        sellerId: currentUser.uid,
        sellerName: sellerName,
        sellerPhone: '',
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        images: _productImages,
        category: _category,
        unit: _unitController.text.trim(),
        saleType: _saleType,
        listedPrice: _saleType == 'fixed_price' ? priceVal : 0,
        referencePrice: _saleType == 'quote_required' ? priceVal : 0,
        stock: stockVal,
        region: _regionController.text.trim(),
        status: 'active',
        moderationStatus: 'approved',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      final newId = await ref.read(productRepositoryProvider).saveProduct(product);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lưu sản phẩm thành công!')),
        );
        context.pushReplacement('/marketplace/products/$newId');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi lưu sản phẩm: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.productId != null ? 'Sửa Sản Phẩm' : 'Đăng Sản Phẩm Mới'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product Image Picker Row
              const Text('Hình ảnh sản phẩm *', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),

              SizedBox(
                height: 90,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    InkWell(
                      onTap: _isUploadingImage ? null : _pickProductImages,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 90,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withAlpha(20),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.primary, width: 1),
                        ),
                        child: _isUploadingImage
                            ? const Center(child: CircularProgressIndicator())
                            : const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_a_photo, color: AppColors.primary),
                                  SizedBox(height: 4),
                                  Text('Thêm ảnh', style: TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.bold)),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    ..._productImages.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final url = entry.value;

                      return Stack(
                        children: [
                          Container(
                            width: 90,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              image: DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
                            ),
                          ),
                          Positioned(
                            top: 2,
                            right: 10,
                            child: GestureDetector(
                              onTap: () {
                                setState(() => _productImages.removeAt(idx));
                              },
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                child: const Icon(Icons.close, color: Colors.white, size: 14),
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Tên sản phẩm nông nghiệp *',
                  hintText: 'VD: Sầu riêng Ri6 Hữu Cơ, Phân bón NPK 16-16-8...',
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Vui lòng nhập tên sản phẩm' : null,
              ),
              const SizedBox(height: 12),

              // Category Picker Sheet (Không bị nhảy che khuất UI)
              InkWell(
                onTap: _showCategoryPicker,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Danh mục sản phẩm *',
                    suffixIcon: Icon(Icons.arrow_drop_down),
                  ),
                  child: Text(
                    _category,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // SaleType
              const Text('Hình thức bán *', style: TextStyle(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('Giá niêm yết'),
                      value: 'fixed_price',
                      groupValue: _saleType,
                      onChanged: (val) => setState(() => _saleType = val!),
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('Báo giá'),
                      value: 'quote_required',
                      groupValue: _saleType,
                      onChanged: (val) => setState(() => _saleType = val!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _priceController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: _saleType == 'fixed_price' ? 'Giá niêm yết (VND) *' : 'Giá tham khảo (VND) *',
                        hintText: 'VD: 85000',
                      ),
                      validator: (val) => val == null || val.trim().isEmpty ? 'Vui lòng nhập giá' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: TextFormField(
                      controller: _unitController,
                      decoration: const InputDecoration(
                        labelText: 'Đơn vị *',
                        hintText: 'VD: kg, bao, chai',
                      ),
                      validator: (val) => val == null || val.trim().isEmpty ? 'Nhập đơn vị' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Khu vực: Tỉnh & Thành phố / Huyện
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _showProvincePicker,
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Tỉnh / Vùng *',
                          suffixIcon: Icon(Icons.arrow_drop_down),
                        ),
                        child: Text(
                          _selectedProvince,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: _showDistrictPicker,
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'TP / Huyện *',
                          suffixIcon: Icon(Icons.arrow_drop_down),
                        ),
                        child: Text(
                          _selectedDistrict.isNotEmpty ? _selectedDistrict : 'Chọn huyện',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _stockController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Số lượng tồn kho *',
                        hintText: 'VD: 500',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _regionController,
                      decoration: const InputDecoration(
                        labelText: 'Địa chỉ cụ thể *',
                        hintText: 'VD: Đà Lạt, Lâm Đồng',
                      ),
                      validator: (val) => val == null || val.trim().isEmpty ? 'Nhập khu vực' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _descriptionController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Mô tả chi tiết sản phẩm *',
                  hintText: 'Đặc điểm, xuất xứ, hướng dẫn sử dụng, bảo quản...',
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Vui lòng nhập mô tả' : null,
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(widget.productId != null ? 'Lưu Thay Đổi' : 'Đăng Bán Sản Phẩm'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
