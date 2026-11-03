/// Model video - ánh xạ từ Firestore collection "videos"
/// Bổ sung các trường dữ liệu nông nghiệp cho "Nông Video"
class VideoModel {
  final String videoId;
  final String videoUri;
  final String authorId;
  final String username;
  final String description;
  final String moderationStatus;
  final int totalLikes;
  final int totalComments;
  final int watchCount;
  final int timestamp;
  final List<String> hashtags;
  final String? location;
  final bool allowDownload;
  final bool allowDuet;
  final bool isCopyrightProtected;

  // ── Mở rộng Nông Nghiệp & Phân loại Chủ đề ─────────────────────────────
  final String?
  topic; // Chủ đề video: 'farming_experience', 'garden_tour', 'product_intro', 'farmer_story', 'other'
  final bool isSponsored; // Khai báo video có quảng cáo hoặc được tài trợ
  final String? crop; // Cây trồng (ví dụ: Sầu riêng, Cà phê, Lúa...)
  final String?
  growthStage; // Giai đoạn (ví dụ: Gieo hạt, Ra hoa, Đậu quả, Thu hoạch...)
  final String? region; // Khu vực (ví dụ: Lâm Đồng, Đắk Lắk, Cần Thơ...)
  final String? technicalTopic; // Chủ đề kỹ thuật chi tiết
  final String? relatedJournalId; // ID nhật ký mùa vụ liên quan
  final List<String> taggedProductIds; // Các sản phẩm gắn kèm
  final double? latitude;
  final double? longitude;
  final bool isPublic;

  VideoModel({
    required this.videoId,
    required this.videoUri,
    required this.authorId,
    this.username = '',
    this.description = '',
    this.moderationStatus = 'pending',
    this.totalLikes = 0,
    this.totalComments = 0,
    this.watchCount = 0,
    required this.timestamp,
    this.hashtags = const [],
    this.location,
    this.allowDownload = true,
    this.allowDuet = true,
    this.isCopyrightProtected = false,
    this.topic,
    this.isSponsored = false,
    this.crop,
    this.growthStage,
    this.region,
    this.technicalTopic,
    this.relatedJournalId,
    this.taggedProductIds = const [],
    this.latitude,
    this.longitude,
    this.isPublic = true,
  });

  /// Trả về nhãn tiếng Việt hiển thị thân thiện cho chủ đề video
  static String getTopicDisplayName(String? topic) {
    switch (topic) {
      case 'farming_experience':
        return 'Kinh nghiệm làm nông';
      case 'garden_tour':
        return 'Giới thiệu vườn';
      case 'product_intro':
        return 'Giới thiệu sản phẩm';
      case 'farmer_story':
        return 'Chuyện nhà nông';
      case 'other':
        return 'Nội dung khác';
      default:
        return '';
    }
  }

  factory VideoModel.fromMap(Map<String, dynamic> map, [String? id]) {
    final vId = map['videoId'] as String? ?? '';

    // Xử lý vị trí cũ (location dạng String) hoặc map địa lý mới
    String? locStr;
    if (map['location'] is String) {
      locStr = map['location'] as String;
    } else if (map['location'] is Map) {
      locStr = (map['location'] as Map)['name'] as String?;
    }

    return VideoModel(
      videoId: vId.isNotEmpty ? vId : (id ?? ''),
      videoUri: map['videoUri'] as String? ?? '',
      authorId: map['authorId'] as String? ?? '',
      username: map['username'] as String? ?? '',
      description: map['description'] as String? ?? '',
      moderationStatus: map['moderationStatus'] as String? ?? 'pending',
      totalLikes: (map['totalLikes'] as num?)?.toInt() ?? 0,
      totalComments: (map['totalComments'] as num?)?.toInt() ?? 0,
      watchCount: (map['watchCount'] as num?)?.toInt() ?? 0,
      timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
      hashtags:
          (map['hashtags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      location: locStr ?? map['region'] as String?,
      allowDownload: map['allowDownload'] as bool? ?? true,
      allowDuet: map['allowDuet'] as bool? ?? true,
      isCopyrightProtected: map['isCopyrightProtected'] as bool? ?? false,
      topic:
          map['topic'] as String? ??
          (map['technicalTopic'] != null ? 'farming_experience' : null),
      isSponsored: map['isSponsored'] as bool? ?? false,
      crop: map['crop'] as String?,
      growthStage: map['growthStage'] as String?,
      region: map['region'] as String? ?? locStr,
      technicalTopic: map['technicalTopic'] as String?,
      relatedJournalId: map['relatedJournalId'] as String?,
      taggedProductIds:
          (map['taggedProductIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      isPublic: map['isPublic'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
    'videoId': videoId,
    'videoUri': videoUri,
    'authorId': authorId,
    'username': username,
    'description': description,
    'moderationStatus': moderationStatus,
    'totalComments': totalComments,
    'totalLikes': totalLikes,
    'watchCount': watchCount,
    'timestamp': timestamp,
    'hashtags': hashtags,
    'location': location,
    'allowDownload': allowDownload,
    'allowDuet': allowDuet,
    'isCopyrightProtected': isCopyrightProtected,
    'topic': topic,
    'isSponsored': isSponsored,
    'crop': crop,
    'growthStage': growthStage,
    'region': region,
    'technicalTopic': technicalTopic,
    'relatedJournalId': relatedJournalId,
    'taggedProductIds': taggedProductIds,
    'latitude': latitude,
    'longitude': longitude,
    'isPublic': isPublic,
  };

  VideoModel copyWith({
    String? videoId,
    String? videoUri,
    String? authorId,
    String? username,
    String? description,
    String? moderationStatus,
    int? totalLikes,
    int? totalComments,
    int? watchCount,
    int? timestamp,
    List<String>? hashtags,
    String? location,
    bool? allowDownload,
    bool? allowDuet,
    bool? isCopyrightProtected,
    String? crop,
    String? growthStage,
    String? region,
    String? technicalTopic,
    String? relatedJournalId,
    List<String>? taggedProductIds,
    double? latitude,
    double? longitude,
    bool? isPublic,
  }) {
    return VideoModel(
      videoId: videoId ?? this.videoId,
      videoUri: videoUri ?? this.videoUri,
      authorId: authorId ?? this.authorId,
      username: username ?? this.username,
      description: description ?? this.description,
      moderationStatus: moderationStatus ?? this.moderationStatus,
      totalLikes: totalLikes ?? this.totalLikes,
      totalComments: totalComments ?? this.totalComments,
      watchCount: watchCount ?? this.watchCount,
      timestamp: timestamp ?? this.timestamp,
      hashtags: hashtags ?? this.hashtags,
      location: location ?? this.location,
      allowDownload: allowDownload ?? this.allowDownload,
      allowDuet: allowDuet ?? this.allowDuet,
      isCopyrightProtected: isCopyrightProtected ?? this.isCopyrightProtected,
      crop: crop ?? this.crop,
      growthStage: growthStage ?? this.growthStage,
      region: region ?? this.region,
      technicalTopic: technicalTopic ?? this.technicalTopic,
      relatedJournalId: relatedJournalId ?? this.relatedJournalId,
      taggedProductIds: taggedProductIds ?? this.taggedProductIds,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isPublic: isPublic ?? this.isPublic,
    );
  }
}
