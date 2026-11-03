import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:toptop_flutter/features/near_me/models/weather_model.dart';
import 'package:toptop_flutter/features/near_me/providers/location_provider.dart';
import 'package:toptop_flutter/features/near_me/repositories/weather_repository.dart';

void main() {
  group('WmoWeatherCode Mapping Tests', () {
    test('maps WMO codes to correct Vietnamese text and icons', () {
      final clearDay = WmoWeatherCode.getDetails(0, isDay: true);
      expect(clearDay.$1, equals('Trời quang'));

      final clearNight = WmoWeatherCode.getDetails(0, isDay: false);
      expect(clearNight.$1, equals('Đêm quang mây'));

      final scattered = WmoWeatherCode.getDetails(2);
      expect(scattered.$1, equals('Mây rải rác'));

      final rain = WmoWeatherCode.getDetails(63);
      expect(rain.$1, equals('Mưa vừa'));

      final thunderstorm = WmoWeatherCode.getDetails(95);
      expect(thunderstorm.$1, equals('Mưa dông'));

      final unknown = WmoWeatherCode.getDetails(999);
      expect(unknown.$1, equals('Nhiều mây'));
    });
  });

  group('Open-Meteo JSON Parsing & Units Tests', () {
    test('parses Open-Meteo current weather JSON correctly without unit double-conversion', () {
      final sampleOpenMeteoJson = {
        'latitude': 11.5753,
        'longitude': 108.1429,
        'timezone': 'Asia/Ho_Chi_Minh',
        'current': {
          'time': '2026-10-21T14:00',
          'temperature_2m': 24.5,
          'relative_humidity_2m': 68,
          'apparent_temperature': 25.0,
          'precipitation': 0.0,
          'weather_code': 2,
          'wind_speed_10m': 8.5,
          'is_day': 1,
        },
      };

      final now = DateTime.now();
      final weather = WeatherData.fromOpenMeteoJson(
        json: sampleOpenMeteoJson,
        latitude: 11.5753,
        longitude: 108.1429,
        locationName: 'Lâm Đồng',
        fetchedTimestamp: now,
      );

      expect(weather.locationName, equals('Lâm Đồng'));
      expect(weather.latitude, equals(11.5753));
      expect(weather.longitude, equals(108.1429));

      expect(weather.current.tempC, equals(24.5));
      expect(weather.current.humidity, equals(68));
      expect(weather.current.windSpeedKmH, equals(8.5));
      expect(weather.current.conditionText, equals('Mây rải rác'));
      expect(weather.current.isDay, isTrue);
      expect(weather.current.dataTime, equals(DateTime.parse('2026-10-21T14:00')));
    });
  });

  group('Open-Meteo Hourly Forecast Parsing Tests', () {
    test('zips hourly arrays into HourlyForecast list and filters past hours', () {
      final sampleJson = {
        'latitude': 11.5753,
        'longitude': 108.1429,
        'current': {
          'time': '2026-10-21T14:00',
          'temperature_2m': 24.5,
          'relative_humidity_2m': 68,
          'weather_code': 2,
          'wind_speed_10m': 8.5,
          'is_day': 1,
        },
        'hourly': {
          'time': ['2026-10-21T10:00', '2026-10-21T14:00', '2026-10-21T15:00'],
          'temperature_2m': [22.0, 24.5, 25.1],
          'relative_humidity_2m': [80, 68, 65],
          'precipitation_probability': [0, 10, 20],
          'precipitation': [0.0, 0.0, 0.2],
          'weather_code': [0, 2, 61],
          'wind_speed_10m': [5.0, 8.5, 9.0],
          'is_day': [1, 1, 1],
        },
      };

      final weather = WeatherData.fromOpenMeteoJson(
        json: sampleJson,
        latitude: 11.5753,
        longitude: 108.1429,
        locationName: 'Lâm Đồng',
        fetchedTimestamp: DateTime.now(),
      );

      // Past hour 10:00 should be filtered out relative to current time 14:00
      expect(weather.hourly.length, equals(2));
      expect(weather.hourly[0].timeIso, equals('2026-10-21T14:00'));
      expect(weather.hourly[0].tempC, equals(24.5));
      expect(weather.hourly[1].timeIso, equals('2026-10-21T15:00'));
      expect(weather.hourly[1].tempC, equals(25.1));
      expect(weather.hourly[1].rainProbability, equals(20));
      expect(weather.hourly[1].rainMm, equals(0.2));
      expect(weather.hourly[1].conditionText, equals('Mưa nhẹ'));
    });
  });

  group('Open-Meteo 7-Day Forecast Parsing Tests', () {
    test('zips daily arrays into DailyForecast list accurately', () {
      final sampleJson = {
        'latitude': 11.5753,
        'longitude': 108.1429,
        'current': {
          'time': '2026-10-21T14:00',
          'temperature_2m': 24.5,
          'relative_humidity_2m': 68,
          'weather_code': 2,
          'wind_speed_10m': 8.5,
          'is_day': 1,
        },
        'daily': {
          'time': ['2026-10-21', '2026-10-22', '2026-10-23', '2026-10-24', '2026-10-25', '2026-10-26', '2026-10-27', '2026-10-28'],
          'weather_code': [2, 61, 3, 0, 1, 80, 2, 63],
          'temperature_2m_max': [26.5, 25.0, 24.8, 27.2, 26.0, 25.5, 26.2, 24.0],
          'temperature_2m_min': [18.2, 17.5, 18.0, 17.0, 18.2, 17.8, 18.1, 17.2],
          'precipitation_probability_max': [30, 60, 40, 10, 20, 50, 30, 70],
          'precipitation_sum': [0.5, 3.2, 1.0, 0.0, 0.0, 2.1, 0.4, 6.5],
          'wind_speed_10m_max': [12.5, 15.0, 10.2, 8.5, 11.0, 14.2, 9.8, 16.5],
          'sunrise': ['2026-10-21T05:45', '2026-10-22T05:45'],
          'sunset': ['2026-10-21T17:48', '2026-10-22T17:48'],
        },
      };

      final weather = WeatherData.fromOpenMeteoJson(
        json: sampleJson,
        latitude: 11.5753,
        longitude: 108.1429,
        locationName: 'Lâm Đồng',
        fetchedTimestamp: DateTime.now(),
      );

      expect(weather.daily.length, equals(8));
      final today = weather.daily[0];
      expect(today.tempMinC, equals(18.2));
      expect(today.tempMaxC, equals(26.5));
      expect(today.rainProbabilityMax, equals(30));
      expect(today.rainSumMm, equals(0.5));
      expect(today.sunriseTimeStr, equals('05:45'));
      expect(today.sunsetTimeStr, equals('17:48'));

      final tomorrow = weather.daily[1];
      expect(tomorrow.dateIso, equals('2026-10-22'));
      expect(tomorrow.tempMinC, equals(17.5));
      expect(tomorrow.tempMaxC, equals(25.0));
      expect(tomorrow.rainProbabilityMax, equals(60));
      expect(tomorrow.rainSumMm, equals(3.2));
      expect(tomorrow.conditionText, equals('Mưa nhẹ'));
    });
  });

  group('WeatherRepository Direct Open-Meteo HTTPS Tests', () {
    test('fetches live weather from Open-Meteo HTTPS API and uses cache on second request', () async {
      int callCount = 0;
      final mockClient = MockClient((request) async {
        callCount++;
        expect(request.url.host, equals('api.open-meteo.com'));
        expect(request.url.path, equals('/v1/forecast'));
        expect(request.url.queryParameters['temperature_unit'], equals('celsius'));
        expect(request.url.queryParameters['wind_speed_unit'], equals('kmh'));
        expect(request.url.queryParameters['forecast_days'], equals('8'));

        return http.Response(
          jsonEncode({
            'latitude': 11.5753,
            'longitude': 108.1429,
            'current': {
              'time': '2026-10-21T14:00',
              'temperature_2m': 24.5,
              'relative_humidity_2m': 68,
              'weather_code': 0,
              'wind_speed_10m': 8.5,
              'is_day': 1,
            },
          }),
          200,
        );
      });

      final repo = WeatherRepository(client: mockClient);

      // First call -> Direct HTTPS network call
      final data1 = await repo.getWeather(
        latitude: 11.5753,
        longitude: 108.1429,
        locationName: 'Lâm Đồng',
      );

      expect(callCount, equals(1));
      expect(data1.isFromCache, isFalse);
      expect(data1.current.tempC, equals(24.5));
      expect(data1.current.windSpeedKmH, equals(8.5));
      expect(data1.attribution, equals('Open-Meteo'));

      // Second call without forceRefresh -> Cache hit
      final data2 = await repo.getWeather(
        latitude: 11.5753,
        longitude: 108.1429,
        locationName: 'Lâm Đồng',
      );

      expect(callCount, equals(1));
      expect(data2.isFromCache, isTrue);
    });
  });

  group('NearMeLocationNotifier Tests', () {
    test('selects preset region correctly', () {
      final notifier = NearMeLocationNotifier();
      expect(notifier.state.regionName, equals('Lâm Đồng'));
      expect(notifier.state.isGps, isFalse);

      notifier.selectPresetRegion('Cần Thơ');

      expect(notifier.state.regionName, equals('Cần Thơ'));
      expect(notifier.state.latitude, equals(10.0452));
      expect(notifier.state.longitude, equals(105.7469));
      expect(notifier.state.isGps, isFalse);
    });
  });
}
