import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/store_model.dart';
import '../repositories/store_repository.dart';

/// Trang Quản trị Danh sách Hồ sơ Gian hàng chờ Xét duyệt
class AdminStoreListScreen extends ConsumerStatefulWidget {
  const AdminStoreListScreen({super.key});

  @override
  ConsumerState<AdminStoreListScreen> createState() => _AdminStoreListScreenState();
}

class _AdminStoreListScreenState extends ConsumerState<AdminStoreListScreen> {
  String _selectedFilter = 'pending';

  @override
  Widget build(BuildContext context) {
    final storesAsync = ref.watch(adminStoresStreamProvider(_selectedFilter.isEmpty ? null : _selectedFilter));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản Trị Xét Duyệt Gian Hàng'),
      ),
      body: Column(
        children: [
          // Filter Bar
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _buildFilterChip('pending', 'Chờ duyệt'),
                const SizedBox(width: 8),
                _buildFilterChip('needs_changes', 'Cần bổ sung'),
                const SizedBox(width: 8),
                _buildFilterChip('approved', 'Đã duyệt'),
                const SizedBox(width: 8),
                _buildFilterChip('rejected', 'Từ chối'),
                const SizedBox(width: 8),
                _buildFilterChip('', 'Tất cả'),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: storesAsync.when(
              data: (stores) {
                if (stores.isEmpty) {
                  return const Center(
                    child: Text('Không có hồ sơ gian hàng nào trong danh mục này.'),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: stores.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final store = stores[index];
                    final submittedDate = store.submittedAt != null
                        ? DateTime.fromMillisecondsSinceEpoch(store.submittedAt!)
                        : DateTime.fromMillisecondsSinceEpoch(store.updatedAt);

                    return Card(
                      child: ListTile(
                        onTap: () {
                          context.push('/admin/store/${store.storeId}/review');
                        },
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                store.storeName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withAlpha(30),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('v${store.version}', style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text('Chủ gian hàng: ${store.contactName} (${store.ownerName})'),
                            Text('Khu vực: ${store.region} • Loại: ${store.storeType == "individual" ? "Cá nhân" : "Doanh nghiệp"}'),
                            Text(
                              'Thời điểm gửi: ${submittedDate.day.toString().padLeft(2, '0')}/${submittedDate.month.toString().padLeft(2, '0')}/${submittedDate.year} ${submittedDate.hour.toString().padLeft(2, '0')}:${submittedDate.minute.toString().padLeft(2, '0')}',
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                        trailing: _buildStatusBadge(store.status),
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

  Widget _buildFilterChip(String value, String label) {
    final isSelected = _selectedFilter == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: AppColors.primary,
      onSelected: (selected) {
        if (selected) setState(() => _selectedFilter = value);
      },
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case 'approved':
        bg = Colors.green.withAlpha(40);
        fg = Colors.green;
        label = 'Đã duyệt';
        break;
      case 'needs_changes':
        bg = Colors.orange.withAlpha(40);
        fg = Colors.orange;
        label = 'Cần bổ sung';
        break;
      case 'rejected':
        bg = Colors.red.withAlpha(40);
        fg = Colors.red;
        label = 'Từ chối';
        break;
      case 'pending':
      default:
        bg = Colors.blue.withAlpha(40);
        fg = Colors.blue;
        label = 'Chờ duyệt';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}

/// Trang Quản trị Chi tiết Review & Xét duyệt Hồ sơ Gian hàng
class AdminStoreReviewDetailScreen extends ConsumerStatefulWidget {
  final String storeId;

  const AdminStoreReviewDetailScreen({
    super.key,
    required this.storeId,
  });

  @override
  ConsumerState<AdminStoreReviewDetailScreen> createState() => _AdminStoreReviewDetailScreenState();
}

class _AdminStoreReviewDetailScreenState extends ConsumerState<AdminStoreReviewDetailScreen> {
  final _reasonController = TextEditingController();
  final _internalNoteController = TextEditingController();

  bool _checkLegible = false;
  bool _checkCorrectType = false;
  bool _checkInfoMatches = false;
  bool _checkNoDiscrepancies = false;

  bool _isSubmitting = false;

  @override
  void dispose() {
    _reasonController.dispose();
    _internalNoteController.dispose();
    super.dispose();
  }

  bool get _allChecklistPassed =>
      _checkLegible && _checkCorrectType && _checkInfoMatches && _checkNoDiscrepancies;

  Future<void> _processReview(StoreModel store, String action) async {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa xác thực tài khoản quản trị.')),
      );
      return;
    }

    if (currentUser.uid == store.ownerId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Quản trị viên không thể tự phê duyệt hồ sơ gian hàng của chính mình.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final reason = _reasonController.text.trim();
    if ((action == 'needs_changes' || action == 'rejected') && reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập lý do phản hồi cho người đăng ký!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await ref.read(storeRepositoryProvider).reviewStoreRegistration(
        storeId: store.storeId,
        expectedVersion: store.version,
        action: action,
        reviewerId: currentUser.uid,
        reviewerName: currentUser.email?.split('@')[0] ?? 'Admin',
        reason: action == 'approved' ? 'Hồ sơ đạt yêu cầu xác minh' : reason,
        internalNote: _internalNoteController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == 'approved'
                  ? 'Đã duyệt hồ sơ gian hàng "${store.storeName}"!'
                  : (action == 'needs_changes'
                      ? 'Đã gửi yêu cầu bổ sung hồ sơ v${store.version}.'
                      : 'Đã từ chối hồ sơ gian hàng.'),
            ),
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi xét duyệt: ${e.toString().replaceAll("Exception: ", "")}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showImageZoom(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(title: const Text('Xem ảnh giấy tờ'), leading: const CloseButton()),
            InteractiveViewer(
              child: Image.network(url, fit: BoxFit.contain),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final storeAsync = ref.watch(publicStoreStreamProvider(widget.storeId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Xét Duyệt Hồ Sơ Gian Hàng'),
      ),
      body: storeAsync.when(
        data: (store) {
          if (store == null) {
            return const Center(child: Text('Không tìm thấy thông tin hồ sơ này.'));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Info Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Hồ sơ v${store.version}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primary)),
                            Chip(label: Text(store.status, style: const TextStyle(fontSize: 11))),
                          ],
                        ),
                        const Divider(),
                        Text('Tên gian hàng: ${store.storeName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        Text('Loại hình: ${store.storeType == "individual" ? "Cá nhân / Nhà vườn" : "Đơn vị kinh doanh (${store.businessSubtype ?? ""})"}' ),
                        Text('Người đại diện: ${store.contactName}'),
                        Text('SĐT liên hệ: ${store.phone}'),
                        Text('Khu vực: ${store.region}'),
                        Text('Địa chỉ chi tiết: ${store.address}'),
                        if (store.taxCode != null) Text('Mã số thuế / ĐKKD: ${store.taxCode}'),
                        if (store.representative != null) Text('Đại diện pháp luật: ${store.representative}'),
                        Text('Danh mục: ${store.targetCategories.join(", ")}'),
                        if (store.description.isNotEmpty) Text('Mô tả: ${store.description}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Verification Documents Viewer
                const Text('Tài liệu & Giấy tờ xác minh:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 8),
                if (store.verificationDocs.isEmpty)
                  const Text('Người đăng ký chưa tải lên tệp tài liệu xác minh nào.', style: TextStyle(color: Colors.red, fontSize: 13))
                else
                  SizedBox(
                    height: 120,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: store.verificationDocs.length,
                      itemBuilder: (context, index) {
                        final url = store.verificationDocs[index];
                        return InkWell(
                          onTap: () => _showImageZoom(context, url),
                          child: Container(
                            margin: const EdgeInsets.only(right: 12),
                            width: 100,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                url,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const Icon(Icons.insert_drive_file, size: 36),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 16),

                // Review Checklist
                Card(
                  color: Colors.green.shade50.withAlpha(50),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Checklist kiểm tra của BQT:', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                        CheckboxListTile(
                          dense: true,
                          title: const Text('1. Tài liệu mở được, đủ mặt và rõ chữ'),
                          value: _checkLegible,
                          onChanged: (v) => setState(() => _checkLegible = v ?? false),
                        ),
                        CheckboxListTile(
                          dense: true,
                          title: const Text('2. Đúng loại tài liệu theo loại gian hàng'),
                          value: _checkCorrectType,
                          onChanged: (v) => setState(() => _checkCorrectType = v ?? false),
                        ),
                        CheckboxListTile(
                          dense: true,
                          title: const Text('3. Khớp tên người đại diện & thông tin khai báo'),
                          value: _checkInfoMatches,
                          onChanged: (v) => setState(() => _checkInfoMatches = v ?? false),
                        ),
                        CheckboxListTile(
                          dense: true,
                          title: const Text('4. Không có dấu hiệu bất thường hay mâu thuẫn'),
                          value: _checkNoDiscrepancies,
                          onChanged: (v) => setState(() => _checkNoDiscrepancies = v ?? false),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Response fields
                TextFormField(
                  controller: _reasonController,
                  decoration: const InputDecoration(
                    labelText: 'Lý do / Phản hồi gửi người đăng ký *',
                    hintText: 'Nhập lý do nếu Yêu cầu bổ sung hoặc Từ chối...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _internalNoteController,
                  decoration: const InputDecoration(
                    labelText: 'Ghi chú nội bộ BQT (Chỉ BQT thấy)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
                        onPressed: _isSubmitting ? null : () => _processReview(store, 'needs_changes'),
                        child: const Text('Bổ sung'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                        onPressed: _isSubmitting ? null : () => _processReview(store, 'rejected'),
                        child: const Text('Từ chối'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: (_isSubmitting || !_allChecklistPassed)
                            ? null
                            : () => _processReview(store, 'approved'),
                        child: const Text('Duyệt hồ sơ', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Lỗi: $e')),
      ),
    );
  }
}
