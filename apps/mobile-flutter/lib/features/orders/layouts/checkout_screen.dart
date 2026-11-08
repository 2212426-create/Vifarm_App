import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../cart/providers/cart_provider.dart';
import '../repositories/order_repository.dart';

/// Màn hình Xác Nhận Đặt Hàng (Checkout)
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();

  String _paymentMethod = 'cod';
  bool _isPlacingOrder = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _placeOrder() async {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;

    if (_phoneController.text.trim().isEmpty || _addressController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng điền đẩy đủ SĐT và Địa chỉ nhận hàng!')),
      );
      return;
    }

    final cartGroups = ref.read(cartGroupsProvider);
    final userProfile = ref.read(currentUserProfileProvider).valueOrNull;
    final buyerName = userProfile?.username ?? currentUser.email?.split('@')[0] ?? '';

    setState(() => _isPlacingOrder = true);

    try {
      final createdOrderIds = await ref.read(orderRepositoryProvider).createOrdersFromCart(
            buyerId: currentUser.uid,
            buyerName: buyerName,
            contactPhone: _phoneController.text.trim(),
            deliveryAddress: _addressController.text.trim(),
            cartGroups: cartGroups,
          );

      for (var group in cartGroups) {
        await ref.read(cartProvider.notifier).clearSelectedItems(group.sellerId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đặt thành công ${createdOrderIds.length} đơn hàng!')),
        );
        context.pushReplacement('/orders');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi đặt hàng: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isPlacingOrder = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartGroups = ref.watch(cartGroupsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final grandTotal = cartGroups.fold<int>(0, (sum, g) => sum + g.selectedFixedPriceTotal);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thanh Toán Đơn Hàng'),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Thông tin giao nhận', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primary)),
                  const SizedBox(height: 12),

                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Số điện thoại nhận hàng *',
                      prefixIcon: Icon(Icons.phone),
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: _addressController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Địa chỉ nhận hàng chi tiết *',
                      hintText: 'VD: Thôn 3, Xã Đức Trọng, Tỉnh Lâm Đồng',
                      prefixIcon: Icon(Icons.location_on),
                    ),
                  ),
                  const SizedBox(height: 20),

                  const Text('Hình thức thanh toán', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primary)),
                  const SizedBox(height: 8),

                  RadioListTile<String>(
                    title: const Text('Thanh toán khi nhận hàng (COD)'),
                    subtitle: const Text('Trả tiền mặt khi shiper giao hàng'),
                    value: 'cod',
                    groupValue: _paymentMethod,
                    onChanged: (val) => setState(() => _paymentMethod = val!),
                  ),
                  RadioListTile<String>(
                    title: const Text('Thanh toán khi đến lấy tại vườn'),
                    subtitle: const Text('Trả trực tiếp cho nhà vườn khi đến lấy'),
                    value: 'pickup_pay',
                    groupValue: _paymentMethod,
                    onChanged: (val) => setState(() => _paymentMethod = val!),
                  ),
                  const SizedBox(height: 20),

                  const Text('Danh sách sản phẩm chốt mua', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primary)),
                  const SizedBox(height: 12),

                  ...cartGroups.map((group) {
                    final selectedItems = group.items.where((i) => i.isSelected && i.saleType == 'fixed_price').toList();
                    if (selectedItems.isEmpty) return const SizedBox.shrink();

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.store, size: 16, color: AppColors.primary),
                                const SizedBox(width: 6),
                                Text(group.sellerName, style: const TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const Divider(),
                            ...selectedItems.map((item) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${item.productName} ${item.variantName != null ? "(${item.variantName})" : ""} x${item.quantity.toInt()} ${item.unit}',
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                    Text(
                                      _formatVND(item.totalPrice),
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -2)),
              ],
            ),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Tổng tiền hàng:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(
                      _formatVND(grandTotal),
                      style: const TextStyle(color: AppColors.primary, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const Spacer(),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  ),
                  onPressed: _isPlacingOrder ? null : _placeOrder,
                  child: _isPlacingOrder
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Xác Nhận Đặt Hàng', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatVND(int price) {
    if (price <= 0) return '0đ';
    return '${price.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.')}đ';
  }
}
