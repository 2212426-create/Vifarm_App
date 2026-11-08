import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/providers/firebase_providers.dart';
import '../../auth/providers/auth_provider.dart';
import '../../products/models/product_model.dart';
import '../models/cart_model.dart';

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItemModel>>((ref) {
  final firestore = ref.watch(firestoreProvider);
  final currentUser = ref.watch(currentUserProvider);
  final notifier = CartNotifier(firestore: firestore, currentUserId: currentUser?.uid);
  return notifier;
});

final cartItemCountProvider = Provider<int>((ref) {
  final cartItems = ref.watch(cartProvider);
  return cartItems.length;
});

final cartGroupsProvider = Provider<List<CartGroupModel>>((ref) {
  final cartItems = ref.watch(cartProvider);
  final Map<String, List<CartItemModel>> map = {};

  for (final item in cartItems) {
    map.putIfAbsent(item.sellerId, () => []).add(item);
  }

  return map.entries.map((entry) {
    final sellerName = entry.value.first.sellerName;
    return CartGroupModel(
      sellerId: entry.key,
      sellerName: sellerName.isNotEmpty ? sellerName : 'Nhà vườn ${entry.key.substring(0, 4)}',
      items: entry.value,
    );
  }).toList();
});

class CartNotifier extends StateNotifier<List<CartItemModel>> {
  final FirebaseFirestore _firestore;
  final String? currentUserId;

  CartNotifier({required this._firestore, required this.currentUserId})
      : super([]) {
    _loadCart();
  }

  Future<void> _loadCart() async {
    if (currentUserId == null || currentUserId!.isEmpty) {
      state = [];
      return;
    }

    try {
      // 1. Tải từ SharedPreferences local cache
      final prefs = await SharedPreferences.getInstance();
      final localData = prefs.getString('cart_$currentUserId');
      if (localData != null && localData.isNotEmpty) {
        final List<dynamic> jsonList = jsonDecode(localData);
        state = jsonList.map((e) => CartItemModel.fromMap(e as Map<String, dynamic>)).toList();
      }

      // 2. Đồng bộ Firestore
      final doc = await _firestore.collection('carts').doc(currentUserId).get();
      if (doc.exists && doc.data() != null) {
        final List<dynamic> itemsJson = doc.data()!['items'] as List<dynamic>? ?? [];
        final firestoreItems = itemsJson.map((e) => CartItemModel.fromMap(e as Map<String, dynamic>)).toList();
        state = firestoreItems;
        _saveCart(firestoreItems);
      }
    } catch (e) {
      // Silent error fallback
    }
  }

  Future<void> _saveCart(List<CartItemModel> items) async {
    if (currentUserId == null || currentUserId!.isEmpty) return;

    // Save to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(items.map((i) => i.toMap()).toList());
    await prefs.setString('cart_$currentUserId', jsonStr);

    // Sync to Firestore
    await _firestore.collection('carts').doc(currentUserId).set({
      'userId': currentUserId,
      'items': items.map((i) => i.toMap()).toList(),
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Thêm sản phẩm vào giỏ (gộp nếu cùng quy cách, tách nếu khác quy cách)
  Future<void> addToCart({
    required String userId,
    required ProductModel product,
    ProductVariantModel? variant,
    required double quantity,
  }) async {
    final isFixedPrice = product.saleType == 'fixed_price';
    final unitPrice = variant != null ? variant.price : (isFixedPrice ? product.listedPrice : product.referencePrice);
    final variantId = variant?.variantId;
    final variantName = variant?.name;

    final cartItemId = '${product.id}_${variantId ?? "default"}';

    final existingIndex = state.indexWhere((i) => i.cartItemId == cartItemId);

    List<CartItemModel> updatedList = [...state];

    if (existingIndex >= 0) {
      // Cùng sản phẩm & cùng quy cách -> Gộp số lượng
      final existing = updatedList[existingIndex];
      updatedList[existingIndex] = existing.copyWith(
        quantity: existing.quantity + quantity,
      );
    } else {
      // Khác quy cách hoặc sản phẩm mới -> Tách dòng
      final newItem = CartItemModel(
        cartItemId: cartItemId,
        productId: product.id,
        sellerId: product.sellerId,
        sellerName: product.sellerName,
        productName: product.name,
        productImage: product.images.isNotEmpty ? product.images.first : '',
        variantId: variantId,
        variantName: variantName,
        unit: product.unit,
        saleType: product.saleType,
        unitPrice: unitPrice,
        quantity: quantity,
        isSelected: true,
        isAvailable: product.stock > 0,
      );
      updatedList.add(newItem);
    }

    state = updatedList;
    await _saveCart(updatedList);
  }

  /// Thay đổi số lượng
  Future<void> updateQuantity(String cartItemId, double newQty) async {
    if (newQty <= 0) {
      await removeItem(cartItemId);
      return;
    }

    final updated = state.map((item) {
      if (item.cartItemId == cartItemId) {
        return item.copyWith(quantity: newQty);
      }
      return item;
    }).toList();

    state = updated;
    await _saveCart(updated);
  }

  /// Toggle chọn item
  Future<void> toggleItemSelection(String cartItemId) async {
    final updated = state.map((item) {
      if (item.cartItemId == cartItemId) {
        return item.copyWith(isSelected: !item.isSelected);
      }
      return item;
    }).toList();

    state = updated;
    await _saveCart(updated);
  }

  /// Toggle chọn cả seller group
  Future<void> toggleGroupSelection(String sellerId, bool isSelected) async {
    final updated = state.map((item) {
      if (item.sellerId == sellerId) {
        return item.copyWith(isSelected: isSelected);
      }
      return item;
    }).toList();

    state = updated;
    await _saveCart(updated);
  }

  /// Xóa item khỏi giỏ
  Future<void> removeItem(String cartItemId) async {
    final updated = state.where((item) => item.cartItemId != cartItemId).toList();
    state = updated;
    await _saveCart(updated);
  }

  /// Xóa các item đã được chọn sau khi đặt hàng thành công
  Future<void> clearSelectedItems(String sellerId) async {
    final updated = state.where((item) => !(item.sellerId == sellerId && item.isSelected)).toList();
    state = updated;
    await _saveCart(updated);
  }
}
