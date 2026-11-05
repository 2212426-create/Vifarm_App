/// Hằng số toàn cục cho ứng dụng ViFarm
class AppConstants {
  AppConstants._();

  // App Info
  static const String appName = 'ViFarm';
  static const String appVersion = '1.0.0';

  // Link chia sẻ video (apps/share-page, GitHub Pages). Trang mở app qua vifarm://open/video/<id>.
  static const String shareBaseUrl = 'https://hubertphung.github.io/vifarm-share-page/?id=';
  // Tin nhắn cũ còn chứa link toptop-share-page; link này chuyển hướng sang trang mới.
  static const List<String> shareUrlPrefixes = [
    shareBaseUrl,
    'https://hubertphung.github.io/toptop-share-page/?id=',
  ];

  // Firebase Realtime Database URL
  static const String rtdbUrl =
      'https://mytiktokclone-f9789-default-rtdb.firebaseio.com/';

  // Cloudinary
  static const String cloudinaryCloudName = 'dbxinpidm';

  // Gemini API Key
  static const String geminiApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '', // Cung cap qua --dart-define-from-file=env.json
  );

  // Firestore Collections
  static const String usersCollection = 'users';
  static const String profilesCollection = 'profiles';
  static const String videosCollection = 'videos';
  static const String commentsCollection = 'comments';
  static const String reportsCollection = 'reports';
  static const String userInterestsCollection = 'user_interests';

  // Realtime Database Paths
  static const String chatPath = 'chats';
  static const String notificationsPath = 'Notifications';
  static const String statusPath = 'status';

  // Notification Action Types
  static const String actionFollow = '0';
  static const String actionComment = '1';
  static const String actionLike = '2';
  static const String actionChat = '3';

  // Limits
  static const int maxAvatarBytes = 3 * 1024 * 1024; // 3MB
  static const int videoFeedLimit = 50;

  // Splash
  static const int splashDurationMs = 1200;

  // Google Colab RecSys API (Cloudflare Tunnel URL)
  static const String recSysApiUrl = String.fromEnvironment(
    'RECSYS_API_URL',
    defaultValue: '',
  );
  static const String recSysStorageKey = 'recsys_colab_api_url';
}
