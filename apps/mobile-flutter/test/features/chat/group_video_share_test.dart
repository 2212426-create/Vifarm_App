import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toptop_flutter/features/auth/providers/auth_provider.dart';
import 'package:toptop_flutter/features/chat/providers/chat_provider.dart';
import 'package:toptop_flutter/features/chat/repositories/chat_repository.dart';
import 'package:toptop_flutter/shared/widgets/universal_share_bottom_sheet.dart';

class ShareUser implements User {
  @override
  String get uid => 'alice';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ShareRepository implements ChatRepository {
  bool? sentToGroup;
  String? recipient;
  @override
  Future<void> sendVideoShare({
    required String senderId,
    required String receiverId,
    required String videoId,
    String? caption,
    bool isGroup = false,
    Map<String, dynamic>? videoMeta,
  }) async {
    sentToGroup = isGroup;
    recipient = receiverId;
    throw StateError('Keep sheet open for assertions');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'video share excludes closed groups and routes groups correctly',
    (tester) async {
      final repo = ShareRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(ShareUser()),
            chatRepositoryProvider.overrideWithValue(repo),
            chatConversationsProvider.overrideWithValue(
              const AsyncData([
                {
                  'chatId': 'active',
                  'title': 'Active group',
                  'isGroup': true,
                  'closed': false,
                },
                {
                  'chatId': 'closed',
                  'title': 'Closed group',
                  'isGroup': true,
                  'closed': true,
                },
              ]),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: UniversalShareBottomSheet(
                content: ShareContentModel(
                  type: ShareContentType.video,
                  id: 'video1',
                  title: 'QA video',
                  shareUrl: 'https://example.test/video1',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Closed group'), findsNothing);
      await tester.tap(find.text('Active group'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Gửi (1)'));
      await tester.tap(find.text('Gửi (1)'));
      await tester.pumpAndSettle();
      expect(repo.sentToGroup, isTrue);
      expect(repo.recipient, 'active');
      expect(find.textContaining('Gửi chia sẻ thất bại'), findsOneWidget);
    },
  );
}
