import '../../video_feed/providers/video_provider.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/providers/firebase_providers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/media/platform_media.dart';
import '../../auth/providers/auth_provider.dart';
import '../../store/models/store_model.dart';
import '../../store/repositories/store_repository.dart';
import '../providers/upload_provider.dart';

/// Màn hình thêm mô tả video, chọn chủ đề nông nghiệp và thực hiện tải lên
class VideoDescriptionScreen extends ConsumerStatefulWidget {
  final XFile? videoFile;
  final String? videoId; // Truyền vào nếu ở chế độ chỉnh sửa (Edit Mode)

  const VideoDescriptionScreen({super.key, this.videoFile, this.videoId});

  @override
  ConsumerState<VideoDescriptionScreen> createState() =>
      _VideoDescriptionScreenState();
}

class _VideoDescriptionScreenState
    extends ConsumerState<VideoDescriptionScreen> {
  final TextEditingController _descController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  // Chủ đề video & Khai báo quảng cáo
  String?
  _selectedTopic; // 'farming_experience' | 'garden_tour' | 'product_intro' | 'farmer_story' | 'other'
  bool _isSponsored = false;

  // Controllers cho các trường thông tin ngữ cảnh theo chủ đề
  final TextEditingController _cropController = TextEditingController();
  final TextEditingController _growthStageController = TextEditingController();
  final TextEditingController _regionController = TextEditingController();
  final TextEditingController _journalIdController = TextEditingController();
  final TextEditingController _productIdController = TextEditingController();

  VideoPlayerController? _videoPlayerController;
  bool _isEditMode = false;
  bool _isAiLoading = false;
  String _previewUrl = '';

  // Trạng thái bảo mật và chiến dịch Đà Lạt
  bool _allowDownload = true;
  bool _isCopyrightProtected = false;
  bool _isDalatCampaign = false;

  @override
  void initState() {
    super.initState();
    _isEditMode = widget.videoId != null && widget.videoId!.isNotEmpty;

    if (_isEditMode) {
      _loadVideoDetails();
    } else if (widget.videoFile != null) {
      _initLocalVideoPlayer();
    }
  }

  @override
  void dispose() {
    _descController.dispose();
    _focusNode.dispose();
    _cropController.dispose();
    _growthStageController.dispose();
    _regionController.dispose();
    _journalIdController.dispose();
    _productIdController.dispose();
    _videoPlayerController?.dispose();
    super.dispose();
  }

  /// Tải thông tin video cũ khi ở chế độ Edit
  Future<void> _loadVideoDetails() async {
    final firestore = ref.read(firestoreProvider);
    final doc = await firestore.collection('videos').doc(widget.videoId).get();
    if (doc.exists) {
      final data = doc.data();
      if (data != null) {
        _descController.text = data['description'] as String? ?? '';
        _selectedTopic = data['topic'] as String?;
        _isSponsored = data['isSponsored'] as bool? ?? false;
        _cropController.text = data['crop'] as String? ?? '';
        _growthStageController.text = data['growthStage'] as String? ?? '';
        _regionController.text = data['region'] as String? ?? '';
        _journalIdController.text = data['relatedJournalId'] as String? ?? '';

        final videoUri = data['videoUri'] as String? ?? '';
        if (videoUri.isNotEmpty) {
          setState(() {
            _previewUrl = videoUri.replaceAll('.mp4', '.jpg');
            if (_previewUrl.contains('/upload/')) {
              _previewUrl = _previewUrl.replaceAll('/upload/', '/upload/so_0/');
            }
          });
        }
      }
    }
  }

  /// Khởi chạy trình xem trước video cục bộ
  Future<void> _initLocalVideoPlayer() async {
    final file = widget.videoFile;
    if (file == null) return;

    try {
      _videoPlayerController = await PlatformMedia.createVideoPreview(file);
      await _videoPlayerController!.initialize();
      await _videoPlayerController!.setLooping(true);
      await _videoPlayerController!.setVolume(0.0);
      await _videoPlayerController!.play();
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể xem trước video: $error')),
        );
      }
    }
  }

  /// Thêm ký tự `#` hoặc ` #` vào vị trí con trỏ trong ô nhập
  void _insertHashtagSymbol() {
    final text = _descController.text;
    final selection = _descController.selection;
    final cursor = selection.start;

    String hashtag = '#';
    if (cursor > 0 && text[cursor - 1] != ' ') {
      hashtag = ' #';
    }

    final newText = text.replaceRange(
      selection.start == -1 ? text.length : selection.start,
      selection.end == -1 ? text.length : selection.end,
      hashtag,
    );

    _descController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset:
            (selection.start == -1 ? text.length : selection.start) +
            hashtag.length,
      ),
    );
    _focusNode.requestFocus();
  }

  /// Gọi Gemini AI gợi ý hashtag dựa trên mô tả hoặc hình ảnh bìa
  Future<void> _suggestHashtags() async {
    setState(() {
      _isAiLoading = true;
    });

    try {
      final gemini = ref.read(geminiServiceProvider);
      String aiResult = '';

      if (_isEditMode && _previewUrl.isNotEmpty) {
        final response = await http.get(Uri.parse(_previewUrl));
        if (response.statusCode == 200) {
          aiResult = await gemini.suggestHashtags(response.bodyBytes);
        }
      }

      if (aiResult.isEmpty) {
        final currentText = _descController.text.trim();
        final textPrompt = currentText.isNotEmpty
            ? 'Hãy gợi ý 5-10 hashtag TikTok tiếng Việt viral liên quan đến mô tả: "$currentText". Chỉ trả về các hashtag cách nhau bởi dấu cách.'
            : 'Hãy gợi ý 5-10 hashtag TikTok tiếng Việt đang thịnh hành (viral) nhất hiện nay. Chỉ trả về các hashtag cách nhau bởi dấu cách.';

        final model = GenerativeModel(
          model: 'gemini-1.5-flash',
          apiKey: AppConstants.geminiApiKey,
        );
        final response = await model.generateContent([
          Content.text(textPrompt),
        ]);
        aiResult = response.text ?? '';
      }

      if (aiResult.isNotEmpty && mounted) {
        final currentText = _descController.text;
        final spacing = (currentText.isEmpty || currentText.endsWith(' '))
            ? ''
            : ' ';
        _descController.text = '$currentText$spacing${aiResult.trim()}';
        _descController.selection = TextSelection.collapsed(
          offset: _descController.text.length,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi gợi ý AI: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAiLoading = false;
        });
      }
    }
  }

  /// Xử lý cập nhật thông tin video ở chế độ Edit
  Future<void> _handleUpdate() async {
    final description = _descController.text.trim();

    final Set<String> hashtagsSet = {};
    final matches = RegExp(
      r'#([A-Za-z0-9_\u00C0-\u1EF9-]+)',
    ).allMatches(description);
    for (final m in matches) {
      final tagText = m.group(1);
      if (tagText != null) {
        hashtagsSet.add(tagText.toLowerCase().trim());
      }
    }
    final List<String> hashtagsList = hashtagsSet.toList();

    final firestore = ref.read(firestoreProvider);
    final user = ref.read(currentUserProvider);

    if (user == null) return;

    setState(() {
      _isAiLoading = true;
    });

    try {
      final updates = <String, dynamic>{
        'description': description,
        'hashtags': hashtagsList,
        'topic': _selectedTopic,
        'isSponsored': _isSponsored,
        'crop': _cropController.text.trim().isNotEmpty
            ? _cropController.text.trim()
            : null,
        'growthStage': _growthStageController.text.trim().isNotEmpty
            ? _growthStageController.text.trim()
            : null,
        'region': _regionController.text.trim().isNotEmpty
            ? _regionController.text.trim()
            : null,
        'relatedJournalId': _journalIdController.text.trim().isNotEmpty
            ? _journalIdController.text.trim()
            : null,
      };

      await firestore.collection('videos').doc(widget.videoId).update(updates);
      await firestore
          .collection('video_summaries')
          .doc(widget.videoId)
          .update(updates);
      await firestore
          .collection('profiles')
          .doc(user.uid)
          .collection('public_videos')
          .doc(widget.videoId)
          .update(updates);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cập nhật thông tin video thành công!')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi cập nhật: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAiLoading = false;
        });
      }
    }
  }

  /// Xử lý đăng tải video mới
  Future<void> _handlePublish() async {
    if (widget.videoFile == null) return;

    final user = ref.read(currentUserProvider);
    final userProfile = ref.read(currentUserProfileProvider).valueOrNull;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng đăng nhập để đăng video!')),
      );
      return;
    }

    final description = _descController.text.trim();

    final Set<String> hashtagsSet = {};
    final matches = RegExp(
      r'#([A-Za-z0-9_\u00C0-\u1EF9-]+)',
    ).allMatches(description);
    for (final m in matches) {
      final tagText = m.group(1);
      if (tagText != null) {
        hashtagsSet.add(tagText.toLowerCase().trim());
      }
    }
    final List<String> hashtagsList = hashtagsSet.toList();

    final myUsername =
        userProfile?.username ?? user.email?.split('@')[0] ?? 'user';

    final uploadNotifier = ref.read(uploadStateProvider.notifier);

    _showUploadProgressDialog();

    final success = await uploadNotifier.uploadAndSaveVideo(
      file: widget.videoFile!,
      description: description,
      authorId: user.uid,
      username: myUsername,
      hashtags: hashtagsList,
      location:
          _selectedTopic == 'garden_tour' &&
              _regionController.text.trim().isNotEmpty
          ? _regionController.text.trim()
          : (_isDalatCampaign ? 'Da Lat' : null),
      allowDownload: _allowDownload,
      allowDuet: true,
      isCopyrightProtected: _isCopyrightProtected,
      topic: _selectedTopic,
      isSponsored: _isSponsored,
      crop: _cropController.text.trim().isNotEmpty
          ? _cropController.text.trim()
          : null,
      growthStage: _growthStageController.text.trim().isNotEmpty
          ? _growthStageController.text.trim()
          : null,
      region: _regionController.text.trim().isNotEmpty
          ? _regionController.text.trim()
          : null,
      relatedJournalId: _journalIdController.text.trim().isNotEmpty
          ? _journalIdController.text.trim()
          : null,
      taggedProductIds: _productIdController.text.trim().isNotEmpty
          ? [_productIdController.text.trim()]
          : const [],
    );

    if (mounted) {
      Navigator.pop(context);
    }

    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đăng video thành công!')));
        uploadNotifier.reset();
        ref.invalidate(videoFeedProvider);
        ref.invalidate(lamDongVideoFeedProvider);
        ref.invalidate(followingVideoFeedProvider);
        context.go('/home');
      }
    } else {
      final err = ref.read(uploadStateProvider).errorMessage;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Đăng video thất bại: $err')));
      }
    }
  }

  void _showUploadProgressDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Consumer(
          builder: (context, ref, _) {
            final uploadState = ref.watch(uploadStateProvider);
            final percent = (uploadState.progress * 100).toInt();

            String statusText = 'Đang chuẩn bị...';
            if (uploadState.status == UploadStatus.uploading) {
              statusText = 'Đang tải video lên: $percent%';
            } else if (uploadState.status == UploadStatus.saving) {
              statusText = 'Đang lưu dữ liệu video...';
            }

            return PopScope(
              canPop: false,
              child: AlertDialog(
                backgroundColor: const Color(0xFF1D1D1F),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      color: AppTheme.primaryColor,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      statusText,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    const SizedBox(height: 10),
                    if (uploadState.status == UploadStatus.uploading)
                      LinearProgressIndicator(
                        value: uploadState.progress,
                        color: AppTheme.primaryColor,
                        backgroundColor: Colors.white10,
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: Text(
          _isEditMode ? 'Sửa thông tin video' : 'Thêm thông tin video',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        centerTitle: true,
      ),
      body: _isAiLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryColor),
            )
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Hộp xem trước và mô tả
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                width: 110,
                                height: 160,
                                color: Colors.white.withValues(alpha: 0.1),
                                child: _isEditMode
                                    ? (_previewUrl.isNotEmpty
                                          ? CachedNetworkImage(
                                              imageUrl: _previewUrl,
                                              fit: BoxFit.cover,
                                              memCacheWidth: 200,
                                              placeholder: (context, url) =>
                                                  const Icon(
                                                    Icons.image,
                                                    color: Colors.white24,
                                                  ),
                                              errorWidget:
                                                  (context, url, error) =>
                                                      const Icon(
                                                        Icons.image,
                                                        color: Colors.white24,
                                                      ),
                                            )
                                          : const Icon(
                                              Icons.image,
                                              color: Colors.white24,
                                            ))
                                    : (_videoPlayerController != null &&
                                              _videoPlayerController!
                                                  .value
                                                  .isInitialized
                                          ? AspectRatio(
                                              aspectRatio:
                                                  _videoPlayerController!
                                                      .value
                                                      .aspectRatio,
                                              child: VideoPlayer(
                                                _videoPlayerController!,
                                              ),
                                            )
                                          : const Center(
                                              child: Icon(
                                                Icons.play_arrow,
                                                color: Colors.white54,
                                                size: 30,
                                              ),
                                            )),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextField(
                                controller: _descController,
                                focusNode: _focusNode,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                ),
                                maxLines: 7,
                                decoration: const InputDecoration(
                                  hintText:
                                      'Bạn muốn chia sẻ điều gì về video này?...',
                                  hintStyle: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 14,
                                  ),
                                  border: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                  filled: false,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Hàng phím hỗ trợ nhập liệu
                        Row(
                          children: [
                            _buildInputHelper(
                              icon: Icons.tag,
                              label: 'Hashtag',
                              onTap: _insertHashtagSymbol,
                            ),
                            const SizedBox(width: 12),
                            _buildInputHelper(
                              icon: Icons.auto_awesome,
                              label: 'Gợi ý AI',
                              onTap: _suggestHashtags,
                              isPrimary: true,
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),
                        const Divider(color: Colors.white12),
                        const SizedBox(height: 12),

                        // === Phần 1: Chọn chủ đề video ("Video này nói về gì?") ===
                        _buildTopicSelectorSection(),

                        // Các trường thông tin ngữ cảnh theo chủ đề
                        _buildContextualFieldsSection(),

                        const SizedBox(height: 24),
                        const Divider(color: Colors.white12),
                        const SizedBox(height: 12),

                        // === Phần 2: Khai báo Quảng cáo / Tài trợ ===
                        const Text(
                          'Khai báo nội dung thương mại',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),

                        _buildSettingsGroup([
                          _buildSwitchTile(
                            title: 'Video có quảng cáo hoặc được tài trợ',
                            subtitle:
                                'Đánh dấu nếu bạn được trả tiền hoặc tặng quà để giới thiệu trong video.',
                            icon: Icons.campaign_outlined,
                            value: _isSponsored,
                            onChanged: (val) =>
                                setState(() => _isSponsored = val),
                          ),
                        ]),

                        const SizedBox(height: 24),
                        // === Phần 3: Quyền riêng tư & Chiến dịch ===
                        const Text(
                          'Cài đặt quyền riêng tư',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),

                        _buildSettingsGroup([
                          _buildSwitchTile(
                            title: 'Cho phép tải xuống',
                            subtitle: 'Người xem có thể lưu video này',
                            icon: Icons.download_rounded,
                            value: _allowDownload,
                            onChanged: (val) =>
                                setState(() => _allowDownload = val),
                          ),
                          const Divider(color: Colors.white10, height: 1),
                          _buildSwitchTile(
                            title: 'Bảo vệ bản quyền',
                            subtitle: 'Đánh dấu video là nội dung gốc',
                            icon: Icons.copyright_rounded,
                            value: _isCopyrightProtected,
                            onChanged: (val) =>
                                setState(() => _isCopyrightProtected = val),
                          ),
                        ]),

                        const SizedBox(height: 24),
                        const Text(
                          'Chiến dịch quảng bá',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),

                        _buildSettingsGroup(
                          [
                            _buildSwitchTile(
                              title: '🌲 Đà Lạt Trong Tôi',
                              subtitle:
                                  'Tham gia chiến dịch để được ưu tiên hiển thị',
                              icon: Icons.eco_rounded,
                              iconColor: const Color(0xFF4CAF50),
                              value: _isDalatCampaign,
                              onChanged: (val) =>
                                  setState(() => _isDalatCampaign = val),
                              activeColor: const Color(0xFF4CAF50),
                            ),
                          ],
                          bgColor: const Color(
                            0xFF4CAF50,
                          ).withValues(alpha: 0.08),
                        ),

                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),

                // Nút hành động đăng/cập nhật cuối trang
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SafeArea(
                    top: false,
                    child: Container(
                      width: double.infinity,
                      height: 54,
                      decoration: BoxDecoration(
                        gradient: AppTheme.brandGradient,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryColor.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _isEditMode ? _handleUpdate : _handlePublish,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          _isEditMode ? 'CẬP NHẬT VIDEO' : 'ĐĂNG VIDEO',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTopicSelectorSection() {
    final topics = [
      {
        'id': 'farming_experience',
        'icon': '🌾',
        'label': 'Kinh nghiệm làm nông',
      },
      {'id': 'garden_tour', 'icon': '🏡', 'label': 'Giới thiệu vườn'},
      {'id': 'product_intro', 'icon': '🛍️', 'label': 'Giới thiệu sản phẩm'},
      {'id': 'farmer_story', 'icon': '📖', 'label': 'Chuyện nhà nông'},
      {'id': 'other', 'icon': '📹', 'label': 'Nội dung khác'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Video này nói về gì?',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            if (_selectedTopic != null)
              TextButton(
                onPressed: () => setState(() => _selectedTopic = null),
                child: const Text(
                  'Bỏ chọn',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: topics.map((t) {
            final id = t['id'] as String;
            final isSelected = _selectedTopic == id;
            return ChoiceChip(
              label: Text('${t['icon']} ${t['label']}'),
              selected: isSelected,
              selectedColor: AppTheme.primaryColor,
              backgroundColor: Colors.white10,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
              onSelected: (selected) {
                setState(() {
                  _selectedTopic = selected ? id : null;
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildContextualFieldsSection() {
    if (_selectedTopic == null ||
        _selectedTopic == 'farmer_story' ||
        _selectedTopic == 'other') {
      return const SizedBox.shrink();
    }

    if (_selectedTopic == 'farming_experience') {
      return Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Chi tiết kinh nghiệm (Không bắt buộc)',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _cropController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Cây trồng (ví dụ: Sầu riêng, Cà phê, Lúa...)',
                labelStyle: TextStyle(color: Colors.white60, fontSize: 13),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _growthStageController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: const InputDecoration(
                labelText:
                    'Công việc / Giai đoạn (ví dụ: Làm đất, Bón phân...)',
                labelStyle: TextStyle(color: Colors.white60, fontSize: 13),
                isDense: true,
              ),
            ),
          ],
        ),
      );
    }

    if (_selectedTopic == 'garden_tour') {
      return Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Thông tin nhà vườn (Không bắt buộc)',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _regionController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: const InputDecoration(
                labelText:
                    'Khu vực / Địa điểm vườn (ví dụ: Đơn Dương, Lâm Đồng)',
                labelStyle: TextStyle(color: Colors.white60, fontSize: 13),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _journalIdController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Liên kết nhật ký mùa vụ (Mã nhật ký nếu có)',
                labelStyle: TextStyle(color: Colors.white60, fontSize: 13),
                isDense: true,
              ),
            ),
          ],
        ),
      );
    }

    if (_selectedTopic == 'product_intro') {
      final currentUser = ref.watch(currentUserProvider);
      final userStoreAsync = currentUser != null
          ? ref.watch(userStoreStreamProvider(currentUser.uid))
          : const AsyncValue<StoreModel?>.data(null);
      final isSeller =
          userStoreAsync.valueOrNull != null &&
          userStoreAsync.valueOrNull?.status == 'approved';

      return Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Gắn sản phẩm giới thiệu',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            if (isSeller) ...[
              TextField(
                controller: _productIdController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  labelText: 'Mã sản phẩm từ gian hàng của bạn',
                  labelStyle: TextStyle(color: Colors.white60, fontSize: 13),
                  isDense: true,
                ),
              ),
            ] else ...[
              const Text(
                'Bạn đang chia sẻ về sản phẩm nông nghiệp. Nếu muốn đăng bán trực tiếp trên ứng dụng, bạn có thể Đăng ký gian hàng.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor,
                  side: const BorderSide(color: AppTheme.primaryColor),
                ),
                icon: const Icon(Icons.storefront, size: 16),
                label: const Text(
                  'Đăng ký gian hàng',
                  style: TextStyle(fontSize: 12),
                ),
                onPressed: () {
                  context.push('/store/register');
                },
              ),
            ],
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildInputHelper({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isPrimary ? const Color(0xFF2B2B2D) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: isPrimary ? null : Border.all(color: Colors.white24),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsGroup(List<Widget> children, {Color? bgColor}) {
    return Container(
      decoration: BoxDecoration(
        color: bgColor ?? Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
    Color? iconColor,
    Color? activeColor,
  }) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      activeColor: activeColor ?? AppTheme.primaryColor,
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      secondary: Icon(icon, color: iconColor ?? Colors.white70),
      value: value,
      onChanged: onChanged,
    );
  }
}
