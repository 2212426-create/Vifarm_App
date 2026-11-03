import 'package:flutter_test/flutter_test.dart';
import 'package:toptop_flutter/features/auth/models/profile_model.dart';
import 'package:toptop_flutter/features/farm_journal/models/journal_model.dart';
import 'package:toptop_flutter/features/products/models/product_model.dart';
import 'package:toptop_flutter/features/store/models/store_model.dart';
import 'package:toptop_flutter/features/video_feed/models/video_model.dart';
import 'package:toptop_flutter/shared/widgets/universal_share_bottom_sheet.dart';

void main() {
  group('ShareContentModel Factory & Privacy Tests', () {
    test('creates ShareContentModel from VideoModel correctly', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final video = VideoModel(
        videoId: 'vid_123',
        authorId: 'auth_123',
        username: 'nong_nghiep_xanh',
        description: 'Kỹ thuật tỉa cành sầu riêng Ri6 tăng năng suất',
        videoUri: 'https://example.com/video.mp4',
        timestamp: now,
      );

      final content = ShareContentModel.fromVideo(video);
      expect(content.type, equals(ShareContentType.video));
      expect(content.id, equals('vid_123'));
      expect(content.title, equals('Kỹ thuật tỉa cành sầu riêng Ri6 tăng năng suất'));
      expect(content.subtitle, equals('@nong_nghiep_xanh'));
      expect(content.shareUrl, contains('vid_123'));
      expect(content.isPrivate, isFalse);
    });

    test('creates ShareContentModel from ProductModel correctly', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final product = ProductModel(
        id: 'prod_456',
        sellerId: 'seller_1',
        sellerName: 'Đại lý VTNN Phú Nông',
        name: 'Phân bón NPK 16-16-8',
        category: 'Phân bón & Thuốc BVTV',
        description: 'Phân bón chất lượng cao',
        listedPrice: 450000,
        images: ['https://example.com/npk.jpg'],
        region: 'Lâm Đồng',
        createdAt: now,
      );

      final content = ShareContentModel.fromProduct(product);
      expect(content.type, equals(ShareContentType.product));
      expect(content.id, equals('prod_456'));
      expect(content.title, equals('Phân bón NPK 16-16-8'));
      expect(content.subtitle, contains('Đại lý VTNN Phú Nông'));
      expect(content.imageUrl, equals('https://example.com/npk.jpg'));
      expect(content.shareUrl, contains('product_prod_456'));
      expect(content.isPrivate, isFalse);
    });

    test('creates ShareContentModel from StoreModel correctly', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final store = StoreModel(
        storeId: 'store_789',
        ownerId: 'owner_1',
        storeName: 'Nông sản Sạch Đức Trọng',
        contactName: 'Nguyễn Văn Nam',
        phone: '0912345678',
        address: 'Thôn 3, Đức Trọng',
        region: 'Lâm Đồng',
        createdAt: now,
        updatedAt: now,
      );

      final content = ShareContentModel.fromStore(store);
      expect(content.type, equals(ShareContentType.store));
      expect(content.id, equals('store_789'));
      expect(content.title, equals('Nông sản Sạch Đức Trọng'));
      expect(content.shareUrl, contains('store_store_789'));
      expect(content.isPrivate, isFalse);
    });

    test('creates ShareContentModel from ProfileModel correctly', () {
      final profile = ProfileModel(
        userId: 'user_101',
        username: 'nguyenvannam',
        fullname: 'Nguyễn Văn Nam',
        avatarUrl: 'https://example.com/avatar.jpg',
        bio: 'Nông dân Lâm Đồng',
      );

      final content = ShareContentModel.fromProfile(profile);
      expect(content.type, equals(ShareContentType.profile));
      expect(content.id, equals('user_101'));
      expect(content.title, equals('Nguyễn Văn Nam'));
      expect(content.subtitle, equals('@nguyenvannam'));
      expect(content.shareUrl, contains('profile_user_101'));
      expect(content.isPrivate, isFalse);
    });

    test('enforces privacy for private Farm Journals', () {
      final now = DateTime.now().millisecondsSinceEpoch;

      final publicJournal = JournalModel(
        id: 'j_pub',
        ownerId: 'u1',
        ownerName: 'Bác Ba',
        name: 'Vườn dưa babii',
        farmLocation: 'Đức Trọng',
        crop: 'Dưa chuột',
        startDate: now,
        region: 'Lâm Đồng',
        privacy: 'public',
        createdAt: now,
      );

      final privateJournal = JournalModel(
        id: 'j_priv',
        ownerId: 'u1',
        ownerName: 'Bác Ba',
        name: 'Vườn mật bí mật',
        farmLocation: 'Đức Trọng',
        crop: 'Dưa chuột',
        startDate: now,
        region: 'Lâm Đồng',
        privacy: 'private',
        createdAt: now,
      );

      final pubContent = ShareContentModel.fromJournal(publicJournal);
      expect(pubContent.isPrivate, isFalse);

      final privContent = ShareContentModel.fromJournal(privateJournal);
      expect(privContent.isPrivate, isTrue);
    });
  });
}
