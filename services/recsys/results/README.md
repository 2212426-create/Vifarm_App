# Kết quả RecSys

Tra cứu đầy đủ tại [CATALOG.md](CATALOG.md). Trạng thái triển khai và các giới hạn
thuộc [CURRENT_STATE](../docs/CURRENT_STATE.md).

## Các báo cáo cần đọc trước

| Báo cáo | Phạm vi |
| :-- | :-- |
| [MF/iDCF/IViDR/CDR Coat — Markdown](benchmark_coat_all_02b9e8eb46_20261022_073711_146173c9_v4.md) · [JSON](benchmark_coat_all_02b9e8eb46_20261022_073711_146173c9_v4.json) | Lượt đầy đủ reference-v2 đã kiểm chứng; giữ source hash huấn luyện gốc |

Không gộp smoke, validation và full benchmark thành cùng một loại kết quả.

## File cũ và lượt chạy mới

Đợt dọn **22/10/2026** chuyển **155 file** cũ/smoke/log vào
[archive theo nhóm](archive/2026-10-22/README.md). Cấp ngoài cùng giảm từ 252 còn 97 file.
Các file còn được script hoặc bằng chứng bất biến tham chiếu vẫn giữ nguyên vị trí.
Một file còn nằm ở cấp ngoài cùng không tự động là kết quả mô hình hiện hành.

Artifact gốc giữ nguyên byte, metric và hash. Tra đường dẫn cũ → mới cùng checksum
trong [manifest](../docs/archive/2026-10-22/results_cleanup/plan.json).
Checkpoint và dữ liệu không thuộc đợt dọn này.

Các lệnh training tiếp tục ghi báo cáo mới vào thư mục này. Đăng ký artifact mới
trong `docs/catalog.json` trước khi chạy `python docs/check_docs.py`; không ghi đè
báo cáo cũ hoặc dùng mtime để suy ra source, seed và giao thức đánh giá.
