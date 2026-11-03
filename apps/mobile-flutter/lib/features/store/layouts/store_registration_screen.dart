import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/store_model.dart';
import '../repositories/store_repository.dart';

enum DocumentUploadStatus { localPicked, uploading, success, failed }

class VerificationDocumentItem {
  final String id;
  final XFile? localFile;
  String? fileName;
  String? downloadUrl;
  DocumentUploadStatus status;
  String? errorMessage;

  VerificationDocumentItem({
    required this.id,
    this.localFile,
    this.fileName,
    this.downloadUrl,
    this.status = DocumentUploadStatus.localPicked,
    this.errorMessage,
  });
}

/// Màn hình Đăng ký Gian hàng Bán hàng Đa bước (Có Lưu nháp & Tải giấy tờ)
class StoreRegistrationScreen extends ConsumerStatefulWidget {
  const StoreRegistrationScreen({super.key});

  @override
  ConsumerState<StoreRegistrationScreen> createState() => _StoreRegistrationScreenState();
}

class _StoreRegistrationScreenState extends ConsumerState<StoreRegistrationScreen> {
  int _currentStep = 0;
  final _step1FormKey = GlobalKey<FormState>();
  final _step2FormKey = GlobalKey<FormState>();
  final _step3FormKey = GlobalKey<FormState>();

  // Step 1: Type
  String _storeType = 'individual'; // 'individual' | 'business'
  String _businessSubtype = 'enterprise'; // 'enterprise' | 'agent' | 'coop'

  // Step 2: Details
  final _storeNameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _contactNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _regionController = TextEditingController(text: 'Lâm Đồng');
  final _addressController = TextEditingController();
  final _pickupLocationController = TextEditingController();

  String _avatarUrl = '';
  String _coverUrl = '';

  final List<String> _selectedCategories = ['Nông sản'];
  final List<String> _selectedFulfillment = ['pickup', 'agreed_delivery'];

  // Step 3: Verification
  final _taxCodeController = TextEditingController();
  final _representativeController = TextEditingController();
  final List<VerificationDocumentItem> _verificationDocItems = [];

  bool _isUploadingMedia = false;
  bool _isSubmitting = false;
  String? _existingStoreId;

  final ImagePicker _picker = ImagePicker();

  final List<String> _allCategories = [
    'Nông sản',
    'Vật tư nông nghiệp',
    'Phân bón & Thuốc BVTV',
    'Cây giống & Hạt giống',
    'Thiết bị & Máy nông nghiệp',
  ];

  final Map<String, String> _fulfillmentLabels = {
    'pickup': 'Bán tại vườn / kho',
    'agreed_delivery': 'Tự vận chuyển / Gửi xe',
    'truck_delivery': 'Xe tải tận nơi',
  };

  @override
  void initState() {
    super.initState();
    _loadExistingDraft();
  }

  Future<void> _loadExistingDraft() async {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;

    final profile = ref.read(currentUserProfileProvider).valueOrNull;
    if (profile != null) {
      if (profile.fullname.isNotEmpty) {
        _contactNameController.text = profile.fullname;
      }
    }
    if (currentUser.phoneNumber != null && currentUser.phoneNumber!.isNotEmpty) {
      _phoneController.text = currentUser.phoneNumber!;
    }

    final store = await ref.read(storeRepositoryProvider).getStoreByOwner(currentUser.uid);
    if (store != null && mounted) {
      _existingStoreId = store.storeId;
      _storeType = store.storeType;
      if (store.businessSubtype != null) _businessSubtype = store.businessSubtype!;
      _storeNameController.text = store.storeName;
      _descriptionController.text = store.description;
      if (store.contactName.isNotEmpty) _contactNameController.text = store.contactName;
      if (store.phone.isNotEmpty) _phoneController.text = store.phone;
      if (store.region.isNotEmpty) _regionController.text = store.region;
      if (store.address.isNotEmpty) _addressController.text = store.address;
      if (store.pickupLocation != null) _pickupLocationController.text = store.pickupLocation!;
      _avatarUrl = store.avatarUrl;
      _coverUrl = store.coverUrl;
      if (store.targetCategories.isNotEmpty) {
        _selectedCategories.clear();
        _selectedCategories.addAll(store.targetCategories);
      }
      if (store.fulfillmentMethods.isNotEmpty) {
        _selectedFulfillment.clear();
        _selectedFulfillment.addAll(store.fulfillmentMethods);
      }
      if (store.taxCode != null) _taxCodeController.text = store.taxCode!;
      if (store.representative != null) _representativeController.text = store.representative!;

      _verificationDocItems.clear();
      for (final docUrl in store.verificationDocs) {
        if (docUrl.trim().isNotEmpty && (docUrl.startsWith('http://') || docUrl.startsWith('https://'))) {
          _verificationDocItems.add(
            VerificationDocumentItem(
              id: '${DateTime.now().millisecondsSinceEpoch}_${docUrl.hashCode}',
              downloadUrl: docUrl,
              fileName: 'Tài liệu xác minh',
              status: DocumentUploadStatus.success,
            ),
          );
        }
      }
      setState(() {});
    }
  }

  @override
  void dispose() {
    _storeNameController.dispose();
    _descriptionController.dispose();
    _contactNameController.dispose();
    _phoneController.dispose();
    _regionController.dispose();
    _addressController.dispose();
    _pickupLocationController.dispose();
    _taxCodeController.dispose();
    _representativeController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadImage(String type) async {
    final XFile? file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null) return; // Silent return on picker cancellation

    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;

    setState(() => _isUploadingMedia = true);

    try {
      final downloadUrl = await ref.read(storeRepositoryProvider).uploadStoreMedia(
        ownerId: currentUser.uid,
        file: file,
        type: type,
      );

      if (mounted) {
        setState(() {
          if (type == 'avatar') _avatarUrl = downloadUrl;
          if (type == 'cover') _coverUrl = downloadUrl;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tải ảnh gian hàng thành công!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không tải được ảnh gian hàng. Vui lòng thử lại.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingMedia = false);
    }
  }

  Future<void> _pickAndUploadDoc() async {
    final XFile? file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null) return; // Silent return without altering previous selection

    final docItem = VerificationDocumentItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      localFile: file,
      fileName: file.name,
      status: DocumentUploadStatus.uploading,
    );

    setState(() {
      _verificationDocItems.add(docItem);
    });

    await _uploadDocItem(docItem);
  }

  Future<void> _uploadDocItem(VerificationDocumentItem docItem) async {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null || docItem.localFile == null) return;

    setState(() {
      docItem.status = DocumentUploadStatus.uploading;
      docItem.errorMessage = null;
    });

    try {
      final downloadUrl = await ref.read(storeRepositoryProvider).uploadStoreMedia(
        ownerId: currentUser.uid,
        file: docItem.localFile!,
        type: 'doc',
      );

      if (mounted) {
        setState(() {
          docItem.downloadUrl = downloadUrl;
          docItem.status = DocumentUploadStatus.success;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tải giấy tờ xác minh thành công!')),
        );
      }
    } catch (e) {
      debugPrint('[StorageDebug] Failed to upload verification document: $e');
      if (mounted) {
        setState(() {
          docItem.status = DocumentUploadStatus.failed;
          docItem.errorMessage = 'Không tải được giấy tờ xác minh. Bấm Thử lại.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không tải được giấy tờ xác minh. Vui lòng thử lại.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<String> get _successfulDocUrls {
    return _verificationDocItems
        .where((d) => d.status == DocumentUploadStatus.success && d.downloadUrl != null && d.downloadUrl!.isNotEmpty)
        .map((d) => d.downloadUrl!)
        .toList();
  }

  StoreModel _buildStoreFromForm(String status) {
    final currentUser = ref.read(currentUserProvider)!;
    final profile = ref.read(currentUserProfileProvider).valueOrNull;

    return StoreModel(
      storeId: _existingStoreId ?? '',
      ownerId: currentUser.uid,
      ownerName: profile?.username ?? currentUser.email?.split('@')[0] ?? '',
      storeType: _storeType,
      businessSubtype: _storeType == 'business' ? _businessSubtype : null,
      storeName: _storeNameController.text.trim(),
      avatarUrl: _avatarUrl,
      coverUrl: _coverUrl,
      description: _descriptionController.text.trim(),
      contactName: _contactNameController.text.trim(),
      phone: _phoneController.text.trim(),
      address: _addressController.text.trim(),
      region: _regionController.text.trim(),
      pickupLocation: _pickupLocationController.text.trim().isNotEmpty ? _pickupLocationController.text.trim() : null,
      targetCategories: _selectedCategories,
      fulfillmentMethods: _selectedFulfillment,
      verificationDocs: _successfulDocUrls,
      taxCode: _taxCodeController.text.trim().isNotEmpty ? _taxCodeController.text.trim() : null,
      representative: _representativeController.text.trim().isNotEmpty ? _representativeController.text.trim() : null,
      status: status,
      operatingStatus: 'active',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _saveDraft() async {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;

    setState(() => _isSubmitting = true);
    try {
      final store = _buildStoreFromForm('draft');
      final sId = await ref.read(storeRepositoryProvider).saveStoreDraft(store);
      _existingStoreId = sId;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã lưu bản nháp đăng ký gian hàng!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lỗi khi lưu bản nháp. Vui lòng thử lại.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _submitRegistration() async {
    if (_storeNameController.text.trim().isEmpty ||
        _contactNameController.text.trim().isEmpty ||
        _phoneController.text.trim().isEmpty ||
        _addressController.text.trim().isEmpty ||
        _regionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng điền đầy đủ thông tin bắt buộc trước khi gửi!')),
      );
      setState(() => _currentStep = 1);
      return;
    }

    if (_selectedCategories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn ít nhất 1 danh mục kinh doanh chủ lực!')),
      );
      setState(() => _currentStep = 1);
      return;
    }

    final hasPendingUploads = _verificationDocItems.any((d) => d.status == DocumentUploadStatus.uploading);
    if (hasPendingUploads) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chờ tệp tài liệu hoàn tất tải lên trước khi gửi!')),
      );
      return;
    }

    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;

    setState(() => _isSubmitting = true);
    try {
      final store = _buildStoreFromForm('pending');
      await ref.read(storeRepositoryProvider).submitStoreRegistration(store);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gửi hồ sơ đăng ký thành công! Đang chờ BQT xét duyệt.')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lỗi gửi hồ sơ đăng ký. Vui lòng thử lại.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _nextStep() {
    if (_currentStep == 0) {
      if (_step1FormKey.currentState?.validate() ?? true) {
        setState(() => _currentStep = 1);
      }
    } else if (_currentStep == 1) {
      if (_step2FormKey.currentState?.validate() ?? false) {
        if (_selectedCategories.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Vui lòng chọn ít nhất 1 danh mục kinh doanh chủ lực!')),
          );
          return;
        }
        setState(() => _currentStep = 2);
      }
    } else if (_currentStep == 2) {
      if (_storeType == 'business') {
        if (_step3FormKey.currentState?.validate() ?? false) {
          setState(() => _currentStep = 3);
        }
      } else {
        setState(() => _currentStep = 3);
      }
    } else if (_currentStep == 3) {
      _submitRegistration();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep -= 1);
    }
  }

  Future<bool> _handlePopScope() async {
    if (_currentStep > 0) {
      setState(() => _currentStep -= 1);
      return false;
    }

    // At step 0, prompt confirmation dialog
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thoát đăng ký bán hàng?'),
        content: const Text('Bạn có muốn lưu bản nháp hồ sơ trước khi thoát không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: const Text('Bỏ thay đổi', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Tiếp tục chỉnh sửa'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('Lưu nháp & Thoát'),
          ),
        ],
      ),
    );

    if (result == 'save') {
      await _saveDraft();
      return true;
    } else if (result == 'discard') {
      return true;
    }
    return false;
  }

  Widget _buildStepHeader() {
    final steps = [
      '1. Hình thức',
      '2. Gian hàng',
      '3. Xác minh',
      '4. Kiểm tra',
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      color: Theme.of(context).brightness == Brightness.dark
          ? AppColors.darkSurface
          : Colors.green.shade50,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(steps.length, (index) {
          final isActive = index == _currentStep;
          final isCompleted = index < _currentStep;

          return InkWell(
            onTap: isCompleted
                ? () {
                    setState(() => _currentStep = index);
                  }
                : null,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isCompleted
                        ? Colors.green
                        : (isActive ? AppColors.primary : Colors.grey.shade400),
                  ),
                  child: isCompleted
                      ? const Icon(Icons.check, size: 12, color: Colors.white)
                      : Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
                const SizedBox(width: 4),
                Text(
                  steps[index].split('. ')[1],
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    color: isActive
                        ? AppColors.primary
                        : (isCompleted ? Colors.green : Colors.grey),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStep1Content() {
    return Form(
      key: _step1FormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Chọn Hình thức Bán hàng',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary),
          ),
          const SizedBox(height: 8),
          const Text(
            'Lựa chọn mô hình phù hợp nhất với hoạt động kinh doanh của bạn.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),

          Card(
            child: Column(
              children: [
                RadioListTile<String>(
                  title: const Text('Cá nhân / Nhà vườn', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Bán nông sản, trái cây thu hoạch trực tiếp từ vườn nhà'),
                  value: 'individual',
                  groupValue: _storeType,
                  activeColor: AppColors.primary,
                  onChanged: (val) {
                    if (val != null) setState(() => _storeType = val);
                  },
                ),
                const Divider(height: 1),
                RadioListTile<String>(
                  title: const Text('Đơn vị kinh doanh', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Doanh nghiệp, Đại lý vật tư, Hợp tác xã (HTX)'),
                  value: 'business',
                  groupValue: _storeType,
                  activeColor: AppColors.primary,
                  onChanged: (val) {
                    if (val != null) setState(() => _storeType = val);
                  },
                ),
              ],
            ),
          ),

          if (_storeType == 'business') ...[
            const SizedBox(height: 16),
            const Text('Loại hình kinh doanh cụ thể:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _businessSubtype,
              decoration: const InputDecoration(
                labelText: 'Loại hình kinh doanh *',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'enterprise', child: Text('Doanh nghiệp nông nghiệp')),
                DropdownMenuItem(value: 'agent', child: Text('Đại lý vật tư / Phân bón / Hạt giống')),
                DropdownMenuItem(value: 'coop', child: Text('Hợp tác xã (HTX) Nông nghiệp')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _businessSubtype = val);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStep2Content() {
    return Form(
      key: _step2FormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Thông tin Gian hàng & Liên hệ',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary),
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _storeNameController,
            decoration: const InputDecoration(
              labelText: 'Tên gian hàng *',
              hintText: 'VD: Nông sản Sạch Đức Trọng / Đại lý VTNN Phú Nông',
              border: OutlineInputBorder(),
            ),
            validator: (v) => v == null || v.trim().isEmpty ? 'Vui lòng nhập tên gian hàng' : null,
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _contactNameController,
            decoration: const InputDecoration(
              labelText: 'Người đại diện / Liên hệ *',
              hintText: 'VD: Nguyễn Văn Nam',
              border: OutlineInputBorder(),
            ),
            validator: (v) => v == null || v.trim().isEmpty ? 'Vui lòng nhập tên người liên hệ' : null,
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Số điện thoại liên hệ *',
              hintText: 'VD: 0912345678',
              border: OutlineInputBorder(),
            ),
            validator: (v) => v == null || v.trim().isEmpty ? 'Vui lòng nhập số điện thoại' : null,
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _regionController,
                  decoration: const InputDecoration(
                    labelText: 'Tỉnh / Khu vực *',
                    hintText: 'VD: Lâm Đồng',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Vui lòng nhập khu vực' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(
                    labelText: 'Địa chỉ chi tiết *',
                    hintText: 'VD: Thôn 3, Đức Trọng',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Vui lòng nhập địa chỉ' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _pickupLocationController,
            decoration: const InputDecoration(
              labelText: 'Địa điểm trung chuyển / Nhận hàng (Không bắt buộc)',
              hintText: 'VD: Bến xe Đức Trọng / Kho QL20',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          // Categories
          const Text('Danh mục kinh doanh chủ lực *:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: _allCategories.map((cat) {
              final isSelected = _selectedCategories.contains(cat);
              return FilterChip(
                label: Text(cat, style: const TextStyle(fontSize: 12)),
                selected: isSelected,
                selectedColor: AppColors.primary,
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedCategories.add(cat);
                    } else {
                      _selectedCategories.remove(cat);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Fulfillment
          const Text('Phương thức giao / nhận hàng *:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: _fulfillmentLabels.entries.map((entry) {
              final isSelected = _selectedFulfillment.contains(entry.key);
              return FilterChip(
                label: Text(entry.value, style: const TextStyle(fontSize: 12)),
                selected: isSelected,
                selectedColor: AppColors.primary,
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedFulfillment.add(entry.key);
                    } else {
                      if (_selectedFulfillment.length > 1) {
                        _selectedFulfillment.remove(entry.key);
                      }
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Avatar & Cover Image Selectors
          const Text('Hình ảnh Gian hàng:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.account_box),
                  label: const Text('Avatar Gian hàng', style: TextStyle(fontSize: 12)),
                  onPressed: _isUploadingMedia ? null : () => _pickAndUploadImage('avatar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.image),
                  label: const Text('Ảnh bìa / Banner', style: TextStyle(fontSize: 12)),
                  onPressed: _isUploadingMedia ? null : () => _pickAndUploadImage('cover'),
                ),
              ),
            ],
          ),
          if (_avatarUrl.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 16),
                const SizedBox(width: 6),
                const Text('Đã chọn Avatar gian hàng', style: TextStyle(fontSize: 12, color: Colors.green)),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _avatarUrl = ''),
                  child: const Text('Xóa', style: TextStyle(color: Colors.red, fontSize: 11)),
                ),
              ],
            ),
          ],
          if (_coverUrl.isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 16),
                const SizedBox(width: 6),
                const Text('Đã chọn Ảnh bìa gian hàng', style: TextStyle(fontSize: 12, color: Colors.green)),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _coverUrl = ''),
                  child: const Text('Xóa', style: TextStyle(color: Colors.red, fontSize: 11)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),

          TextFormField(
            controller: _descriptionController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Giới thiệu gian hàng',
              hintText: 'Kinh nghiệm, sản phẩm chủ lực, cam kết chất lượng...',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep3Content() {
    return Form(
      key: _step3FormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Hồ sơ & Giấy tờ Xác minh',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tải lên hình ảnh giấy tờ để BQT kiểm duyệt (CCCD / ĐKKD / Giấy chứng nhận HTX).',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),

          if (_storeType == 'business') ...[
            TextFormField(
              controller: _taxCodeController,
              decoration: const InputDecoration(
                labelText: 'Mã số thuế / Mã ĐKKD *',
                border: OutlineInputBorder(),
              ),
              validator: (v) => v == null || v.trim().isEmpty ? 'Nhập mã số thuế / ĐKKD' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _representativeController,
              decoration: const InputDecoration(
                labelText: 'Người đại diện pháp luật *',
                border: OutlineInputBorder(),
              ),
              validator: (v) => v == null || v.trim().isEmpty ? 'Nhập người đại diện pháp luật' : null,
            ),
            const SizedBox(height: 16),
          ],

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Giấy tờ xác minh (CCCD / ĐKKD / Giấy chứng nhận):', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Tải tệp tài liệu xác minh'),
                    onPressed: _pickAndUploadDoc,
                  ),
                  const SizedBox(height: 12),
                  if (_verificationDocItems.isNotEmpty) ...[
                    Text('Đã chọn ${_verificationDocItems.length} tệp tài liệu:', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 8),
                    Column(
                      children: List.generate(_verificationDocItems.length, (index) {
                        final docItem = _verificationDocItems[index];

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              // Local / Remote Image Thumbnail Preview
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  color: Colors.grey.shade200,
                                  child: docItem.localFile != null
                                      ? (kIsWeb
                                          ? Image.network(docItem.localFile!.path, fit: BoxFit.cover)
                                          : Image.file(File(docItem.localFile!.path), fit: BoxFit.cover))
                                      : (docItem.downloadUrl != null
                                          ? Image.network(docItem.downloadUrl!, fit: BoxFit.cover)
                                          : const Icon(Icons.insert_drive_file, color: AppColors.primary)),
                                ),
                              ),
                              const SizedBox(width: 10),

                              // Document status & name
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      docItem.fileName ?? 'Tài liệu ${index + 1}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    _buildDocStatusWidget(docItem),
                                  ],
                                ),
                              ),

                              // Retry / Delete actions
                              if (docItem.status == DocumentUploadStatus.failed)
                                IconButton(
                                  icon: const Icon(Icons.refresh, color: Colors.orange, size: 20),
                                  tooltip: 'Thử lại tải lên',
                                  onPressed: () => _uploadDocItem(docItem),
                                ),

                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                tooltip: 'Xóa tệp này',
                                onPressed: () {
                                  setState(() {
                                    _verificationDocItems.removeAt(index);
                                  });
                                },
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                  ] else
                    const Text('Chưa có tệp tài liệu nào được chọn.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocStatusWidget(VerificationDocumentItem docItem) {
    switch (docItem.status) {
      case DocumentUploadStatus.uploading:
        return const Row(
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
            ),
            SizedBox(width: 6),
            Text('Đang tải lên...', style: TextStyle(fontSize: 11, color: AppColors.primary)),
          ],
        );
      case DocumentUploadStatus.success:
        return const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 14),
            SizedBox(width: 4),
            Text('Tải lên thành công', style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold)),
          ],
        );
      case DocumentUploadStatus.failed:
        return Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 14),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                docItem.errorMessage ?? 'Tải lên thất bại',
                style: const TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      case DocumentUploadStatus.localPicked:
        return const Text('Đã chọn trên máy', style: TextStyle(fontSize: 11, color: Colors.grey));
    }
  }

  Widget _buildStep4Content() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Kiểm tra & Gửi Đăng ký',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary),
        ),
        const SizedBox(height: 16),

        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tóm tắt hồ sơ đăng ký gian hàng:', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 15)),
                const Divider(),
                const SizedBox(height: 6),
                _buildSummaryRow('Tên gian hàng', _storeNameController.text),
                _buildSummaryRow('Hình thức', _storeType == 'individual' ? 'Cá nhân / Nhà vườn' : 'Đơn vị kinh doanh'),
                if (_storeType == 'business')
                  _buildSummaryRow('Loại hình', _businessSubtype == 'enterprise' ? 'Doanh nghiệp' : (_businessSubtype == 'agent' ? 'Đại lý vật tư' : 'HTX')),
                _buildSummaryRow('Người đại diện', _contactNameController.text),
                _buildSummaryRow('Số điện thoại', _phoneController.text),
                _buildSummaryRow('Khu vực', _regionController.text),
                _buildSummaryRow('Địa chỉ', _addressController.text),
                if (_pickupLocationController.text.isNotEmpty)
                  _buildSummaryRow('Địa điểm trung chuyển', _pickupLocationController.text),
                _buildSummaryRow('Danh mục chủ lực', _selectedCategories.join(', ')),
                _buildSummaryRow('Giao hàng', _selectedFulfillment.map((f) => _fulfillmentLabels[f] ?? f).join(', ')),
                _buildSummaryRow('Tài liệu xác minh', '${_successfulDocUrls.length} tệp đã tải thành công'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: const Row(
            children: [
              Icon(Icons.shield, color: Colors.blue, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '🔒 Giấy tờ xác minh được lưu bảo mật và chỉ sử dụng cho Ban quản trị kiểm duyệt hồ sơ, không công khai lên ứng dụng.',
                  style: TextStyle(fontSize: 11, color: Colors.blue),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
          ),
          Expanded(
            child: Text(value.isNotEmpty ? value : '—', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _handlePopScope();
        if (shouldPop && context.mounted) {
          context.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Đăng Ký Bán Hàng'),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.bookmark_border, size: 18, color: AppColors.primary),
              label: const Text('Lưu nháp', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
              onPressed: _isSubmitting ? null : _saveDraft,
            ),
          ],
        ),
        body: Column(
          children: [
            _buildStepHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: () {
                  switch (_currentStep) {
                    case 0:
                      return _buildStep1Content();
                    case 1:
                      return _buildStep2Content();
                    case 2:
                      return _buildStep3Content();
                    case 3:
                      return _buildStep4Content();
                    default:
                      return _buildStep1Content();
                  }
                }(),
              ),
            ),

            // Pinned Bottom Action Bar
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.darkSurface
                    : Colors.white,
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    if (_currentStep > 0) ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isSubmitting ? null : _prevStep,
                          child: const Text('Quay lại'),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _isSubmitting
                            ? null
                            : (_currentStep == 3 ? _submitRegistration : _nextStep),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text(
                                _currentStep == 3 ? 'Gửi đăng ký' : 'Tiếp tục',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
