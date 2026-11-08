import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../orders/repositories/order_repository.dart';
import '../../quote_requests/repositories/quote_repository.dart';
import '../../quote_requests/widgets/quote_card_widget.dart';

/// Màn hình Quản Lý Đơn Bán & Yêu Cầu Báo Giá Dành Cho Gian Hàng
class SellerOrdersScreen extends ConsumerStatefulWidget {
  const SellerOrdersScreen({super.key});

  @override
  ConsumerState<SellerOrdersScreen> createState() => _SellerOrdersScreenState();
}

class _SellerOrdersScreenState extends ConsumerState<SellerOrdersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    if (currentUser == null) return const Scaffold(body: Center(child: Text('Vui lòng đăng nhập!')));

    final ordersAsync = ref.watch(userOrdersStreamProvider(currentUser.uid));
    final quotesAsync = ref.watch(userQuotesStreamProvider(currentUser.uid));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản Lý Đơn Bán'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Đơn Bán'),
            Tab(text: 'Yêu Cầu Báo Giá'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Orders Received
          ordersAsync.when(
            data: (orders) {
              final sellerOrders = orders.where((o) => o.sellerId == currentUser.uid).toList();
              if (sellerOrders.isEmpty) {
                return const Center(child: Text('Chưa có đơn bán nào.'));
              }

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: sellerOrders.length,
                itemBuilder: (context, index) {
                  final order = sellerOrders[index];
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
                              Text('Khách mua: ${order.buyerName}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              _buildStatusBadge(order.status),
                            ],
                          ),
                          const Divider(),
                          ...order.items.map((i) => Text('${i.productName} x${i.quantity.toInt()} ${i.unit} (${_formatVND(i.itemTotal)})')),
                          const Divider(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Tổng: ${_formatVND(order.grandTotal)}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                              OutlinedButton(
                                onPressed: () => context.push('/orders/${order.id}'),
                                child: const Text('Xử lý đơn'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(child: Text('Lỗi: $err')),
          ),

          // Tab 2: Quote Requests Received
          quotesAsync.when(
            data: (quotes) {
              final sellerQuotes = quotes.where((q) => q.sellerId == currentUser.uid).toList();
              if (sellerQuotes.isEmpty) {
                return const Center(child: Text('Chưa có yêu cầu báo giá nào từ khách hàng.'));
              }

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: sellerQuotes.length,
                itemBuilder: (context, index) {
                  final quote = sellerQuotes[index];
                  return QuoteCardWidget(quote: quote);
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(child: Text('Lỗi: $err')),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    switch (status) {
      case 'confirmed': return const Chip(label: Text('Đã xác nhận', style: TextStyle(color: Colors.white, fontSize: 10)), backgroundColor: AppColors.primary);
      case 'shipping': return const Chip(label: Text('Đang giao', style: TextStyle(color: Colors.white, fontSize: 10)), backgroundColor: Colors.blue);
      case 'completed': return const Chip(label: Text('Hoàn thành', style: TextStyle(color: Colors.white, fontSize: 10)), backgroundColor: AppColors.success);
      default: return Chip(label: Text(status, style: const TextStyle(color: Colors.white, fontSize: 10)), backgroundColor: Colors.grey);
    }
  }

  String _formatVND(int price) {
    if (price <= 0) return '0đ';
    return '${price.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.')}đ';
  }
}
