import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toptop_flutter/features/video_feed/providers/video_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VolumeSync logic tests', () {
    test('Default videoMuteProvider is false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(videoMuteProvider), isFalse);
    });

    test('Muting updates videoMuteProvider to true', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(videoMuteProvider.notifier).state = true;
      expect(container.read(videoMuteProvider), isTrue);
    });

    test('Hardware volume 0 translates to muted', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Simulating event parsing logic: volume == 0 || isMuted == true
      void handleHardwareVolume({required int volume, required bool isMuted}) {
        final muted = isMuted || volume == 0;
        container.read(videoMuteProvider.notifier).state = muted;
      }

      handleHardwareVolume(volume: 0, isMuted: false);
      expect(container.read(videoMuteProvider), isTrue);

      handleHardwareVolume(volume: 8, isMuted: false);
      expect(container.read(videoMuteProvider), isFalse);

      handleHardwareVolume(volume: 12, isMuted: true);
      expect(container.read(videoMuteProvider), isTrue);
    });
  });
}
