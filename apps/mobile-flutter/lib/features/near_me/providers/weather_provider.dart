import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/weather_model.dart';
import '../repositories/weather_repository.dart';
import 'location_provider.dart';

final weatherRepositoryProvider = Provider<WeatherRepository>((ref) {
  return WeatherRepository();
});

class WeatherNotifier extends StateNotifier<AsyncValue<WeatherData>> {
  final WeatherRepository _repository;
  final NearMeLocationState _locationState;

  WeatherNotifier(this._repository, this._locationState)
      : super(const AsyncValue.loading()) {
    fetchWeather();
  }

  Future<void> fetchWeather({bool forceRefresh = false}) async {
    if (forceRefresh && state.hasValue) {
      // Maintain previous value while loading background refresh
    } else {
      state = const AsyncValue.loading();
    }

    try {
      final data = await _repository.getWeather(
        latitude: _locationState.latitude,
        longitude: _locationState.longitude,
        locationName: _locationState.displayName,
        forceRefresh: forceRefresh,
      );
      if (mounted) {
        state = AsyncValue.data(data);
      }
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }
}

final weatherNotifierProvider =
    StateNotifierProvider.autoDispose<WeatherNotifier, AsyncValue<WeatherData>>((ref) {
  final repo = ref.watch(weatherRepositoryProvider);
  final location = ref.watch(nearMeLocationProvider);
  return WeatherNotifier(repo, location);
});
