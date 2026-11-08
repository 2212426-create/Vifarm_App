import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../repositories/order_repository.dart';

/// Màn hình Chi Tiết Đơn Hàng & Chuyển Trạng Thái (State Machine)
class OrderDetailScreen extends ConsumerWidget {
  final String orderId;

  const OrderDetailScreen({
    super.key,
    required this.orderId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final orderAsync = ref.watch(orderDetailStreamProvider(orderId));

    return orderAsync.when(
      data: (order) {
        if (order == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Chi tiết đơn hàng')),
            body: const Center(child: Text('Không tìm thấy đơn hàng!')),
          );
        }

        final isSeller = currentUser?.uid == order.sellerId;

        return Scaffold(
          appBar: AppBar(
            title: Text('Đơn hàng #${order.id.substring(0, 6)}'),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status Banner
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.local_shipping, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Trạng thái: ${_getStatusLabel(order.status)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 15),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Delivery Info
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.location_on, color: AppColors.primary),
                    title: Text('Địa chỉ giao hàng (${order.contactPhone})'),
                    subtitle: Text(order.deliveryAddress),
                  ),
                ),
                const SizedBox(height: 16),

                // Items list
                const Text('Danh sách sản phẩm', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: order.items.map((item) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withAlpha(20),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: item.productImage.isNotEmpty
                                    ? Image.network(item.productImage, fit: BoxFit.cover)
                                    : const Icon(Icons.grass, color: AppColors.primary),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.productName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                    Text('${_formatVND(item.price)} x ${item.quantity.toInt()} ${item.unit}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                  ],
                                ),
                              ),
                              Text(_formatVND(item.itemTotal), style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Summary Total
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Tiền hàng:'),
                            Text(_formatVND(order.itemTotal)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Phí giao hàng:'),
                            Text(_formatVND(order.shippingFee)),
                          ],
                        ),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Tổng thanh toán:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            Text(_formatVND(order.grandTotal), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.primary)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Seller / Buyer State Transitions
                if (isSeller) ...[
                  const Text('Thao tác của Người Bán:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (order.status == 'confirmed')
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                        onPressed: () {
                          ref.read(orderRepositoryProvider).updateOrderStatus(orderId: order.id, newStatus: 'shipping');
                        },
                        child: const Text('Đánh Dấu Đang Giao Hàng', style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  if (order.status == 'shipping')
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                        onPressed: () {
                          ref.read(orderRepositoryProvider).updateOrderStatus(orderId: order.id, newStatus: 'completed');
                        },
                        child: const Text('Hoàn Thành Đơn Hàng', style: TextStyle(color: Colors.white)),
                      ),
                    ),
                ],

                if (order.status != 'completed' && order.status != 'cancelled') ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                      onPressed: () {
                        ref.read(orderRepositoryProvider).updateOrderStatus(orderId: order.id, newStatus: 'cancelled');
                      },
                      child: const Text('Hủy Đơn Hàng'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, stack) => Scaffold(body: Center(child: Text('Lỗi: $err'))),
    );
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'pending_seller_confirmation': return 'Chờ người bán xác nhận';
      case 'confirmed': return 'Đã xác nhận';
      case 'shipping': return 'Đang giao hàng';
      case 'completed': return 'Hoàn thành';
      case 'cancelled': return 'Đã hủy';
      default: return status;
    }
  }

  String _formatVND(int price) {
    if (price <= 0) return '0đ';
    return '${price.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.')}đ';
  }
}
