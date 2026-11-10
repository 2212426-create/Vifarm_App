import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/chat_provider.dart';

class ChatConnectionBanner extends ConsumerWidget {
  const ChatConnectionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = ref.watch(chatConnectionProvider);
    if (connected.valueOrNull != false && !connected.hasError) {
      return const SizedBox.shrink();
    }
    return const Padding(
      padding: EdgeInsets.all(12),
      child: Text(
        'Chat riêng đang mất kết nối với máy chủ. Tin chưa gửi được giữ để thử lại. Trạng thái này không áp dụng cho chat nhóm.',
        textAlign: TextAlign.center,
      ),
    );
  }
}
