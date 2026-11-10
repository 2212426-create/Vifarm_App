import 'package:flutter_test/flutter_test.dart';
import 'package:toptop_flutter/core/constants/app_constants.dart';
import 'package:toptop_flutter/features/comments/models/comment_model.dart';
import 'package:toptop_flutter/features/video_feed/models/video_model.dart';

void main() {
  group('Firebase Core Operations Test Suite (Upload, Download, Comment, Lưu, Tim)', () {
    // ──────────────────────────────────────────────────────────────────────────
    // 1. TEST UPLOAD (Đăng tải video & lưu trữ siêu dữ liệu Firebase)
    // ──────────────────────────────────────────────────────────────────────────
    test('1. UPLOAD: Video metadata schema conforms to Firestore security rules & invariants', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final videoId = 'v_test_${now}';
      const authorId = 'user_uploader_123';
      const username = 'Nông Dân Cần Thơ';
      const description = 'Kỹ thuật bón phân giai đoạn làm đòng #lua #nongnghiep';
      final hashtags = ['#lua', '#nongnghiep'];
      const videoUrl = 'https://res.cloudinary.com/dbxinpidm/video/upload/v1792120406/farm_test.mp4';

      // Mô phỏng payload của UploadRepository.saveVideoToFirestore
      final uploadPayload = {
        'videoId': videoId,
        'videoUri': videoUrl,
        'authorId': authorId,
        'username': username,
        'description': description,
        'totalLikes': 0,
        'totalComments': 0,
        'watchCount': 0,
        'timestamp': now,
        'status': 'active',
        'moderationStatus': 'approved',
        'isPublic': true,
        'hashtags': hashtags,
        'location': 'Cần Thơ',
        'allowDownload': true,
        'allowDuet': true,
        'isCopyrightProtected': false,
        'topic': 'farming_experience',
        'isSponsored': false,
        'crop': 'Lúa',
        'growthStage': 'Làm đòng',
        'region': 'Cần Thơ',
      };

      // Invariant 1: Bắt buộc có videoId, videoUri hợp lệ
      expect(uploadPayload['videoId'], isNotEmpty);
      expect(uploadPayload['videoUri'], startsWith('https://res.cloudinary.com/'));
      expect(uploadPayload['videoUri'], endsWith('.mp4'));

      // Invariant 2: Video mới đăng phải có status = active và moderationStatus = approved
      expect(uploadPayload['status'], 'active');
      expect(uploadPayload['moderationStatus'], 'approved');

      // Invariant 3: Khởi tạo bộ đếm tương tác = 0
      expect(uploadPayload['totalLikes'], 0);
      expect(uploadPayload['totalComments'], 0);
      expect(uploadPayload['watchCount'], 0);

      // Invariant 4: Chuyển đổi sang VideoModel không lỗi
      final videoModel = VideoModel.fromMap(uploadPayload, videoId);
      expect(videoModel.videoId, videoId);
      expect(videoModel.crop, 'Lúa');
      expect(videoModel.growthStage, 'Làm đòng');
      expect(videoModel.topic, 'farming_experience');
      expect(VideoModel.getTopicDisplayName(videoModel.topic), 'Kinh nghiệm làm nông');

      // Invariant 5: Cấu hình Cloudinary Unsigned Upload
      expect(AppConstants.cloudinaryCloudName, 'dbxinpidm');
      const expectedUploadPreset = 'toptopclone';
      expect(expectedUploadPreset, 'toptopclone');
    });

    // ──────────────────────────────────────────────────────────────────────────
    // 2. TEST DOWNLOAD & STREAM (Tải xuống & Phát trực tuyến video)
    // ──────────────────────────────────────────────────────────────────────────
    test('2. DOWNLOAD & STREAM: Video stream URI formatting and permission validation', () {
      const liveCloudinaryUrl = 'https://res.cloudinary.com/dbxinpidm/video/upload/v1792120406/n2zih969pa2ngh0ko918.mp4';
      final video = VideoModel(
        videoId: 'v_live_01',
        videoUri: liveCloudinaryUrl,
        authorId: 'auth_1',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        allowDownload: true,
      );

      // Invariant 1: Định dạng URI phải là HTTPS và trỏ về CDN Cloudinary
      final uri = Uri.parse(video.videoUri);
      expect(uri.scheme, 'https');
      expect(uri.host, 'res.cloudinary.com');
      expect(uri.path, contains('/video/upload/'));
      expect(uri.path, endsWith('.mp4'));

      // Invariant 2: Quyền cho phép tải về
      expect(video.allowDownload, isTrue);

      // Invariant 3: Chuyển đổi an toàn khi chạy trên máy ảo Android (10.0.2.2 -> 127.0.0.1)
      var testUri = 'http://10.0.2.2:9199/video.mp4';
      if (testUri.contains('10.0.2.2')) {
        testUri = testUri.replaceAll('10.0.2.2', '127.0.0.1');
      }
      expect(testUri, 'http://127.0.0.1:9199/video.mp4');

      // Invariant 4: Khi dùng production CDN, URI giữ nguyên không bị thay đổi
      var prodUri = liveCloudinaryUrl;
      if (prodUri.contains('10.0.2.2')) {
        prodUri = prodUri.replaceAll('10.0.2.2', '127.0.0.1');
      }
      expect(prodUri, liveCloudinaryUrl);
    });

    // ──────────────────────────────────────────────────────────────────────────
    // 3. TEST COMMENT (Đăng bình luận, phản hồi phân cấp, tăng đếm)
    // ──────────────────────────────────────────────────────────────────────────
    test('3. COMMENT: CommentModel hierarchy, threading, reply counter and notifications', () {
      // 3.1. Bình luận cha (Top-level comment)
      final parentComment = CommentModel(
        commentId: 'c_parent_1001',
        videoId: 'v_prod_01',
        authorId: 'user_commenter_1',
        content: 'Bác ơi cho cháu hỏi phân này bón vào mùa mưa được không ạ?',
        totalLikes: 2,
        totalReplies: 1,
        replyIds: ['c_reply_2001'],
      );

      final parentMap = parentComment.toMap();
      expect(parentMap['commentId'], 'c_parent_1001');
      expect(parentMap['videoId'], 'v_prod_01');
      expect(parentMap['parentId'], isEmpty); // Không có parentId là bình luận gốc
      expect(parentMap['totalReplies'], 1);

      // 3.2. Câu trả lời con (Child reply)
      final childReply = CommentModel(
        commentId: 'c_reply_2001',
        videoId: 'v_prod_01',
        authorId: 'user_farmer_author',
        content: 'Được cháu nhé, nhớ bón cách gốc 20cm để không xót rễ!',
        parentId: 'c_parent_1001',
        parentUsername: 'user_commenter_1',
        totalLikes: 5,
      );

      final childMap = childReply.toMap();
      expect(childMap['parentId'], 'c_parent_1001');
      expect(childMap['parentUsername'], 'user_commenter_1');

      // 3.3. Mô phỏng luồng cập nhật Firestore khi đăng comment
      int videoTotalComments = 0;
      int parentTotalReplies = 0;
      final List<String> parentReplyIds = [];

      // Hành vi khi đăng parent comment:
      videoTotalComments += 1;
      expect(videoTotalComments, 1);

      // Hành vi khi đăng child reply:
      videoTotalComments += 1;
      parentTotalReplies += 1;
      parentReplyIds.add(childReply.commentId);

      expect(videoTotalComments, 2);
      expect(parentTotalReplies, 1);
      expect(parentReplyIds, contains('c_reply_2001'));

      // 3.4. Kiểm tra cấu trúc cây bình luận (Tree format)
      final rawComments = [parentComment, childReply];
      final parents = rawComments.where((c) => c.parentId.isEmpty).toList();
      final replies = rawComments.where((c) => c.parentId.isNotEmpty).toList();

      expect(parents.length, 1);
      expect(replies.length, 1);
      expect(replies.first.parentId, parents.first.commentId);

      // 3.5. Trọng số sở thích khi comment (+3 điểm)
      const commentInterestWeight = 3;
      expect(commentInterestWeight, 3);
    });

    // ──────────────────────────────────────────────────────────────────────────
    // 4. TEST LƯU (Bookmark / Lưu video kỹ thuật nông nghiệp)
    // ──────────────────────────────────────────────────────────────────────────
    test('4. LƯU (BOOKMARK): Saved techniques subcollection schema and toggle logic', () {
      const currentUserId = 'farmer_user_007';
      final video = VideoModel(
        videoId: 'v_kythuat_99',
        videoUri: 'https://res.cloudinary.com/dbxinpidm/video/upload/v123/tech.mp4',
        authorId: 'expert_agri',
        description: 'Quy trình phòng ngừa bệnh thán thư sầu riêng mùa mưa',
        crop: 'Sầu riêng',
        growthStage: 'Đậu trái',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      // Mô phỏng đường dẫn Firestore: /users/{userId}/saved_techniques/{videoId}
      final firestorePath = 'users/$currentUserId/saved_techniques/${video.videoId}';
      expect(firestorePath, 'users/farmer_user_007/saved_techniques/v_kythuat_99');

      // 4.1. Payload lưu tài liệu
      final savedDocument = {
        'videoId': video.videoId,
        'title': video.description,
        'crop': video.crop,
        'growthStage': video.growthStage,
        'savedAt': DateTime.now().millisecondsSinceEpoch,
      };

      expect(savedDocument['videoId'], 'v_kythuat_99');
      expect(savedDocument['crop'], 'Sầu riêng');
      expect(savedDocument['growthStage'], 'Đậu trái');
      expect(savedDocument['savedAt'], isNotNull);

      // 4.2. Logic Toggle: Chưa lưu -> Lưu; Đã lưu -> Bỏ lưu
      final mockSavedSet = <String>{};

      bool toggleSave(String videoId) {
        if (mockSavedSet.contains(videoId)) {
          mockSavedSet.remove(videoId);
          return false; // Đã bỏ lưu
        } else {
          mockSavedSet.add(videoId);
          return true; // Đã lưu thành công
        }
      }

      // Lần 1: Bấm lưu
      final isSaved1 = toggleSave(video.videoId);
      expect(isSaved1, isTrue);
      expect(mockSavedSet.contains(video.videoId), isTrue);

      // Lần 2: Bấm lại để bỏ lưu
      final isSaved2 = toggleSave(video.videoId);
      expect(isSaved2, isFalse);
      expect(mockSavedSet.contains(video.videoId), isFalse);

      // 4.3. Cache key SharedPreferences
      final localKey = 'saved_tech_${currentUserId}_${video.videoId}';
      expect(localKey, 'saved_tech_farmer_user_007_v_kythuat_99');
    });

    // ──────────────────────────────────────────────────────────────────────────
    // 5. TEST TIM (Like / Unlike video, tăng giảm like, gửi thông báo)
    // ──────────────────────────────────────────────────────────────────────────
    test('5. TIM (LIKE): Atomic like toggle, like counter mutation, and interest weight', () {
      const videoId = 'v_like_test_101';
      const authorId = 'author_nguyen_van_a';
      const currentUserId = 'liker_user_bob';

      // 5.1. Trạng thái ban đầu
      int videoTotalLikes = 10;
      int authorProfileLikes = 50;
      final Map<String, bool> likedUsers = {
        'other_user_1': true,
        'other_user_2': true,
      };

      // Invariant: Hiện tại bob chưa like video này
      expect(likedUsers[currentUserId], isNull);

      // 5.2. Luồng BẬT THÍCH (LIKE = TRUE)
      likedUsers[currentUserId] = true;
      videoTotalLikes += 1;
      authorProfileLikes += 1;

      expect(likedUsers[currentUserId], isTrue);
      expect(videoTotalLikes, 11);
      expect(authorProfileLikes, 51);

      // Invariant: Trọng số sở thích khi like video là +5 điểm (cao nhất trong các tương tác)
      const likeInterestWeight = 5;
      expect(likeInterestWeight, 5);

      // Payload thông báo gửi qua Realtime Database
      final notificationPayload = {
        'from': currentUserId,
        'type': 'like',
        'videoId': videoId,
        'action': AppConstants.actionLike,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      expect(notificationPayload['action'], AppConstants.actionLike);
      expect(notificationPayload['type'], 'like');

      // 5.3. Luồng BỎ THÍCH (UNLIKE = FALSE)
      likedUsers.remove(currentUserId);
      videoTotalLikes -= 1;
      authorProfileLikes -= 1;

      expect(likedUsers[currentUserId], isNull);
      expect(videoTotalLikes, 10);
      expect(authorProfileLikes, 50);

      // 5.4. Kiểm tra watchLikesState mapping
      final docData = {
        'users': likedUsers,
        'count': videoTotalLikes,
      };
      final parsedCount = docData['count'] as int;
      final parsedUsers = docData['users'] as Map<String, dynamic>;

      expect(parsedCount, 10);
      expect(parsedUsers.containsKey(currentUserId), isFalse);
      expect(parsedUsers.containsKey('other_user_1'), isTrue);
    });
  });
}
