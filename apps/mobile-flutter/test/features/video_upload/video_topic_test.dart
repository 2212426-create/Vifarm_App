import 'package:flutter_test/flutter_test.dart';
import 'package:toptop_flutter/features/video_feed/models/video_model.dart';

void main() {
  group('Video Topic & Commercial Declaration Tests', () {
    test('maps all 5 topics to senior-friendly Vietnamese display names', () {
      expect(
        VideoModel.getTopicDisplayName('farming_experience'),
        equals('Kinh nghiệm làm nông'),
      );
      expect(
        VideoModel.getTopicDisplayName('garden_tour'),
        equals('Giới thiệu vườn'),
      );
      expect(
        VideoModel.getTopicDisplayName('product_intro'),
        equals('Giới thiệu sản phẩm'),
      );
      expect(
        VideoModel.getTopicDisplayName('farmer_story'),
        equals('Chuyện nhà nông'),
      );
      expect(VideoModel.getTopicDisplayName('other'), equals('Nội dung khác'));
      expect(VideoModel.getTopicDisplayName(null), equals(''));
      expect(VideoModel.getTopicDisplayName(''), equals(''));
    });

    test(
      'serializes and deserializes VideoModel with topic and isSponsored correctly',
      () {
        final video = VideoModel(
          videoId: 'v101',
          videoUri: 'https://cloudinary.com/v101.mp4',
          authorId: 'u55',
          username: 'nong_dan_lam_dong',
          description: 'Chăm sóc vườn cà phê mới trồng #caphe #lamdong',
          timestamp: 1700000000000,
          topic: 'garden_tour',
          isSponsored: true,
          region: 'Lâm Đồng',
        );

        final map = video.toMap();
        expect(map['topic'], equals('garden_tour'));
        expect(map['isSponsored'], isTrue);
        expect(map['region'], equals('Lâm Đồng'));

        final parsed = VideoModel.fromMap(map, 'v101');
        expect(parsed.videoId, equals('v101'));
        expect(parsed.topic, equals('garden_tour'));
        expect(parsed.isSponsored, isTrue);
        expect(parsed.region, equals('Lâm Đồng'));
        expect(
          VideoModel.getTopicDisplayName(parsed.topic),
          equals('Giới thiệu vườn'),
        );
      },
    );

    test(
      'handles legacy videos without topic gracefully without defaulting all to technical',
      () {
        final legacyMap = <String, dynamic>{
          'videoId': 'v_legacy',
          'videoUri': 'https://cloudinary.com/legacy.mp4',
          'authorId': 'u1',
          'description': 'Video chuyện trò ngày Tết',
          'timestamp': 1600000000000,
        };

        final parsed = VideoModel.fromMap(legacyMap);
        expect(parsed.topic, isNull);
        expect(parsed.isSponsored, isFalse);
        expect(VideoModel.getTopicDisplayName(parsed.topic), equals(''));
      },
    );
  });
}
