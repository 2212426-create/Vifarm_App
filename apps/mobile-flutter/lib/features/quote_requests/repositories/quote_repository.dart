import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/firebase_providers.dart';
import '../../orders/repositories/order_repository.dart';
import '../../products/models/product_model.dart';
import '../models/quote_model.dart';

final quoteRepositoryProvider = Provider<QuoteRepository>((ref) {
  return QuoteRepository(
    firestore: ref.watch(firestoreProvider),
    database: ref.watch(realtimeDbProvider),
    orderRepository: ref.watch(orderRepositoryProvider),
  );
});

final userQuotesStreamProvider = StreamProvider.family<List<QuoteRequestModel>, String>((ref, userId) {
  return ref.watch(quoteRepositoryProvider).watchUserQuotes(userId);
});

final quoteDetailStreamProvider = StreamProvider.family<QuoteRequestModel?, String>((ref, quoteId) {
  return ref.watch(quoteRepositoryProvider).watchQuoteDetail(quoteId);
});

class QuoteRepository {
  final FirebaseFirestore _firestore;
  final FirebaseDatabase _database;
  final OrderRepository _orderRepository;

  QuoteRepository({
    required this._firestore,
    required this._database,
    required this._orderRepository,
  });

  Stream<List<QuoteRequestModel>> watchUserQuotes(String userId) {
    if (userId.isEmpty) return Stream.value([]);
    return _firestore
        .collection('quote_requests')
        .where('buyerId', isEqualTo: userId)
        .snapshots()
        .asyncMap((buyerSnap) async {
      final buyerQuotes = buyerSnap.docs.map((d) => QuoteRequestModel.fromMap(d.data(), d.id)).toList();

      final sellerSnap = await _firestore
          .collection('quote_requests')
          .where('sellerId', isEqualTo: userId)
          .get();

      final sellerQuotes = sellerSnap.docs.map((d) => QuoteRequestModel.fromMap(d.data(), d.id)).toList();

      final Map<String, QuoteRequestModel> combined = {};
      for (var q in buyerQuotes) {
        combined[q.id] = q;
      }
      for (var q in sellerQuotes) {
        combined[q.id] = q;
      }

      final list = combined.values.toList();
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return list;
    });
  }

  Stream<QuoteRequestModel?> watchQuoteDetail(String quoteId) {
    if (quoteId.isEmpty) return Stream.value(null);
    return _firestore.collection('quote_requests').doc(quoteId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return QuoteRequestModel.fromMap(doc.data()!, doc.id);
    });
  }

  Future<String> createQuoteRequest({
    required String buyerId,
    required String buyerName,
    required ProductModel product,
    ProductVariantModel? variant,
    required double quantity,
  }) async {
    final docRef = _firestore.collection('quote_requests').doc();
    final now = DateTime.now().millisecondsSinceEpoch;

    final request = QuoteRequestModel(
      id: docRef.id,
      buyerId: buyerId,
      buyerName: buyerName,
      sellerId: product.sellerId,
      sellerName: product.sellerName,
      productId: product.id,
      productName: product.name,
      productImage: product.images.isNotEmpty ? product.images.first : '',
      variantName: variant?.name,
      quantity: quantity,
      unit: product.unit,
      currentVersion: 1,
      status: 'pending',
      versions: [],
      createdAt: now,
      updatedAt: now,
    );

    await docRef.set(request.toMap());

    await _sendQuoteChatNotification(
      buyerId: buyerId,
      sellerId: product.sellerId,
      quoteId: docRef.id,
      message: '🏷️ Đã gửi yêu cầu báo giá cho: ${product.name}',
    );

    return docRef.id;
  }

  Future<void> submitQuoteOffer({
    required String quoteId,
    required int itemPrice,
    required int shippingFee,
    required int validHours,
    required String notes,
  }) async {
    final docRef = _firestore.collection('quote_requests').doc(quoteId);
    final doc = await docRef.get();
    if (!doc.exists) return;

    final quote = QuoteRequestModel.fromMap(doc.data()!, doc.id);
    final newVersionNum = quote.currentVersion + 1;
    final now = DateTime.now().millisecondsSinceEpoch;
    final validUntil = now + (validHours * 3600 * 1000);

    final grandTotal = (itemPrice * quote.quantity).round() + shippingFee;

    final newVersion = QuoteVersionModel(
      version: newVersionNum,
      itemPrice: itemPrice,
      shippingFee: shippingFee,
      grandTotal: grandTotal,
      validUntil: validUntil,
      notes: notes,
      createdAt: now,
    );

    final updatedVersions = [...quote.versions, newVersion];

    await docRef.update({
      'currentVersion': newVersionNum,
      'status': 'quoted',
      'versions': updatedVersions.map((v) => v.toMap()).toList(),
      'updatedAt': now,
    });

    await _sendQuoteChatNotification(
      buyerId: quote.buyerId,
      sellerId: quote.sellerId,
      quoteId: quoteId,
      message: '✅ Người bán đã báo giá v$newVersionNum: ${grandTotal.toString()}đ',
    );
  }

  Future<String> acceptQuoteOffer({
    required String quoteId,
    required String deliveryAddress,
    required String contactPhone,
  }) async {
    final docRef = _firestore.collection('quote_requests').doc(quoteId);
    final doc = await docRef.get();
    if (!doc.exists) throw Exception('Yêu cầu báo giá không tồn tại');

    final quote = QuoteRequestModel.fromMap(doc.data()!, doc.id);
    if (quote.isExpired) throw Exception('Báo giá này đã hết hạn!');

    final version = quote.latestVersion;
    if (version == null) throw Exception('Chưa có báo giá nào được gửi!');

    await docRef.update({
      'status': 'accepted',
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });

    final orderId = await _orderRepository.createOrderFromQuote(
      quote: quote,
      version: version,
      deliveryAddress: deliveryAddress,
      contactPhone: contactPhone,
    );

    return orderId;
  }

  Future<void> _sendQuoteChatNotification({
    required String buyerId,
    required String sellerId,
    required String quoteId,
    required String message,
  }) async {
    try {
      final chatRoomId = buyerId.compareTo(sellerId) < 0 ? '${buyerId}_$sellerId' : '${sellerId}_$buyerId';
      final ref = _database.ref('chats').child(chatRoomId).push();
      await ref.set({
        'senderId': buyerId,
        'receiverId': sellerId,
        'message': message,
        'quoteId': quoteId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      // Ignore
    }
  }
}
