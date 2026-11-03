import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../models/weather_model.dart';
import '../providers/location_provider.dart';
import '../providers/weather_provider.dart';
import '../repositories/weather_repository.dart';
import 'weather_detail_bottom_sheet.dart';

/// Weather Widget displaying real-time weather data from Open-Meteo
class WeatherWidget extends ConsumerStatefulWidget {
  const WeatherWidget({super.key});

  @override
  ConsumerState<WeatherWidget> createState() => _WeatherWidgetState();
}

class _WeatherWidgetState extends ConsumerState<WeatherWidget> {
  bool _isRefreshing = false;

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);

    try {
      await ref
          .read(weatherNotifierProvider.notifier)
          .fetchWeather(forceRefresh: true);
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final weatherAsync = ref.watch(weatherNotifierProvider);
    final locationState = ref.watch(nearMeLocationProvider);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF232B2B)
            : Colors.green.shade900,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24, width: 0.5),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: weatherAsync.when(
        data: (data) {
          final current = data.current;
          final details = WmoWeatherCode.getDetails(current.weatherCode, isDay: current.isDay);

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(details.$2, color: AppColors.secondary, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                '${data.locationName} • ${current.tempC.toStringAsFixed(1)}°C',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              current.conditionText,
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Độ ẩm: ${current.humidity}% • Gió: ${current.windSpeedKmH.toStringAsFixed(1)} km/h • '
                          '${data.isFromCache ? "Dữ liệu gần nhất: ${_formatTime(data.fetchedTimestamp)}" : "Dữ liệu lúc: ${_formatTime(current.dataTime)}"} • '
                          '${data.attribution}',
                          style: const TextStyle(color: Colors.white70, fontSize: 10),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // Actions
                  IconButton(
                    icon: _isRefreshing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.refresh, color: Colors.white70, size: 18),
                    tooltip: 'Làm mới thời tiết',
                    onPressed: _isRefreshing ? null : _handleRefresh,
                    visualDensity: VisualDensity.compact,
                  ),

                  InkWell(
                    onTap: () => WeatherDetailBottomSheet.show(context, data),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(30),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        children: [
                          Text(
                            'Xem chi tiết',
                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                          Icon(Icons.chevron_right, color: Colors.white, size: 14),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
        loading: () => Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.secondary),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Đang tải thời tiết cho ${locationState.displayName}...',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ],
        ),
        error: (err, stack) {
          final errorMsg = err is WeatherException ? err.message : err.toString().replaceAll('Exception: ', '');

          return Row(
            children: [
              const Icon(Icons.cloud_off, color: Colors.orangeAccent, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Thống kê thời tiết chưa khả dụng',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      errorMsg,
                      style: const TextStyle(color: Colors.white70, fontSize: 10),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _handleRefresh,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.secondary,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Thử lại', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }
}
