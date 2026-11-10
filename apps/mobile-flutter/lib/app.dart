import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/providers/firebase_providers.dart';
import 'core/providers/theme_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/chat/providers/chat_provider.dart';
import 'features/video_feed/services/volume_sync_service.dart';

/// Widget gốc của ứng dụng ViFarm
/// Cấu hình Material 3 theme, GoRouter, và quản lý Presence người dùng
class ViFarmApp extends ConsumerStatefulWidget {
  const ViFarmApp({super.key});

  @override
  ConsumerState<ViFarmApp> createState() => _ViFarmAppState();
}

class _ViFarmAppState extends ConsumerState<ViFarmApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final currentUid = ref.read(authStateProvider).valueOrNull?.uid;
      if (currentUid == null) return;

      final chatRepo = ref.read(chatRepositoryProvider);
      if (state == AppLifecycleState.resumed) {
        chatRepo.updatePresence(currentUid, true);
      } else if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.inactive ||
          state == AppLifecycleState.detached) {
        chatRepo.updatePresence(currentUid, false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeNotifierProvider);

    // Kích hoạt tự động Presence & Kết nối (Riverpod tự động hủy subscription cũ khi logout)
    ref.watch(currentUserPresenceProvider);
    ref.watch(volumeSyncServiceProvider);

    return MaterialApp.router(
      title: 'ViFarm',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        if (!kIsWeb || child == null) return child ?? const SizedBox.shrink();

        return ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
