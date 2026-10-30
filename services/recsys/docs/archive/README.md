# Lưu trữ tài liệu RecSys

**Nội dung trong archive là lịch sử, có thể chứa nhận định đã bị đính chính.**
Trạng thái được phép dùng cho công việc hiện tại: [CURRENT_STATE](../CURRENT_STATE.md).

| Mốc lưu trữ | Nội dung |
| :-- | :-- |
| [20/10/2026](2026-10-20/README.md) | Review/điều tra/bảng paper, slide/kịch bản và PPTX cũ; ZIP nguyên byte của 19 tài liệu Markdown |

ZIP giữ bản gốc; `backup_manifest.json` ghi SHA-256 từng member và ZIP.
Bản Markdown đọc trực tiếp có nhãn lịch sử, đường dẫn đã đổi theo vị trí mới;
`readable_manifest.json` ghi hash riêng, không thay hash bản gốc.

Archive cũ không ghi đè. Đợt sửa tiếp theo phải có mốc mới hoặc tên phiên bản mới.
Đính chính được ghi ngoài snapshot. Không sao chép các kết luận thắng/thua,
warm-start, API/deployment hoặc số test từ archive thành trạng thái hiện hành.

Mốc 20/10 còn có [ZIP notebook trước sửa mô tả](2026-10-20/notebook_documentation_before_cleanup.zip)
và [manifest notebook](2026-10-20/notebook_documentation_manifest.json). Chỉ sửa
nội dung Markdown giới thiệu; code cell không đổi và notebook không được chạy trong đợt dọn.
