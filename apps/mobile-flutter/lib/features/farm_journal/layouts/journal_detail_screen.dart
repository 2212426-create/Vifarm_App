import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/share_button.dart';
import '../../../shared/widgets/universal_share_bottom_sheet.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/journal_model.dart';
import '../repositories/journal_repository.dart';

/// Màn hình Chi tiết Nhật ký mùa vụ với Timeline sinh động
class JournalDetailScreen extends ConsumerStatefulWidget {
  final String journalId;

  const JournalDetailScreen({super.key, required this.journalId});

  @override
  ConsumerState<JournalDetailScreen> createState() =>
      _JournalDetailScreenState();
}

class _JournalDetailScreenState extends ConsumerState<JournalDetailScreen> {
  bool _isDeleting = false;
  bool _showInvalidEntries = false;

  Future<void> _confirmAndDelete(
    BuildContext context,
    JournalModel journal,
    String currentUserId,
  ) async {
    return showDialog(
      context: context,
      barrierDismissible: !_isDeleting,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Xóa nhật ký "${journal.name}"?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Hành động này sẽ xóa vĩnh viễn nhật ký và tất cả các mục ghi chép thuộc nhật ký này.',
                    style: TextStyle(height: 1.4),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Lưu ý: Các video đăng độc lập trên trang cá nhân sẽ không bị xóa mà chỉ gỡ liên kết với nhật ký này.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      height: 1.3,
                    ),
                  ),
                  if (_isDeleting) ...[
                    const SizedBox(height: 16),
                    const Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.red,
                          ),
                        ),
                        SizedBox(width: 12),
                        Text('Đang xóa nhật ký...'),
                      ],
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: _isDeleting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Hủy'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _isDeleting
                      ? null
                      : () async {
                          setDialogState(() => _isDeleting = true);
                          try {
                            await ref
                                .read(journalRepositoryProvider)
                                .deleteJournal(journal.id, currentUserId);
                            if (mounted && dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Đã xóa nhật ký "${journal.name}" thành công!',
                                  ),
                                ),
                              );
                              context.pop();
                            }
                          } catch (e) {
                            if (mounted && dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Xóa nhật ký thất bại: ${e.toString().replaceAll("Exception: ", "")}',
                                  ),
                                  action: SnackBarAction(
                                    label: 'Thử lại',
                                    onPressed: () => _confirmAndDelete(
                                      context,
                                      journal,
                                      currentUserId,
                                    ),
                                  ),
                                ),
                              );
                            }
                          } finally {
                            if (mounted) {
                              setState(() => _isDeleting = false);
                            }
                          }
                        },
                  child: const Text('Xóa nhật ký'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final journalAsync = ref.watch(
      journalDetailStreamProvider(widget.journalId),
    );
    final entriesAsync = ref.watch(
      journalEntriesStreamProvider(widget.journalId),
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return journalAsync.when(
      data: (journal) {
        if (journal == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Nhật ký mùa vụ')),
            body: const Center(child: Text('Không tìm thấy nhật ký này!')),
          );
        }

        final isOwner =
            currentUser != null && currentUser.uid == journal.ownerId;
        final isPrivate = journal.privacy == 'private' && !isOwner;

        if (isPrivate) {
          return Scaffold(
            appBar: AppBar(title: const Text('Nhật ký mùa vụ')),
            body: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('Nhật ký này ở chế độ riêng tư.'),
                ],
              ),
            ),
          );
        }

        final seasonStartDate = DateTime.fromMillisecondsSinceEpoch(
          journal.startDate,
        );

        return Scaffold(
          appBar: AppBar(
            title: Text(journal.name),
            actions: [
              ShareButton(content: ShareContentModel.fromJournal(journal)),
              if (isOwner) ...[
                IconButton(
                  icon: const Icon(Icons.playlist_add),
                  tooltip: 'Thêm ghi chép',
                  onPressed: () {
                    context.push('/journal/${journal.id}/entry/create');
                  },
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') {
                      context.push('/journal/${journal.id}/edit');
                    } else if (value == 'delete') {
                      _confirmAndDelete(context, journal, currentUser.uid);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 20),
                          SizedBox(width: 8),
                          Text('Chỉnh sửa nhật ký'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_forever,
                            color: Colors.red,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Xóa nhật ký',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header card
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withAlpha(40),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '🌱 ${journal.crop} ${journal.variety != null && journal.variety!.isNotEmpty ? "(${journal.variety})" : ""}',
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: journal.status == 'in_progress'
                                    ? Colors.green.withAlpha(40)
                                    : Colors.blue.withAlpha(40),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                journal.status == 'in_progress'
                                    ? 'Đang canh tác'
                                    : 'Đã kết thúc',
                                style: TextStyle(
                                  color: journal.status == 'in_progress'
                                      ? Colors.green
                                      : Colors.blue,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          journal.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.location_on,
                              size: 16,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '${journal.farmLocation} - ${journal.region}',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 13,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.calendar_today,
                              size: 16,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Bắt đầu mùa vụ: ${seasonStartDate.day.toString().padLeft(2, '0')}/${seasonStartDate.month.toString().padLeft(2, '0')}/${seasonStartDate.year}',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (journal.description.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          const Divider(),
                          Text(
                            journal.description,
                            style: const TextStyle(fontSize: 13, height: 1.4),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Timeline Entries Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Dòng thời gian nhật ký',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    if (isOwner)
                      TextButton.icon(
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Thêm ghi chép'),
                        onPressed: () {
                          context.push('/journal/${journal.id}/entry/create');
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // Timeline entries and starting milestone
                entriesAsync.when(
                  data: (allEntries) {
                    final validEntries = <JournalEntryModel>[];
                    final invalidEntries = <JournalEntryModel>[];

                    for (final entry in allEntries) {
                      final classification = JournalModel.classifyEntry(
                        entry,
                        journal.startDate,
                      );
                      if (classification.isValid) {
                        validEntries.add(entry);
                      } else {
                        invalidEntries.add(entry);
                      }
                    }

                    // Sort valid entries using 3-tier comparator (recordDate -> postDate -> id)
                    validEntries.sort(JournalModel.compareEntries);

                    debugPrint(
                      '[JournalDebug] Total: ${allEntries.length}, Valid: ${validEntries.length}, Invalid: ${invalidEntries.length}, Expanded: $_showInvalidEntries',
                    );

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Warning banner for Owner if legacy entries have invalid dates
                        if (isOwner && invalidEntries.isNotEmpty) ...[
                          Card(
                            color: isDark
                                ? Colors.amber.shade900.withAlpha(80)
                                : Colors.amber.shade50,
                            shape: RoundedRectangleBorder(
                              side: BorderSide(
                                color: Colors.amber.shade700,
                                width: 1,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.warning_amber_rounded,
                                        color: Colors.amber,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Có ${invalidEntries.length} mục ghi chép cần kiểm tra lại ngày thực hiện.',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          setState(
                                            () => _showInvalidEntries =
                                                !_showInvalidEntries,
                                          );
                                        },
                                        child: Text(
                                          _showInvalidEntries
                                              ? 'Thu gọn'
                                              : 'Xem danh sách',
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Text(
                                    'Các mục này có ngày thực hiện trước ngày bắt đầu mùa vụ hoặc trong tương lai. Bạn có thể sửa ngày thực hiện cho đúng.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  if (_showInvalidEntries) ...[
                                    const SizedBox(height: 10),
                                    const Divider(),
                                    Column(
                                      children: List.generate(invalidEntries.length, (
                                        index,
                                      ) {
                                        final invEntry = invalidEntries[index];
                                        final classification =
                                            JournalModel.classifyEntry(
                                              invEntry,
                                              journal.startDate,
                                            );
                                        final invDate =
                                            DateTime.fromMillisecondsSinceEpoch(
                                              invEntry.recordDate,
                                            );
                                        final dateStr = invEntry.recordDate > 0
                                            ? '${invDate.day.toString().padLeft(2, '0')}/${invDate.month.toString().padLeft(2, '0')}/${invDate.year}'
                                            : 'Chưa có ngày hợp lệ';

                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (index > 0)
                                              const Divider(height: 16),
                                            Text(
                                              invEntry.title,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Ngày đang lưu: $dateStr',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.redAccent,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              classification.reasonMessage,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.end,
                                              children: [
                                                TextButton.icon(
                                                  icon: const Icon(
                                                    Icons.delete_outline,
                                                    size: 16,
                                                    color: Colors.red,
                                                  ),
                                                  label: const Text(
                                                    'Xóa',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.red,
                                                    ),
                                                  ),
                                                  onPressed: () async {
                                                    final confirm = await showDialog<bool>(
                                                      context: context,
                                                      builder: (dialogCtx) => AlertDialog(
                                                        title: const Text(
                                                          'Xóa mục ghi chép?',
                                                        ),
                                                        content: Text(
                                                          'Bạn có chắc chắn muốn xóa mục "${invEntry.title}" không?',
                                                        ),
                                                        actions: [
                                                          TextButton(
                                                            onPressed: () =>
                                                                Navigator.pop(
                                                                  dialogCtx,
                                                                  false,
                                                                ),
                                                            child: const Text(
                                                              'Hủy',
                                                            ),
                                                          ),
                                                          ElevatedButton(
                                                            style: ElevatedButton.styleFrom(
                                                              backgroundColor:
                                                                  Colors.red,
                                                              foregroundColor:
                                                                  Colors.white,
                                                            ),
                                                            onPressed: () =>
                                                                Navigator.pop(
                                                                  dialogCtx,
                                                                  true,
                                                                ),
                                                            child: const Text(
                                                              'Xóa',
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                    if (confirm == true) {
                                                      await ref
                                                          .read(
                                                            journalRepositoryProvider,
                                                          )
                                                          .deleteJournalEntry(
                                                            journal.id,
                                                            invEntry.id,
                                                          );
                                                    }
                                                  },
                                                ),
                                                const SizedBox(width: 8),
                                                ElevatedButton.icon(
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        AppColors.primary,
                                                    foregroundColor:
                                                        Colors.white,
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 10,
                                                          vertical: 6,
                                                        ),
                                                    minimumSize: Size.zero,
                                                    tapTargetSize:
                                                        MaterialTapTargetSize
                                                            .shrinkWrap,
                                                  ),
                                                  icon: const Icon(
                                                    Icons.edit,
                                                    size: 14,
                                                  ),
                                                  label: const Text(
                                                    'Sửa ngày',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                  onPressed: () {
                                                    context.push(
                                                      '/journal/${journal.id}/entry/${invEntry.id}/edit',
                                                    );
                                                  },
                                                ),
                                              ],
                                            ),
                                          ],
                                        );
                                      }),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Starting Milestone Node (🚩 Bắt đầu mùa vụ - dd/MM/yyyy)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              children: [
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade800,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.flag,
                                    size: 12,
                                    color: Colors.white,
                                  ),
                                ),
                                if (validEntries.isNotEmpty)
                                  Container(
                                    width: 2,
                                    height: 30,
                                    color: AppColors.primary.withAlpha(120),
                                  ),
                              ],
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.amber.shade900.withAlpha(40)
                                      : Colors.amber.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.amber.shade700.withAlpha(100),
                                  ),
                                ),
                                child: Text(
                                  '🚩 Bắt đầu mùa vụ — ${seasonStartDate.day.toString().padLeft(2, '0')}/${seasonStartDate.month.toString().padLeft(2, '0')}/${seasonStartDate.year}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: isDark
                                        ? Colors.amber.shade200
                                        : Colors.amber.shade900,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        if (validEntries.isEmpty) ...[
                          const SizedBox(height: 20),
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.note_add_outlined,
                                    size: 48,
                                    color: isDark
                                        ? AppColors.darkTextHint
                                        : AppColors.lightTextHint,
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Chưa có ghi chép công việc nào trong mùa vụ này.',
                                  ),
                                  if (isOwner)
                                    const Text(
                                      'Bấm "Thêm ghi chép" để ghi nhận công việc đầu tiên!',
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 12),

                          // List of valid entries sorted chronologically (oldest to newest)
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: validEntries.length,
                            itemBuilder: (context, index) {
                              final entry = validEntries[index];
                              final recordDate =
                                  DateTime.fromMillisecondsSinceEpoch(
                                    entry.recordDate,
                                  );
                              final isLast = index == validEntries.length - 1;
                              final dayNumber = JournalModel.calculateDayNumber(
                                recordDate,
                                seasonStartDate,
                              );

                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Left timeline node
                                  Column(
                                    children: [
                                      Container(
                                        width: 16,
                                        height: 16,
                                        decoration: BoxDecoration(
                                          color: AppColors.primary,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                      if (!isLast)
                                        Container(
                                          width: 2,
                                          height: 130,
                                          color: AppColors.primary.withAlpha(
                                            80,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(width: 12),

                                  // Right entry content card
                                  Expanded(
                                    child: Card(
                                      margin: const EdgeInsets.only(bottom: 16),
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Row(
                                                  children: [
                                                    Text(
                                                      '${recordDate.day.toString().padLeft(2, '0')}/${recordDate.month.toString().padLeft(2, '0')}/${recordDate.year}',
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color:
                                                            AppColors.primary,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 2,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: AppColors.primary
                                                            .withAlpha(30),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              4,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        'Ngày thứ $dayNumber',
                                                        style: const TextStyle(
                                                          color:
                                                              AppColors.primary,
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),

                                                Row(
                                                  children: [
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 2,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: AppColors
                                                            .accentBrown
                                                            .withAlpha(30),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              4,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        entry.growthStage,
                                                        style: const TextStyle(
                                                          color: AppColors
                                                              .accentBrown,
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                    if (isOwner)
                                                      IconButton(
                                                        icon: const Icon(
                                                          Icons.edit,
                                                          size: 16,
                                                        ),
                                                        padding:
                                                            EdgeInsets.zero,
                                                        constraints:
                                                            const BoxConstraints(),
                                                        tooltip: 'Sửa ghi chép',
                                                        onPressed: () {
                                                          context.push(
                                                            '/journal/${journal.id}/entry/${entry.id}/edit',
                                                          );
                                                        },
                                                      ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              entry.title,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              entry.notes,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                height: 1.4,
                                              ),
                                            ),
                                            if (entry.attachedVideoUrl !=
                                                    null &&
                                                entry
                                                    .attachedVideoUrl!
                                                    .isNotEmpty) ...[
                                              const SizedBox(height: 8),
                                              OutlinedButton.icon(
                                                icon: const Icon(
                                                  Icons.play_circle_fill,
                                                  size: 18,
                                                ),
                                                label: const Text(
                                                  'Xem video kỹ thuật',
                                                ),
                                                onPressed: () {
                                                  context.push(
                                                    '/video/${entry.attachedVideoUrl}',
                                                  );
                                                },
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ],
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (err, stack) => Text('Lỗi: $err'),
                ),
              ],
            ),
          ),
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, stack) => Scaffold(body: Center(child: Text('Lỗi: $err'))),
    );
  }
}
