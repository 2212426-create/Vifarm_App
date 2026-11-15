// Kiểm thử cờ exposure: /recommend gắn vào VideoModel, logInteraction gửi đúng giá trị được truyền.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:toptop_flutter/features/video_feed/models/video_model.dart';
import 'package:toptop_flutter/features/video_feed/services/recsys_service.dart';

void main() {
  test('VideoModel.fromMap mặc định exposure normal và đọc được random', () {
    expect(VideoModel.fromMap({'videoId': 'a'}).exposure, 'normal');
    expect(
        VideoModel.fromMap({'videoId': 'a', 'exposure': 'random'}).exposure,
        'random');
    expect(VideoModel.fromMap({'videoId': 'a'}).toMap().containsKey('exposure'),
        isFalse);
  });

  test('getRecommendations gắn exposure vào từng VideoModel', () async {
    final client = MockClient((req) async {
      if (req.url.host.endsWith('firebaseio.com')) {
        return http.Response(jsonEncode('http://test.local'), 200);
      }
      if (req.url.path == '/health') {
        return http.Response('{"status":"ok"}', 200);
      }
      return http.Response(
        jsonEncode({
          'recommendations': [
            {'videoId': 'a', 'exposure': 'random'},
            {'videoId': 'b', 'exposure': 'normal'},
          ],
        }),
        200,
      );
    });
    final service =
        RecSysService(client: client, idTokenProvider: () async => 't');
    final recs = await service.getRecommendations(userId: 'u', limit: 2);
    expect(recs!.map((v) => v.exposure).toList(), ['random', 'normal']);
  });

  test('logInteraction gửi đúng exposure được truyền, mặc định normal', () async {
    final sent = <Map<String, dynamic>>[];
    final client = MockClient((req) async {
      // RTDB REST trả URL máy chủ giả, sau đó service gọi /health để kiểm tra.
      if (req.url.host.endsWith('firebaseio.com')) {
        return http.Response(jsonEncode('http://test.local'), 200);
      }
      if (req.url.path == '/health') {
        return http.Response('{"status":"ok"}', 200);
      }
      sent.add(jsonDecode(req.body) as Map<String, dynamic>);
      return http.Response('{}', 200);
    });
    final service =
        RecSysService(client: client, idTokenProvider: () async => 't');

    service.logInteraction(
        userId: 'u',
        videoId: 'a',
        playTimeMs: 800,
        isLike: false,
        exposure: 'random');
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
