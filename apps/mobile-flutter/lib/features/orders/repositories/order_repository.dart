import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/firebase_providers.dart';
import '../../cart/models/cart_model.dart';
import '../../quote_requests/models/quote_model.dart';
import '../models/order_model.dart';

final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  return OrderRepository(firestore: ref.watch(firestoreProvider));
});

final userOrdersStreamProvider = StreamProvider.family<List<OrderModel>, String>((ref, userId) {
  return ref.watch(orderRepositoryProvider).watchUserOrders(userId);
});

final orderDetailStreamProvider = StreamProvider.family<OrderModel?, String>((ref, orderId) {
  return ref.watch(orderRepositoryProvider).watchOrderDetail(orderId);
});

class OrderRepository {
  final FirebaseFirestore _firestore;

  OrderRepository({required this._firestore});

  /// Stream danh sách đơn hàng liên quan đến user (là buyer hoặc seller)
  Stream<List<OrderModel>> watchUserOrders(String userId) {
    if (userId.isEmpty) return Stream.value([]);
    return _firestore
        .collection('orders')
        .where('buyerId', isEqualTo: userId)
        .snapshots()
        .asyncMap((buyerSnap) async {
      final buyerOrders = buyerSnap.docs.map((d) => OrderModel.fromMap(d.data(), d.id)).toList();

      final sellerSnap = await _firestore
          .collection('orders')
          .where('sellerId', isEqualTo: userId)
          .get();

      final sellerOrders = sellerSnap.docs.map((d) => OrderModel.fromMap(d.data(), d.id)).toList();

      final Map<String, OrderModel> map = {};
      for (var o in buyerOrders) {
        map[o.id] = o;
      }
      for (var o in sellerOrders) {
        map[o.id] = o;
      }

      final list = map.values.toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// Stream chi tiết 1 đơn hàng
  Stream<OrderModel?> watchOrderDetail(String orderId) {
    if (orderId.isEmpty) return Stream.value(null);
    return _firestore.collection('orders').doc(orderId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return OrderModel.fromMap(doc.data()!, doc.id);
    });
  }

  /// Đặt hàng từ Giỏ hàng - TỰ ĐỘNG TÁCH ĐƠN RIÊNG THEO MỖI NGƯỜI BÁN
  Future<List<String>> createOrdersFromCart({
    required String buyerId,
    required String buyerName,
    required String contactPhone,
    required String deliveryAddress,
    required List<CartGroupModel> cartGroups,
  }) async {
    final List<String> createdOrderIds = [];

    for (final group in cartGroups) {
      final selectedItems = group.items.where((i) => i.isSelected && i.saleType == 'fixed_price').toList();
      if (selectedItems.isEmpty) continue;

      try {
        final docRef = _firestore.collection('orders').doc();
        final now = DateTime.now().millisecondsSinceEpoch;

        final itemSnapshots = selectedItems.map((item) {
          return OrderItemSnapshot(
            productId: item.productId,
            productName: item.productName,
            productImage: item.productImage,
            variantId: item.variantId,
            variantName: item.variantName,
            unit: item.unit,
            price: item.unitPrice,
            quantity: item.quantity,
            itemTotal: item.totalPrice,
          );
        }).toList();

        final itemTotal = selectedItems.fold<int>(0, (sum, i) => sum + i.totalPrice);
        const shippingFee = 30000; // Mặc định hoặc thỏa thuận
        final grandTotal = itemTotal + shippingFee;

        final order = OrderModel(
          id: docRef.id,
          buyerId: buyerId,
          buyerName: buyerName,
          sellerId: group.sellerId,
          sellerName: group.sellerName,
          items: itemSnapshots,
          itemTotal: itemTotal,
          shippingFee: shippingFee,
          isShippingFeeKnown: true,
          grandTotal: grandTotal,
          fulfillmentType: 'agreed_delivery',
          paymentMethod: 'cod',
          contactPhone: contactPhone,
          deliveryAddress: deliveryAddress,
          status: 'confirmed',
          createdAt: now,
          updatedAt: now,
        );

        // Trừ tồn kho nguyên tử (transaction)
        await _firestore.runTransaction((transaction) async {
          for (final item in selectedItems) {
            final productRef = _firestore.collection('products').doc(item.productId);
            final pDoc = await transaction.get(productRef);
            if (pDoc.exists) {
              final currentStock = (pDoc.data()?['stock'] as num?)?.toInt() ?? 0;
              final newStock = (currentStock - item.quantity.toInt()).clamp(0, 999999);
              transaction.update(productRef, {'stock': newStock});
            }
          }
          transaction.set(docRef, order.toMap());
        });

        createdOrderIds.add(docRef.id);
      } catch (e) {
        // Continue creating orders for other sellers
      }
    }

    return createdOrderIds;
  }

  /// Tạo đơn hàng từ Báo giá đã chốt
  Future<String> createOrderFromQuote({
    required QuoteRequestModel quote,
    required QuoteVersionModel version,
    required String deliveryAddress,
    required String contactPhone,
  }) async {
    final docRef = _firestore.collection('orders').doc();
    final now = DateTime.now().millisecondsSinceEpoch;

    final itemSnapshot = OrderItemSnapshot(
      productId: quote.productId,
      productName: quote.productName,
      productImage: quote.productImage,
      variantName: quote.variantName,
      unit: quote.unit,
      price: version.itemPrice,
      quantity: quote.quantity,
      itemTotal: (version.itemPrice * quote.quantity).round(),
    );

    final order = OrderModel(
      id: docRef.id,
      buyerId: quote.buyerId,
      buyerName: quote.buyerName,
      sellerId: quote.sellerId,
      sellerName: quote.sellerName,
      items: [itemSnapshot],
      itemTotal: itemSnapshot.itemTotal,
      shippingFee: version.shippingFee,
      isShippingFeeKnown: true,
      grandTotal: version.grandTotal,
      fulfillmentType: 'agreed_delivery',
      paymentMethod: 'cod',
      contactPhone: contactPhone,
      deliveryAddress: deliveryAddress,
      status: 'confirmed',
      quoteId: quote.id,
      createdAt: now,
      updatedAt: now,
    );

    await docRef.set(order.toMap());
    return docRef.id;
  }

  /// Cập nhật trạng thái đơn hàng (State Machine)
  Future<void> updateOrderStatus({
    required String orderId,
    required String newStatus,
  }) async {
    final docRef = _firestore.collection('orders').doc(orderId);

    // Nếu chuyển sang cancelled, hoàn tồn kho nguyên tử 1 lần
    if (newStatus == 'cancelled') {
      await _firestore.runTransaction((transaction) async {
        final oDoc = await transaction.get(docRef);
        if (!oDoc.exists) return;
        final order = OrderModel.fromMap(oDoc.data()!, oDoc.id);

        if (order.status != 'cancelled') {
          for (final item in order.items) {
            final pRef = _firestore.collection('products').doc(item.productId);
            final pDoc = await transaction.get(pRef);
            if (pDoc.exists) {
              final currentStock = (pDoc.data()?['stock'] as num?)?.toInt() ?? 0;
              transaction.update(pRef, {'stock': currentStock + item.quantity.toInt()});
            }
          }
          transaction.update(docRef, {
            'status': 'cancelled',
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
          });
        }
      });
    } else {
      await docRef.update({
        'status': newStatus,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }
}
