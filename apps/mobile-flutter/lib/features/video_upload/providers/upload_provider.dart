import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/providers/firebase_providers.dart';
import '../repositories/legacy_hashtag_fixer.dart';
import '../repositories/upload_repository.dart';
import '../services/gemini_service.dart';
import '../../upload/services/video_copyright_service.dart';

/// Các trạng thái có thể có của tiến trình tải lên video
enum UploadStatus { idle, uploading, saving, success, error }

/// Lớp đại diện cho trạng thái hiện tại của tác vụ upload
class UploadState {
  final UploadStatus status;
  final double progress;
  final String? errorMessage;
  final String? videoUrl;

  UploadState({
    required this.status,
    this.progress = 0.0,
    this.errorMessage,
    this.videoUrl,
  });

  UploadState copyWith({
    UploadStatus? status,
    double? progress,
    String? errorMessage,
    String? videoUrl,
  }) {
    return UploadState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      errorMessage: errorMessage ?? this.errorMessage,
      videoUrl: videoUrl ?? this.videoUrl,
    );
  }
}

/// Provider của GeminiService
final geminiServiceProvider = Provider<GeminiService>((ref) {
  return GeminiService();
});

/// Provider của UploadRepository
final uploadRepositoryProvider = Provider<UploadRepository>((ref) {
  return UploadRepository(firestore: ref.watch(firestoreProvider));
});

/// Provider của LegacyHashtagFixer
final legacyHashtagFixerProvider = Provider<LegacyHashtagFixer>((ref) {
  return LegacyHashtagFixer(
    firestore: ref.watch(firestoreProvider),
    geminiService: ref.watch(geminiServiceProvider),
  );
});

/// Bộ quản lý trạng thái tải lên video (UploadNotifier)
class UploadNotifier extends StateNotifier<UploadState> {
  final UploadRepository _repository;
  final GeminiService _geminiService;

  UploadNotifier(this._repository, this._geminiService)
    : super(UploadState(status: UploadStatus.idle));

  /// Thực thi toàn bộ quy trình: Tải lên Cloudinary -> Lưu thông tin Firestore
  Future<bool> uploadAndSaveVideo({
    required XFile file,
    required String description,
    required String authorId,
    required String username,
    required List<String> hashtags,
    String? location,
    bool allowDownload = true,
    bool allowDuet = true,
    bool isCopyrightProtected = false,
    String? topic,
    bool isSponsored = false,
    String? crop,
    String? growthStage,
    String? region,
    String? relatedJournalId,
    List<String>? taggedProductIds,
  }) async {
    state = UploadState(status: UploadStatus.uploading, progress: 0.0);

    try {
      final videoId = DateTime.now().millisecondsSinceEpoch.toString();

      // 1. Tải lên Cloudinary với theo dõi tiến độ
      final videoUrl = await _repository.uploadVideoToCloudinary(
        file: file,
        onProgress: (p) {
          state = UploadState(status: UploadStatus.uploading, progress: p);
        },
      );

      // --- KIỂM DUYỆT BẢN QUYỀN (NGƯỜI 2) ---
      final copyrightService = VideoCopyrightService();
      
      // Tạo fingerprint cho video dựa trên kích thước và header bytes
      // (fast client-side fingerprinting trước khi worker backend phân tích sâu DCT keyframe)
      final fileSize = await file.length();
      final stream = file.openRead(0, 2048);
      final headerBytes = await stream.expand((b) => b).toList();
      final contentDigest = headerBytes.fold<int>(fileSize, (acc, b) => (acc * 31 + b) & 0x7FFFFFFF);
      final hashBase = contentDigest.toRadixString(16).padLeft(16, '0');
      List<String> newHashes = List.generate(5, (i) => '${hashBase.substring(0, 14)}${i.toRadixString(16).padLeft(2, '0')}');

      final allVideos = await _repository.getAllVideosForCopyrightCheck();
      
      final bestMatch = await copyrightService.findMostSimilarVideo(
        newHashes: newHashes,
        databaseRecords: allVideos,
      );

      double visualSimilarity = bestMatch?['calculated_similarity'] ?? 0.0;
      bool isSameAuthor = bestMatch?['author_id'] == authorId;

      final eval = copyrightService.evaluateCopyrightRisk(
        visualSimilarity: visualSimilarity,
        audioSimilarity: visualSimilarity,
        isSameAuthor: isSameAuthor,
      );

      if (eval.decision == CopyrightDecision.blocked || eval.decision == CopyrightDecision.duplicate) {
        throw Exception(eval.message); // Chặn tải lên để tránh spam video trùng lặp
      }

      // --- KIỂM DUYỆT AI & PHÂN LOẠI NÔNG NGHIỆP (NGƯỜI 1 & 3) ---
      // Gọi model mock để lấy metadata
      final aiMetadata = await _geminiService.mockAnalyzeVideo();
      // Ta có thể nối thêm hashtag AI gợi ý vào hashtags do người dùng nhập
      final List<String> combinedHashtags = List.from(hashtags)
        ..addAll((aiMetadata['suggested_hashtags'] as List<String>));

      // 2. Chuyển trạng thái lưu Firestore
      state = state.copyWith(status: UploadStatus.saving);

      await _repository.saveVideoToFirestore(
        videoId: videoId,
        videoUrl: videoUrl,
        description: description,
        authorId: authorId,
        username: username,
        hashtags: combinedHashtags.toSet().toList(), // Lọc trùng
        location: location,
        allowDownload: allowDownload,
        allowDuet: allowDuet,
        isCopyrightProtected: isCopyrightProtected,
        topic: topic,
        isSponsored: isSponsored,
        crop: crop,
        growthStage: growthStage,
        region: region,
        relatedJournalId: relatedJournalId,
        taggedProductIds: taggedProductIds,
        keyframesPhash: newHashes,
        moderationStatus: eval.decision == CopyrightDecision.pendingReview ? 'pending' : 'approved',
        copyrightMatch: eval.decision == CopyrightDecision.pendingReview ? bestMatch : null,
      );

      // 3. Kết thúc thành công
      state = state.copyWith(status: UploadStatus.success, videoUrl: videoUrl);
      return true;
    } catch (e) {
      state = state.copyWith(
        status: UploadStatus.error,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  /// Khởi tạo lại trạng thái upload
  void reset() {
    state = UploadState(status: UploadStatus.idle);
  }
}

/// Provider quản lý trạng thái tác vụ tải lên video
final uploadStateProvider = StateNotifierProvider<UploadNotifier, UploadState>((
  ref,
) {
  return UploadNotifier(
    ref.watch(uploadRepositoryProvider),
    ref.watch(geminiServiceProvider),
  );
});
