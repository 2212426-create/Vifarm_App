import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/weather_model.dart';

class WeatherException implements Exception {
  final String message;
  final String? code;

  WeatherException(this.message, {this.code});

  @override
  String toString() => message;
}

class WeatherRepository {
  final http.Client _client;

  // In-memory cache keyed by prefix + rounded lat,lon string
  final Map<String, WeatherData> _cache = {};
  final Map<String, DateTime> _lastFetchTimes = {};

  static const Duration defaultTtl = Duration(minutes: 20);
  static const Duration minFetchInterval = Duration(seconds: 3);

  WeatherRepository({http.Client? client}) : _client = client ?? http.Client();

  String _getCacheKey(double lat, double lon) {
    return 'openmeteo_v1_${lat.toStringAsFixed(2)},${lon.toStringAsFixed(2)}';
  }

  String _generateRequestId() {
    final rand = Random().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return 'req_$rand';
  }

  /// Get live weather data directly from official Open-Meteo HTTPS API
  Future<WeatherData> getWeather({
    required double latitude,
    required double longitude,
    required String locationName,
    bool forceRefresh = false,
  }) async {
    final key = _getCacheKey(latitude, longitude);
    final now = DateTime.now();
    final reqId = _generateRequestId();

    // 1. Throttle manual refresh requests (minimum 3 seconds)
    final lastFetch = _lastFetchTimes[key];
    if (forceRefresh && lastFetch != null && now.difference(lastFetch) < minFetchInterval) {
      final cached = _cache[key];
      if (cached != null) return cached;
    }

    // 2. Check valid cache if not forcing refresh
    if (!forceRefresh && _cache.containsKey(key)) {
      final cached = _cache[key]!;
      if (now.difference(cached.fetchedTimestamp) < defaultTtl) {
        return cached.copyWith(isFromCache: true, locationName: locationName);
      }
    }

    // 3. Construct HTTPS Uri for Open-Meteo forecast API with current, hourly, and daily forecasts
    final uri = Uri.https(
      'api.open-meteo.com',
      '/v1/forecast',
      {
        'latitude': latitude.toString(),
        'longitude': longitude.toString(),
        'current': 'temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m,is_day',
        'hourly': 'temperature_2m,relative_humidity_2m,precipitation_probability,precipitation,weather_code,wind_speed_10m,is_day',
        'daily': 'weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum,wind_speed_10m_max,sunrise,sunset',
        'timezone': 'auto',
        'forecast_days': '8',
        'temperature_unit': 'celsius',
        'wind_speed_unit': 'kmh',
        'precipitation_unit': 'mm',
      },
    );

    debugPrint('[WeatherDebug] --------------------------------------------------');
    debugPrint('[WeatherDebug] 🕒 Request Start: ${now.toIso8601String()}');
    debugPrint('[WeatherDebug] 🆔 Request ID: $reqId');
    debugPrint('[WeatherDebug] 📍 Location: $locationName (${latitude.toStringAsFixed(2)}, ${longitude.toStringAsFixed(2)})');
    debugPrint('[WeatherDebug] 🌐 Direct HTTPS API: https://api.open-meteo.com/v1/forecast');
    debugPrint('[WeatherDebug] 🛰️ Target Coordinates: lat=${latitude.toStringAsFixed(4)}, lon=${longitude.toStringAsFixed(4)}');

    final stopwatch = Stopwatch()..start();

    try {
      _lastFetchTimes[key] = now;
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      stopwatch.stop();

      debugPrint('[WeatherDebug] 📡 HTTP Status Code: ${response.statusCode}');
      debugPrint('[WeatherDebug] ⏱️ Latency: ${stopwatch.elapsedMilliseconds} ms');
      debugPrint('[WeatherDebug] --------------------------------------------------');

      Map<String, dynamic> bodyJson = {};
      try {
        if (response.body.isNotEmpty) {
          bodyJson = jsonDecode(response.body) as Map<String, dynamic>? ?? {};
        }
      } catch (_) {}

      if (response.statusCode == 200) {
        final data = WeatherData.fromOpenMeteoJson(
          json: bodyJson,
          latitude: latitude,
          longitude: longitude,
          locationName: locationName,
          fetchedTimestamp: now,
          isFromCache: false,
        );

        _cache[key] = data;
        return data;
      } else if (response.statusCode == 429) {
        if (_cache.containsKey(key)) {
          return _cache[key]!.copyWith(isFromCache: true, locationName: locationName);
        }
        throw WeatherException(
          'Hạn mức truy vấn Open-Meteo đã vượt giới hạn. Vui lòng thử lại sau.',
          code: 'RATE_LIMITED',
        );
      } else {
        if (_cache.containsKey(key)) {
          return _cache[key]!.copyWith(isFromCache: true, locationName: locationName);
        }
        throw WeatherException(
          'Không thể kết nối dịch vụ thời tiết Open-Meteo (${response.statusCode})',
          code: 'SERVER_ERROR',
        );
      }
    } on TimeoutException {
      stopwatch.stop();
      debugPrint('[WeatherDebug] ❌ TimeoutException');
      debugPrint('[WeatherDebug] --------------------------------------------------');

      if (_cache.containsKey(key)) {
        return _cache[key]!.copyWith(isFromCache: true, locationName: locationName);
      }
      throw WeatherException(
        'Kết nối dịch vụ thời tiết quá thời gian (Timeout). Vui lòng thử lại.',
        code: 'TIMEOUT',
      );
    } catch (e) {
      stopwatch.stop();
      debugPrint('[WeatherDebug] ❌ Connection Exception: $e');
      debugPrint('[WeatherDebug] --------------------------------------------------');

      if (_cache.containsKey(key)) {
        return _cache[key]!.copyWith(isFromCache: true, locationName: locationName);
      }
      if (e is WeatherException) rethrow;
      throw WeatherException(
        'Không thể kết nối dịch vụ thời tiết Open-Meteo. Vui lòng kiểm tra kết nối mạng.',
        code: 'CONNECTION_FAILED',
      );
    }
  }

  void clearCache() {
    _cache.clear();
    _lastFetchTimes.clear();
  }
}
