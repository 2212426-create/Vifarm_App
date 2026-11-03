import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../models/journal_model.dart';
import '../repositories/journal_repository.dart';

/// Màn hình chỉnh sửa mục nhật ký (hỗ trợ điều chỉnh ngày thực hiện recordDate hoặc xóa mục)
class EditJournalEntryScreen extends ConsumerStatefulWidget {
  final String journalId;
  final String entryId;

  const EditJournalEntryScreen({
    super.key,
    required this.journalId,
    required this.entryId,
  });

  @override
  ConsumerState<EditJournalEntryScreen> createState() => _EditJournalEntryScreenState();
}

class _EditJournalEntryScreenState extends ConsumerState<EditJournalEntryScreen> {
  final _formKey = GlobalKey<FormState>();

  final _titleController = TextEditingController();
  final _notesController = TextEditingController();
  final _stageController = TextEditingController();
  final _videoUrlController = TextEditingController();

  DateTime? _recordDate;
  String _privacy = 'public';
  bool _isLoading = false;
  bool _isInitialized = false;
  JournalEntryModel? _originalEntry;

  final List<String> _stagesSuggestion = [
    'Làm đất / Gieo trồng',
    'Tỉa cành / Tạo tán',
    'Bón phân đợt 1',
    'Bón phân đợt 2',
    'Phun thuốc phòng trừ sâu bệnh',
    'Xử lý ra hoa',
    'Tỉa hoa / Tỉa quả',
    'Nuôi quả',
    'Thu hoạch',
    'Chăm sóc sau thu hoạch',
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _stageController.dispose();
    _videoUrlController.dispose();
    super.dispose();
  }

  void _initFromEntry(JournalEntryModel entry) {
    if (_isInitialized) return;
    _originalEntry = entry;
    _titleController.text = entry.title;
    _notesController.text = entry.notes;
    _stageController.text = entry.growthStage;
    _videoUrlController.text = entry.attachedVideoUrl ?? '';
    _recordDate = DateUtils.dateOnly(DateTime.fromMillisecondsSinceEpoch(entry.recordDate));
    _privacy = entry.privacy;
    _isInitialized = true;
  }

  Future<void> _submit(JournalModel journal) async {
    if (!_formKey.currentState!.validate() || _recordDate == null || _originalEntry == null) return;

    final now = DateTime.now();
    final today = DateUtils.dateOnly(now);
    final seasonStartDate = DateUtils.dateOnly(DateTime.fromMillisecondsSinceEpoch(journal.startDate));

    if (_recordDate!.isBefore(seasonStartDate)) {
      final startStr = '${seasonStartDate.day.toString().padLeft(2, '0')}/${seasonStartDate.month.toString().padLeft(2, '0')}/${seasonStartDate.year}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ngày thực hiện không được trước ngày bắt đầu mùa vụ ($startStr).'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_recordDate!.isAfter(today)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ngày thực hiện không được trong tương lai.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final updatedEntry = JournalEntryModel(
        id: _originalEntry!.id,
        journalId: widget.journalId,
        recordDate: _recordDate!.millisecondsSinceEpoch,
        postDate: _originalEntry!.postDate,
        growthStage: _stageController.text.trim(),
        title: _titleController.text.trim(),
        notes: _notesController.text.trim(),
        attachedVideoUrl: _videoUrlController.text.trim().isNotEmpty ? _videoUrlController.text.trim() : null,
        attachedImageUrls: _originalEntry!.attachedImageUrls,
        privacy: _privacy,
      );

      await ref.read(journalRepositoryProvider).updateJournalEntry(updatedEntry);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cập nhật mục nhật ký thành công!')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi cập nhật mục nhật ký: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteEntry() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa mục ghi chép này?'),
        content: const Text('Hành động này sẽ xóa vĩnh viễn mục ghi chép này.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await ref.read(journalRepositoryProvider).deleteJournalEntry(widget.journalId, widget.entryId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã xóa mục ghi chép!')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi xóa mục ghi chép: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final journalAsync = ref.watch(journalDetailStreamProvider(widget.journalId));
    final entriesAsync = ref.watch(journalEntriesStreamProvider(widget.journalId));
    final today = DateUtils.dateOnly(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sửa Mục Nhật Ký'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            tooltip: 'Xóa mục này',
            onPressed: _isLoading ? null : _deleteEntry,
          ),
        ],
      ),
      body: journalAsync.when(
        data: (journal) {
          if (journal == null) {
            return const Center(child: Text('Không tìm thấy thông tin mùa vụ.'));
          }

          final seasonStartDate = DateUtils.dateOnly(DateTime.fromMillisecondsSinceEpoch(journal.startDate));

          return entriesAsync.when(
            data: (entries) {
              final entry = entries.firstWhere(
                (e) => e.id == widget.entryId,
                orElse: () => JournalEntryModel(
                  id: '',
                  journalId: '',
                  recordDate: 0,
                  postDate: 0,
                  growthStage: '',
                  title: '',
                  notes: '',
                ),
              );

              if (entry.id.isEmpty) {
                return const Center(child: Text('Mục ghi chép này không tồn tại hoặc đã bị xóa.'));
              }

              _initFromEntry(entry);

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Ngày thực hiện
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.event, color: AppColors.primary),
                                title: const Text('Ngày thực hiện *'),
                                subtitle: Text(
                                  _recordDate != null
                                      ? '${_recordDate!.day.toString().padLeft(2, '0')}/${_recordDate!.month.toString().padLeft(2, '0')}/${_recordDate!.year}'
                                      : 'Chọn ngày',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primary),
                                ),
                                trailing: const Icon(Icons.edit_calendar),
                                onTap: () async {
                                  final initial = _recordDate != null && _recordDate!.isBefore(seasonStartDate)
                                      ? seasonStartDate
                                      : (_recordDate != null && _recordDate!.isAfter(today) ? today : (_recordDate ?? today));

                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: initial,
                                    firstDate: seasonStartDate,
                                    lastDate: today,
                                  );
                                  if (picked != null) {
                                    setState(() => _recordDate = DateUtils.dateOnly(picked));
                                  }
                                },
                              ),
                              const Text(
                                'Gợi ý: Chọn ngày công việc thực sự diễn ra. Bạn có thể ghi bù từ ngày bắt đầu mùa vụ.',
                                style: TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _titleController,
                        decoration: const InputDecoration(
                          labelText: 'Tiêu đề công việc *',
                        ),
                        validator: (val) => val == null || val.trim().isEmpty ? 'Vui lòng nhập tiêu đề' : null,
                      ),
                      const SizedBox(height: 12),

                      // Giai đoạn
                      const Text('Giai đoạn cây trồng:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _stagesSuggestion.map((stage) {
                          final isSelected = _stageController.text == stage;
                          return ChoiceChip(
                            label: Text(stage),
                            selected: isSelected,
                            onSelected: (selected) {
                              if (selected) {
                                setState(() => _stageController.text = stage);
                              }
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _stageController,
                        decoration: const InputDecoration(
                          labelText: 'Tên giai đoạn tùy chỉnh',
                        ),
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _notesController,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Ghi chú công việc / Tình trạng cây *',
                        ),
                        validator: (val) => val == null || val.trim().isEmpty ? 'Vui lòng nhập ghi chú' : null,
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _videoUrlController,
                        decoration: const InputDecoration(
                          labelText: 'Link video kỹ thuật đính kèm (nếu có)',
                          prefixIcon: Icon(Icons.video_library),
                        ),
                      ),
                      const SizedBox(height: 16),

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
                          onPressed: _isLoading ? null : () => _submit(journal),
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
            error: (e, s) => Center(child: Text('Lỗi: $e')),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Lỗi: $e')),
      ),
    );
  }
}
