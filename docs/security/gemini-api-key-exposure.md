# Gemini API key bị lộ trong mã nguồn app Flutter

- **Ngày phát hiện:** 2026-10-16 (khi review cấu trúc repo, PR #16)
- **Mức độ:** Cao — key thật, có thể bị dùng để gọi Gemini và tính tiền vào tài khoản của nhóm
- **Trạng thái:** Đã xử lý trong code (Đã xoá defaultValue, tạo env.example.json, cập nhật .gitignore)

## Vấn đề

`apps/mobile-flutter/lib/core/constants/app_constants.dart` đặt Gemini API key thật làm
giá trị mặc định:

```dart
static const String geminiApiKey = String.fromEnvironment(
  'GEMINI_API_KEY',
  defaultValue: 'AIzaSyDEI08…',   // key thật, đã rút gọn trong tài liệu này
);
```

- Key đã có trong lịch sử git từ commit `51fcb37` ("switch to flutter") và đã được push lên
  GitHub. Chỉ xoá khỏi code **không** đủ: ai clone repo vẫn xem được commit cũ.
- Mọi bản APK build không truyền `--dart-define` đều nhúng key này.
- Nơi dùng key: `lib/features/video_upload/services/gemini_service.dart` và
  `lib/features/video_upload/layouts/video_description_screen.dart` (gợi ý hashtag).

Không bị ảnh hưởng:
- `apps/mobile-android` (Java cũ) đọc key từ `local.properties` (không commit).
- `apps/admin-web` đọc `VITE_GEMINI_API_KEY` từ `.env` (không commit).
- Các key `AIzaSy…` trong `firebase_options.dart` và `google-services.json` là key cấu hình
  Firebase, được thiết kế để công khai và bảo vệ bằng Firestore rules — không phải lỗi này.

## Cách xử lý

### Bước 1 — Thu hồi key cũ (làm ngay, người giữ tài khoản Google Cloud)

- [ ] Vào Google AI Studio → API keys, hoặc Google Cloud Console → APIs & Services →
      Credentials; **xoá / regenerate** key bắt đầu bằng `AIzaSyDEI08`.
- [ ] Tạo key mới và giới hạn ngay:
  - API restrictions: chỉ *Generative Language API*.
  - Application restrictions: *Android apps*, nhập package name và SHA-1 của app.
- [ ] Không dán key mới vào code, chat hay tài liệu.

Sau khi key cũ bị thu hồi, bản trong lịch sử git không còn dùng được, nên **không cần viết
lại lịch sử** repo nhóm (việc đó làm hỏng nhánh của mọi thành viên).

### Bước 2 — Bỏ key khỏi mã nguồn

- [ ] Xoá `defaultValue` trong `app_constants.dart` (để chuỗi rỗng khi không truyền key).
- [ ] Thêm `apps/mobile-flutter/env.example.json`:
      `{"GEMINI_API_KEY": "<điền key của bạn>"}`; thêm `apps/mobile-flutter/env.json` vào `.gitignore`.
- [ ] Build/chạy bằng: `flutter run --dart-define-from-file=env.json`
      (tương tự cho `flutter build apk`). Ghi lệnh này vào README.
- [ ] Khi key rỗng, `gemini_service.dart` và `video_description_screen.dart` tắt gợi ý
      hashtag và báo người dùng, thay vì gọi API rồi lỗi.

### Bước 3 — Hướng lâu dài

Truyền key qua `--dart-define` hay `.env` vẫn nhúng key vào APK / bundle JavaScript của web
quản trị; người có kinh nghiệm vẫn trích ra được. Để chặn triệt để, app không gọi Gemini
trực tiếp mà đi qua một trong hai cách:

- **Firebase AI Logic** (Gemini qua Firebase) kết hợp **Firebase App Check**; hoặc
- một Cloud Function / dịch vụ trong `services/` giữ key ở server, app chỉ gọi endpoint đó.

## Kiểm tra sau khi sửa

- [ ] `git grep -n "AIzaSyDEI08"` không còn kết quả.
- [ ] Gọi API bằng key cũ trả lỗi `API_KEY_INVALID`.
- [ ] Gợi ý hashtag vẫn chạy khi build với `env.json`; app không lỗi khi build không có key.
- [ ] Kiểm tra mục *Security → Secret scanning* của repo GitHub và đóng cảnh báo (nếu có).
