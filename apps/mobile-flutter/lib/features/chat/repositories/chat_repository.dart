import 'group_chat_repository.dart';
// ignore_for_file: prefer_initializing_formals

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import '../models/chat_message_model.dart';
import '../models/notification_model.dart';

/// Repository quản lý Chat, Presence & Notifications trên Realtime Database & Firestore
/// Port từ ChatActivity.java, InboxFragment.java, InboxActivity.java và GlobalVariable.java
class ChatRepository {
  final FirebaseFirestore _firestore;
  final FirebaseDatabase _database;

  ChatRepository({
    required FirebaseFirestore firestore,
    required FirebaseDatabase database,
  }) : _firestore = firestore,
       _database = database;

  /// Tạo Room ID duy nhất từ hai user ID (sắp xếp tăng dần theo bảng chữ cái)
  String getRoomId(String id1, String id2) {
    return (id1.compareTo(id2) < 0) ? '${id1}_$id2' : '${id2}_$id1';
  }

  /// Gửi tin nhắn với type và metadata tùy chọn
  Future<void> sendMessage({
    required String senderId,
    required String receiverId,
    required String message,
    String type = 'text',
    Map<String, dynamic>? metadata,
  }) async {
    try {
      // Native listeners can emit an initial false before the current state.
      // Timeout only this read, never an enqueued write (which may commit later).
      await _database
          .ref('.info/connected')
          .onValue
          .firstWhere((event) => event.snapshot.value == true)
          .timeout(const Duration(seconds: 3));
      if (senderId == receiverId ||
          message.trim().isEmpty ||
          message.length > 4000) {
        throw ArgumentError('Tin nhắn hoặc người nhận không hợp lệ.');
      }
      final timestamp = ServerValue.timestamp;
      final roomId = getRoomId(senderId, receiverId);
      final members = [senderId, receiverId]..sort();
      // Immutable membership is checked independently of message content.
      await _database.ref('ChatMembers/$roomId').set({
        'first': members[0],
        'second': members[1],
      });

      // 1. Đẩy tin nhắn vào node Chats/{roomId}
      final messagesRef = _database.ref('Chats').child(roomId);
      final msgKey = messagesRef.push().key;
      if (msgKey == null) throw StateError('Không tạo được mã tin nhắn.');

      final Map<String, dynamic> msgData = {
        'senderId': senderId,
        'receiverId': receiverId,
        'message': message,
        'timestamp': timestamp,
        'type': type,
        'metadata': metadata,
      };

      // Chuẩn bị cập nhật đa điểm (multi-path updates)
      final Map<String, dynamic> updates = {};

      // Ghi tin nhắn
      updates['/Chats/$roomId/$msgKey'] = msgData;

      // Cập nhật ChatList cho người gửi
      final senderPreview = {
        'id': receiverId,
        'lastMessage': message,
        'lastMessageType': type,
        'timestamp': timestamp,
        'roomId': roomId,
        'messageId': msgKey,
      };

      // Cập nhật ChatList cho người nhận
      final receiverPreview = {
        'id': senderId,
        'lastMessage': message,
        'lastMessageType': type,
        'timestamp': timestamp,
        'roomId': roomId,
        'messageId': msgKey,
      };
      // Update fields so receiving a message does not reset a user's pin.
      for (final field in senderPreview.entries) {
        updates['/ChatList/$senderId/$receiverId/${field.key}'] = field.value;
      }
      for (final field in receiverPreview.entries) {
        updates['/ChatList/$receiverId/$senderId/${field.key}'] = field.value;
      }

      // Thực hiện cập nhật đồng thời
      await _database.ref().update(updates);

      // Cross-user notifications must be created by a trusted backend.
    } catch (e) {
      debugPrint("Firebase Database send message error: $e");
      rethrow;
    }
  }

  /// Gửi tin nhắn chia sẻ video (type: video_share) với metadata đầy đủ
  Future<void> sendVideoShare({
    required String senderId,
    required String receiverId,
    required String videoId,
    String? caption,
    bool isGroup = false,
    Map<String, dynamic>? videoMeta,
  }) async {
    final messageText = caption != null && caption.isNotEmpty
        ? caption
        : 'Đã chia sẻ một video';

    if (isGroup) {
      await GroupChatRepository(_firestore).send(
        groupId: receiverId,
        senderId: senderId,
        text: messageText,
        type: 'video_share',
        metadata: {...?videoMeta, 'videoId': videoId},
      );
    } else {
      // Gửi vào Realtime Database cho 1-1
      await sendMessage(
        senderId: senderId,
        receiverId: receiverId,
        message: messageText,
        type: 'video_share',
        metadata: {'videoId': videoId, ...?videoMeta},
      );
    }
  }

  /// Stream danh sách tin nhắn trong một cuộc trò chuyện
  Stream<List<ChatMessageModel>> watchMessages(String roomId) {
    if (roomId.trim().isEmpty) {
      return Stream.value([]);
    }
    return _database.ref('Chats').child(roomId).onValue.map((event) {
      final snapshot = event.snapshot;
      if (!snapshot.exists || snapshot.value == null) {
        return [];
      }

      final List<ChatMessageModel> messages = [];
      try {
        final data = snapshot.value as Map<dynamic, dynamic>;
        data.forEach((key, val) {
          if (val is Map) {
            messages.add(ChatMessageModel.fromMap(val, id: key.toString()));
          }
        });
      } catch (e) {
        debugPrint("Error parsing messages: $e");
      }

      // Sắp xếp theo timestamp tăng dần để hiển thị từ cũ đến mới
      messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return messages;
    });
  }

  /// Stream danh sách cuộc trò chuyện của một user từ Realtime Database
  Stream<List<Map<String, dynamic>>> watchChatList(String userId) {
    if (userId.trim().isEmpty) {
      return Stream.value([]);
    }
    return _database.ref('ChatList').child(userId).onValue.map((event) {
      final snapshot = event.snapshot;
      if (!snapshot.exists || snapshot.value == null) {
        return [];
      }

      final List<Map<String, dynamic>> list = [];
      try {
        final data = snapshot.value as Map<dynamic, dynamic>;
        data.forEach((key, val) {
          if (val is Map) {
            final timestampVal = val['timestamp'] ?? val['lastTimestamp'] ?? 0;
            final int timestamp = timestampVal is num
                ? timestampVal.toInt()
                : (int.tryParse(timestampVal.toString()) ?? 0);

            list.add({
              'userId': key.toString(),
              'lastMessage': val['lastMessage'] as String? ?? '',
              'timestamp': timestamp,
              'isPinned': val['isPinned'] ?? false,
            });
          }
        });
      } catch (e) {
        debugPrint("Error parsing chat list: $e");
      }

      // Sắp xếp cuộc trò chuyện có tin nhắn mới nhất lên đầu
      list.sort((a, b) => b['timestamp'].compareTo(a['timestamp']));
      return list;
    });
  }

  /// Stream danh sách các nhóm chat từ Firestore mà user tham gia
  Stream<List<Map<String, dynamic>>> watchGroupChats(String userId) {
    return _firestore
        .collection('chats')
        .where('isGroup', isEqualTo: true)
        .where('memberIds', arrayContains: userId)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data();
            final lastMsgAt = data['lastMessageAt'] as Timestamp?;
            return {
              'chatId': doc.id,
              'title': data['groupName'] ?? 'Nhóm',
              'avatarUrl': data['avatarUrl'] ?? '',
              'lastMessage': data['lastMessage'] ?? '',
              'timestamp': lastMsgAt?.millisecondsSinceEpoch ?? 0,
              'isGroup': true,
              'closed': data['closed'] == true,
              'isPinned': (data['pinnedBy'] as Map?)?[userId] == true,
              'memberIds': List<String>.from(data['memberIds'] ?? []),
            };
          }).toList();
        });
  }

  /// Cập nhật trạng thái hoạt động (presence) của user hiện tại
  Future<void> updatePresence(String userId, bool online) async {
    if (userId.trim().isEmpty) return;
    try {
      final statusRef = _database.ref('status').child(userId);

      final Map<String, dynamic> offlineStatus = {
        'online': false,
        'lastActive': ServerValue.timestamp,
      };

      if (online) {
        final Map<String, dynamic> onlineStatus = {
          'online': true,
          'lastActive': ServerValue.timestamp,
        };

        // Tự động set offline khi ngắt kết nối
        await statusRef.onDisconnect().set(offlineStatus);
        await statusRef.set(onlineStatus);
      } else {
        await statusRef.set(offlineStatus);
      }
    } catch (e) {
      // Log lỗi và bỏ qua để tránh gây crash app khi Firebase chưa được cấp quyền đầy đủ
      debugPrint("Firebase Database presence error: $e");
    }
  }

  /// Khởi tạo listener tự động đồng bộ kết nối mạng
  void setupPresenceAutomation(String userId) {
    if (userId.trim().isEmpty) return;
    // Theo dõi trạng thái kết nối mạng của Firebase
    _database
        .ref('.info/connected')
        .onValue
        .listen(
          (event) {
            try {
              final connected = event.snapshot.value as bool? ?? false;
              if (connected) {
                updatePresence(userId, true);
              }
            } catch (e) {
              debugPrint("Error in presence connection listener: $e");
            }
          },
          onError: (e) {
            debugPrint("Presence connection stream error: $e");
          },
        );
  }

  /// Stream kiểm tra online status của một user cụ thể
  Stream<bool> watchUserOnlineStatus(String userId) {
    if (userId.trim().isEmpty) {
      return Stream.value(false);
    }
    return _database.ref('status').child(userId).child('online').onValue.map((
      event,
    ) {
      final val = event.snapshot.value;
      if (val is bool) return val;
      if (val is String) return val.toLowerCase() == 'true';
      if (val is num) return val == 1;
      return false;
    });
  }

  /// Stream danh sách thông báo của user từ Realtime Database
  Stream<List<NotificationModel>> watchNotifications(String userId) {
    if (userId.trim().isEmpty) {
      return Stream.value([]);
    }
    return _database.ref('Notifications').child(userId).onValue.map((event) {
      final snapshot = event.snapshot;
      if (!snapshot.exists || snapshot.value == null) {
        return [];
      }

      final List<NotificationModel> list = [];
      try {
        final data = snapshot.value as Map<dynamic, dynamic>;
        data.forEach((key, val) {
          if (val is Map) {
            list.add(NotificationModel.fromMap(val, id: key.toString()));
          }
        });
      } catch (e) {
        debugPrint("Error parsing notifications: $e");
      }

      // Sắp xếp thông báo mới nhất lên đầu
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return list;
    });
  }

  // ============================================================
  // TYPING INDICATOR
  // ============================================================

  /// Cập nhật trạng thái đang nhập của user trong room
  Future<void> setTyping({
    required String roomId,
    required String userId,
    required bool isTyping,
  }) async {
    try {
      final ref = _database.ref('typing/$roomId/$userId');
      if (isTyping) {
        await ref.set({'isTyping': true, 'timestamp': ServerValue.timestamp});
      } else {
        await ref.remove();
      }
    } catch (e) {
      debugPrint('setTyping error: $e');
    }
  }

  /// Stream theo dõi trạng thái đang nhập của người khác trong room
  Stream<bool> watchTyping(String roomId, String otherUserId) {
    if (roomId.isEmpty || otherUserId.isEmpty) return Stream.value(false);
    return _database.ref('typing/$roomId/$otherUserId/isTyping').onValue.map((
      event,
    ) {
      final val = event.snapshot.value;
      if (val is bool) return val;
      if (val is String) return val.toLowerCase() == 'true';
      if (val is num) return val != 0;
      return false;
    });
  }

  // ============================================================
  // READ RECEIPT (SEEN STATUS)
  // ============================================================

  /// Đánh dấu đã xem tất cả tin nhắn từ người khác trong room
  Future<void> markMessagesAsSeen({
    required String roomId,
    required String viewerId,
    required String otherUserId,
  }) async {
    try {
      final snap = await _database.ref('Chats/$roomId').once();
      if (!snap.snapshot.exists || snap.snapshot.value == null) return;

      final data = snap.snapshot.value as Map<dynamic, dynamic>;
      final Map<String, dynamic> updates = {};

      data.forEach((key, val) {
        if (val is Map) {
          final senderId = val['senderId'] as String? ?? '';
          final seenBy = val['seenBy'] as Map? ?? {};
          // Chỉ đánh dấu tin nhắn từ người khác, chưa được đọc
          if (senderId == otherUserId && !seenBy.containsKey(viewerId)) {
            updates['Chats/$roomId/$key/seenBy/$viewerId'] =
                ServerValue.timestamp;
          }
        }
      });

      if (updates.isNotEmpty) {
        await _database.ref().update(updates);
      }
    } catch (e) {
      debugPrint('markMessagesAsSeen error: $e');
    }
  }

  /// Bật/Tắt ghim cuộc trò chuyện (Hỗ trợ cả Group và 1-1)
  Future<void> togglePin({
    required String chatId,
    required bool isPinned,
    required bool isGroup,
    String? currentUid,
    String? otherUid,
  }) async {
    try {
      if (isGroup) {
        if (currentUid == null) throw StateError('Cần đăng nhập.');
        // Cập nhật ghim cho nhóm (Firestore)
        await _firestore.collection('chats').doc(chatId).update({
          'pinnedBy.$currentUid': isPinned,
        });
      } else if (currentUid != null && otherUid != null) {
        // Cập nhật ghim cho chat 1-1 (Realtime Database)
        await _database
            .ref('ChatList')
            .child(currentUid)
            .child(otherUid)
            .update({'isPinned': isPinned});
      }
    } catch (e) {
      debugPrint('togglePin error: $e');
      rethrow;
    }
  }
}
