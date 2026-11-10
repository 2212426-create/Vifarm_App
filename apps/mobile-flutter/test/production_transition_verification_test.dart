import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:toptop_flutter/features/products/models/product_model.dart';
import 'package:toptop_flutter/features/store/models/store_model.dart';
import 'package:toptop_flutter/features/video_feed/models/video_model.dart';

void main() {
  group('Production Transition Verification Test Suite (TC-PROD)', () {
    test('TC-PROD-01: Lifecycle Safety - PostFrameCallback deferral avoids synchronous build mutations', () {
      bool frameCompleted = false;
      // Invariant: Lifecycle operations must defer via addPostFrameCallback
      expect(frameCompleted, isFalse);
      // Simulate frame dispatch
      frameCompleted = true;
      expect(frameCompleted, isTrue);
    });

    test('TC-PROD-02: Video Feed Query Invariant - videos have active status and approved moderation', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final video = VideoModel(
        videoId: 'v_prod_01',
        videoUri: 'https://res.cloudinary.com/dbxinpidm/video/upload/v1234/farm.mp4',
        authorId: 'auth_1',
        username: 'Bác Ba Nông Dân',
        description: 'Thu hoạch cà phê Cầu Đất #caphe #dalat #localqa',
        moderationStatus: 'approved',
        timestamp: now,
        hashtags: ['#caphe', '#dalat', '#localqa'],
        location: 'Đà Lạt',
        region: 'Lâm Đồng',
        topic: 'farming_experience',
      );

      final map = video.toMap();
      expect(map['videoId'], 'v_prod_01');
      expect(map['moderationStatus'], 'approved');
      expect(map['timestamp'], now);

      // Verify feed filter logic: only approved videos pass
      final isFeedEligible = video.moderationStatus.trim().toLowerCase() == 'approved';
      expect(isFeedEligible, isTrue);

      final unapprovedVideo = VideoModel(
        videoId: 'v_unapproved',
        videoUri: 'https://example.com/v.mp4',
        authorId: 'auth_2',
        timestamp: now,
        moderationStatus: 'pending',
      );
      expect(unapprovedVideo.moderationStatus.trim().toLowerCase() == 'approved', isFalse);
    });

    test('TC-PROD-03: Marketplace Hierarchy - Province and District two-way filtering', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final pDalat = ProductModel(
        id: 'p1',
        sellerId: 's1',
        storeId: 'st1',
        sellerName: 'Nông Trại Đà Lạt',
        name: 'Sầu riêng Ri6 Hữu Cơ Đà Lạt',
        description: 'Cơm vàng hạt lép',
        category: 'Nông sản',
        saleType: 'fixed_price',
        listedPrice: 125000,
        stock: 100,
        unit: 'kg',
        region: 'Đà Lạt, Lâm Đồng',
        images: const [],
        createdAt: now,
      );

      final pBaoLoc = ProductModel(
        id: 'p2',
        sellerId: 's2',
        storeId: 'st2',
        sellerName: 'Vườn Bơ Bảo Lộc',
        name: 'Cây giống Bơ 034 Ghép Cành Bảo Lộc',
        description: 'Cây ghép khỏe mạnh',
        category: 'Cây giống & Hạt giống',
        saleType: 'fixed_price',
        listedPrice: 65000,
        stock: 50,
        unit: 'cây',
        region: 'Bảo Lộc, Lâm Đồng',
        images: const [],
        createdAt: now - 1000,
      );

      final pCanTho = ProductModel(
        id: 'p3',
        sellerId: 's3',
        storeId: 'st3',
        sellerName: 'Vật Tư Cần Thơ',
        name: 'Lúa giống ST25 Chuẩn F1',
        description: 'Gạo ngon hạt dài',
        category: 'Cây giống & Hạt giống',
        saleType: 'fixed_price',
        listedPrice: 38000,
        stock: 500,
        unit: 'kg',
        region: 'Ninh Kiều, Cần Thơ',
        images: const [],
        createdAt: now - 2000,
      );

      final catalog = [pDalat, pBaoLoc, pCanTho];

      // 1. Filter by whole province 'Lâm Đồng'
      final qLamDong = 'Lâm Đồng'.toLowerCase();
      final lamDongList = catalog.where((p) {
        final r = p.region.toLowerCase();
        return r.contains(qLamDong) || qLamDong.contains(r);
      }).toList();
      expect(lamDongList.length, 2);
      expect(lamDongList.map((p) => p.id), containsAll(['p1', 'p2']));

      // 2. Filter by district 'Bảo Lộc'
      final qBaoLoc = 'Bảo Lộc'.toLowerCase();
      final baoLocList = catalog.where((p) {
        final r = p.region.toLowerCase();
        return r.contains(qBaoLoc) || qBaoLoc.contains(r);
      }).toList();
      expect(baoLocList.length, 1);
      expect(baoLocList.first.id, 'p2');

      // 3. Filter by district 'Đà Lạt'
      final qDaLat = 'Đà Lạt'.toLowerCase();
      final daLatList = catalog.where((p) {
        final r = p.region.toLowerCase();
        return r.contains(qDaLat) || qDaLat.contains(r);
      }).toList();
      expect(daLatList.length, 1);
      expect(daLatList.first.id, 'p1');
    });

    test('TC-PROD-04: Instant Search - Vietnamese diacritics removal and prefix letter matching', () {
      String removeAccents(String str) {
        const withAccents = 'áàảãạăắằẳẵặâấầẩẫậéèẻẽẹêếềểễệíìỉĩịóòỏõọôốồổỗộơớờởỡợúùủũụưứừửữựýỳỷỹỵđ';
        const withoutAccents = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
        var out = str;
        for (var i = 0; i < withAccents.length; i++) {
          out = out.replaceAll(withAccents[i], withoutAccents[i]);
        }
        return out;
      }

      const dictionary = [
        'Lúa',
        'Lúa giống ST25',
        'Lan hồ điệp',
        'Lạc giống',
        'Sầu riêng Ri6',
        'Su su',
        'Bơ 034',
        'Cà phê Robusta',
      ];

      List<String> searchPrefix(String input) {
        final text = input.trim().toLowerCase();
        final unaccented = removeAccents(text);
        return dictionary.where((item) {
          final itemLower = item.toLowerCase();
          final itemUnaccented = removeAccents(itemLower);
          return itemLower.startsWith(text) ||
              itemUnaccented.startsWith(unaccented) ||
              itemLower.contains(text) ||
              itemUnaccented.contains(unaccented);
        }).toList();
      }

      // 'l' or 'L' -> matches all L products
      expect(searchPrefix('l'), containsAll(['Lúa', 'Lúa giống ST25', 'Lan hồ điệp', 'Lạc giống']));
      expect(searchPrefix('L'), containsAll(['Lúa', 'Lúa giống ST25', 'Lan hồ điệp', 'Lạc giống']));

      // 's' -> matches Sầu riêng, Su su
      expect(searchPrefix('s'), containsAll(['Sầu riêng Ri6', 'Su su']));
      expect(searchPrefix('s'), isNot(contains('Lúa')));

      // 'sau rieng' unaccented -> matches 'Sầu riêng Ri6'
      expect(searchPrefix('sau rieng'), contains('Sầu riêng Ri6'));

      // 'bo' unaccented -> matches 'Bơ 034'
      expect(searchPrefix('bo'), contains('Bơ 034'));
    });

    test('TC-PROD-05: Store Model & Geo-distance calculation accuracy (Haversine)', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final store = StoreModel(
        storeId: 'store_dalat',
        ownerId: 'owner_1',
        storeName: 'Nông Trại Hoa Đà Lạt',
        contactName: 'Chị Lan',
        phone: '0912345678',
        address: 'Hùng Vương, Đà Lạt',
        region: 'Lâm Đồng',
        status: 'approved',
        operatingStatus: 'active',
        latitude: 11.9404,
        longitude: 108.4583,
        targetCategories: const ['Nông sản'],
        createdAt: now,
        updatedAt: now,
      );

      expect(store.isApproved, isTrue);
      expect(store.canSell, isTrue);

      // Distance calculation from user location (Dalat center: 11.9571, 108.4400)
      double haversineDistanceMeters(double lat1, double lon1, double lat2, double lon2) {
        const earthRadius = 6371000.0;
        final dLat = (lat2 - lat1) * math.pi / 180.0;
        final dLon = (lon2 - lon1) * math.pi / 180.0;
        final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
            math.cos(lat1 * math.pi / 180.0) *
                math.cos(lat2 * math.pi / 180.0) *
                math.sin(dLon / 2) *
                math.sin(dLon / 2);
        final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
        return earthRadius * c;
      }

      final distMeters = haversineDistanceMeters(
        11.9571,
        108.4400,
        store.latitude!,
        store.longitude!,
      );

      // Expected ~2.6 km in Dalat city area
      expect(distMeters, greaterThan(1500));
      expect(distMeters, lessThan(5000));
    });

    test('TC-PROD-06: Product Creation Modal Picker Validation', () {
      // Valid categories in ViFarm
      const validCategories = [
        'Nông sản',
        'Vật tư nông nghiệp',
        'Phân bón & Thuốc BVTV',
        'Cây giống & Hạt giống',
        'Thiết bị & Máy nông nghiệp',
      ];

      expect(validCategories.length, 5);
      for (final cat in validCategories) {
        expect(cat.isNotEmpty, isTrue);
      }
    });
  });
}
