import 'package:cloud_firestore/cloud_firestore.dart';

class GroupChatRepository {
  GroupChatRepository(this.firestore);
  final FirebaseFirestore firestore;

  Future<void> send({
    required String groupId,
    required String senderId,
    required String text,
    String type = 'text',
    Map<String, dynamic>? metadata,
  }) async {
    if (text.trim().isEmpty || text.length > 4000) {
      throw ArgumentError('Tin nhắn phải có từ 1 đến 4000 ký tự.');
    }
    final group = firestore.collection('chats').doc(groupId);
    final batch = firestore.batch();
    batch.set(group.collection('messages').doc(), {
      'senderId': senderId,
      'message': text,
      'type': type,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'metadata': ?metadata,
    });
    batch.update(group, {
      'lastMessage': text,
      'lastMessageAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> changeMembers(
    String groupId,
    List<String> ids, {
    required bool add,
  }) async {
    final group = firestore.collection('chats').doc(groupId);
    await firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(group);
      final data = snapshot.data();
      if (data == null) throw StateError('Nhóm không còn tồn tại.');
      final members = List<String>.from(data['memberIds']);
      final next = add
          ? {...members, ...ids}.toList()
          : members.where((id) => !ids.contains(id)).toList();
      if (next.isEmpty ||
          next.length > 50 ||
          !next.contains(data['createdBy'])) {
        throw StateError(
          'Giữ chủ nhóm và tối đa 50 thành viên. Chủ nhóm cần kết thúc nhóm để rời.',
        );
      }
      transaction.update(group, {'memberIds': next});
    });
  }
}
