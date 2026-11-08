import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/firebase_providers.dart';
import '../models/product_model.dart';

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepository(firestore: ref.watch(firestoreProvider));
});

final marketplaceProductsStreamProvider = StreamProvider.family<List<ProductModel>, ({String? category, String? region, String? saleType, String? query})>((ref, arg) {
  return ref.watch(productRepositoryProvider).watchMarketplaceProducts(
    category: arg.category,
    region: arg.region,
    saleType: arg.saleType,
    searchQuery: arg.query,
  );
});

final sellerProductsStreamProvider = StreamProvider.family<List<ProductModel>, String>((ref, sellerId) {
  return ref.watch(productRepositoryProvider).watchSellerProducts(sellerId);
});

final productDetailStreamProvider = StreamProvider.family<ProductModel?, String>((ref, productId) {
  return ref.watch(productRepositoryProvider).watchProductDetail(productId);
});

class ProductRepository {
  final FirebaseFirestore _firestore;

  ProductRepository({required this._firestore});

  /// Stream danh sách sản phẩm hiển thị trên Chợ
  Stream<List<ProductModel>> watchMarketplaceProducts({
    String? category,
    String? region,
    String? saleType,
    String? searchQuery,
  }) {
    return _firestore
        .collection('products')
        .where('status', isEqualTo: 'active')
        .where('moderationStatus', isEqualTo: 'approved')
        .snapshots()
        .map((snapshot) {
      var list = snapshot.docs
          .map((doc) => ProductModel.fromMap(doc.data(), doc.id))
          .toList();

      if (category != null && category.isNotEmpty && category != 'Tất cả') {
        list = list.where((p) => p.category == category).toList();
      }
      if (region != null && region.isNotEmpty && region != 'Tất cả') {
        list = list.where((p) => p.region == region).toList();
      }
      if (saleType != null && saleType.isNotEmpty && saleType != 'Tất cả') {
        list = list.where((p) => p.saleType == saleType).toList();
      }
      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final q = searchQuery.trim().toLowerCase();
        list = list.where((p) => p.name.toLowerCase().contains(q) || p.description.toLowerCase().contains(q)).toList();
      }

      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// Stream danh sách sản phẩm của người bán
  Stream<List<ProductModel>> watchSellerProducts(String sellerId) {
    if (sellerId.isEmpty) return Stream.value([]);
    return _firestore
        .collection('products')
        .where('sellerId', isEqualTo: sellerId)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs
          .map((doc) => ProductModel.fromMap(doc.data(), doc.id))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// Stream chi tiết 1 sản phẩm
  Stream<ProductModel?> watchProductDetail(String productId) {
    if (productId.isEmpty) return Stream.value(null);
    return _firestore.collection('products').doc(productId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return ProductModel.fromMap(doc.data()!, doc.id);
    });
  }

  /// Lấy 1 sản phẩm dạng Future (dùng khi open bottom sheet khẩn cấp)
  Future<ProductModel?> getProductOnce(String productId) async {
    if (productId.isEmpty) return null;
    final doc = await _firestore.collection('products').doc(productId).get();
    if (!doc.exists) return null;
    return ProductModel.fromMap(doc.data()!, doc.id);
  }

  /// Tạo sản phẩm mới
  Future<String> saveProduct(ProductModel product) async {
    final isNew = product.id.isEmpty;
    final docRef = isNew ? _firestore.collection('products').doc() : _firestore.collection('products').doc(product.id);

    final data = product.toMap();
    if (isNew) {
      data['id'] = docRef.id;
      data['createdAt'] = DateTime.now().millisecondsSinceEpoch;
    }

    await docRef.set(data, SetOptions(merge: true));
    return docRef.id;
  }

  /// Đổi trạng thái ẩn/hiện sản phẩm
  Future<void> toggleProductStatus(String productId, String newStatus) async {
    await _firestore.collection('products').doc(productId).update({
      'status': newStatus,
    });
  }
}
