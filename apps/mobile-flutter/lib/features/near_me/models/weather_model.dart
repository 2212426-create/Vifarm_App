import 'package:flutter/material.dart';

/// Helper mapping WMO Weather Interpretation Codes to Vietnamese text & Material icons.
class WmoWeatherCode {
  static (String, IconData) getDetails(int code, {bool isDay = true}) {
    switch (code) {
      case 0:
        return (
          isDay ? 'Trời quang' : 'Đêm quang mây',
          isDay ? Icons.wb_sunny : Icons.nights_stay,
        );
      case 1:
        return (
          isDay ? 'Nắng nhẹ' : 'Đêm ít mây',
          isDay ? Icons.wb_sunny_outlined : Icons.nights_stay_outlined,
        );
      case 2:
        return (
          'Mây rải rác',
          isDay ? Icons.cloud_queue : Icons.cloud_outlined,
        );
      case 3:
        return ('Nhiều mây', Icons.cloud);
      case 45:
      case 48:
        return ('Sương mù', Icons.foggy);
      case 51:
      case 53:
      case 55:
        return ('Mưa phun', Icons.grain);
      case 56:
      case 57:
        return ('Mưa phun lạnh', Icons.ac_unit);
      case 61:
        return ('Mưa nhẹ', Icons.water_drop_outlined);
      case 63:
        return ('Mưa vừa', Icons.water_drop);
      case 65:
        return ('Mưa to', Icons.umbrella);
      case 66:
      case 67:
        return ('Mưa băng', Icons.ac_unit);
      case 71:
      case 73:
      case 75:
      case 77:
        return ('Tuyết rơi', Icons.ac_unit);
      case 80:
        return ('Mưa rào nhẹ', Icons.water_drop_outlined);
      case 81:
        return ('Mưa rào vừa', Icons.water_drop);
      case 82:
        return ('Mưa rào rất to', Icons.umbrella);
      case 85:
      case 86:
        return ('Mưa tuyết rào', Icons.ac_unit);
      case 95:
        return ('Mưa dông', Icons.thunderstorm);
      case 96:
      case 99:
        return ('Mưa dông có đá', Icons.thunderstorm);
      default:
        return ('Nhiều mây', Icons.cloud);
    }
  }
}

class CurrentWeather {
  final double tempC;
  final int humidity;
  final double windSpeedKmH;
  final int weatherCode;
  final String conditionText;
  final bool isDay;
  final DateTime dataTime;

  CurrentWeather({
    required this.tempC,
    required this.humidity,
    required this.windSpeedKmH,
    required this.weatherCode,
    required this.conditionText,
    required this.isDay,
    required this.dataTime,
  });

  factory CurrentWeather.fromOpenMeteoJson(Map<String, dynamic> json) {
    final currentMap = json['current'] as Map<String, dynamic>? ?? {};

    final tempC = (currentMap['temperature_2m'] as num?)?.toDouble() ?? 0.0;
    final humidity = (currentMap['relative_humidity_2m'] as num?)?.toInt() ?? 0;
    final windSpeedKmH = (currentMap['wind_speed_10m'] as num?)?.toDouble() ?? 0.0;
    final code = (currentMap['weather_code'] as num?)?.toInt() ?? 0;
    final isDayBool = ((currentMap['is_day'] as num?)?.toInt() ?? 1) == 1;

    final details = WmoWeatherCode.getDetails(code, isDay: isDayBool);

    final timeStr = currentMap['time'] as String?;
    DateTime dataTime;
    if (timeStr != null && timeStr.isNotEmpty) {
      try {
        dataTime = DateTime.parse(timeStr);
      } catch (_) {
        dataTime = DateTime.now();
      }
    } else {
      dataTime = DateTime.now();
    }

    return CurrentWeather(
      tempC: tempC,
      humidity: humidity,
      windSpeedKmH: windSpeedKmH,
      weatherCode: code,
      conditionText: details.$1,
      isDay: isDayBool,
      dataTime: dataTime,
    );
  }
}

class HourlyForecast {
  final String timeIso;
  final DateTime time;
  final double tempC;
  final int humidity;
  final int rainProbability;
  final double rainMm;
  final int weatherCode;
  final String conditionText;
  final double windSpeedKmH;
  final bool isDay;

  HourlyForecast({
    required this.timeIso,
    required this.time,
    required this.tempC,
    required this.humidity,
    required this.rainProbability,
    required this.rainMm,
    required this.weatherCode,
    required this.conditionText,
    required this.windSpeedKmH,
    required this.isDay,
  });

  factory HourlyForecast.fromOpenMeteoArrays({
    required String timeIso,
    required double tempC,
    required int humidity,
    required int rainProbability,
    required double rainMm,
    required int weatherCode,
    required double windSpeedKmH,
    required bool isDay,
  }) {
    DateTime parsedTime;
    try {
      parsedTime = DateTime.parse(timeIso);
    } catch (_) {
      parsedTime = DateTime.now();
    }

    final details = WmoWeatherCode.getDetails(weatherCode, isDay: isDay);

    return HourlyForecast(
      timeIso: timeIso,
      time: parsedTime,
      tempC: tempC,
      humidity: humidity,
      rainProbability: rainProbability,
      rainMm: rainMm,
      weatherCode: weatherCode,
      conditionText: details.$1,
      windSpeedKmH: windSpeedKmH,
      isDay: isDay,
    );
  }
}

class DailyForecast {
  final String dateIso;
  final DateTime date;
  final double tempMinC;
  final double tempMaxC;
  final int rainProbabilityMax;
  final double rainSumMm;
  final double windSpeedMaxKmH;
  final int weatherCode;
  final String conditionText;
  final String? sunriseTimeStr;
  final String? sunsetTimeStr;

  DailyForecast({
    required this.dateIso,
    required this.date,
    required this.tempMinC,
    required this.tempMaxC,
    required this.rainProbabilityMax,
    required this.rainSumMm,
    required this.windSpeedMaxKmH,
    required this.weatherCode,
    required this.conditionText,
    this.sunriseTimeStr,
    this.sunsetTimeStr,
  });

  factory DailyForecast.fromOpenMeteoArrays({
    required String dateIso,
    required double tempMinC,
    required double tempMaxC,
    required int rainProbabilityMax,
    required double rainSumMm,
    required double windSpeedMaxKmH,
    required int weatherCode,
    String? sunriseIso,
    String? sunsetIso,
  }) {
    DateTime parsedDate;
    try {
      parsedDate = DateTime.parse(dateIso);
    } catch (_) {
      parsedDate = DateTime.now();
    }

    final details = WmoWeatherCode.getDetails(weatherCode, isDay: true);

    String? formatIsoTime(String? iso) {
      if (iso == null || iso.isEmpty) return null;
      try {
        final dt = DateTime.parse(iso);
        final h = dt.hour.toString().padLeft(2, '0');
        final m = dt.minute.toString().padLeft(2, '0');
        return '$h:$m';
      } catch (_) {
        return null;
      }
    }

    return DailyForecast(
      dateIso: dateIso,
      date: parsedDate,
      tempMinC: tempMinC,
      tempMaxC: tempMaxC,
      rainProbabilityMax: rainProbabilityMax,
      rainSumMm: rainSumMm,
      windSpeedMaxKmH: windSpeedMaxKmH,
      weatherCode: weatherCode,
      conditionText: details.$1,
      sunriseTimeStr: formatIsoTime(sunriseIso),
      sunsetTimeStr: formatIsoTime(sunsetIso),
    );
  }
}

class WeatherData {
  final double latitude;
  final double longitude;
  final String locationName;
  final CurrentWeather current;
  final List<HourlyForecast> hourly;
  final List<DailyForecast> daily;
  final DateTime fetchedTimestamp;
  final bool isFromCache;
  final String attribution;

  WeatherData({
    required this.latitude,
    required this.longitude,
    required this.locationName,
    required this.current,
    required this.hourly,
    required this.daily,
    required this.fetchedTimestamp,
    this.isFromCache = false,
    this.attribution = 'Open-Meteo',
  });

  factory WeatherData.fromOpenMeteoJson({
    required Map<String, dynamic> json,
    required double latitude,
    required double longitude,
    required String locationName,
    required DateTime fetchedTimestamp,
    bool isFromCache = false,
  }) {
    final currentWeather = CurrentWeather.fromOpenMeteoJson(json);

    // Parse Hourly
    final hourlyList = <HourlyForecast>[];
    final hourlyMap = json['hourly'] as Map<String, dynamic>?;
    if (hourlyMap != null) {
      final times = (hourlyMap['time'] as List?)?.cast<String>() ?? [];
      final temps = (hourlyMap['temperature_2m'] as List?)?.cast<num>() ?? [];
      final humidities = (hourlyMap['relative_humidity_2m'] as List?)?.cast<num>() ?? [];
      final probs = (hourlyMap['precipitation_probability'] as List?)?.cast<num>() ?? [];
      final rains = (hourlyMap['precipitation'] as List?)?.cast<num>() ?? [];
      final codes = (hourlyMap['weather_code'] as List?)?.cast<num>() ?? [];
      final winds = (hourlyMap['wind_speed_10m'] as List?)?.cast<num>() ?? [];
      final days = (hourlyMap['is_day'] as List?)?.cast<num>() ?? [];

      final now = currentWeather.dataTime;
      final cutoff = now.subtract(const Duration(minutes: 45));

      for (int i = 0; i < times.length; i++) {
        try {
          final t = DateTime.parse(times[i]);
          if (t.isAfter(cutoff)) {
            final isDayBool = i < days.length ? (days[i].toInt() == 1) : (t.hour >= 6 && t.hour < 18);
            hourlyList.add(HourlyForecast.fromOpenMeteoArrays(
              timeIso: times[i],
              tempC: i < temps.length ? temps[i].toDouble() : 0.0,
              humidity: i < humidities.length ? humidities[i].toInt() : 0,
              rainProbability: i < probs.length ? probs[i].toInt() : 0,
              rainMm: i < rains.length ? rains[i].toDouble() : 0.0,
              weatherCode: i < codes.length ? codes[i].toInt() : 0,
              windSpeedKmH: i < winds.length ? winds[i].toDouble() : 0.0,
              isDay: isDayBool,
            ));
          }
        } catch (_) {}
      }
    }

    // Parse Daily
    final dailyList = <DailyForecast>[];
    final dailyMap = json['daily'] as Map<String, dynamic>?;
    if (dailyMap != null) {
      final times = (dailyMap['time'] as List?)?.cast<String>() ?? [];
      final minTemps = (dailyMap['temperature_2m_min'] as List?)?.cast<num>() ?? [];
      final maxTemps = (dailyMap['temperature_2m_max'] as List?)?.cast<num>() ?? [];
      final probs = (dailyMap['precipitation_probability_max'] as List?)?.cast<num>() ?? [];
      final sums = (dailyMap['precipitation_sum'] as List?)?.cast<num>() ?? [];
      final winds = (dailyMap['wind_speed_10m_max'] as List?)?.cast<num>() ?? [];
      final codes = (dailyMap['weather_code'] as List?)?.cast<num>() ?? [];
      final sunrises = (dailyMap['sunrise'] as List?)?.cast<String>() ?? [];
      final sunsets = (dailyMap['sunset'] as List?)?.cast<String>() ?? [];

      for (int i = 0; i < times.length && i < 8; i++) {
        dailyList.add(DailyForecast.fromOpenMeteoArrays(
          dateIso: times[i],
          tempMinC: i < minTemps.length ? minTemps[i].toDouble() : 0.0,
          tempMaxC: i < maxTemps.length ? maxTemps[i].toDouble() : 0.0,
          rainProbabilityMax: i < probs.length ? probs[i].toInt() : 0,
          rainSumMm: i < sums.length ? sums[i].toDouble() : 0.0,
          windSpeedMaxKmH: i < winds.length ? winds[i].toDouble() : 0.0,
          weatherCode: i < codes.length ? codes[i].toInt() : 0,
          sunriseIso: i < sunrises.length ? sunrises[i] : null,
          sunsetIso: i < sunsets.length ? sunsets[i] : null,
        ));
      }
    }

    return WeatherData(
      latitude: latitude,
      longitude: longitude,
      locationName: locationName,
      current: currentWeather,
      hourly: hourlyList,
      daily: dailyList,
      fetchedTimestamp: fetchedTimestamp,
      isFromCache: isFromCache,
    );
  }

  WeatherData copyWith({
    bool? isFromCache,
    String? locationName,
  }) {
    return WeatherData(
      latitude: latitude,
      longitude: longitude,
      locationName: locationName ?? this.locationName,
      current: current,
      hourly: hourly,
      daily: daily,
      fetchedTimestamp: fetchedTimestamp,
      isFromCache: isFromCache ?? this.isFromCache,
      attribution: attribution,
    );
  }
}
