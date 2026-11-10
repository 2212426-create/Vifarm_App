import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/video_provider.dart';

/// Service đồng bộ trạng thái loa/âm lượng của thiết bị với UI ViFarm
class VolumeSyncService with WidgetsBindingObserver {
  static const MethodChannel _channel = MethodChannel('vifarm/volume_channel');
  static const EventChannel _eventChannel =
      EventChannel('vifarm/volume_events');

  final Ref _ref;
  StreamSubscription? _subscription;
  bool _initialized = false;

  VolumeSyncService(this._ref);

  void init() {
    if (_initialized) return;
    _initialized = true;

    WidgetsBinding.instance.addObserver(this);

    if (kIsWeb) return;

    // 1. Kiểm tra âm lượng hiện tại khi khởi động
    checkVolume();

    // 2. Lắng nghe sự kiện thay đổi âm lượng phần cứng từ máy
    try {
      _subscription = _eventChannel.receiveBroadcastStream().listen(
        (dynamic event) {
          if (event is Map) {
            final isMuted = event['isMuted'] as bool? ?? false;
            final volume = (event['volume'] as num?)?.toInt() ?? 0;
            final muted = isMuted || volume == 0;
            _ref.read(videoMuteProvider.notifier).state = muted;
          }
        },
        onError: (err) {
          debugPrint('[VolumeSyncService] EventChannel error: $err');
        },
      );
    } catch (e) {
      debugPrint('[VolumeSyncService] Could not listen to volume events: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        checkVolume();
      });
    }
  }

  Future<void> checkVolume() async {
    if (kIsWeb) return;
    try {
      final res = await _channel.invokeMethod<Map>('getVolume');
      if (res != null) {
        final isMuted = res['isMuted'] as bool? ?? false;
        final volume = (res['volume'] as num?)?.toInt() ?? 0;
        final muted = isMuted || volume == 0;
        _ref.read(videoMuteProvider.notifier).state = muted;
      }
    } catch (e) {
      debugPrint('[VolumeSyncService] getVolume error: $e');
    }
  }

  Future<void> setMute(bool mute) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('setMute', {'mute': mute});
      await checkVolume();
    } catch (e) {
      debugPrint('[VolumeSyncService] setMute error: $e');
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _subscription = null;
    _initialized = false;
  }
}

final volumeSyncServiceProvider = Provider<VolumeSyncService>((ref) {
  final service = VolumeSyncService(ref);
  service.init();
  ref.onDispose(() => service.dispose());
  return service;
});
