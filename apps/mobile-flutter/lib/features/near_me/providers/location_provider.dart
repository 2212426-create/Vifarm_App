import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../services/geocoding_service.dart';

class PresetRegion {
  final String name;
  final double latitude;
  final double longitude;

  const PresetRegion(this.name, this.latitude, this.longitude);
}

const List<PresetRegion> defaultPresetRegions = [
  PresetRegion('Lâm Đồng', 11.5753, 108.1429),
  PresetRegion('Đắc Lắk', 12.6667, 108.0500),
  PresetRegion('Gia Lai', 13.9833, 108.0000),
  PresetRegion('Đồng Nai', 10.9574, 106.8427),
  PresetRegion('Cần Thơ', 10.0452, 105.7469),
  PresetRegion('Hà Nội', 21.0285, 105.8542),
  PresetRegion('TP. Hồ Chí Minh', 10.8231, 106.6297),
  if (kDebugMode)
    PresetRegion('Bến Thành (test)', 10.7725, 106.6980),
];

class NearMeLocationState {
  final bool isGps;
  final double latitude;
  final double longitude;
  final String regionName;
  final String displayName;
  final String? errorMessage;
  final bool isLoadingGps;
  final double? accuracyMeters;
  final DateTime? measuredAt;
  final bool isMocked;

  const NearMeLocationState({
    required this.isGps,
    required this.latitude,
    required this.longitude,
    required this.regionName,
    required this.displayName,
    this.errorMessage,
    this.isLoadingGps = false,
    this.accuracyMeters,
    this.measuredAt,
    this.isMocked = false,
  });

  NearMeLocationState copyWith({
    bool? isGps,
    double? latitude,
    double? longitude,
    String? regionName,
    String? displayName,
    String? errorMessage,
    bool? isLoadingGps,
  }) {
    return NearMeLocationState(
      isGps: isGps ?? this.isGps,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      regionName: regionName ?? this.regionName,
      displayName: displayName ?? this.displayName,
      errorMessage: errorMessage,
      isLoadingGps: isLoadingGps ?? this.isLoadingGps,
      accuracyMeters: accuracyMeters,
      measuredAt: measuredAt,
      isMocked: isMocked,
    );
  }
}

class NearMeLocationNotifier extends StateNotifier<NearMeLocationState> {
  int _request = 0;
  NearMeLocationNotifier()
    : super(
        const NearMeLocationState(
          isGps: false,
          latitude: 11.5753,
          longitude: 108.1429,
          regionName: 'Lâm Đồng',
          displayName: 'Lâm Đồng (chọn tay)',
        ),
      );

  void selectPresetRegion(String name) {
    _request++;
    final found = defaultPresetRegions.firstWhere(
      (r) => r.name == name,
      orElse: () => defaultPresetRegions.first,
    );
    state = NearMeLocationState(
      isGps: false,
      latitude: found.latitude,
      longitude: found.longitude,
      regionName: found.name,
      displayName: '${found.name} (chọn tay)',
      errorMessage: null,
      isLoadingGps: false,
    );
  }

  Future<bool> enableGps() async {
    final request = ++_request;
    state = state.copyWith(isLoadingGps: true, errorMessage: null);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!mounted || request != _request) return false;
      if (!serviceEnabled) {
        state = state.copyWith(
          isLoadingGps: false,
          errorMessage: 'GPS đang tắt. Vui lòng bật định vị trên thiết bị.',
        );
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (!mounted || request != _request) return false;
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (!mounted || request != _request) return false;
        if (permission == LocationPermission.denied) {
          state = state.copyWith(
            isLoadingGps: false,
            errorMessage: 'Quyền vị trí bị từ chối.',
          );
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        state = state.copyWith(
          isLoadingGps: false,
          errorMessage:
              'Quyền vị trí bị từ chối vĩnh viễn. Vui lòng bật trong Cài đặt.',
        );
        return false;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted || request != _request) return false;
      final age = DateTime.now().difference(position.timestamp);
      if (!position.latitude.isFinite ||
          !position.longitude.isFinite ||
          position.latitude.abs() > 90 ||
          position.longitude.abs() > 180 ||
          !position.accuracy.isFinite ||
          position.accuracy <= 0 ||
          position.accuracy > 1000 ||
          age > const Duration(minutes: 2) ||
          age < const Duration(minutes: -1)) {
        state = state.copyWith(
          isLoadingGps: false,
          errorMessage:
              'Vị trí GPS cũ hoặc sai số quá lớn. Hãy thử lại ở nơi thoáng.',
        );
        return false;
      }

            String displayStr =
          '${position.isMocked ? "Vị trí giả lập" : "GPS"} '
          '(${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}) '
          '±${position.accuracy.round()} m';
      String regionName = 'Vị trí hiện tại';

      try {
        final geocoded = await reverseGeocode(position.latitude, position.longitude);
        if (geocoded != null) {
          if (geocoded.region.isNotEmpty) {
            regionName = geocoded.region;
          }
          displayStr = '${geocoded.fullAddress} (±${position.accuracy.round()}m)';
        }
      } catch (err) {
        debugPrint('Geocoding lookup error: $err');
      }

      state = NearMeLocationState(
        isGps: true,
        latitude: position.latitude,
        longitude: position.longitude,
        regionName: regionName,
        displayName: displayStr,
        isLoadingGps: false,
        accuracyMeters: position.accuracy,
        measuredAt: position.timestamp,
        isMocked: position.isMocked,
      );
      return true;
    } catch (e) {
      if (!mounted || request != _request) return false;
      state = state.copyWith(
        isLoadingGps: false,
        errorMessage: 'Không thể lấy vị trí GPS. Đã giữ khu vực hiện tại.',
      );
      return false;
    }
  }

  void resetToManualDefault() {
    selectPresetRegion('Lâm Đồng');
  }
}

final nearMeLocationProvider =
    StateNotifierProvider<NearMeLocationNotifier, NearMeLocationState>((ref) {
      return NearMeLocationNotifier();
    });
