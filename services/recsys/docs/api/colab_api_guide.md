# RecSys API cho app TopTop

**Hướng dẫn hiện hành, mốc 20/10/2026.** API có dữ liệu và siêu tham số phục vụ riêng;
không dùng cấu hình hoặc điểm API làm benchmark Coat/KuaiRand.
[Trạng thái và bằng chứng](../CURRENT_STATE.md).

Mã nguồn: [`src/api/`](../../src/api/). Kiểm thử: [`tests/test_api.py`](../../tests/test_api.py).

## Mô hình phục vụ

| `model` | Cách tính điểm | Huấn luyện |
| :-- | :-- | :-- |
| `mf` | sigmoid(⟨p_u, q_i⟩ + b_u + b_i), μ=0 | Adam + MSE trên score thô, decay mọi tham số, khởi tạo uniform như iDCF |
| `cdr` | sigmoid(⟨p_u, q_i⟩), ReleasedCDR 4 chiều, variance filter 10, dropout .5 | Source DR-BIAS update/loss, LR .05, wd .0001; item-frequency propensity (kẹp 0,05–1), MC 10; sampler có hoàn lại |
| `popularity` | log(1 + watchCount + 5·totalLikes) + log(1 + số lượt dương) | Không học; dùng cho user chưa có lịch sử |
| `ividr` | Không phục vụ | Đã loại khỏi hệ thống do tác giả không công bố mã nguồn và không thể tái lập; tự động chọn mô hình khả dụng kèm `fallback_reason` |

Nhãn dương: `is_like` hoặc `play_time_ms ≥ 3000`. Cặp user–video lặp được gộp, dương nếu có ít nhất một lần dương.
Mô hình được huấn luyện lại sau mỗi `retrain_every` (mặc định 20) tương tác mới, hoặc khi gọi `/api/v1/sync`.
Huấn luyện chạy ở luồng nền trên bản sao dữ liệu; `/recommend` tiếp tục dùng mô hình cũ cho tới khi mô hình mới
được hoán đổi nguyên khối. Mỗi thời điểm chỉ có một lượt huấn luyện. Lượt lỗi giữ mô hình cũ và báo ở
`/health` (`retraining`, `last_retrain_error`). Phản hồi `/interaction` có `retrain_started`.
ConAlign và CDR phục vụ dùng trọng số 1/clamp(tần suất video tương đối, .05, 1): video ít lượt nhất nặng gấp
tối đa 20 lần, số epoch cố định, không có early stopping vì app chưa có tập validation online.
CDR app không có random-exposure log nên không dùng Naive Bayes calibration như Coat/Yahoo.
`training_stats.cdr` công bố triển khai và các điều chỉnh phục vụ. Không gọi điểm API là tái lập paper.

## Nguồn dữ liệu

`RECSYS_DATA_SOURCE` = `auto` (mặc định) | `live` | `export`:

- Video và user: Firestore REST. Nếu Firestore không trả video nào, dùng `firestore_data.json`
  hoặc `toptop_processed_bundle.json` trong `RECSYS_EXPORT_DIR`.
- Tương tác: `toptop_interactions.csv` (export), lượt like trong RTDB `Notifications`
  (chỉ giữ khi `fromUsername` ánh xạ duy nhất tới một uid) và log của API
  (`RECSYS_INTERACTION_LOG`, mặc định `data/api/interactions_log.csv`).

Quyền đọc Firestore, số video và trạng thái moderation phụ thuộc dữ liệu/rules đang
chạy. Đợt dọn tài liệu này không kiểm tra lại tài khoản hoặc dữ liệu live. Không dùng
số lượng video của bản export/truy vấn cũ để mô tả môi trường hiện tại; kiểm tra
`/health`, snapshot thực tế và tham số `filter_rejected` khi chẩn đoán feed.

## Endpoint

| Method | Path | Ghi chú |
| :-- | :-- | :-- |
| GET | `/health` | Nguồn dữ liệu, số tương tác, mô hình đã huấn luyện |
| POST | `/api/v1/recommend` | `{user_id, k, model, filter_rejected, exclude_video_ids}` → `recommendations` (khóa camelCase của Firestore), `model_used`, `fallback_reason`. Không có token: phục vụ như khách |
| POST | `/api/v1/interaction` | `{video_id, play_time_ms, is_like}`; **bắt buộc** Bearer token |
| POST | `/api/v1/compare` | Top-K của mọi mô hình khả dụng cho cùng user; quy tắc token như `/recommend` |
| GET | `/api/v1/items/popular` | Top-K theo độ phổ biến |
| POST | `/api/v1/sync` | Nạp lại dữ liệu và huấn luyện lại; **bắt buộc** `X-Admin-Key` |

## Xác thực

Mã: [`src/api/auth.py`](../../src/api/auth.py).

- `RECSYS_AUTH_MODE=firebase` (mặc định): app gửi `Authorization: Bearer <Firebase ID token>`. Server kiểm tra
  chữ ký bằng khóa công khai của Google, `aud`/`iss` theo `TOPTOP_FIREBASE_PROJECT` (mặc định `mytiktokclone-f9789`),
  rồi lấy user_id từ `sub` của token. user_id trong body khác uid của token bị từ chối 403. Token sai/hết hạn: 401;
  không tải được khóa công khai: 503. Token hợp lệ được cache tới khi hết hạn.
- `RECSYS_AUTH_MODE=off`: tin user_id trong body. Chỉ dùng khi chạy cục bộ.
- `RECSYS_ADMIN_KEY`: bắt buộc để gọi `/api/v1/sync` (header `X-Admin-Key`). Không đặt thì `/sync` bị tắt,
  trừ chế độ `off`.
- CORS không cho credentials; API không dùng cookie.

Còn mở: `/health`, `/api/v1/items/popular` và `/api/v1/weather` không cần token và chưa có giới hạn tần suất.
Endpoint thời tiết ghép `appid` vào URL vì AgroMonitoring chỉ nhận key qua query; server không log URL này.

## Chạy

Cục bộ:

```powershell
.\venv\Scripts\python.exe -m uvicorn src.api.app:app --port 8000
```

Có Cloudflare Tunnel và ghi URL vào `server_config/recsys_url` để app tự kết nối:

```powershell
.\venv\Scripts\python.exe -m src.api.tunnel --port 8000
```

Google Colab: mở [notebook API](../../notebooks/TopTop_RecSys_Colab_API.ipynb)
(sinh bằng [build_notebook.py](../../notebooks/build_notebook.py)), chọn Run all.
Notebook lấy code từ GitHub; kiểm tra đúng revision đã đồng bộ trước khi dùng
kết quả. Không mặc định notebook đang chạy source của workspace cục bộ.
