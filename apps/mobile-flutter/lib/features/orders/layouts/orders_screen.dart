import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/order_model.dart';
import '../repositories/order_repository.dart';

/// Màn hình Quản lý Đơn Hàng Mua & Bán
class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final List<String> _tabs = [
    'Tất cả',
    'Chờ xác nhận',
    'Đã xác nhận',
    'Đang giao',
    'Hoàn thành',
    'Đã hủy',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);

    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Đơn hàng')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.receipt_long, size: 64, color: AppColors.primary),
              const SizedBox(height: 16),
              const Text('Vui lòng đăng nhập để xem đơn hàng!'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.go('/auth'),
                child: const Text('Đăng nhập'),
              ),
            ],
          ),
        ),
      );
    }

    final ordersAsync = ref.watch(userOrdersStreamProvider(currentUser.uid));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản Lý Đơn Hàng'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: _tabs.map((t) => Tab(text: t)).toList(),
        ),
      ),
      body: ordersAsync.when(
        data: (orders) {
          return TabBarView(
            controller: _tabController,
            children: _tabs.map((tab) {
              final filtered = _filterOrdersByTab(orders, tab);
              if (filtered.isEmpty) {
                return const Center(child: Text('Không có đơn hàng nào trong mục này.'));
              }
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final order = filtered[index];
                  return _OrderCard(order: order, currentUserId: currentUser.uid);
                },
              );
            }).toList(),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Lỗi: $err')),
      ),
    );
  }

  List<OrderModel> _filterOrdersByTab(List<OrderModel> orders, String tab) {
    switch (tab) {
      case 'Chờ xác nhận':
        return orders.where((o) => o.status == 'pending_seller_confirmation' || o.status == 'pending_buyer_confirmation').toList();
      case 'Đã xác nhận':
        return orders.where((o) => o.status == 'confirmed').toList();
      case 'Đang giao':
        return orders.where((o) => o.status == 'shipping').toList();
      case 'Hoàn thành':
        return orders.where((o) => o.status == 'completed').toList();
      case 'Đã hủy':
        return orders.where((o) => o.status == 'cancelled').toList();
      default:
        return orders;
    }
  }
}

class _OrderCard extends ConsumerWidget {
  final OrderModel order;
  final String currentUserId;

  const _OrderCard({required this.order, required this.currentUserId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBuyer = currentUserId == order.buyerId;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.store, size: 16, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      isBuyer ? order.sellerName : 'Khách mua: ${order.buyerName}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
                _buildStatusBadge(order.status),
              ],
            ),
            const Divider(),

            ...order.items.map((item) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withAlpha(20),
                        borderRadius: BorderRadius.circular(4),
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
                          Text(item.productName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text('${_formatVND(item.price)} x ${item.quantity.toInt()} ${item.unit}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ),
                    Text(_formatVND(item.itemTotal), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              );
            }),
            const Divider(),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Tổng thanh toán: ${_formatVND(order.grandTotal)}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 14)),
                OutlinedButton(
                  onPressed: () {
                    context.push('/orders/${order.id}');
                  },
                  child: const Text('Chi tiết đơn'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    switch (status) {
      case 'confirmed':
        return const Chip(label: Text('Đã xác nhận', style: TextStyle(color: Colors.white, fontSize: 10)), backgroundColor: AppColors.primary);
      case 'shipping':
        return const Chip(label: Text('Đang giao', style: TextStyle(color: Colors.white, fontSize: 10)), backgroundColor: Colors.blue);
      case 'completed':
        return const Chip(label: Text('Hoàn thành', style: TextStyle(color: Colors.white, fontSize: 10)), backgroundColor: AppColors.success);
      case 'cancelled':
        return const Chip(label: Text('Đã hủy', style: TextStyle(color: Colors.white, fontSize: 10)), backgroundColor: Colors.grey);
      default:
        return Chip(label: Text(status, style: const TextStyle(color: Colors.white, fontSize: 10)), backgroundColor: AppColors.warning);
    }
  }

  String _formatVND(int price) {
    if (price <= 0) return '0đ';
    return '${price.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.')}đ';
  }
}
