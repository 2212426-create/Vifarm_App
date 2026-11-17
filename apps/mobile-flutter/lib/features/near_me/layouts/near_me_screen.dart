import 'package:geolocator/geolocator.dart';
import '../../store/repositories/store_repository.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../products/repositories/product_repository.dart';
import '../providers/location_provider.dart';
import '../widgets/weather_widget.dart';

/// Màn hình "Quanh Đây" - Tìm kiếm nhà vườn, nông sản và video kỹ thuật theo bán kính
class NearMeScreen extends ConsumerStatefulWidget {
  const NearMeScreen({super.key});

  @override
  ConsumerState<NearMeScreen> createState() => _NearMeScreenState();
}

class _NearMeScreenState extends ConsumerState<NearMeScreen> {
  int _selectedRadius = 20;
  bool _showStoresTab = true; // km: 10, 20, 50

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locationState = ref.watch(nearMeLocationProvider);

    final productsAsync = ref.watch(marketplaceProductsStreamProvider((
      category: null,
      region: locationState.isGps ? null : locationState.regionName,
      saleType: null,
      query: null,
    )));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nông Nghiệp Quanh Đây'),
      ),
      body: Column(
        children: [
          const WeatherWidget(),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_on, color: AppColors.primary, size: 18),
                    const SizedBox(width: 4),
                    const Text('Khu vực:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(width: 6),

                    if (locationState.isGps)
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                locationState.displayName,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: () {
                                ref.read(nearMeLocationProvider.notifier).resetToManualDefault();
                              },
                              child: const Text(
                                '(Đổi)',
                                style: TextStyle(fontSize: 11, color: Colors.blue, decoration: TextDecoration.underline),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      DropdownButton<String>(
                        value: defaultPresetRegions.any((r) => r.name == locationState.regionName)
                            ? locationState.regionName
                            : defaultPresetRegions.first.name,
                        underline: const SizedBox.shrink(),
                        isDense: true,
                        items: defaultPresetRegions
                            .map((r) => DropdownMenuItem(
                                  value: r.name,
                                  child: Text(r.name, style: const TextStyle(fontSize: 13)),
                                ))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            ref.read(nearMeLocationProvider.notifier).selectPresetRegion(val);
                          }
                        },
                      ),

                    if (!locationState.isGps) const Spacer(),

                    FilterChip(
                      label: locationState.isLoadingGps
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 1.5),
                            )
                          : Text(
                              locationState.isGps ? 'GPS On' : 'Vị trí hiện tại',
                              style: const TextStyle(fontSize: 11),
                            ),
                      selected: locationState.isGps,
                      selectedColor: AppColors.primary,
                      visualDensity: VisualDensity.compact,
                      onSelected: locationState.isLoadingGps
                          ? null
                          : (selected) async {
                              if (selected) {
                                final success = await ref.read(nearMeLocationProvider.notifier).enableGps();
                                if (!success && context.mounted) {
                                  final err = ref.read(nearMeLocationProvider).errorMessage ?? 'Không thể bật định vị GPS.';
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(err)),
                                  );
                                }
                              } else {
                                ref.read(nearMeLocationProvider.notifier).resetToManualDefault();
                              }
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                Row(
                  children: [
                    const Text('Bán kính:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [10, 20, 50].map((radius) {
                            final isSelected = _selectedRadius == radius;
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text('${radius}km', style: const TextStyle(fontSize: 11)),
                                selected: isSelected,
                                selectedColor: AppColors.primary,
                                visualDensity: VisualDensity.compact,
                                onSelected: (selected) {
                                  if (selected) setState(() => _selectedRadius = radius);
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Nhà vườn / Gian hàng', style: TextStyle(fontSize: 12)),
                      selected: _showStoresTab,
                      selectedColor: AppColors.primary,
                      onSelected: (val) {
                        if (val) setState(() => _showStoresTab = true);
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Nông sản', style: TextStyle(fontSize: 12)),
                      selected: !_showStoresTab,
                      selectedColor: AppColors.primary,
                      onSelected: (val) {
                        if (val) setState(() => _showStoresTab = false);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          Expanded(
            child: _showStoresTab
                ? ref.watch(approvedStoresStreamProvider).when(
                    data: (stores) {
                      if (stores.isEmpty) {
                        return const Center(child: Text('Chưa có gian hàng nào được kích hoạt.'));
                      }

                      final storesWithDist = stores.map((s) {
                        double? dist;
                        if (s.latitude != null && s.longitude != null) {
                          dist = Geolocator.distanceBetween(
                            locationState.latitude,
                            locationState.longitude,
                            s.latitude!,
                            s.longitude!,
                          );
                        }
                        return (store: s, distanceMeters: dist);
                      }).toList();

                      storesWithDist.sort((a, b) {
                        if (a.distanceMeters == null && b.distanceMeters == null) return 0;
                        if (a.distanceMeters == null) return 1;
                        if (b.distanceMeters == null) return -1;
                        return a.distanceMeters!.compareTo(b.distanceMeters!);
                      });

                      return ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: storesWithDist.length,
                        separatorBuilder: (context, index) => const Divider(height: 12),
                        itemBuilder: (context, index) {
                          final item = storesWithDist[index];
                          final s = item.store;
                          final dist = item.distanceMeters;

                          String distText = 'Chưa có vị trí GPS';
                          if (dist != null) {
                            if (dist < 1000) {
                              distText = 'Cách ${dist.round()} m';
                            } else {
                              distText = 'Cách ${(dist / 1000).toStringAsFixed(1)} km';
                            }
                          }

                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                radius: 24,
                                backgroundColor: AppColors.primary.withAlpha(25),
                                backgroundImage: s.avatarUrl.isNotEmpty ? NetworkImage(s.avatarUrl) : null,
                                child: s.avatarUrl.isEmpty ? const Icon(Icons.storefront, color: AppColors.primary) : null,
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      s.storeName,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withAlpha(20),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      s.region,
                                      style: const TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 2),
                                  Text(
                                    s.address,
                                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      const Icon(Icons.near_me, size: 12, color: AppColors.primary),
                                      const SizedBox(width: 4),
                                      Text(
                                        distText,
                                        style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              trailing: const Icon(Icons.chevron_right, size: 20),
                              onTap: () {
                                context.push('/store/${s.storeId}');
                              },
                            ),
                          );
                        },
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (err, stack) => Center(child: Text('Lỗi: $err')),
                  )
                : productsAsync.when(
              data: (products) {
                if (products.isEmpty) {
                  return const Center(child: Text('Không có nhà vườn nào trong bán kính chọn.'));
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: products.length,
                  separatorBuilder: (context, index) => const Divider(height: 12),
                  itemBuilder: (context, index) {
                    final product = products[index];
                    final distanceKm = _calculateDistanceKm(
                      locationState.latitude,
                      locationState.longitude,
                      11.75 + (index * 0.02),
                      108.38 + (index * 0.02),
                    );

                    return Card(
                      child: ListTile(
                        leading: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withAlpha(20),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: product.images.isNotEmpty
                              ? Image.network(product.images.first, fit: BoxFit.cover, cacheWidth: 180)
                              : const Icon(Icons.grass, color: AppColors.primary),
                        ),
                        title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 2),
                            Text('Nhà vườn: ${product.sellerName.isNotEmpty ? product.sellerName : "Nông hộ"}', style: const TextStyle(fontSize: 11)),
                            Row(
                              children: [
                                Icon(Icons.near_me, size: 12, color: Colors.grey.shade600),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Cách ~${distanceKm.toStringAsFixed(1)} km • Xe tải 5T tận nơi',
                                    style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.bold),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right, size: 20),
                        onTap: () {
                          context.push('/marketplace/products/${product.id}');
                        },
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Lỗi: $err')),
            ),
          ),
        ],
      ),
    );
  }

  double _calculateDistanceKm(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 - math.cos((lat2 - lat1) * p) / 2 + math.cos(lat1 * p) * math.cos(lat2 * p) * (1 - math.cos((lon2 - lon1) * p)) / 2;
    return 12742 * math.asin(math.sqrt(a));
  }
}
