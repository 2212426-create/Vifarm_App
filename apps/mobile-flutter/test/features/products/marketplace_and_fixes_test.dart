import 'package:flutter_test/flutter_test.dart';
import 'package:toptop_flutter/features/products/models/product_model.dart';
import 'package:toptop_flutter/features/products/repositories/product_repository.dart';

void main() {
  group('Marketplace Sub-Region & Prefix Search Tests', () {
    test('First-letter & prefix matching matches Vietnamese agricultural terms', () {
      const suggestions = [
        'Lúa',
        'Lúa giống',
        'Lan hồ điệp',
        'Lạc',
        'Sầu riêng',
        'Sầu riêng Ri6',
        'Su su',
        'Phân bón',
        'Cà phê',
      ];

      String removeAccents(String str) {
        const withAccents = 'áàảãạăắằẳẵặâấầẩẫậéèẻẽẹêếềểễệíìỉĩịóòỏõọôốồổỗộơớờởỡợúùủũụưứừửữựýỳỷỹỵđ';
        const withoutAccents = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
        var out = str;
        for (var i = 0; i < withAccents.length; i++) {
          out = out.replaceAll(withAccents[i], withoutAccents[i]);
        }
        return out;
      }

      List<String> matchQuery(String query) {
        final text = query.trim().toLowerCase();
        final unaccented = removeAccents(text);
        return suggestions.where((item) {
          final itemLower = item.toLowerCase();
          final itemUnaccented = removeAccents(itemLower);
          return itemLower.startsWith(text) ||
              itemUnaccented.startsWith(unaccented) ||
              itemLower.contains(text) ||
              itemUnaccented.contains(unaccented);
        }).toList();
      }

      // Query 'l' or 'L' -> matches Lúa, Lúa giống, Lan hồ điệp, Lạc
      final lMatches = matchQuery('L');
      expect(lMatches, contains('Lúa'));
      expect(lMatches, contains('Lúa giống'));
      expect(lMatches, contains('Lan hồ điệp'));
      expect(lMatches, contains('Lạc'));
      expect(lMatches, isNot(contains('Sầu riêng')));

      // Query 's' -> matches Sầu riêng, Su su
      final sMatches = matchQuery('s');
      expect(sMatches, contains('Sầu riêng'));
      expect(sMatches, contains('Sầu riêng Ri6'));
      expect(sMatches, contains('Su su'));

      // Query 'sau' unaccented -> matches Sầu riêng
      final sauMatches = matchQuery('sau');
      expect(sauMatches, contains('Sầu riêng'));
    });

    test('Region bi-directional matching works for districts in provinces', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final p1 = ProductModel(
        id: '1',
        sellerId: 's1',
        storeId: 'store1',
        sellerName: 'Nông Trại Đà Lạt',
        name: 'Sầu riêng Ri6',
        description: 'Sầu riêng chuẩn sạch',
        category: 'Nông sản',
        saleType: 'fixed_price',
        listedPrice: 85000,
        stock: 50,
        unit: 'kg',
        region: 'Đà Lạt, Lâm Đồng',
        images: const [],
        createdAt: now,
      );

      final p2 = ProductModel(
        id: '2',
        sellerId: 's2',
        storeId: 'store2',
        sellerName: 'Nông Sản Đắk Lắk',
        name: 'Bơ 034',
        description: 'Bơ sáp loại 1',
        category: 'Nông sản',
        saleType: 'fixed_price',
        listedPrice: 45000,
        stock: 100,
        unit: 'kg',
        region: 'Buôn Ma Thuột, Đắk Lắk',
        images: const [],
        createdAt: now,
      );

      final allProducts = [p1, p2];

      // Filter by province 'Lâm Đồng'
      final lamDongQuery = 'Lâm Đồng'.toLowerCase();
      final lamDongProducts = allProducts.where((p) {
        final r = p.region.toLowerCase();
        return r.contains(lamDongQuery) || lamDongQuery.contains(r);
      }).toList();
      expect(lamDongProducts.length, 1);
      expect(lamDongProducts.first.name, 'Sầu riêng Ri6');

      // Filter by district 'Đà Lạt'
      final daLatQuery = 'Đà Lạt'.toLowerCase();
      final daLatProducts = allProducts.where((p) {
        final r = p.region.toLowerCase();
        return r.contains(daLatQuery) || daLatQuery.contains(r);
      }).toList();
      expect(daLatProducts.length, 1);
      expect(daLatProducts.first.name, 'Sầu riêng Ri6');

      // Filter by non-existent district
      final giaLaiQuery = 'Gia Lai'.toLowerCase();
      final giaLaiProducts = allProducts.where((p) {
        final r = p.region.toLowerCase();
        return r.contains(giaLaiQuery) || giaLaiQuery.contains(r);
      }).toList();
      expect(giaLaiProducts.isEmpty, true);
    });

    test('ProductRepository.isRegionMatched handles production district-only regions (e.g. Đơn Dương in Lâm Đồng)', () {
      // Production database case: product has region 'Đơn Dương', buyer filters by province 'Lâm Đồng'
      expect(ProductRepository.isRegionMatched('Đơn Dương', 'Lâm Đồng'), isTrue);
      expect(ProductRepository.isRegionMatched('Đà Lạt', 'Lâm Đồng'), isTrue);
      expect(ProductRepository.isRegionMatched('Bảo Lộc, Lâm Đồng', 'Lâm Đồng'), isTrue);
      expect(ProductRepository.isRegionMatched('Đơn Dương', 'Đơn Dương'), isTrue);
      expect(ProductRepository.isRegionMatched('Hà Nội', 'Lâm Đồng'), isFalse);
      expect(ProductRepository.isRegionMatched('Đơn Dương', 'Tất cả'), isTrue);
      expect(ProductRepository.isRegionMatched('Đơn Dương', ''), isTrue);
    });
  });
}
