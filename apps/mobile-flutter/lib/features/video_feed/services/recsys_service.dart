import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
import '../models/video_model.dart';

/// Dịch vụ kết nối tới ViFarm Backend / Recommendation API
class RecSysService {
  final http.Client _client;
  final FirebaseDatabase? _database;
  String? _cachedApiUrl;
  DateTime? _lastCacheTime;
  String? _lastUrlSource;

  RecSysService({
    http.Client? client,
    FirebaseDatabase? database,
  })  : _client = client ?? http.Client(),
        _database = database;

  /// Nguồn cấu hình URL máy chủ gần nhất đã được phân giải
  String? get lastUrlSource => _lastUrlSource;

  Future<bool> _isHealthOk(String rawUrl, {int timeoutSeconds = 2}) async {
    final clean = _cleanUrl(rawUrl);
    if (clean.isEmpty || !clean.startsWith('http')) return false;

    try {
      final res = await _client
          .get(Uri.parse('$clean/health'))
          .timeout(Duration(seconds: timeoutSeconds));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Lấy địa chỉ API hoàn toàn tự động, có kiểm tra sức khỏe server qua /health
  Future<String?> getActiveApiUrl() async {
    // 1. Dùng cache bộ nhớ 30 giây nếu server vẫn sống
    if (_cachedApiUrl != null &&
        _lastCacheTime != null &&
        DateTime.now().difference(_lastCacheTime!).inSeconds < 30) {
      return _cachedApiUrl;
    }

    // 2. Đọc từ Firebase Realtime Database qua SDK
    try {
      if (_database != null) {
        final snapshot = await _database.ref('server_config/recsys_url').get();
        if (snapshot.exists && snapshot.value != null) {
          final urlStr = snapshot.value.toString().trim();
          if (urlStr.isNotEmpty && urlStr.startsWith('http')) {
            final cleaned = _cleanUrl(urlStr);
            if (await _isHealthOk(cleaned)) {
              _cachedApiUrl = cleaned;
              _lastCacheTime = DateTime.now();
              _lastUrlSource = 'Firebase RTDB SDK';
              debugPrint('[RecSysService] 🚀 Phát hiện Colab Server qua RTDB SDK: $_cachedApiUrl');
              return _cachedApiUrl;
            } else {
              debugPrint('[RecSysService] ⚠️ Tunnel RTDB SDK ($cleaned) không phản hồi /health, bỏ qua.');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[RecSysService] Đọc qua Firebase SDK không khả dụng ($e)');
    }

    // 3. Đọc từ Firebase Realtime Database REST API
    try {
      final res = await _client
          .get(Uri.parse('${AppConstants.rtdbUrl}server_config/recsys_url.json'))
          .timeout(const Duration(seconds: 3));
      if (res.statusCode == 200 && res.body.isNotEmpty && res.body != 'null') {
        final parsed = jsonDecode(res.body)?.toString().trim();
        if (parsed != null && parsed.isNotEmpty && parsed.startsWith('http')) {
          final cleaned = _cleanUrl(parsed);
          if (await _isHealthOk(cleaned)) {
            _cachedApiUrl = cleaned;
            _lastCacheTime = DateTime.now();
            _lastUrlSource = 'Firebase RTDB REST';
            debugPrint('[RecSysService] 🌐 Phát hiện Colab Server qua RTDB REST: $_cachedApiUrl');
            return _cachedApiUrl;
          } else {
            debugPrint('[RecSysService] ⚠️ Tunnel RTDB REST ($cleaned) không phản hồi /health, bỏ qua.');
          }
        }
      }
    } catch (_) {}

    // 4. Dự phòng qua environment define / SharedPreferences
    if (AppConstants.recSysApiUrl.trim().isNotEmpty) {
      final cleaned = _cleanUrl(AppConstants.recSysApiUrl.trim());
      if (await _isHealthOk(cleaned)) {
        _cachedApiUrl = cleaned;
        _lastCacheTime = DateTime.now();
        _lastUrlSource = 'AppConstants / Dart Define';
        return _cachedApiUrl;
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString(AppConstants.recSysStorageKey);
      if (savedUrl != null && savedUrl.trim().isNotEmpty) {
        final cleaned = _cleanUrl(savedUrl.trim());
        if (await _isHealthOk(cleaned)) {
          _cachedApiUrl = cleaned;
          _lastCacheTime = DateTime.now();
          _lastUrlSource = 'SharedPreferences';
          return _cachedApiUrl;
        }
      }
    } catch (_) {}

    // 5. Thử các địa chỉ Local Development mặc định
    final localCandidates = (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
        ? ['http://10.0.2.2:8000', 'http://127.0.0.1:8000', 'http://localhost:8000']
        : ['http://localhost:8000', 'http://127.0.0.1:8000'];

    for (final candidate in localCandidates) {
      if (await _isHealthOk(candidate, timeoutSeconds: 1)) {
        _cachedApiUrl = candidate;
        _lastCacheTime = DateTime.now();
        _lastUrlSource = 'Localhost / Dev Server';
        debugPrint('[RecSysService] 💻 Kết nối thành công Localhost Server: $_cachedApiUrl');
        return _cachedApiUrl;
      }
    }

    // Nếu không máy chủ nào phản hồi /health, trả về local fallback mặc định cho môi trường
    final defaultFallback = (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
        ? 'http://10.0.2.2:8000'
        : 'http://localhost:8000';

    _lastUrlSource = 'Default Platform Fallback (Offline/Not Responding)';
    return defaultFallback;
  }

  /// Kiểm tra trạng thái máy chủ qua endpoint /health
  Future<Map<String, dynamic>> checkHealth([String? targetUrl]) async {
    final url = targetUrl != null ? _cleanUrl(targetUrl.trim()) : await getActiveApiUrl();
    if (url == null || url.isEmpty) {
      return {'online': false, 'error': 'Chưa phát hiện máy chủ backend'};
    }

    final stopwatch = Stopwatch()..start();
    try {
      final response = await _client
          .get(Uri.parse('$url/health'))
          .timeout(const Duration(seconds: 4));
      stopwatch.stop();

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return {
          'online': true,
          'latency_ms': stopwatch.elapsedMilliseconds,
          'data': data,
        };
      } else {
        return {
          'online': false,
          'error': 'Máy chủ phản hồi HTTP ${response.statusCode}',
        };
      }
    } catch (e) {
      stopwatch.stop();
      return {
        'online': false,
        'error': 'Không thể kết nối ($e)',
      };
    }
  }

  /// Lấy danh sách video gợi ý
  Future<List<VideoModel>?> getRecommendations({
    String? userId,
    int limit = 20,
    String model = 'ividr',
    bool filterRejected = true,
  }) async {
    final url = await getActiveApiUrl();
    if (url == null || url.isEmpty) return null;

    try {
      final response = await _client.post(
        Uri.parse('$url/api/v1/recommend'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId ?? 'guest',
          'k': limit,
          'model': model,
          'filter_rejected': filterRejected,
        }),
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final recs = data['recommendations'] as List?;
        if (recs != null && recs.isNotEmpty) {
          final list = <VideoModel>[];
          for (final item in recs) {
            if (item is Map<String, dynamic>) {
              final vId = (item['videoId'] ?? item['video_id'])?.toString();
              list.add(VideoModel.fromMap(item, vId));
            }
          }
          debugPrint('[RecSysService] ✨ Nhận thành công ${list.length} video gợi ý từ server');
          return list;
        }
      }
    } catch (e) {
      debugPrint('[RecSysService] Backend không phản hồi ($e) -> Fallback Firestore');
    }
    return null;
  }

  void logInteraction({
    required String? userId,
    required String videoId,
    required int playTimeMs,
    required bool isLike,
  }) {
    _sendInteractionAsync(
      userId: userId,
      videoId: videoId,
      playTimeMs: playTimeMs,
      isLike: isLike,
    );
  }

  Future<void> _sendInteractionAsync({
    required String? userId,
    required String videoId,
    required int playTimeMs,
    required bool isLike,
  }) async {
    final url = await getActiveApiUrl();
    if (url == null || url.isEmpty) return;

    try {
      await _client.post(
        Uri.parse('$url/api/v1/interaction'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId ?? 'guest',
          'video_id': videoId,
          'play_time_ms': playTimeMs,
          'is_like': isLike,
        }),
      ).timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  String _cleanUrl(String raw) {
    var url = raw.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }
}
