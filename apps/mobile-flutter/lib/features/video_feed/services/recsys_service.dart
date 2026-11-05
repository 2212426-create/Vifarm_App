import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
import '../models/video_model.dart';

/// Dịch vụ kết nối tới Google Colab RESTful Recommendation API
/// Tự động lấy URL từ Firebase Cloud mà người dùng không cần bật/nhập gì thủ công!
class RecSysService {
  final http.Client _client;
  final FirebaseDatabase? _database;
  String? _cachedApiUrl;
  DateTime? _lastCacheTime;

  RecSysService({
    http.Client? client,
    FirebaseDatabase? database,
  })  : _client = client ?? http.Client(),
        _database = database;

  /// Lấy địa chỉ API hoàn toàn tự động (Ưu tiên Firebase Realtime Database do Colab tự đồng bộ lên)
  Future<String?> getActiveApiUrl() async {
    // 1. Dùng cache bộ nhớ 30 giây để tránh truy vấn mạng liên tục
    if (_cachedApiUrl != null &&
        _lastCacheTime != null &&
        DateTime.now().difference(_lastCacheTime!).inSeconds < 30) {
      return _cachedApiUrl;
    }

    // 2. Tự động đọc từ Firebase Realtime Database qua SDK
    try {
      if (_database != null) {
        final snapshot = await _database.ref('server_config/recsys_url').get();
        if (snapshot.exists && snapshot.value != null) {
          final urlStr = snapshot.value.toString().trim();
          if (urlStr.isNotEmpty && urlStr.startsWith('http')) {
            _cachedApiUrl = _cleanUrl(urlStr);
            _lastCacheTime = DateTime.now();
            debugPrint('[RecSysService] 🚀 Tự động phát hiện Colab RecSys Server: $_cachedApiUrl');
            return _cachedApiUrl;
          }
        }
      }
    } catch (e) {
      debugPrint('[RecSysService] Đọc qua Firebase SDK không khả dụng ($e)');
    }

    // 3. Dự phòng đọc trực tiếp qua Firebase Realtime Database REST API công khai
    try {
      final res = await _client
          .get(Uri.parse('${AppConstants.rtdbUrl}server_config/recsys_url.json'))
          .timeout(const Duration(seconds: 3));
      if (res.statusCode == 200 && res.body.isNotEmpty && res.body != 'null') {
        final parsed = jsonDecode(res.body)?.toString().trim();
        if (parsed != null && parsed.isNotEmpty && parsed.startsWith('http')) {
          _cachedApiUrl = _cleanUrl(parsed);
          _lastCacheTime = DateTime.now();
          debugPrint('[RecSysService] 🌐 Đã lấy Colab URL qua RTDB REST: $_cachedApiUrl');
          return _cachedApiUrl;
        }
      }
    } catch (_) {}

    // 4. Dự phòng qua biến môi trường --dart-define hoặc SharedPreferences nếu có
    if (AppConstants.recSysApiUrl.trim().isNotEmpty) {
      return _cleanUrl(AppConstants.recSysApiUrl.trim());
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString(AppConstants.recSysStorageKey);
      if (savedUrl != null && savedUrl.trim().isNotEmpty) {
        return _cleanUrl(savedUrl.trim());
      }
    } catch (_) {}

    return null;
  }

  /// Kiểm tra trạng thái máy chủ Colab qua endpoint /health
  Future<Map<String, dynamic>> checkHealth([String? targetUrl]) async {
    final url = targetUrl != null ? _cleanUrl(targetUrl.trim()) : await getActiveApiUrl();
    if (url == null || url.isEmpty) {
      return {'online': false, 'error': 'Chưa phát hiện máy chủ Colab'};
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

  /// Lấy danh sách video gợi ý từ mô hình Causal Debiasing trên Colab
  Future<List<VideoModel>?> getRecommendations({
    String? userId,
    int limit = 20,
    String model = 'conalign',
    bool filterRejected = true,
    List<String>? excludeVideoIds,
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
          'exclude_video_ids': excludeVideoIds ?? [],
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
          debugPrint('[RecSysService] ✨ Nhận thành công ${list.length} video gợi ý từ Colab AI');
          return list;
        }
      } else {
        debugPrint('[RecSysService] HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('[RecSysService] Colab RecSys không phản hồi ($e) -> Tự động chuyển sang Firestore fallback');
    }
    return null;
  }

  /// Ghi nhận hành vi tương tác khi xem video (xem >= 3s hoặc thả tim like)
  void logInteraction({
    required String? userId,
    required String videoId,
    required int playTimeMs,
    required bool isLike,
  }) {
    // Chạy ngầm trong background không chặn UI
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
    } catch (_) {
      // Bỏ qua lỗi ngầm
    }
  }

  String _cleanUrl(String raw) {
    var url = raw.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }
}
