import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'package:toptop_flutter/features/auth/providers/auth_provider.dart';
import 'package:toptop_flutter/features/auth/layouts/auth_choice_screen.dart';
import 'package:toptop_flutter/features/auth/layouts/login_screen.dart';
import 'package:toptop_flutter/features/auth/layouts/signup_screen.dart';
import 'package:toptop_flutter/features/auth/layouts/splash_screen.dart';
import 'package:toptop_flutter/features/cart/layouts/cart_screen.dart';
import 'package:toptop_flutter/features/chat/layouts/inbox_screen.dart';
import 'package:toptop_flutter/features/chat/layouts/chat_screen.dart';
import 'package:toptop_flutter/features/chat/layouts/group_chat_screen.dart';
import 'package:toptop_flutter/features/chat/layouts/group_settings_screen.dart';
import 'package:toptop_flutter/features/chat/layouts/group_management_screen.dart';
import 'package:toptop_flutter/features/chat/layouts/notifications_screen.dart';
import 'package:toptop_flutter/features/chat/layouts/shared_video_player_screen.dart';
import 'package:toptop_flutter/features/farm_journal/layouts/create_journal_entry_screen.dart';
import 'package:toptop_flutter/features/farm_journal/layouts/create_journal_screen.dart';
import 'package:toptop_flutter/features/farm_journal/layouts/edit_journal_entry_screen.dart';
import 'package:toptop_flutter/features/farm_journal/layouts/edit_journal_screen.dart';
import 'package:toptop_flutter/features/farm_journal/layouts/journal_detail_screen.dart';
import 'package:toptop_flutter/features/hashtags/layouts/hashtag_screen.dart';
import 'package:toptop_flutter/features/near_me/layouts/near_me_screen.dart';
import 'package:toptop_flutter/features/orders/layouts/checkout_screen.dart';
import 'package:toptop_flutter/features/orders/layouts/order_detail_screen.dart';
import 'package:toptop_flutter/features/orders/layouts/orders_screen.dart';
import 'package:toptop_flutter/features/products/layouts/edit_product_screen.dart';
import 'package:toptop_flutter/features/products/layouts/marketplace_screen.dart';
import 'package:toptop_flutter/features/products/layouts/product_detail_screen.dart';
import 'package:toptop_flutter/features/profile/layouts/profile_screen.dart';
import 'package:toptop_flutter/features/profile/layouts/edit_profile_screen.dart';
import 'package:toptop_flutter/features/profile/layouts/edit_field_screen.dart';
import 'package:toptop_flutter/features/profile/layouts/follow_list_screen.dart';
import 'package:toptop_flutter/features/store/layouts/admin_store_review_screen.dart';
import 'package:toptop_flutter/features/quote_requests/layouts/quote_requests_screen.dart';
import 'package:toptop_flutter/features/saved_techniques/layouts/saved_techniques_screen.dart';
import 'package:toptop_flutter/features/settings/layouts/settings_screen.dart';
import 'package:toptop_flutter/features/settings/layouts/account_settings_screen.dart';
import 'package:toptop_flutter/features/settings/layouts/change_password_screen.dart';
import 'package:toptop_flutter/features/settings/layouts/delete_account_screen.dart';
import 'package:toptop_flutter/features/settings/layouts/appearance_screen.dart';
import 'package:toptop_flutter/features/search/layouts/search_screen.dart';
import 'package:toptop_flutter/features/store/layouts/public_store_screen.dart';
import 'package:toptop_flutter/features/store/layouts/seller_orders_screen.dart';
import 'package:toptop_flutter/features/store/layouts/seller_overview_screen.dart';
import 'package:toptop_flutter/features/store/layouts/seller_products_screen.dart';
import 'package:toptop_flutter/features/store/layouts/seller_store_settings_screen.dart';
import 'package:toptop_flutter/features/store/layouts/store_registration_screen.dart';
import 'package:toptop_flutter/features/video_feed/layouts/video_feed_screen.dart';
import 'package:toptop_flutter/features/video_feed/layouts/single_video_screen.dart';
import 'package:toptop_flutter/features/video_upload/layouts/camera_screen.dart';
import 'package:toptop_flutter/features/video_upload/layouts/video_description_screen.dart';
import 'package:toptop_flutter/shared/widgets/bottom_nav_shell.dart';
import 'package:toptop_flutter/shared/widgets/seller_bottom_nav_shell.dart';

/// Notifier giúp GoRouter refresh mà không phải tái tạo lại instance toàn cục
class RouterNotifier extends ChangeNotifier {
  final Ref _ref;

  RouterNotifier(this._ref) {
    _ref.listen(authStateProvider, (_, __) => notifyListeners());
  }
}

final routerNotifierProvider = Provider<RouterNotifier>((ref) {
  return RouterNotifier(ref);
});

/// Cấu hình GoRouter đa chế độ (Normal Buyer Shell vs Seller Workspace Shell)
final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(routerNotifierProvider);

  CustomTransitionPage<void> buildSlidePage({
    required LocalKey key,
    required Widget child,
  }) {
    return CustomTransitionPage<void>(
      key: key,
      child: child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          ),
          child: child,
        );
      },
    );
  }

  return GoRouter(
    refreshListenable: notifier,
    initialLocation: '/home',
    debugLogDiagnostics: true,

    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final isLoggedIn = authState.valueOrNull != null;
      final isLoading = authState.isLoading;
      final currentPath = state.uri.path;

      if (currentPath == '/') return null; // Giữ nguyên '/' để SplashScreen thực thi animation
      if (isLoading) return null;

      final isAuthRoute = currentPath.startsWith('/auth');

      final isAllowedGuestRoute =
          isAuthRoute ||
          currentPath == '/home' ||
          currentPath == '/near-me' ||
          currentPath == '/marketplace' ||
          currentPath == '/search' ||
          currentPath.startsWith('/hashtag/') ||
          currentPath.startsWith('/store/') ||
          currentPath.startsWith('/marketplace/products/') ||
          currentPath.startsWith('/journal/') ||
          currentPath.startsWith('/video/') ||
          currentPath.startsWith('/user/');

      if (!isLoggedIn && !isAllowedGuestRoute) {
        return '/auth';
      }

      if (isLoggedIn && isAuthRoute) {
        return '/home';
      }

      return null;
    },

    routes: [
      GoRoute(path: '/', builder: (context, state) => const SplashScreen()),

      GoRoute(
        path: '/auth',
        builder: (context, state) => const AuthChoiceScreen(),
        routes: [
          GoRoute(
            path: 'login',
            builder: (context, state) => const LoginScreen(),
          ),
          GoRoute(
            path: 'signup',
            builder: (context, state) => const SignupScreen(),
          ),
        ],
      ),

      // 1. Normal Mode Bottom Navigation Shell
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return BottomNavShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const VideoFeedScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/near-me',
                builder: (context, state) => const NearMeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/marketplace',
                builder: (context, state) => const MarketplaceScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/my-farm',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),

      // 2. Seller Mode Bottom Navigation Shell
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return SellerBottomNavShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/seller/overview',
                builder: (context, state) => const SellerOverviewScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/seller/products',
                builder: (context, state) => const SellerProductsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/seller/orders',
                builder: (context, state) => const SellerOrdersScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/seller/messages',
                builder: (context, state) => const InboxScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/seller/store',
                builder: (context, state) => const SellerStoreSettingsScreen(),
              ),
            ],
          ),
        ],
      ),

      // Fullscreen App Routes
      GoRoute(
        path: '/hashtag/:tag',
        builder: (context, state) {
          final tag = state.pathParameters['tag'] ?? '';
          return HashtagScreen(tag: tag);
        },
      ),

      GoRoute(
        path: '/store/register',
        builder: (context, state) => const StoreRegistrationScreen(),
      ),

      GoRoute(
        path: '/store/:storeId',
        builder: (context, state) {
          final sId = state.pathParameters['storeId'] ?? '';
          return PublicStoreScreen(storeId: sId);
        },
      ),

      GoRoute(
        path: '/search',
        builder: (context, state) => const SearchScreen(),
      ),

      GoRoute(
        path: '/inbox',
        builder: (context, state) => const InboxScreen(),
      ),

      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),

      GoRoute(
        path: '/saved-techniques',
        builder: (context, state) => const SavedTechniquesScreen(),
      ),

      GoRoute(
        path: '/journal/create',
        builder: (context, state) => const CreateJournalScreen(),
      ),

      GoRoute(
        path: '/journal/:journalId',
        builder: (context, state) {
          final jId = state.pathParameters['journalId'] ?? '';
          return JournalDetailScreen(journalId: jId);
        },
      ),

      GoRoute(
        path: '/journal/:journalId/edit',
        builder: (context, state) {
          final jId = state.pathParameters['journalId'] ?? '';
          return EditJournalScreen(journalId: jId);
        },
      ),

      GoRoute(
        path: '/journal/:journalId/entry/create',
        builder: (context, state) {
          final jId = state.pathParameters['journalId'] ?? '';
          return CreateJournalEntryScreen(journalId: jId);
        },
      ),

      GoRoute(
        path: '/journal/:journalId/entry/:entryId/edit',
        builder: (context, state) {
          final jId = state.pathParameters['journalId'] ?? '';
          final eId = state.pathParameters['entryId'] ?? '';
          return EditJournalEntryScreen(journalId: jId, entryId: eId);
        },
      ),

      GoRoute(
        path: '/admin/stores',
        builder: (context, state) => const AdminStoreListScreen(),
      ),

      GoRoute(
        path: '/admin/store/:storeId/review',
        builder: (context, state) {
          final sId = state.pathParameters['storeId'] ?? '';
          return AdminStoreReviewDetailScreen(storeId: sId);
        },
      ),

      GoRoute(
        path: '/marketplace/products/create',
        builder: (context, state) => const EditProductScreen(),
      ),

      GoRoute(
        path: '/marketplace/products/edit/:productId',
        builder: (context, state) {
          final pId = state.pathParameters['productId'] ?? '';
          return EditProductScreen(productId: pId);
        },
      ),

      GoRoute(
        path: '/marketplace/products/:productId',
        builder: (context, state) {
          final pId = state.pathParameters['productId'] ?? '';
          return ProductDetailScreen(productId: pId);
        },
      ),

      GoRoute(
        path: '/cart',
        builder: (context, state) => const CartScreen(),
      ),

      GoRoute(
        path: '/checkout',
        builder: (context, state) => const CheckoutScreen(),
      ),

      GoRoute(
        path: '/orders',
        builder: (context, state) => const OrdersScreen(),
      ),

      GoRoute(
        path: '/orders/:orderId',
        builder: (context, state) {
          final oId = state.pathParameters['orderId'] ?? '';
          return OrderDetailScreen(orderId: oId);
        },
      ),

      GoRoute(
        path: '/quote-requests',
        builder: (context, state) => const QuoteRequestsScreen(),
      ),

      GoRoute(
        path: '/camera',
        pageBuilder: (context, state) => CustomTransitionPage(
          child: const CameraScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1.0, 0.0),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeInOut),
              ),
              child: child,
            );
          },
        ),
      ),

      GoRoute(
        path: '/video/description',
        builder: (context, state) {
          final videoId = state.uri.queryParameters['videoId'];
          return VideoDescriptionScreen(
            videoFile: state.extra is XFile ? state.extra as XFile : null,
            videoId: videoId,
          );
        },
      ),

      GoRoute(
        path: '/video/:videoId',
        builder: (context, state) {
          final videoId = state.pathParameters['videoId'] ?? '';
          final showComments = state.uri.queryParameters['showComments'] == 'true';
          return SingleVideoScreen(
            videoId: videoId,
            showComments: showComments,
          );
        },
      ),

      GoRoute(
        path: '/user/:userId',
        pageBuilder: (context, state) {
          final userId = state.pathParameters['userId'] ?? '';
          return buildSlidePage(
            key: state.pageKey,
            child: ProfileScreen(userId: userId),
          );
        },
      ),

      GoRoute(
        path: '/user/:userId/followers',
        pageBuilder: (context, state) {
          final userId = state.pathParameters['userId'] ?? '';
          return buildSlidePage(
            key: state.pageKey,
            child: FollowListScreen(userId: userId, initialTabIndex: 1),
          );
        },
      ),

      GoRoute(
        path: '/user/:userId/following',
        pageBuilder: (context, state) {
          final userId = state.pathParameters['userId'] ?? '';
          return buildSlidePage(
            key: state.pageKey,
            child: FollowListScreen(userId: userId, initialTabIndex: 0),
          );
        },
      ),

      GoRoute(
        path: '/profile/edit',
        pageBuilder: (context, state) => buildSlidePage(
          key: state.pageKey,
          child: const EditProfileScreen(),
        ),
      ),

      GoRoute(
        path: '/profile/edit/:field',
        pageBuilder: (context, state) {
          final field = state.pathParameters['field'] ?? '';
          return buildSlidePage(
            key: state.pageKey,
            child: EditFieldScreen(field: field),
          );
        },
      ),

      GoRoute(
        path: '/chat/:receiverId',
        pageBuilder: (context, state) {
          final receiverId = state.pathParameters['receiverId'] ?? '';
          final name = state.uri.queryParameters['name'] ?? '';
          final avatar = state.uri.queryParameters['avatar'] ?? '';
          return buildSlidePage(
            key: state.pageKey,
            child: ChatScreen(
              receiverId: receiverId,
              receiverName: name,
              receiverAvatar: avatar,
            ),
          );
        },
      ),

      GoRoute(
        path: '/groupchat/:groupId',
        pageBuilder: (context, state) {
          final groupId = state.pathParameters['groupId'] ?? '';
          final name = state.uri.queryParameters['name'] ?? 'Nhóm';
          return buildSlidePage(
            key: state.pageKey,
            child: GroupChatScreen(
              groupId: groupId,
              groupName: name,
            ),
          );
        },
      ),

      GoRoute(
        path: '/group-settings/:groupId',
        pageBuilder: (context, state) {
          final groupId = state.pathParameters['groupId'] ?? '';
          return buildSlidePage(
            key: state.pageKey,
            child: GroupSettingsScreen(groupId: groupId),
          );
        },
      ),

      GoRoute(
        path: '/group-management/:groupId',
        pageBuilder: (context, state) {
          final groupId = state.pathParameters['groupId'] ?? '';
          return buildSlidePage(
            key: state.pageKey,
            child: GroupManagementScreen(groupId: groupId),
          );
        },
      ),

      GoRoute(
        path: '/notifications',
        pageBuilder: (context, state) => buildSlidePage(
          key: state.pageKey,
          child: const NotificationsScreen(),
        ),
      ),

      GoRoute(
        path: '/shared-videos/:roomId',
        builder: (context, state) {
          final roomId = state.pathParameters['roomId'] ?? '';
          final videoId = state.uri.queryParameters['videoId'] ?? '';
          return SharedVideoPlayerScreen(
            roomId: roomId,
            initialVideoId: videoId,
          );
        },
      ),

      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) => buildSlidePage(
          key: state.pageKey,
          child: const SettingsScreen(),
        ),
        routes: [
          GoRoute(
            path: 'account',
            pageBuilder: (context, state) => buildSlidePage(
              key: state.pageKey,
              child: const AccountSettingsScreen(),
            ),
          ),
          GoRoute(
            path: 'password',
            pageBuilder: (context, state) => buildSlidePage(
              key: state.pageKey,
              child: const ChangePasswordScreen(),
            ),
          ),
          GoRoute(
            path: 'delete-account',
            pageBuilder: (context, state) => buildSlidePage(
              key: state.pageKey,
              child: const DeleteAccountScreen(),
            ),
          ),
          GoRoute(
            path: 'appearance',
            pageBuilder: (context, state) => buildSlidePage(
              key: state.pageKey,
              child: const AppearanceScreen(),
            ),
          ),
        ],
      ),
    ],

    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Không tìm thấy trang: ${state.uri.path}'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.go('/home'),
              child: const Text('Về trang chủ'),
            ),
          ],
        ),
      ),
    ),
  );
});
