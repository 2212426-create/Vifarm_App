import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toptop_flutter/core/providers/firebase_providers.dart';
import 'package:toptop_flutter/features/auth/models/profile_model.dart';
import 'package:toptop_flutter/features/chat/layouts/chat_screen.dart';
import 'package:toptop_flutter/features/chat/providers/chat_provider.dart';
import 'package:toptop_flutter/features/chat/repositories/chat_repository.dart';

class ChatUser implements User {
  @override
  String get uid => 'alice';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ControlledChat implements ChatRepository {
  Completer<void> pending = Completer<void>();
  int sends = 0;
  @override
  String getRoomId(String a, String b) => 'alice_bob';
  @override
  Future<void> sendMessage({
    required String senderId,
    required String receiverId,
    required String message,
    String type = 'text',
    Map<String, dynamic>? metadata,
  }) {
    sends++;
    return pending.future;
  }

  @override
  Future<void> setTyping({
    required String roomId,
    required String userId,
    required bool isTyping,
  }) async {}
  @override
  Future<void> markMessagesAsSeen({
    required String roomId,
    required String viewerId,
    required String otherUserId,
  }) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> showChat(
  WidgetTester tester,
  ControlledChat repo, {
  bool connected = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream.value(ChatUser())),
        chatRepositoryProvider.overrideWithValue(repo),
        chatConnectionProvider.overrideWith((ref) => Stream.value(connected)),
        chatMessagesProvider.overrideWith((ref, room) => Stream.value([])),
        typingStatusProvider.overrideWith((ref, key) => Stream.value(false)),
        userOnlineStatusProvider.overrideWith(
          (ref, uid) => Stream.value(false),
        ),
        chatProfileProvider.overrideWith(
          (ref, uid) =>
              Stream.value(ProfileModel(userId: uid, username: 'Bob')),
        ),
      ],
      child: const MaterialApp(
        home: ChatScreen(receiverId: 'bob', receiverName: 'Bob'),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets(
    'failed send keeps draft; retry clears only after acknowledgement',
    (tester) async {
      final repo = ControlledChat();
      await showChat(tester, repo);
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      expect(repo.sends, 1);
      expect(find.text('hello'), findsOneWidget);
      repo.pending.completeError(StateError('denied'));
      await tester.pump();
      expect(find.text('hello'), findsOneWidget);
      expect(find.textContaining('Chưa gửi được'), findsOneWidget);
      repo.pending = Completer<void>();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      repo.pending.complete();
      await tester.pump();
      expect(find.text('hello'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'offline banner is visible and later draft survives older acknowledgement',
    (tester) async {
      final repo = ControlledChat();
      await showChat(tester, repo, connected: false);
      expect(find.textContaining('Chat riêng đang mất kết nối'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'first');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'next draft');
      repo.pending.complete();
      await tester.pump();
      expect(find.text('next draft'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
