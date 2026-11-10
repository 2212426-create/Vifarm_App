import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../auth/providers/auth_provider.dart';
import '../models/video_model.dart';
import '../providers/video_provider.dart';

/// Trạng thái hoạt ảnh trái tim khi double tap
class FloatingHeart {
  final UniqueKey key;
  final Offset position;
  final double rotation;

  FloatingHeart({
    required this.key,
    required this.position,
    required this.rotation,
  });
}

/// Widget phát Video chính, xử lý vòng đời của VideoPlayerController,
/// cử chỉ tap/double-tap, và phát tự động qua VisibilityDetector.
class VideoPlayerWidget extends ConsumerStatefulWidget {
  final VideoModel video;
  /// Nếu true, tự khởi tạo và phát ngay khi widget mount (dùng cho SingleVideoScreen)
  final bool autoPlay;

  const VideoPlayerWidget({
    super.key,
    required this.video,
    this.autoPlay = false,
  });

  @override
  ConsumerState<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends ConsumerState<VideoPlayerWidget>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _controller;
  bool _isVisible = false;
  bool _hasLoggedWatch = false;
  bool _hasLoggedComplete = false;
  DateTime? _startTime;
  final List<FloatingHeart> _hearts = [];

  @override
  void initState() {
    super.initState();
    // Lazy preload: Khởi tạo và buffer trước controller ngay khi item được widget tree nạp
    _initController();
    if (widget.autoPlay) {
      _isVisible = true;
    }
  }

  void _initController() {
    if (_controller != null) return;

    var uriString = widget.video.videoUri;
    if (uriString.contains('10.0.2.2')) {
      uriString = uriString.replaceAll('10.0.2.2', '127.0.0.1');
    }

    _controller = VideoPlayerController.networkUrl(
      Uri.parse(uriString),
    );
    _controller!.initialize().then((_) {
      if (mounted) {
        _controller!.setLooping(true);
        final isMuted = ref.read(videoMuteProvider);
        _controller!.setVolume(isMuted ? 0 : 1);
        
        if (_isVisible) {
          _controller!.play();
          _startTime = DateTime.now();
          _trackWatch();
        }
        setState(() {});
      }
    }).catchError((err) {
      debugPrint('[VideoPlayerWidget] init error for ${widget.video.videoId}: $err');
    });
  }

  void _disposeController() {
    if (_controller != null) {
      _controller!.dispose();
      _controller = null;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _trackWatch() {
    if (_hasLoggedWatch) return;
    _hasLoggedWatch = true;

    final repo = ref.read(videoRepositoryProvider);

    repo.incrementWatchCount(
      videoId: widget.video.videoId,
      authorId: widget.video.authorId,
    );

    final isDalatCampaign = widget.video.location == 'Da Lat' ||
        widget.video.hashtags.any((tag) => const ['dalat', 'dalatdulich', 'khamphadalat']
            .contains(tag.toLowerCase().replaceAll('#', '')));
    if (isDalatCampaign) {
      repo.recordCampaignView(widget.video.videoId);
    }
  }

  void _checkWatchProgress() {
    if (_controller == null || !mounted || !_isVisible) return;

    final duration = _controller!.value.duration;
    final position = _controller!.value.position;
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    if (_startTime != null) {
      final elapsed = DateTime.now().difference(_startTime!).inSeconds;
      if (elapsed >= 3) {
        final repo = ref.read(videoRepositoryProvider);
        repo.markVideoAsWatched(user.uid, widget.video.videoId);

        repo.logRecSysInteraction(
          userId: user.uid,
          videoId: widget.video.videoId,
          playTimeMs: elapsed * 1000,
          isLike: false,
        );

        repo.recordInterest(
          tags: widget.video.hashtags,
          currentUid: user.uid,
          weight: 1,
        );
        _startTime = null;
      }
    }

    if (duration.inMilliseconds > 0 && !_hasLoggedComplete) {
      final progress = position.inMilliseconds / duration.inMilliseconds;
      if (progress >= 0.9) {
        _hasLoggedComplete = true;
        final repo = ref.read(videoRepositoryProvider);
        repo.recordInterest(
          tags: widget.video.hashtags,
          currentUid: user.uid,
          weight: 2,
        );
      }
    }
  }

  void _handleTap() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
      } else {
        _controller!.play();
      }
    });
  }

  void _handleDoubleTap(Offset localPosition) {
    HapticFeedback.mediumImpact();

    final randomAngle = (math.Random().nextDouble() * 40 - 20) * math.pi / 180;
    final newHeart = FloatingHeart(
      key: UniqueKey(),
      position: localPosition,
      rotation: randomAngle,
    );

    setState(() {
      _hearts.add(newHeart);
    });

    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) {
        setState(() {
          _hearts.removeWhere((heart) => heart.key == newHeart.key);
        });
      }
    });

    _likeVideoIfNotAlready();
  }

  Future<void> _likeVideoIfNotAlready() async {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;

    final likesState = ref.read(videoLikesStateProvider(widget.video.videoId)).valueOrNull;
    final likedUsers = likesState?['users'] as Map<String, dynamic>? ?? {};
    final isAlreadyLiked = likedUsers[currentUser.uid] == true;

    if (!isAlreadyLiked) {
      final userProfile = ref.read(currentUserProfileProvider).valueOrNull;
      final username = userProfile?.username ?? currentUser.email?.split('@')[0] ?? '';
      await ref.read(videoRepositoryProvider).toggleLike(
            videoId: widget.video.videoId,
            authorId: widget.video.authorId,
            currentUid: currentUser.uid,
            isLiked: true,
            currentUsername: username,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMuted = ref.watch(videoMuteProvider);
    if (_controller != null && _controller!.value.isInitialized) {
      _controller!.setVolume(isMuted ? 0 : 1);
    }

    final hasController = _controller != null && _controller!.value.isInitialized;

    return VisibilityDetector(
      key: Key('video_vis_${widget.video.videoId}'),
      onVisibilityChanged: (info) {
        if (!mounted) return;

        if (widget.autoPlay) return;

        final visible = info.visibleFraction > 0.5;
        if (visible != _isVisible) {
          _isVisible = visible;
          if (_isVisible) {
            if (_controller == null) {
              _initController();
            } else if (_controller!.value.isInitialized) {
              _controller!.play();
              _startTime = DateTime.now();
              _trackWatch();
            }
          } else {
            if (_controller != null && _controller!.value.isInitialized) {
              _controller!.pause();
              _checkWatchProgress();
            }
          }
        }

// Controller được giữ buffer để vuốt lại phát ngay; giải phóng trong dispose()
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Trình phát Video
          GestureDetector(
            onTap: _handleTap,
            onDoubleTapDown: (details) => _handleDoubleTap(details.localPosition),
            child: hasController
                ? Center(
                    child: AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio,
                      child: VideoPlayer(_controller!),
                    ),
                  )
                : Container(
                    color: Colors.black,
                    child: const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                      ),
                    ),
                  ),
          ),

          // Hiển thị icon Pause/Play ở giữa màn hình nếu đang tạm dừng thủ công
          // Dùng IgnorePointer để sự kiện chạm xuyên trực tiếp xuống GestureDetector phía dưới
          if (hasController && !_controller!.value.isPlaying)
            Align(
              alignment: Alignment.center,
              child: IgnorePointer(
                child: Semantics(
                  label: 'Phát video',
                  button: true,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Colors.black45,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow,
                      size: 50,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),

          // Hiển thị vòng xoay tải nếu video đang buffer
          if (hasController && _controller!.value.isBuffering)
            const Align(
              alignment: Alignment.center,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
              ),
            ),

          // Thanh tiến trình phát ở cuối video
          if (hasController)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: VideoProgressIndicator(
                _controller!,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: Colors.white70,
                  bufferedColor: Colors.white10,
                  backgroundColor: Colors.transparent,
                ),
              ),
            ),

          // Hoạt ảnh trái tim khi Double Tap
          ..._hearts.map((heart) {
            return Positioned(
              left: heart.position.dx - 50,
              top: heart.position.dy - 50,
              child: RepaintBoundary(
                child: TweenAnimationBuilder<double>(
                  key: heart.key,
                  duration: const Duration(milliseconds: 700),
                  tween: Tween<double>(begin: 0.0, end: 1.0),
                  builder: (context, value, child) {
                    double scale = 1.0;
                    double opacity = 1.0;
                    double translateUp = 0.0;

                    if (value < 0.3) {
                      scale = (value / 0.3) * 1.3;
                      opacity = value / 0.3;
                    } else {
                      scale = 1.3 - ((value - 0.3) / 0.7) * 0.5;
                      opacity = 1.0 - (value - 0.3) / 0.7;
                      translateUp = ((value - 0.3) / 0.7) * -120;
                    }

                    return Opacity(
                      opacity: opacity.clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, translateUp),
                        child: Transform.rotate(
                          angle: heart.rotation * (value * 1.5),
                          child: Transform.scale(
                            scale: scale.clamp(0.0, 2.0),
                            child: const Icon(
                              Icons.favorite,
                              size: 100,
                              color: Color(0xFFFE2C55),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
