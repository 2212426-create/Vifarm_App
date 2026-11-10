import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:toptop_flutter/features/near_me/providers/location_provider.dart';

class FakeGps extends GeolocatorPlatform {
  bool enabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  final position = Completer<Position>();
  LocationSettings? settings;
  @override
  Future<bool> isLocationServiceEnabled() async => enabled;
  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) {
    settings = locationSettings;
    return position.future;
  }
}

Position fix({double accuracy = 5, DateTime? time}) => Position(
  latitude: 10.8231,
  longitude: 106.6297,
  timestamp: time ?? DateTime.now(),
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
  isMocked: true,
);

void main() {
  late GeolocatorPlatform original;
  late FakeGps gps;
  late NearMeLocationNotifier notifier;
  setUp(() {
    original = GeolocatorPlatform.instance;
    gps = FakeGps();
    GeolocatorPlatform.instance = gps;
    notifier = NearMeLocationNotifier();
  });
  tearDown(() {
    notifier.dispose();
    GeolocatorPlatform.instance = original;
  });

  test('GPS coordinates retain precision, accuracy and mock label', () async {
    gps.position.complete(fix());
    expect(await notifier.enableGps(), true);
    expect(notifier.state.latitude, 10.8231);
    expect(notifier.state.longitude, 106.6297);
    expect(notifier.state.accuracyMeters, 5);
    expect(notifier.state.displayName, contains('±5m'));
    expect(gps.settings!.accuracy, LocationAccuracy.high);
  });
  test('a stale GPS result cannot replace a manual selection', () async {
    final pending = notifier.enableGps();
    await Future<void>.delayed(Duration.zero);
    notifier.selectPresetRegion('Cần Thơ');
    gps.position.complete(fix());
    expect(await pending, false);
    expect(notifier.state.regionName, 'Cần Thơ');
    expect(notifier.state.isGps, false);
  });
  test(
    'old and imprecise fixes are rejected instead of called current GPS',
    () async {
      gps.position.complete(
        fix(
          accuracy: 2000,
          time: DateTime.now().subtract(const Duration(minutes: 10)),
        ),
      );
      expect(await notifier.enableGps(), false);
      expect(notifier.state.isGps, false);
      expect(notifier.state.errorMessage, isNotNull);
    },
  );
  test('disabled GPS preserves the manually selected location', () async {
    gps.enabled = false;
    notifier.selectPresetRegion('Hà Nội');
    expect(await notifier.enableGps(), false);
    expect(notifier.state.latitude, 21.0285);
  });
}
