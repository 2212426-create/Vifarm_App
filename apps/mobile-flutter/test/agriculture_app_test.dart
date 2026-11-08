import 'package:flutter_test/flutter_test.dart';
import 'package:toptop_flutter/features/cart/models/cart_model.dart';
import 'package:toptop_flutter/features/orders/models/order_model.dart';
import 'package:toptop_flutter/features/quote_requests/models/quote_model.dart';
import 'package:toptop_flutter/features/video_feed/models/video_model.dart';

void main() {
  group('Nông Video Unit Tests', () {
    test('VideoModel backward compatibility and agricultural fields parsing', () {
      final legacyMap = {
        'videoId': 'v123',
        'videoUri': 'https://example.com/video.mp4',
        'authorId': 'u1',
        'location': 'Lâm Đồng',
        'timestamp': 1700000000000,
      };

      final video = VideoModel.fromMap(legacyMap);
      expect(video.videoId, equals('v123'));
      expect(video.location, equals('Lâm Đồng'));
      expect(video.region, equals('Lâm Đồng'));
      expect(video.crop, isNull);

      final agriMap = {
        'videoId': 'v124',
        'videoUri': 'https://example.com/video2.mp4',
        'authorId': 'u2',
        'crop': 'Sầu riêng',
        'growthStage': 'Ra hoa',
        'region': 'Đắk Lắk',
        'taggedProductIds': ['p1', 'p2'],
        'timestamp': 1700000000000,
      };

      final agriVideo = VideoModel.fromMap(agriMap);
      expect(agriVideo.crop, equals('Sầu riêng'));
      expect(agriVideo.growthStage, equals('Ra hoa'));
      expect(agriVideo.region, equals('Đắk Lắk'));
      expect(agriVideo.taggedProductIds.length, equals(2));
    });

    test('Cart line item grouping logic', () {
      final item1 = CartItemModel(
        cartItemId: 'p1_v1',
        productId: 'p1',
        sellerId: 's1',
        sellerName: 'Nhà vườn A',
        productName: 'Sầu riêng Ri6',
        variantId: 'v1',
        variantName: 'Bao 25kg',
        saleType: 'fixed_price',
        unitPrice: 100000,
        quantity: 2,
      );

      final item2 = CartItemModel(
        cartItemId: 'p1_v2',
        productId: 'p1',
        sellerId: 's1',
        sellerName: 'Nhà vườn A',
        productName: 'Sầu riêng Ri6',
        variantId: 'v2',
        variantName: 'Bao 50kg',
        saleType: 'fixed_price',
        unitPrice: 180000,
        quantity: 1,
      );

      expect(item1.cartItemId, isNot(equals(item2.cartItemId)));
      expect(item1.totalPrice, equals(200000));
      expect(item2.totalPrice, equals(180000));

      final group = CartGroupModel(
        sellerId: 's1',
        sellerName: 'Nhà vườn A',
        items: [item1, item2],
      );

      expect(group.selectedFixedPriceTotal, equals(380000));
    });

    test('Quote Request versioning and expiration check', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final version1 = QuoteVersionModel(
        version: 1,
        itemPrice: 75000,
        shippingFee: 30000,
        grandTotal: 180000,
        validUntil: now + 3600000, // Valid for 1 hour
        createdAt: now,
      );

      final quote = QuoteRequestModel(
        id: 'q1',
        buyerId: 'b1',
        sellerId: 's1',
        productId: 'p1',
        productName: 'Phân bón NPK',
        quantity: 2,
        currentVersion: 1,
        versions: [version1],
        createdAt: now,
        updatedAt: now,
      );

      expect(quote.latestVersion?.grandTotal, equals(180000));
      expect(quote.isExpired, isFalse);
    });

    test('OrderModel fields and total calculation', () {
      final snapshot = OrderItemSnapshot(
        productId: 'p1',
        productName: 'Phân hữu cơ',
        price: 50000,
        quantity: 3,
        itemTotal: 150000,
      );

      final order = OrderModel(
        id: 'o1',
        buyerId: 'b1',
        sellerId: 's1',
        items: [snapshot],
        itemTotal: 150000,
        shippingFee: 20000,
        grandTotal: 170000,
        contactPhone: '0912345678',
        deliveryAddress: 'Lâm Đồng',
        createdAt: 1700000000000,
        updatedAt: 1700000000000,
      );

      expect(order.grandTotal, equals(170000));
      expect(order.items.length, equals(1));
    });
  });
}
