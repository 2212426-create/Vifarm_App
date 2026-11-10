import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toptop_flutter/features/auth/models/profile_model.dart';
import 'package:toptop_flutter/features/chat/providers/chat_provider.dart';
import 'package:toptop_flutter/features/chat/widgets/create_group_bottom_sheet.dart';

void main() {
  testWidgets('creation validates membership before attempting network writes', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [
      selectableFriendsProvider.overrideWith((ref) async => [ProfileModel(userId: 'bob', username: 'Bob')]),
    ], child: const MaterialApp(home: Scaffold(body: CreateGroupBottomSheet()))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Farm QA');
    await tester.pump();
    await tester.tap(find.text('Tạo'));
    await tester.pump();
    expect(find.textContaining('chọn 1–49 thành viên'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('overlong name is rejected even with a selected member', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [
      selectableFriendsProvider.overrideWith((ref) async => [ProfileModel(userId: 'bob', username: 'Bob')]),
    ], child: MaterialApp(home: Scaffold(body: CreateGroupBottomSheet(initialFriend: ProfileModel(userId: 'bob', username: 'Bob'))))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'x' * 81);
    await tester.pump();
    await tester.tap(find.text('Tạo'));
    await tester.pump();
    expect(find.textContaining('Nhập tên 1–80'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
