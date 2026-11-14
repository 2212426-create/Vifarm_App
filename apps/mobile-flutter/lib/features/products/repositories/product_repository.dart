import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../core/utils/text_utils.dart';
import '../models/product_model.dart';

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepository(
    firestore: ref.watch(firestoreProvider),
    storage: ref.watch(firebaseStorageProvider),
  );
});

// autoDispose: mỗi chuỗi tìm kiếm là một tham số family; không tự hủy thì mỗi phím gõ
// để lại một listener Firestore sống mãi trên toàn bộ collection products.
final marketplaceProductsStreamProvider = StreamProvider.autoDispose.family<List<ProductModel>, ({String? category, String? region, String? saleType, String? query})>((ref, arg) {
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
  static const Map<String, List<String>> provinceDistricts = {
    'Lâm Đồng': [
      'Đà Lạt', 'Bảo Lộc', 'Đức Trọng', 'Đơn Dương', 'Di Linh', 'Lạc Dương',
      'Lâm Hà', 'Bảo Lâm', 'Đạ Huoai', 'Đạ Tẻh', 'Cát Tiên',
    ],
    'Đắk Lắk': [
      'Buôn Ma Thuột', 'Buôn Hồ', 'Krông Pắc', 'Cư M\'gar', 'Ea Kar', 'Krông Năng', 'Krông Búk',
    ],
    'Gia Lai': [
      'Pleiku', 'An Khê', 'Ayun Pa', 'Chư Sê', 'Đak Đoa', 'Ia Grai',
    ],
    'Đồng Nai': [
      'Biên Hòa', 'Long Khánh', 'Long Thành', 'Nhơn Trạch', 'Định Quán', 'Xuân Lộc',
    ],
    'Cần Thơ': [
      'Ninh Kiều', 'Cái Răng', 'Bình Thủy', 'Ô Môn', 'Thốt Nốt', 'Phong Điền',
    ],
    'TP.HCM': [
      'Củ Chi', 'Hóc Môn', 'Bình Chánh', 'Cần Giờ', 'Thủ Đức',
    ],
  };

  /// [provinceDistricts] đã bỏ dấu, tính một lần (trước đây tính lại cho từng sản phẩm).
  static final Map<String, List<String>> _normalizedProvinceDistricts = {
    for (final entry in provinceDistricts.entries)
      TextUtils.removeDiacritics(entry.key):
          entry.value.map(TextUtils.removeDiacritics).toList(),
  };

  /// Kiểm tra sản phẩm có khớp khu vực tìm kiếm / lọc (hỗ trợ cả cấp Tỉnh và cấp Huyện/Xã)
  static bool isRegionMatched(String productRegion, String queryRegion) {
    if (queryRegion.isEmpty || queryRegion == 'Tất cả') return true;
    final pNorm = TextUtils.removeDiacritics(productRegion);
    final qNorm = TextUtils.removeDiacritics(queryRegion);
    if (pNorm.contains(qNorm) || qNorm.contains(pNorm)) return true;

    for (final entry in _normalizedProvinceDistricts.entries) {
      final provNorm = entry.key;
      if (qNorm == provNorm || qNorm.contains(provNorm)) {
        for (final distNorm in entry.value) {
          if (pNorm.contains(distNorm) || distNorm.contains(pNorm)) {
            return true;
          }
        }
      }
    }
    return false;
  }

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  ProductRepository({
    required FirebaseFirestore firestore,
    FirebaseStorage? storage,
  })  : _firestore = firestore,
        _storage = storage ?? FirebaseStorage.instance;

  /// Tải tệp hình ảnh sản phẩm lên Firebase Storage
  Future<String> uploadProductMedia({
    required String sellerId,
    required XFile file,
  }) async {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final ext = file.path.split('.').last.toLowerCase();
    final safeExt = (ext == 'png' || ext == 'webp') ? ext : 'jpg';
    final mime = safeExt == 'png' ? 'image/png' : 'image/jpeg';
    final target = _storage.ref('products/$sellerId/$timestamp.$safeExt');

    if (!kIsWeb && file.path.isNotEmpty) {
      await target.putFile(File(file.path), SettableMetadata(contentType: mime));
    } else {
      await target.putData(await file.readAsBytes(), SettableMetadata(contentType: mime));
    }
    return await target.getDownloadURL();
  }

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
        list = list.where((p) => isRegionMatched(p.region, region)).toList();
      }
      if (saleType != null && saleType.isNotEmpty && saleType != 'Tất cả') {
        list = list.where((p) => p.saleType == saleType).toList();
      }
      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final q = searchQuery.trim().toLowerCase();
        final qNorm = TextUtils.removeDiacritics(q);
        list = list.where((p) {
          final name = p.name.toLowerCase();
          final desc = p.description.toLowerCase();
          final nameNorm = TextUtils.removeDiacritics(name);
          final descNorm = TextUtils.removeDiacritics(desc);
          return name.contains(q) ||
              desc.contains(q) ||
              nameNorm.contains(qNorm) ||
              descNorm.contains(qNorm) ||
              nameNorm.startsWith(qNorm);
        }).toList();
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
        .where('status', isEqualTo: 'active')
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
