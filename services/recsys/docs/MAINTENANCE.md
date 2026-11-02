# Cập nhật tài liệu RecSys

Kiểm tra bằng `python docs/check_docs.py` từ `services/recsys`. Lệnh chỉ đọc và báo lỗi: file chưa phân loại,
liên kết hỏng, file bảo vệ bị đổi, source lệch mốc đã ghi. Nó không xác nhận đúng đắn khoa học của nội dung.

## Nơi chịu trách nhiệm

| Nội dung | File |
| :-- | :-- |
| Trạng thái, bảng điểm, giới hạn | [CURRENT_STATE](CURRENT_STATE.md) |
| Định nghĩa phương pháp, khác biệt với paper/source | [paper_model_alignment](benchmarks/paper_model_alignment.md) |
| Giao thức benchmark | [evaluation_protocol](benchmarks/evaluation_protocol.md) |
| Phân loại kết quả | [results/CATALOG](../results/CATALOG.md) |
| Mốc kiểm chứng dạng máy đọc | [state_snapshot.json](state_snapshot.json) |

Không tạo thêm kết luận hoặc bảng cấu hình song song; dẫn liên kết tới nơi chịu trách nhiệm.

## Giữ tài liệu gọn

Từ 02/11/2026 Git là nơi lưu lịch sử. Sửa thẳng tài liệu hiện hành để nó luôn đúng trạng thái mới.

1. Không tạo ZIP, snapshot hay thư mục archive theo ngày cho tài liệu.
2. Không ghi nhật ký từng mốc vào CURRENT_STATE; thay nội dung cũ bằng trạng thái mới, chi tiết để trong commit.
3. Chỉ giữ log của mốc kiểm chứng mới nhất, xóa log của mốc trước khi thêm mốc mới.
4. Không commit kết quả smoke. Chỉ giữ báo cáo đang được trích dẫn trong `results/` và `results/studies/`.
5. Bài viết phân tích chỉ giữ phần còn dùng; hướng đã thay thế thì bỏ, không để lại như lịch sử.

## Khi có thay đổi

1. Đối chiếu code thực thi và metadata gốc; tách rõ đã triển khai, kết quả validation/test và giả thuyết.
2. Sau khi đổi source/config, chạy kiểm chứng rồi cập nhật CURRENT_STATE và `state_snapshot.json`.
   Không đổi hash của lượt chạy cũ; nếu chưa chạy lại thì ghi rõ số thuộc mốc trước.
3. Không ghi đè file kết quả hoặc PDF; lượt chạy mới tạo file mới và đăng ký trong `results/CATALOG.md`.
4. Đăng ký file mới trong `catalog.json` (`path`, `role`, `immutable`; file bảo vệ có thêm `sha256`).
5. Chạy `check_docs.py`.

## Khôi phục tài liệu cũ

Toàn bộ tài liệu, log và kết quả trước đợt dọn 02/11/2026 còn trong Git tại commit `a91f0bd`:

```powershell
git ls-tree -r --name-only a91f0bd -- services/recsys/docs/archive
git checkout a91f0bd -- services/recsys/docs/archive/2026-10-22
```
