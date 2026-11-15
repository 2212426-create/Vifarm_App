// Kiểm thử RecSysService giữ cờ exposure của /recommend và gửi lại trong /interaction.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:toptop_flutter/features/video_feed/services/recsys_service.dart';

void main() {
  test('gửi exposure random cho video được phát ngẫu nhiên', () async {
    final sent = <Map<String, dynamic>>[];
    final client = MockClient((req) async {
      // RTDB REST trả URL máy chủ giả, sau đó service gọi /health để kiểm tra.
      if (req.url.host.endsWith('firebaseio.com')) {
        return http.Response(jsonEncode('http://test.local'), 200);
      }
      if (req.url.path == '/health') {
        return http.Response('{"status":"ok"}', 200);
      }
      if (req.url.path == '/api/v1/recommend') {
        return http.Response(
          jsonEncode({
            'recommendations': [
              {'videoId': 'a', 'exposure': 'random'},
              {'videoId': 'b', 'exposure': 'normal'},
            ],
          }),
          200,
        );
      }
      sent.add(jsonDecode(req.body) as Map<String, dynamic>);
      return http.Response('{}', 200);
    });
    final service =
        RecSysService(client: client, idTokenProvider: () async => 't');

    final recs = await service.getRecommendations(userId: 'u', limit: 2);
    expect(recs, isNotNull);
    expect(service.isRandomExposure('a'), isTrue);
    expect(service.isRandomExposure('b'), isFalse);

    service.logInteraction(
        userId: 'u', videoId: 'a', playTimeMs: 800, isLike: false);
    service.logInteraction(
        userId: 'u', videoId: 'b', playTimeMs: 800, isLike: false);
    // Chờ có đủ 2 body, giới hạn số vòng để test không treo.
    for (var i = 0; i < 100 && sent.length < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(sent, hasLength(2));
    final byVideo = {for (final b in sent) b['video_id']: b['exposure']};
    expect(byVideo, {'a': 'random', 'b': 'normal'});
  });
}
