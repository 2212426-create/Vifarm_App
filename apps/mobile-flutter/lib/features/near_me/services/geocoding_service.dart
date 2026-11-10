import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class GeocodedAddress {
  final String fullAddress;
  final String region;
  final String city;
  final String? road;
  final double latitude;
  final double longitude;

  const GeocodedAddress({
    required this.fullAddress,
    required this.region,
    required this.city,
    this.road,
    required this.latitude,
    required this.longitude,
  });
}

/// Chuyển đổi tọa độ GPS thành địa chỉ thực tế (reverse geocoding)
/// Ưu tiên OpenStreetMap Nominatim, dự phòng BigDataCloud API.
Future<GeocodedAddress?> reverseGeocode(
  double lat,
  double lon, {
  http.Client? client,
}) async {
  if (!lat.isFinite || !lon.isFinite || lat.abs() > 90 || lon.abs() > 180) {
    return null;
  }

  final httpClient = client ?? http.Client();
  final shouldClose = client == null;

  try {
    // 1. OpenStreetMap Nominatim (tiếng Việt, chi tiết tới cấp đường/phường)
    final uri = Uri.parse(
      'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lon&addressdetails=1',
    );
    final response = await httpClient
        .get(uri, headers: {'User-Agent': 'ViFarm-App/1.0'})
        .timeout(const Duration(seconds: 4));

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final address = data['address'] as Map<String, dynamic>? ?? {};

      final state = address['state']?.toString().replaceAll('Tỉnh ', '').trim() ?? 'Lâm Đồng';
      final city = address['city']?.toString() ??
          address['town']?.toString() ??
          address['suburb']?.toString() ??
          '';
      final road = address['road']?.toString();
      final suburb = address['suburb']?.toString();
      final neighbourhood = address['neighbourhood']?.toString();

      final parts = <String>[];
      if (road != null && road.isNotEmpty) parts.add(road);
      if (neighbourhood != null && neighbourhood.isNotEmpty && !parts.contains(neighbourhood)) {
        parts.add(neighbourhood);
      }
      if (suburb != null && suburb.isNotEmpty && !parts.contains(suburb)) {
        parts.add(suburb);
      }
      if (city.isNotEmpty && !parts.contains(city)) parts.add(city);
      if (state.isNotEmpty && !parts.contains(state)) parts.add(state);

      final cleanAddress = parts.isNotEmpty
          ? parts.join(', ')
          : (data['display_name']?.toString() ?? '');

      if (cleanAddress.isNotEmpty) {
        return GeocodedAddress(
          fullAddress: cleanAddress,
          region: state,
          city: city,
          road: road,
          latitude: lat,
          longitude: lon,
        );
      }
    }
  } catch (e) {
    debugPrint('Nominatim geocode failed ($e), falling back to BigDataCloud');
  }

  try {
    // 2. Dự phòng: BigDataCloud Reverse Geocoding
    final bdcUri = Uri.parse(
      'https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=$lat&longitude=$lon&localityLanguage=vi',
    );
    final bdcRes = await httpClient.get(bdcUri).timeout(const Duration(seconds: 4));
    if (bdcRes.statusCode == 200) {
      final data = jsonDecode(utf8.decode(bdcRes.bodyBytes)) as Map<String, dynamic>;
      final state = data['principalSubdivision']?.toString().replaceAll('Tỉnh ', '').trim() ?? 'Lâm Đồng';
      final city = data['city']?.toString() ?? data['locality']?.toString() ?? '';

      final parts = <String>[];
      if (city.isNotEmpty) parts.add(city);
      if (state.isNotEmpty && !parts.contains(state)) parts.add(state);

      final full = parts.isNotEmpty ? parts.join(', ') : state;
      return GeocodedAddress(
        fullAddress: full,
        region: state,
        city: city,
        latitude: lat,
        longitude: lon,
      );
    }
  } catch (e) {
    debugPrint('BigDataCloud geocode failed: $e');
  } finally {
    if (shouldClose) httpClient.close();
  }

  return null;
}
