import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/journal_model.dart';
import '../repositories/journal_repository.dart';

/// Màn hình tạo Hồ Sơ Nhật Ký Mùa Vụ
class CreateJournalScreen extends ConsumerStatefulWidget {
  const CreateJournalScreen({super.key});

  @override
  ConsumerState<CreateJournalScreen> createState() => _CreateJournalScreenState();
}

class _CreateJournalScreenState extends ConsumerState<CreateJournalScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _cropController = TextEditingController();
  final _varietyController = TextEditingController();
  final _regionController = TextEditingController();
  final _descriptionController = TextEditingController();

  late DateTime _startDate;
  String _privacy = 'public'; // 'public' | 'private'
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _startDate = DateUtils.dateOnly(DateTime.now());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _cropController.dispose();
    _varietyController.dispose();
    _regionController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final now = DateTime.now();
    final currentToday = DateUtils.dateOnly(now);
    final currentEarliest = JournalModel.getEarliestAllowedStartDate(currentToday);

    if (!JournalModel.isValidStartDate(_startDate, now)) {
      final earliestStr = '${currentEarliest.day.toString().padLeft(2, '0')}/${currentEarliest.month.toString().padLeft(2, '0')}/${currentEarliest.year}';
      final todayStr = '${currentToday.day.toString().padLeft(2, '0')}/${currentToday.month.toString().padLeft(2, '0')}/${currentToday.year}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ngày bắt đầu phải nằm trong khoảng $earliestStr đến $todayStr.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng đăng nhập để tạo nhật ký!')),
      );
      return;
    }

    final userProfile = ref.read(currentUserProfileProvider).valueOrNull;
    final ownerName = userProfile?.username ?? currentUser.email?.split('@')[0] ?? '';

    setState(() => _isLoading = true);

    try {
      final journal = JournalModel(
        id: '',
        ownerId: currentUser.uid,
        ownerName: ownerName,
        name: _nameController.text.trim(),
        farmLocation: _locationController.text.trim(),
        crop: _cropController.text.trim(),
        variety: _varietyController.text.trim().isNotEmpty ? _varietyController.text.trim() : null,
        startDate: DateUtils.dateOnly(_startDate).millisecondsSinceEpoch,
        region: _regionController.text.trim(),
        description: _descriptionController.text.trim(),
        status: 'in_progress',
        privacy: _privacy,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      final newJournalId = await ref.read(journalRepositoryProvider).createJournal(journal);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tạo hồ sơ nhật ký thành công!')),
        );
        context.pushReplacement('/journal/$newJournalId');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi tạo nhật ký: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final earliestAllowedDate = JournalModel.getEarliestAllowedStartDate(today);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thêm Nhật Ký Mùa Vụ'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Thông tin vườn / Mùa vụ',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Tên nhật ký / Mùa vụ *',
                  hintText: 'VD: Nhật ký Sầu Riêng Ri6 2026 - Lô A1',
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Vui lòng nhập tên nhật ký' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _cropController,
                decoration: const InputDecoration(
                  labelText: 'Loại cây trồng *',
                  hintText: 'VD: Sầu riêng, Cà phê, Lúa, Dưa lưới...',
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Vui lòng nhập loại cây trồng' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _varietyController,
                      decoration: const InputDecoration(
                        labelText: 'Giống cây (nếu có)',
                        hintText: 'VD: Ri6, DONA, ST25...',
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
                      validator: (val) => val == null || val.trim().isEmpty ? 'Vui lòng nhập khu vực' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(
                  labelText: 'Vườn / Lô / Thửa đất *',
                  hintText: 'VD: Vườn nhà - Thôn 3, Đức Trọng',
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Vui lòng nhập vị trí vườn' : null,
              ),
              const SizedBox(height: 16),

              // Chọn ngày bắt đầu với giới hạn 3 tháng
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ngày bắt đầu mùa vụ *'),
                    subtitle: Text(
                      '${_startDate.day.toString().padLeft(2, '0')}/${_startDate.month.toString().padLeft(2, '0')}/${_startDate.year}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primary),
                    ),
                    trailing: const Icon(Icons.calendar_today, color: AppColors.primary),
                    onTap: () async {
                      final currentToday = DateUtils.dateOnly(DateTime.now());
                      final currentEarliest = JournalModel.getEarliestAllowedStartDate(currentToday);

                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _startDate.isBefore(currentEarliest)
                            ? currentEarliest
                            : (_startDate.isAfter(currentToday) ? currentToday : _startDate),
                        firstDate: currentEarliest,
                        lastDate: currentToday,
                      );
                      if (picked != null) {
                        setState(() => _startDate = DateUtils.dateOnly(picked));
                      }
                    },
                  ),
                  Text(
                    'Gợi ý: Ngày bắt đầu phải nằm trong khoảng ${earliestAllowedDate.day.toString().padLeft(2, '0')}/${earliestAllowedDate.month.toString().padLeft(2, '0')}/${earliestAllowedDate.year} đến ${today.day.toString().padLeft(2, '0')}/${today.month.toString().padLeft(2, '0')}/${today.year}.',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Mô tả / Ghi chú ban đầu',
                  hintText: 'Mục tiêu năng suất, diện tích, quy trình chăm sóc...',
                ),
              ),
              const SizedBox(height: 16),

              // Quyền riêng tư
              const Text('Quyền riêng tư:', style: TextStyle(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('Công khai'),
                      subtitle: const Text('Mọi người đều xem được'),
                      value: 'public',
                      groupValue: _privacy,
                      onChanged: (val) => setState(() => _privacy = val!),
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('Riêng tư'),
                      subtitle: const Text('Chỉ mình tôi xem'),
                      value: 'private',
                      groupValue: _privacy,
                      onChanged: (val) => setState(() => _privacy = val!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Tạo Nhật Ký Mùa Vụ'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
