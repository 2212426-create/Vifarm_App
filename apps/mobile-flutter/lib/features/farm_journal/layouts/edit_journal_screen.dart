import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/journal_model.dart';
import '../repositories/journal_repository.dart';

/// Màn hình chỉnh sửa Hồ Sơ Nhật Ký Mùa Vụ
class EditJournalScreen extends ConsumerStatefulWidget {
  final String journalId;

  const EditJournalScreen({
    super.key,
    required this.journalId,
  });

  @override
  ConsumerState<EditJournalScreen> createState() => _EditJournalScreenState();
}

class _EditJournalScreenState extends ConsumerState<EditJournalScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _cropController = TextEditingController();
  final _varietyController = TextEditingController();
  final _regionController = TextEditingController();
  final _descriptionController = TextEditingController();

  DateTime? _startDate;
  String _privacy = 'public';
  String _status = 'in_progress';
  bool _isLoading = false;
  bool _isInitialized = false;
  JournalModel? _originalJournal;

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

  void _initFromJournal(JournalModel journal) {
    if (_isInitialized) return;
    _originalJournal = journal;
    _nameController.text = journal.name;
    _locationController.text = journal.farmLocation;
    _cropController.text = journal.crop;
    _varietyController.text = journal.variety ?? '';
    _regionController.text = journal.region;
    _descriptionController.text = journal.description;
    _startDate = DateUtils.dateOnly(DateTime.fromMillisecondsSinceEpoch(journal.startDate));
    _privacy = journal.privacy;
    _status = journal.status;
    _isInitialized = true;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _startDate == null || _originalJournal == null) return;

    final now = DateTime.now();
    final currentToday = DateUtils.dateOnly(now);
    final currentEarliest = JournalModel.getEarliestAllowedStartDate(currentToday);

    final isStartDateChanged = _startDate!.millisecondsSinceEpoch != _originalJournal!.startDate;

    if (isStartDateChanged) {
      // 1. Check 3 calendar month rule for new start date
      if (!JournalModel.isValidStartDate(_startDate!, now)) {
        final earliestStr = '${currentEarliest.day.toString().padLeft(2, '0')}/${currentEarliest.month.toString().padLeft(2, '0')}/${currentEarliest.year}';
        final todayStr = '${currentToday.day.toString().padLeft(2, '0')}/${currentToday.month.toString().padLeft(2, '0')}/${currentToday.year}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ngày bắt đầu mùa vụ mới phải nằm trong khoảng $earliestStr đến $todayStr.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // 2. Check conflict with existing entries
      final entries = ref.read(journalEntriesStreamProvider(widget.journalId)).valueOrNull ?? [];
      if (entries.isNotEmpty) {
        final earliestEntryDate = entries
            .map((e) => DateUtils.dateOnly(DateTime.fromMillisecondsSinceEpoch(e.recordDate)))
            .reduce((a, b) => a.isBefore(b) ? a : b);

        if (_startDate!.isAfter(earliestEntryDate)) {
          final newStartStr = '${_startDate!.day.toString().padLeft(2, '0')}/${_startDate!.month.toString().padLeft(2, '0')}/${_startDate!.year}';
          final entryStr = '${earliestEntryDate.day.toString().padLeft(2, '0')}/${earliestEntryDate.month.toString().padLeft(2, '0')}/${earliestEntryDate.year}';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Không thể đổi ngày bắt đầu thành $newStartStr vì đã có ghi chép ngày $entryStr. Vui lòng điều chỉnh hoặc xóa ghi chép này trước.'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
          return;
        }
      }
    }

    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null || currentUser.uid != _originalJournal!.ownerId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bạn không có quyền chỉnh sửa nhật ký này!')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final updatedJournal = JournalModel(
        id: _originalJournal!.id,
        ownerId: _originalJournal!.ownerId,
        ownerName: _originalJournal!.ownerName,
        name: _nameController.text.trim(),
        farmLocation: _locationController.text.trim(),
        crop: _cropController.text.trim(),
        variety: _varietyController.text.trim().isNotEmpty ? _varietyController.text.trim() : null,
        startDate: DateUtils.dateOnly(_startDate!).millisecondsSinceEpoch,
        region: _regionController.text.trim(),
        description: _descriptionController.text.trim(),
        status: _status,
        privacy: _privacy,
        createdAt: _originalJournal!.createdAt,
      );

      await ref.read(journalRepositoryProvider).updateJournal(updatedJournal, currentUser.uid);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cập nhật nhật ký thành công!')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi cập nhật nhật ký: ${e.toString().replaceAll("Exception: ", "")}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final journalAsync = ref.watch(journalDetailStreamProvider(widget.journalId));
    final today = DateUtils.dateOnly(DateTime.now());
    final earliestAllowedDate = JournalModel.getEarliestAllowedStartDate(today);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chỉnh Sửa Nhật Ký Mùa Vụ'),
      ),
      body: journalAsync.when(
        data: (journal) {
          if (journal == null) {
            return const Center(child: Text('Không tìm thấy nhật ký này!'));
          }

          _initFromJournal(journal);

          return SingleChildScrollView(
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
                    ),
                    validator: (val) => val == null || val.trim().isEmpty ? 'Vui lòng nhập tên nhật ký' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _cropController,
                    decoration: const InputDecoration(
                      labelText: 'Loại cây trồng *',
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
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _regionController,
                          decoration: const InputDecoration(
                            labelText: 'Tỉnh / Khu vực *',
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
                    ),
                    validator: (val) => val == null || val.trim().isEmpty ? 'Vui lòng nhập vị trí vườn' : null,
                  ),
                  const SizedBox(height: 16),

                  // Ngày bắt đầu
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Ngày bắt đầu mùa vụ *'),
                        subtitle: Text(
                          _startDate != null
                              ? '${_startDate!.day.toString().padLeft(2, '0')}/${_startDate!.month.toString().padLeft(2, '0')}/${_startDate!.year}'
                              : 'Chọn ngày',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primary),
                        ),
                        trailing: const Icon(Icons.calendar_today, color: AppColors.primary),
                        onTap: () async {
                          final currentToday = DateUtils.dateOnly(DateTime.now());
                          final currentEarliest = JournalModel.getEarliestAllowedStartDate(currentToday);

                          final initial = _startDate != null && _startDate!.isBefore(currentEarliest)
                              ? currentEarliest
                              : (_startDate != null && _startDate!.isAfter(currentToday) ? currentToday : (_startDate ?? currentToday));

                          final picked = await showDatePicker(
                            context: context,
                            initialDate: initial,
                            firstDate: currentEarliest,
                            lastDate: currentToday,
                          );
                          if (picked != null) {
                            setState(() => _startDate = DateUtils.dateOnly(picked));
                          }
                        },
                      ),
                      Text(
                        'Gợi ý: Ngày bắt đầu thay đổi phải nằm trong khoảng ${earliestAllowedDate.day.toString().padLeft(2, '0')}/${earliestAllowedDate.month.toString().padLeft(2, '0')}/${earliestAllowedDate.year} đến ${today.day.toString().padLeft(2, '0')}/${today.month.toString().padLeft(2, '0')}/${today.year}.',
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
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Trạng thái mùa vụ
                  const Text('Trạng thái mùa vụ:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('Đang canh tác'),
                          value: 'in_progress',
                          groupValue: _status,
                          onChanged: (val) => setState(() => _status = val!),
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('Đã kết thúc'),
                          value: 'finished',
                          groupValue: _status,
                          onChanged: (val) => setState(() => _status = val!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Quyền riêng tư
                  const Text('Quyền riêng tư:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('Công khai'),
                          value: 'public',
                          groupValue: _privacy,
                          onChanged: (val) => setState(() => _privacy = val!),
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('Riêng tư'),
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
                          : const Text('Lưu Thay Đổi'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Lỗi: $err')),
      ),
    );
  }
}
