import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../models/weather_model.dart';

enum HourlyMode { restOfToday, next24Hours }

class WeatherDetailBottomSheet extends StatefulWidget {
  final WeatherData weatherData;

  const WeatherDetailBottomSheet({
    super.key,
    required this.weatherData,
  });

  static void show(BuildContext context, WeatherData weatherData) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => WeatherDetailBottomSheet(weatherData: weatherData),
    );
  }

  @override
  State<WeatherDetailBottomSheet> createState() => _WeatherDetailBottomSheetState();
}

class _WeatherDetailBottomSheetState extends State<WeatherDetailBottomSheet> {
  HourlyMode _hourlyMode = HourlyMode.restOfToday;
  int? _selectedHourIndex;
  int? _selectedDayIndex;

  String _formatDayLabel(DateTime dt, int dayOffset) {
    if (dayOffset == 0) return 'Hôm nay';
    final weekdays = [
      '',
      'Thứ 2',
      'Thứ 3',
      'Thứ 4',
      'Thứ 5',
      'Thứ 6',
      'Thứ 7',
      'Chủ Nhật'
    ];
    final dayStr = weekdays[dt.weekday];
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    return '$dayStr, $day/$month';
  }

  String _formatHourLabel(DateTime dt, int index) {
    if (index == 0 && dt.difference(DateTime.now()).inMinutes.abs() < 45) {
      return 'Bây giờ';
    }
    final hourStr = dt.hour.toString().padLeft(2, '0');
    return '$hourStr:00';
  }

  String _formatTimestamp(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    return '$hour:$minute $day/$month/${dt.year}';
  }

  List<HourlyForecast> _getFilteredHourly(WeatherData data) {
    if (data.hourly.isEmpty) return [];

    final now = data.current.dataTime;

    if (_hourlyMode == HourlyMode.restOfToday) {
      final filtered = data.hourly
          .where((h) => h.time.year == now.year && h.time.month == now.month && h.time.day == now.day)
          .toList();
      // If rest of today is empty (late night), show next 12 hours
      return filtered.isNotEmpty ? filtered : data.hourly.take(12).toList();
    } else {
      return data.hourly.take(24).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final weatherData = widget.weatherData;
    final current = weatherData.current;
    final details = WmoWeatherCode.getDetails(current.weatherCode, isDay: current.isDay);

    final todayDaily = weatherData.daily.isNotEmpty ? weatherData.daily.first : null;
    final forecast7Days = weatherData.daily.length > 1
        ? weatherData.daily.sublist(1)
        : weatherData.daily;

    final hourlyList = _getFilteredHourly(weatherData);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag handle
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withAlpha(100),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.wb_sunny_rounded, color: AppColors.secondary, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Chi tiết thời tiết ${weatherData.locationName}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Content List
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    // 1. Current Weather Header Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isDark
                              ? [const Color(0xFF2C3E50), const Color(0xFF000000)]
                              : [const Color(0xFF2E7D32), const Color(0xFF1B5E20)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${current.tempC.toStringAsFixed(1)}°C',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 38,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    current.conditionText,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              Icon(
                                details.$2,
                                color: AppColors.secondary,
                                size: 58,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (todayDaily != null) ...[
                            Text(
                              'Nhiệt độ hôm nay: ${todayDaily.tempMinC.toStringAsFixed(0)}°C - ${todayDaily.tempMaxC.toStringAsFixed(0)}°C',
                              style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 8),
                          ],
                          const Divider(color: Colors.white24, height: 1),
                          const SizedBox(height: 12),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Column(
                                children: [
                                  const Icon(Icons.water_drop_outlined, color: Colors.white70, size: 20),
                                  const SizedBox(height: 4),
                                  const Text('Độ ẩm', style: TextStyle(color: Colors.white70, fontSize: 11)),
                                  Text(
                                    '${current.humidity}%',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ],
                              ),
                              Container(height: 30, width: 0.5, color: Colors.white24),
                              Column(
                                children: [
                                  const Icon(Icons.air, color: Colors.white70, size: 20),
                                  const SizedBox(height: 4),
                                  const Text('Tốc độ gió', style: TextStyle(color: Colors.white70, fontSize: 11)),
                                  Text(
                                    '${current.windSpeedKmH.toStringAsFixed(1)} km/h',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ],
                              ),
                              Container(height: 30, width: 0.5, color: Colors.white24),
                              Column(
                                children: [
                                  const Icon(Icons.my_location, color: Colors.white70, size: 20),
                                  const SizedBox(height: 4),
                                  const Text('Tọa độ', style: TextStyle(color: Colors.white70, fontSize: 11)),
                                  Text(
                                    '${weatherData.latitude.toStringAsFixed(2)}, ${weatherData.longitude.toStringAsFixed(2)}',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // 2. Hourly Forecast Section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Dự báo theo giờ',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),

                        // Mode Selector ChoiceChips
                        Row(
                          children: [
                            ChoiceChip(
                              label: const Text('Còn lại hôm nay', style: TextStyle(fontSize: 10)),
                              selected: _hourlyMode == HourlyMode.restOfToday,
                              selectedColor: AppColors.primary,
                              visualDensity: VisualDensity.compact,
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() {
                                    _hourlyMode = HourlyMode.restOfToday;
                                    _selectedHourIndex = null;
                                  });
                                }
                              },
                            ),
                            const SizedBox(width: 6),
                            ChoiceChip(
                              label: const Text('24 giờ tới', style: TextStyle(fontSize: 10)),
                              selected: _hourlyMode == HourlyMode.next24Hours,
                              selectedColor: AppColors.primary,
                              visualDensity: VisualDensity.compact,
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() {
                                    _hourlyMode = HourlyMode.next24Hours;
                                    _selectedHourIndex = null;
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    if (hourlyList.isNotEmpty) ...[
                      SizedBox(
                        height: 115,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: hourlyList.length,
                          separatorBuilder: (context, index) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final h = hourlyList[index];
                            final hDetails = WmoWeatherCode.getDetails(h.weatherCode, isDay: h.isDay);
                            final isSelected = _selectedHourIndex == index;
                            final isNextDay = _hourlyMode == HourlyMode.next24Hours &&
                                h.time.day != current.dataTime.day;

                            return InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedHourIndex = isSelected ? null : index;
                                });
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: 78,
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? (isDark ? Colors.white24 : Colors.green.shade100)
                                      : (isDark ? Colors.white.withAlpha(15) : Colors.grey.shade100),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected ? AppColors.primary : (isDark ? Colors.white10 : Colors.black12),
                                    width: isSelected ? 1.5 : 1.0,
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      isNextDay ? '${h.time.hour.toString().padLeft(2, '0')}:00 (N.Mai)' : _formatHourLabel(h.time, index),
                                      style: TextStyle(
                                        fontSize: isNextDay ? 9 : 10,
                                        fontWeight: FontWeight.w600,
                                        color: isNextDay ? Colors.orange : (isDark ? Colors.white : Colors.black87),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Icon(hDetails.$2, size: 24, color: AppColors.primary),
                                    Text(
                                      '${h.tempC.toStringAsFixed(0)}°C',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                    if (h.rainProbability > 0)
                                      Text(
                                        '💧${h.rainProbability}%',
                                        style: const TextStyle(fontSize: 9, color: Colors.blue, fontWeight: FontWeight.bold),
                                      )
                                    else
                                      const SizedBox(height: 12),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      // Selected Hourly Details Card
                      if (_selectedHourIndex != null && _selectedHourIndex! < hourlyList.length) ...[
                        const SizedBox(height: 10),
                        () {
                          final h = hourlyList[_selectedHourIndex!];
                          final dayName = _formatDayLabel(h.time, h.time.day == current.dataTime.day ? 0 : 1);
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.black26 : Colors.green.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.primary.withAlpha(100)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Mốc ${_formatHourLabel(h.time, _selectedHourIndex!)} • $dayName',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    Text(
                                      h.conditionText,
                                      style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12, color: AppColors.primary),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    Text('Nhiệt độ: ${h.tempC.toStringAsFixed(1)}°C', style: const TextStyle(fontSize: 11)),
                                    Text('Độ ẩm: ${h.humidity}%', style: const TextStyle(fontSize: 11)),
                                    Text('Gió: ${h.windSpeedKmH.toStringAsFixed(1)} km/h', style: const TextStyle(fontSize: 11)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '🌧️ Lượng mưa dự báo trong 1 giờ: ${h.rainMm > 0 ? "${h.rainMm.toStringAsFixed(1)} mm" : "0 mm (Không mưa)"} (Khả năng mưa: ${h.rainProbability}%)',
                                  style: const TextStyle(fontSize: 11, color: Colors.blue),
                                ),
                              ],
                            ),
                          );
                        }(),
                      ],
                    ] else
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Không có dữ liệu dự báo giờ cho khoảng thời gian này.', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ),

                    const SizedBox(height: 20),

                    // 3. Section Title: 7 Days Forecast
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Dự báo 7 ngày tiếp theo',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        Text(
                          'Chạm để xem chi tiết',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // 7-Day List
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: forecast7Days.length,
                      separatorBuilder: (context, index) => const Divider(height: 10),
                      itemBuilder: (context, index) {
                        final d = forecast7Days[index];
                        final dDetails = WmoWeatherCode.getDetails(d.weatherCode, isDay: true);
                        final isSelected = _selectedDayIndex == index;

                        return InkWell(
                          onTap: () {
                            setState(() {
                              _selectedDayIndex = isSelected ? null : index;
                            });
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? (isDark ? Colors.white10 : Colors.green.shade50)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    SizedBox(
                                      width: 100,
                                      child: Text(
                                        _formatDayLabel(d.date, index + 1),
                                        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                                      ),
                                    ),
                                    Icon(dDetails.$2, size: 22, color: AppColors.primary),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        d.conditionText,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark ? Colors.white70 : Colors.black87,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (d.rainProbabilityMax > 0)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 8),
                                        child: Text(
                                          '💧${d.rainProbabilityMax}%',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.blue,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    Text(
                                      '${d.tempMinC.toStringAsFixed(0)}° - ${d.tempMaxC.toStringAsFixed(0)}°C',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                    Icon(
                                      isSelected ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                      size: 18,
                                      color: Colors.grey,
                                    ),
                                  ],
                                ),

                                // Expanded details for selected day
                                if (isSelected) ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.black26 : Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isDark ? Colors.white12 : Colors.black12,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                                      children: [
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '🌧️ Lượng mưa: ${d.rainSumMm > 0 ? "${d.rainSumMm.toStringAsFixed(1)} mm" : "0 mm (Ít/không mưa)"}',
                                              style: const TextStyle(fontSize: 11),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '💨 Gió cực đại: ${d.windSpeedMaxKmH.toStringAsFixed(1)} km/h',
                                              style: const TextStyle(fontSize: 11),
                                            ),
                                          ],
                                        ),
                                        if (d.sunriseTimeStr != null && d.sunsetTimeStr != null)
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '🌅 Mọc: ${d.sunriseTimeStr}',
                                                style: const TextStyle(fontSize: 11),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '🌇 Lặn: ${d.sunsetTimeStr}',
                                                style: const TextStyle(fontSize: 11),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 20),

                    // Info Container
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.access_time_rounded, size: 16, color: Colors.grey),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  weatherData.isFromCache
                                      ? 'Dữ liệu lưu tạm gần nhất (${_formatTimestamp(weatherData.fetchedTimestamp)})'
                                      : 'Thời điểm tải dữ liệu: ${_formatTimestamp(weatherData.fetchedTimestamp)}',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.verified, size: 16, color: AppColors.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Nguồn dữ liệu chính thức: ${weatherData.attribution} API. Dự báo mang tính tham khảo khu vực.',
                                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
