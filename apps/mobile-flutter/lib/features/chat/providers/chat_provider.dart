import 'dart:async';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../auth/models/profile_model.dart';
import '../../profile/providers/profile_provider.dart';
import '../models/chat_message_model.dart';
import '../models/notification_model.dart';
import '../repositories/chat_repository.dart';

/// Provider cho ChatRepository
final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(
    firestore: ref.watch(firestoreProvider),
    database: ref.watch(realtimeDbProvider),
  );
});

final chatConnectionProvider = StreamProvider<bool>((ref) {
  return ref
      .watch(realtimeDbProvider)
      .ref('.info/connected')
      .onValue
      .map((event) => event.snapshot.value == true);
});

final groupDetailsProvider = StreamProvider.autoDispose
    .family<Map<String, dynamic>?, String>((ref, groupId) {
      return ref
          .watch(firestoreProvider)
          .collection('chats')
          .doc(groupId)
          .snapshots()
          .map((snapshot) => snapshot.data());
    });

// Chat needs display identity, never the private profile (birthdate, etc.).
final chatProfileProvider = StreamProvider.family<ProfileModel, String>((
  ref,
  uid,
) {
  return ref
      .watch(firestoreProvider)
      .collection('public_profiles')
      .doc(uid)
      .snapshots()
      .map((snapshot) {
        final data = snapshot.data();
        return ProfileModel(
          userId: uid,
          username: data?['username'] as String? ?? 'Người dùng',
          avatarUrl: data?['avatarUrl'] as String? ?? '',
        );
      });
});

/// StreamProvider theo dõi danh sách tin nhắn theo Room ID
final chatMessagesProvider =
    StreamProvider.family<List<ChatMessageModel>, String>((ref, roomId) {
      return ref.watch(chatRepositoryProvider).watchMessages(roomId);
    });

/// StreamProvider cho 1-1 chats từ RTDB
final directChatsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final authState = ref.watch(authStateProvider);
  final currentUid = authState.valueOrNull?.uid;
  if (currentUid == null) return Stream.value([]);
  return ref.watch(chatRepositoryProvider).watchChatList(currentUid);
});

/// StreamProvider cho Group chats từ Firestore
final groupChatsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final authState = ref.watch(authStateProvider);
  final currentUid = authState.valueOrNull?.uid;
  if (currentUid == null) return Stream.value([]);
  return ref.watch(chatRepositoryProvider).watchGroupChats(currentUid);
});

/// StreamProvider tổng hợp cả 1-1 và Group chats
final chatConversationsProvider =
    Provider<AsyncValue<List<Map<String, dynamic>>>>((ref) {
      final direct = ref.watch(directChatsProvider);
      final groups = ref.watch(groupChatsProvider);

      if (direct is AsyncLoading || groups is AsyncLoading) {
        return const AsyncLoading();
      }
      if (direct is AsyncError) {
        return AsyncError(direct.error!, direct.stackTrace ?? StackTrace.empty);
      }
      if (groups is AsyncError) {
        return AsyncError(groups.error!, groups.stackTrace ?? StackTrace.empty);
      }

      final list = <Map<String, dynamic>>[
        ...direct.value ?? [],
        ...groups.value ?? [],
      ];

      // Sắp xếp: 1. Pinned lên đầu, 2. Theo timestamp giảm dần
      list.sort((a, b) {
        final p1 = (a['isPinned'] == true) ? 1 : 0;
        final p2 = (b['isPinned'] == true) ? 1 : 0;
        if (p1 != p2) return p2.compareTo(p1);

        final t1 = a['timestamp'] as int? ?? 0;
        final t2 = b['timestamp'] as int? ?? 0;
        return t2.compareTo(t1);
      });

      return AsyncData(list);
    });

/// StreamProvider theo dõi trạng thái online của một user cụ thể
final userOnlineStatusProvider = StreamProvider.family<bool, String>((
  ref,
  userId,
) {
  return ref.watch(chatRepositoryProvider).watchUserOnlineStatus(userId);
});

/// StreamProvider theo dõi trạng thái "đang nhập" trong một room
/// Key = "$roomId|$otherUserId"
final typingStatusProvider = StreamProvider.family<bool, String>((ref, key) {
  final parts = key.split('|');
  if (parts.length != 2) return Stream.value(false);
  final roomId = parts[0];
  final otherUserId = parts[1];
  return ref.watch(chatRepositoryProvider).watchTyping(roomId, otherUserId);
});

/// StreamProvider theo dõi danh sách thông báo của user hiện tại
final notificationsProvider = StreamProvider<List<NotificationModel>>((ref) {
  final authState = ref.watch(authStateProvider);
  final currentUid = authState.valueOrNull?.uid;

  if (currentUid == null) {
    return Stream.value([]);
  }

  return ref.watch(chatRepositoryProvider).watchNotifications(currentUid);
});

/// Lớp hỗ trợ so sánh sâu danh sách ID để tối ưu hóa Riverpod select
class UserIdsList {
  final List<String> ids;
  UserIdsList(this.ids);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserIdsList &&
          const DeepCollectionEquality().equals(ids, other.ids);

  @override
  int get hashCode => const DeepCollectionEquality().hash(ids);
}

/// Provider trích xuất danh sách User ID từ các cuộc trò chuyện và ngăn chặn rebuild thừa
final chatUserIdsProvider = Provider<List<String>>((ref) {
  final convsAsync = ref.watch(chatConversationsProvider);
  return convsAsync.maybeWhen(
    data: (list) {
      final Set<String> ids = {};
      final currentUid = ref.read(authStateProvider).valueOrNull?.uid;
      for (final c in list) {
        if (c['isGroup'] == true) {
          final members = c['memberIds'] as List<dynamic>? ?? [];
          for (final m in members) {
            if (m is String && m != currentUid) ids.add(m);
          }
        } else {
          final uid = c['userId'] as String?;
          if (uid != null && uid != currentUid) ids.add(uid);
        }
      }
      return ids.toList();
    },
    orElse: () => const <String>[],
  );
});

/// StreamProvider theo dõi danh sách User ID đang Online trong danh sách chat
final activeUsersProvider = StreamProvider<List<String>>((ref) {
  final userIds = ref.watch(chatUserIdsProvider);
  if (userIds.isEmpty) return Stream.value([]);

  final database = ref.watch(realtimeDbProvider);
  final controller = AsyncStreamController<List<String>>();
  final Map<String, bool> onlineStates = {};
  final List<dynamic> subscriptions = [];

  void emitCurrentOnline() {
    final onlineIds = userIds
        .where((uid) => onlineStates[uid] == true)
        .toList();
    if (!controller.isClosed) {
      controller.add(onlineIds);
    }
  }

  for (final uid in userIds) {
    if (uid == 'system_admin') continue;
    final sub = database
        .ref('status')
        .child(uid)
        .child('online')
        .onValue
        .listen(
          (event) {
            final val = event.snapshot.value;
            final bool isOnline;
            if (val is bool) {
              isOnline = val;
            } else if (val is String) {
              isOnline = val.toLowerCase() == 'true';
            } else if (val is num) {
              isOnline = val == 1;
            } else {
              isOnline = false;
            }
            onlineStates[uid] = isOnline;
            emitCurrentOnline();
          },
          onError: (error) {
            debugPrint("Error listening to online status of $uid: $error");
            onlineStates[uid] = false;
            emitCurrentOnline();
          },
        );
    subscriptions.add(sub);
  }

  // Phát tín hiệu ban đầu
  emitCurrentOnline();

  ref.onDispose(() {
    for (final sub in subscriptions) {
      sub.cancel();
    }
    controller.close();
  });

  return controller.stream;
});

/// FutureProvider lấy hồ sơ của tất cả người dùng trong danh sách chat (Inbox)
final inboxProfilesProvider = FutureProvider<List<ProfileModel>>((ref) async {
  final userIds = ref.watch(chatUserIdsProvider);
  final profiles = <ProfileModel>[];

  for (final id in userIds) {
    if (id == 'system_admin') continue;
    try {
      final p = await ref.read(chatProfileProvider(id).future);
      profiles.add(p);
    } catch (_) {}
  }
  return profiles;
});

/// Provider tổng hợp danh sách người dùng có thể thêm vào nhóm (Following + Inbox)
final selectableFriendsProvider = FutureProvider<List<ProfileModel>>((
  ref,
) async {
  final currentUid = ref.watch(authStateProvider).valueOrNull?.uid ?? '';
  if (currentUid.isEmpty) return [];

  // 1. Lấy danh sách Following
  List<ProfileModel> following = [];
  try {
    following = await ref.read(followingFutureProvider(currentUid).future);
  } catch (_) {
    // Inbox contacts remain usable when legacy following profiles are unavailable.
  }

  // 2. Lấy danh sách từ Inbox
  final inbox = await ref.read(inboxProfilesProvider.future);

  // 3. Hợp nhất và loại bỏ trùng lặp dựa trên userId
  final Map<String, ProfileModel> merged = {};
  for (final p in following) {
    merged[p.userId] = p;
  }
  for (final p in inbox) {
    merged[p.userId] = p;
  }

  return merged.values.toList();
});

class AsyncStreamController<T> {
  final _controller = StreamController<T>.broadcast();
  bool get isClosed => _controller.isClosed;
  Stream<T> get stream => _controller.stream;

  void add(T event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  void close() {
    _controller.close();
  }
}

/// Provider quản lý timestamp thời điểm cuối cùng người dùng xem thông báo
final lastReadNotificationTimestampProvider =
    StateNotifierProvider<LastReadTimestampNotifier, int>((ref) {
      return LastReadTimestampNotifier();
    });

class LastReadTimestampNotifier extends StateNotifier<int> {
  LastReadTimestampNotifier() : super(0) {
    _load();
  }

  static const _key = 'last_read_notification_timestamp';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getInt(_key) ?? 0;
    } catch (_) {}
  }

  Future<void> updateTimestamp() async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_key, now);
      state = now;
    } catch (_) {}
  }
}

/// Provider tự động quản lý sự hiện diện (Presence) của người dùng hiện tại
final currentUserPresenceProvider = Provider<void>((ref) {
  final authState = ref.watch(authStateProvider);
  final user = authState.valueOrNull;
  if (user == null) return;

  final database = ref.watch(realtimeDbProvider);
  final chatRepo = ref.watch(chatRepositoryProvider);
  final uid = user.uid;

  // Đặt trạng thái online ban đầu
  chatRepo.updatePresence(uid, true);

  // Lắng nghe tự động trạng thái kết nối mạng của Firebase
  final sub = database
      .ref('.info/connected')
      .onValue
      .listen(
        (event) {
          try {
            final connected = event.snapshot.value as bool? ?? false;
            if (connected) {
              chatRepo.updatePresence(uid, true);
            }
          } catch (e) {
            debugPrint("Error in presence connection listener: $e");
          }
        },
        onError: (e) {
          debugPrint("Presence connection stream error: $e");
        },
      );

  ref.onDispose(() {
    sub.cancel();
    // Đặt trạng thái offline khi người dùng logout hoặc ứng dụng dispose
    chatRepo.updatePresence(uid, false);
  });
});
