// Kiểm thử tích hợp RecSysService với RecSys API chạy thật (services/recsys).
// Mặc định bị bỏ qua; chạy khi có server:
//   flutter test --no-pub test/recsys_api_integration_test.dart \
//     --dart-define=RECSYS_API_URL=http://127.0.0.1:8765 --dart-define=IT_MODE=firebase
//   flutter test --no-pub test/recsys_api_integration_test.dart \
//     --dart-define=RECSYS_API_URL=http://127.0.0.1:8766 --dart-define=IT_MODE=off --dart-define=IT_USER=<uid>
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:toptop_flutter/features/video_feed/services/recsys_service.dart';

const apiUrl = String.fromEnvironment('RECSYS_API_URL');
const mode = String.fromEnvironment('IT_MODE');
const warmUser = String.fromEnvironment('IT_USER');

/// Gửi request thật tới server cục bộ, chặn RTDB để không đọc URL tunnel production.
class RecordingClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  final List<String> log = [];
  final List<Map<String, String>> headers = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.host.endsWith('firebaseio.com')) {
      return http.StreamedResponse(Stream.value(utf8.encode('null')), 200);
    }
    final response = await _inner.send(request);
    if (request.url.path != '/health') {
      log.add('${request.method} ${request.url.path} ${response.statusCode}');
      headers.add(Map.of(request.headers));
    }
    return response;
  }

  Future<void> waitFor(String entryPrefix) async {
    for (var i = 0; i < 50 && !log.any((e) => e.startsWith(entryPrefix)); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}

void main() {
  final skip = apiUrl.isEmpty ? 'Cần --dart-define=RECSYS_API_URL' : null;

  group('firebase auth mode', skip: skip ?? (mode == 'firebase' ? null : 'IT_MODE != firebase'), () {
    test('khách: gợi ý độ phổ biến, không gửi Authorization', () async {
      final client = RecordingClient();
      final service = RecSysService(client: client, idTokenProvider: () async => null);
      final videos = await service.getRecommendations(userId: null, limit: 5);
      expect(videos, isNotNull);
      expect(videos, isNotEmpty);
      expect(client.log, ['POST /api/v1/recommend 200']);
      expect(client.headers.single.containsKey('Authorization'), isFalse);
    });

    test('khách: không gửi tương tác', () async {
      final client = RecordingClient();
      final service = RecSysService(client: client, idTokenProvider: () async => null);
      service.logInteraction(userId: null, videoId: 'v', playTimeMs: 5000, isLike: true);
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(client.log, isEmpty);
    });

    test('token giả: server trả 401, client rơi về fallback (null)', () async {
      final client = RecordingClient();
      final service = RecSysService(client: client, idTokenProvider: () async => 'forged.token.value');
      final videos = await service.getRecommendations(userId: 'someone', limit: 5);
      expect(videos, isNull);
      expect(client.log, ['POST /api/v1/recommend 401']);
      expect(client.headers.single['Authorization'], 'Bearer forged.token.value');
    });

    test('token giả: tương tác bị 401, client không ném lỗi', () async {
      final client = RecordingClient();
      final service = RecSysService(client: client, idTokenProvider: () async => 'forged.token.value');
      service.logInteraction(userId: 'someone', videoId: 'v', playTimeMs: 5000, isLike: true);
      await client.waitFor('POST /api/v1/interaction');
      expect(client.log, ['POST /api/v1/interaction 401']);
    });
  });

  group('auth off (chạy cục bộ)', skip: skip ?? (mode == 'off' ? null : 'IT_MODE != off'), () {
    test('user có lịch sử nhận gợi ý cá nhân hóa từ ConAlign', () async {
      final client = RecordingClient();
      final service = RecSysService(client: client, idTokenProvider: () async => null);
      final videos = await service.getRecommendations(userId: warmUser, limit: 5);
      expect(videos, isNotEmpty);
      expect(videos!.every((v) => v.videoUri.isNotEmpty), isTrue);
      expect(client.log, ['POST /api/v1/recommend 200']);

      final raw = await http.post(Uri.parse('$apiUrl/api/v1/recommend'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'user_id': warmUser, 'k': 5, 'model': 'conalign'}));
      final body = jsonDecode(raw.body) as Map<String, dynamic>;
      expect(body['model_used'], 'conalign');
      expect(body['is_cold_start'], isFalse);
    });

    test('tương tác của user được ghi nhận', () async {
      final client = RecordingClient();
      final service = RecSysService(client: client, idTokenProvider: () async => null);
      final videos = await service.getRecommendations(userId: warmUser, limit: 1);
      service.logInteraction(userId: warmUser, videoId: videos!.first.videoId, playTimeMs: 9000, isLike: true);
      await client.waitFor('POST /api/v1/interaction');
      expect(client.log.last, 'POST /api/v1/interaction 200');
    });
  });
}
