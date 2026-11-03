import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../models/journal_model.dart';
import '../repositories/journal_repository.dart';

/// Màn hình thêm mục nhật ký mới cho 1 mùa vụ (hỗ trợ chọn ngày thực hiện recordDate để đăng bù)
class CreateJournalEntryScreen extends ConsumerStatefulWidget {
  final String journalId;

  const CreateJournalEntryScreen({
    super.key,
    required this.journalId,
  });

  @override
  ConsumerState<CreateJournalEntryScreen> createState() => _CreateJournalEntryScreenState();
}

class _CreateJournalEntryScreenState extends ConsumerState<CreateJournalEntryScreen> {
  final _formKey = GlobalKey<FormState>();

  final _titleController = TextEditingController();
  final _notesController = TextEditingController();
  final _stageController = TextEditingController(text: 'Chăm sóc định kỳ');
  final _videoUrlController = TextEditingController();

  late DateTime _recordDate;
  String _privacy = 'public';
  bool _isLoading = false;

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
  void initState() {
    super.initState();
    _recordDate = DateUtils.dateOnly(DateTime.now());
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _stageController.dispose();
    _videoUrlController.dispose();
    super.dispose();
  }

  Future<void> _submit(JournalModel journal) async {
    if (!_formKey.currentState!.validate()) return;

    final now = DateTime.now();
    final today = DateUtils.dateOnly(now);
    final seasonStartDate = DateUtils.dateOnly(DateTime.fromMillisecondsSinceEpoch(journal.startDate));

    if (_recordDate.isBefore(seasonStartDate)) {
      final startStr = '${seasonStartDate.day.toString().padLeft(2, '0')}/${seasonStartDate.month.toString().padLeft(2, '0')}/${seasonStartDate.year}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ngày thực hiện không được trước ngày bắt đầu mùa vụ ($startStr).'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_recordDate.isAfter(today)) {
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
      final entry = JournalEntryModel(
        id: '',
        journalId: widget.journalId,
        recordDate: DateUtils.dateOnly(_recordDate).millisecondsSinceEpoch,
        postDate: DateTime.now().millisecondsSinceEpoch,
        growthStage: _stageController.text.trim(),
        title: _titleController.text.trim(),
        notes: _notesController.text.trim(),
        attachedVideoUrl: _videoUrlController.text.trim().isNotEmpty ? _videoUrlController.text.trim() : null,
        privacy: _privacy,
      );

      await ref.read(journalRepositoryProvider).addJournalEntry(entry);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thêm mục nhật ký thành công!')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi thêm nhật ký: $e')),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thêm Mục Nhật Ký'),
      ),
      body: journalAsync.when(
        data: (journal) {
          if (journal == null) {
            return const Center(child: Text('Không tìm thấy thông tin mùa vụ.'));
          }

          final seasonStartDate = DateUtils.dateOnly(DateTime.fromMillisecondsSinceEpoch(journal.startDate));

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
                              '${_recordDate.day.toString().padLeft(2, '0')}/${_recordDate.month.toString().padLeft(2, '0')}/${_recordDate.year}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primary),
                            ),
                            trailing: const Icon(Icons.edit_calendar),
                            onTap: () async {
                              final initial = _recordDate.isBefore(seasonStartDate)
                                  ? seasonStartDate
                                  : (_recordDate.isAfter(today) ? today : _recordDate);

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
                      hintText: 'VD: Tưới nước & bón NPK đợt 2',
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
                      hintText: 'Liều lượng phân bón, tình hình sâu bệnh, thời tiết...',
                    ),
                    validator: (val) => val == null || val.trim().isEmpty ? 'Vui lòng nhập ghi chú' : null,
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _videoUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Link video kỹ thuật đính kèm (nếu có)',
                      hintText: 'Link video hoặc ID video',
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
                          : const Text('Lưu Mục Nhật Ký'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Lỗi: $e')),
      ),
    );
  }
}
