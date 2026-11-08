// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/media/platform_media.dart';

/// Request tùy chỉnh kế thừa từ http.MultipartRequest để giám sát tiến độ tải lên
class MultipartRequestWithProgress extends http.MultipartRequest {
  final void Function(int bytesUploaded, int totalBytes) onProgress;

  MultipartRequestWithProgress(
    super.method,
    super.url, {
    required this.onProgress,
  });

  @override
  http.ByteStream finalize() {
    final byteStream = super.finalize();
    final total = contentLength;
    int bytesUploaded = 0;

    final transformer = StreamTransformer<List<int>, List<int>>.fromHandlers(
      handleData: (data, sink) {
        bytesUploaded += data.length;
        onProgress(bytesUploaded, total);
        sink.add(data);
      },
    );

    return http.ByteStream(byteStream.transform(transformer));
  }
}

/// Repository xử lý việc tải video lên Cloudinary và lưu siêu dữ liệu video lên Firestore
class UploadRepository {
  final FirebaseFirestore _firestore;

  UploadRepository({required FirebaseFirestore firestore})
    : _firestore = firestore;

  /// Tải video cục bộ lên Cloudinary bằng REST API và báo tiến trình tải lên từ 0.0 -> 1.0
  Future<String> uploadVideoToCloudinary({
    required XFile file,
    required void Function(double progress) onProgress,
  }) async {
    final url = Uri.parse(
      'https://api.cloudinary.com/v1_1/${AppConstants.cloudinaryCloudName}/video/upload',
    );

    final request = MultipartRequestWithProgress(
      'POST',
      url,
      onProgress: (uploaded, total) {
        if (total > 0) {
          final fraction = uploaded / total;
          // Giới hạn trong khoảng 0.0 đến 1.0
          onProgress(fraction.clamp(0.0, 1.0));
        }
      },
    );

    // Thêm các tham số unsigned upload preset
    request.fields['upload_preset'] = 'toptopclone';

    // Đính kèm tệp video
    final multipartFile = await PlatformMedia.createCloudinaryVideoPart(file);
    request.files.add(multipartFile);

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200 || response.statusCode == 201) {
      // Thành công, giải mã URL phản hồi
      // Cloudinary trả về JSON có chứa trường "secure_url"
      final data = response.body;
      final match = RegExp(r'"secure_url"\s*:\s*"([^"]+)"').firstMatch(data);
      if (match != null && match.groupCount >= 1) {
        return match.group(1)!;
      }
      throw Exception(
        'Không tìm thấy secure_url trong phản hồi từ Cloudinary.',
      );
    } else {
      throw Exception(
        'Tải video thất bại với mã trạng thái: ${response.statusCode}. Phản hồi: ${response.body}',
      );
    }
  }

  /// Tải ảnh lên Cloudinary
  Future<String> uploadImageToCloudinary({
    required XFile file,
  }) async {
    final url = Uri.parse(
      'https://api.cloudinary.com/v1_1/${AppConstants.cloudinaryCloudName}/image/upload',
    );

    final request = http.MultipartRequest('POST', url);
    request.fields['upload_preset'] = 'toptopclone';

    final multipartFile = await PlatformMedia.createCloudinaryVideoPart(file);
    request.files.add(multipartFile);

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = response.body;
      final match = RegExp(r'"secure_url"\s*:\s*"([^"]+)"').firstMatch(data);
      if (match != null && match.groupCount >= 1) {
        return match.group(1)!;
      }
      throw Exception('Không tìm thấy secure_url trong phản hồi từ Cloudinary.');
    } else {
      throw Exception('Tải ảnh thất bại: ${response.statusCode}. ${response.body}');
    }
  }

  /// Đồng bộ lưu trữ siêu dữ liệu video lên các bảng Firestore tương ứng
  Future<void> saveVideoToFirestore({
    required String videoId,
    required String videoUrl,
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
    List<String>? keyframesPhash,
    String moderationStatus = 'pending',
    Map<String, dynamic>? copyrightMatch,
  }) async {
    // 1. Tạo bản ghi video gốc trong bộ sưu tập "videos"
    final videoData = {
      'videoId': videoId,
      'videoUri': videoUrl,
      'authorId': authorId,
      'username': username,
      'description': description,
      'totalLikes': 0,
      'totalComments': 0,
      'watchCount': 0,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'moderationStatus': moderationStatus,
      'hashtags': hashtags,
      'location': location,
      'allowDownload': allowDownload,
      'allowDuet': allowDuet,
      'isCopyrightProtected': isCopyrightProtected,
      'topic': ?topic,
      'isSponsored': isSponsored,
      if (crop != null && crop.isNotEmpty) 'crop': crop,
      if (growthStage != null && growthStage.isNotEmpty) 'growthStage': growthStage,
      if (region != null && region.isNotEmpty) 'region': region,
      if (relatedJournalId != null && relatedJournalId.isNotEmpty) 'relatedJournalId': relatedJournalId,
      if (taggedProductIds != null && taggedProductIds.isNotEmpty) 'taggedProductIds': taggedProductIds,
      'keyframes_phash': ?keyframesPhash,
      'copyrightMatch': ?copyrightMatch,
    };

    await _firestore
        .collection(AppConstants.videosCollection)
        .doc(videoId)
        .set(videoData);

    // 2. Tạo URL ảnh bìa tự động bằng tính năng thay đổi định dạng của Cloudinary
    String thumbUrl = 'https://picsum.photos/200/300'; // Dự phòng
    if (videoUrl.contains('cloudinary.com')) {
      thumbUrl = videoUrl.replaceAll('.mp4', '.jpg');
      if (thumbUrl.contains('/upload/')) {
        // Tải ảnh xem trước từ giây thứ 0
        thumbUrl = thumbUrl.replaceAll('/upload/', '/upload/so_0/');
      }
    }

    final summaryData = {
      'videoId': videoId,
      'thumbnailUri': thumbUrl,
      'watchCount': 0,
    };

    // 3. Lưu bản ghi tóm tắt vào collection video_summaries
    await _firestore
        .collection('video_summaries')
        .doc(videoId)
        .set(summaryData);

    // 4. Đồng bộ lưu vào danh sách video công khai của hồ sơ người dùng
    await _firestore
        .collection(AppConstants.profilesCollection)
        .doc(authorId)
        .collection('public_videos')
        .doc(videoId)
        .set(summaryData);

    // 5. Lưu thông tin chỉ mục hashtag để tìm kiếm thuận tiện
    final batch = _firestore.batch();
    for (final tag in hashtags) {
      final hashtagRef = _firestore.collection('hashtags').doc();
      batch.set(hashtagRef, {
        'hashtag': tag,
        'videoId': videoId,
        'thumbnailUri': thumbUrl,
      });
    }
    await batch.commit();

    if (moderationStatus == 'pending' && copyrightMatch != null) {
      await _firestore.collection('copyright_moderation_queue').add({
        'suspect_video_id': videoId,
        'suspect_uploader_id': authorId,
        'original_video_id': copyrightMatch['video_id'],
        'original_author_id': copyrightMatch['author_id'],
        'similarity_score': copyrightMatch['calculated_similarity'],
        'status': 'pending',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  /// Lấy danh sách vân tay video để đối soát bản quyền
  Future<List<Map<String, dynamic>>> getAllVideosForCopyrightCheck() async {
    final snapshot = await _firestore.collection('videos').orderBy('timestamp', descending: true).limit(200).get();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      
      // Lấy vân tay đã lưu trong CSDL, nếu không có thì mặc định là chuỗi rỗng
      List<String> phash = [];
      if (data['keyframes_phash'] != null) {
        phash = List<String>.from(data['keyframes_phash']);
      }
      
      return {
        'video_id': data['videoId'],
        'author_id': data['authorId'],
        'keyframes_phash': phash,
      };
    }).toList();
  }
}
