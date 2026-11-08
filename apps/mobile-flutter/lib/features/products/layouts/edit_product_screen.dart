import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../profile/providers/profile_provider.dart';
import '../models/product_model.dart';
import '../repositories/product_repository.dart';

/// Màn hình Đăng / Sửa Sản phẩm Nông Nghiệp (Tích hợp ImagePicker chọn nhiều ảnh)
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
  final _regionController = TextEditingController();
  final _unitController = TextEditingController(text: 'kg');
  final _stockController = TextEditingController(text: '100');

  String _category = 'Nông sản';
  String _saleType = 'fixed_price';
  bool _isLoading = false;
  bool _isUploadingImage = false;

  final List<String> _productImages = [];
  final ImagePicker _picker = ImagePicker();

  final List<String> _categories = [
    'Nông sản',
    'Vật tư nông nghiệp',
    'Phân bón & Thuốc BVTV',
    'Cây giống & Hạt giống',
    'Thiết bị & Máy nông nghiệp',
  ];

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
        final url = await ref.read(profileRepositoryProvider).updateAvatar(currentUser.uid, file);
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

              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(labelText: 'Danh mục sản phẩm *'),
                items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _category = val);
                },
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
                        labelText: 'Tỉnh / Khu vực *',
                        hintText: 'VD: Lâm Đồng',
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
