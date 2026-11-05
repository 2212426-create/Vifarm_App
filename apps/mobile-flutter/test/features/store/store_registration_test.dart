import 'package:flutter_test/flutter_test.dart';
import 'package:toptop_flutter/features/store/models/store_model.dart';

void main() {
  group('StoreModel Registration & Draft Serialization Tests', () {
    test('creates StoreModel draft with default and custom values', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final store = StoreModel(
        storeId: 'store_123',
        ownerId: 'user_456',
        ownerName: 'Nông hộ Nam',
        storeType: 'individual',
        storeName: 'Nông sản Sạch Đức Trọng',
        contactName: 'Nguyễn Văn Nam',
        phone: '0912345678',
        address: 'Thôn 3, Đức Trọng',
        region: 'Lâm Đồng',
        targetCategories: ['Nông sản', 'Cây giống & Hạt giống'],
        fulfillmentMethods: ['pickup', 'agreed_delivery'],
        status: 'draft',
        createdAt: now,
        updatedAt: now,
      );

      final map = store.toMap();
      expect(map['status'], equals('draft'));
      expect(map['storeType'], equals('individual'));
      expect(map['version'], equals(1));
      expect(map['targetCategories'], contains('Nông sản'));

      final parsed = StoreModel.fromMap(map, 'store_123');
      expect(parsed.storeId, equals('store_123'));
      expect(parsed.storeName, equals('Nông sản Sạch Đức Trọng'));
      expect(parsed.status, equals('draft'));
      expect(parsed.version, equals(1));
      expect(parsed.isApproved, isFalse);
    });

    test('creates Business StoreModel with pending status, versioning, and audit history', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final auditEntry = StoreAuditLog(
        version: 1,
        status: 'needs_changes',
        reviewerId: 'admin_1',
        reviewerName: 'Admin Minh',
        reason: 'Thiếu ảnh mặt sau CCCD',
        internalNote: 'Người gửi chưa tải đủ 2 mặt',
        timestamp: now - 3600000,
      );

      final store = StoreModel(
        storeId: 'store_999',
        ownerId: 'user_888',
        ownerName: 'Công ty Phú Nông',
        storeType: 'business',
        businessSubtype: 'enterprise',
        storeName: 'Đại lý VTNN Phú Nông',
        contactName: 'Trần Văn Phú',
        phone: '0988888888',
        address: '123 QL20, Đức Trọng',
        region: 'Lâm Đồng',
        taxCode: '0123456789',
        representative: 'Trần Văn Phú',
        verificationDocs: ['https://storage.firebase.com/doc1.jpg'],
        status: 'pending',
        version: 2,
        auditHistory: [auditEntry],
        createdAt: now,
        updatedAt: now,
      );

      final map = store.toMap();
      expect(map['status'], equals('pending'));
      expect(map['version'], equals(2));
      expect(map['auditHistory'].length, equals(1));
      expect(map['auditHistory'][0]['reason'], equals('Thiếu ảnh mặt sau CCCD'));

      final parsed = StoreModel.fromMap(map, 'store_999');
      expect(parsed.storeId, equals('store_999'));
      expect(parsed.status, equals('pending'));
      expect(parsed.version, equals(2));
      expect(parsed.auditHistory.length, equals(1));
      expect(parsed.auditHistory[0].reviewerName, equals('Admin Minh'));
      expect(parsed.canSell, isFalse);
    });

    test('filters out invalid or empty verification document URLs cleanly', () {
      final rawDocs = [
        'https://firebasestorage.googleapis.com/v0/b/app.appspot.com/o/doc1.jpg',
        '',
        '   ',
        'invalid_local_file_path',
        'http://example.com/doc2.png',
      ];

      final validDocs = rawDocs
          .where((doc) => doc.trim().isNotEmpty && (doc.startsWith('http://') || doc.startsWith('https://')))
          .toList();

      expect(validDocs.length, equals(2));
      expect(validDocs[0], equals('https://firebasestorage.googleapis.com/v0/b/app.appspot.com/o/doc1.jpg'));
      expect(validDocs[1], equals('http://example.com/doc2.png'));
    });
  });
}
