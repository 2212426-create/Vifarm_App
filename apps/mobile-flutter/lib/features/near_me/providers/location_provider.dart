import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

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
];

class NearMeLocationState {
  final bool isGps;
  final double latitude;
  final double longitude;
  final String regionName;
  final String displayName;
  final String? errorMessage;
  final bool isLoadingGps;

  const NearMeLocationState({
    required this.isGps,
    required this.latitude,
    required this.longitude,
    required this.regionName,
    required this.displayName,
    this.errorMessage,
    this.isLoadingGps = false,
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
    );
  }
}

class NearMeLocationNotifier extends StateNotifier<NearMeLocationState> {
  NearMeLocationNotifier()
      : super(const NearMeLocationState(
          isGps: false,
          latitude: 11.5753,
          longitude: 108.1429,
          regionName: 'Lâm Đồng',
          displayName: 'Lâm Đồng',
        ));

  void selectPresetRegion(String name) {
    final found = defaultPresetRegions.firstWhere(
      (r) => r.name == name,
      orElse: () => defaultPresetRegions.first,
    );
    state = state.copyWith(
      isGps: false,
      latitude: found.latitude,
      longitude: found.longitude,
      regionName: found.name,
      displayName: found.name,
      errorMessage: null,
      isLoadingGps: false,
    );
  }

  Future<bool> enableGps() async {
    state = state.copyWith(isLoadingGps: true, errorMessage: null);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        state = state.copyWith(
          isLoadingGps: false,
          errorMessage: 'GPS đang tắt. Vui lòng bật định vị trên thiết bị.',
        );
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
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
          errorMessage: 'Quyền vị trí bị từ chối vĩnh viễn. Vui lòng bật trong Cài đặt.',
        );
        return false;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );

      final displayStr = 'Vị trí hiện tại (${position.latitude.toStringAsFixed(2)}, ${position.longitude.toStringAsFixed(2)})';
      
      state = NearMeLocationState(
        isGps: true,
        latitude: position.latitude,
        longitude: position.longitude,
        regionName: 'Vị trí hiện tại',
        displayName: displayStr,
        isLoadingGps: false,
      );
      return true;
    } catch (e) {
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
