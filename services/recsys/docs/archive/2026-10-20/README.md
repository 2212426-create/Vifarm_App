# Snapshot trước dọn tài liệu — 20/10/2026

**LỊCH SỬ / ĐÃ BỊ THAY THẾ.** Mốc này lưu nội dung có thể mâu thuẫn với source hiện
tại; không phải bản xác nhận số liệu hoặc phương pháp.
[Đọc CURRENT_STATE](../../CURRENT_STATE.md).

## Bản nguyên gốc

[documentation_before_cleanup.zip](documentation_before_cleanup.zip) chứa 19 tài liệu
đúng byte trước đợt dọn, gồm README, hướng dẫn, đề cương, bản chép paper và slide.
[backup_manifest.json](backup_manifest.json) ghi đường dẫn gốc và checksum từng file.
Không sửa file trong ZIP để làm cho nhận định cũ đúng với source mới.

## Bản đọc trực tiếp

Các file dưới đây chỉ thêm nhãn lịch sử và đổi đường dẫn; câu chữ phân tích/số liệu
cũ được giữ để đối chiếu, **không mặc định còn đúng**:

- [Điều tra root cause](benchmarks/root_cause_analysis.md): lẫn nhiều mốc source;
  các bước “tiếp theo” và trạng thái warm-start đã có quyết định mới.
- [Review 19/10](benchmarks/review_2026-10-19.md): warm-start/cache và số test thuộc mốc cũ.
- [Bảng paper ghép cũ](benchmarks/paper_reference_comparison.md): ghép biến thể CDR;
  không dùng làm bảng xếp hạng giữa paper/dự án.
- [Slide cũ](presentation/presentation_slides.md) và [kịch bản cũ](presentation/presentation_script.md):
  có kết luận thắng MF, khử confounding hoàn toàn và hiệu năng phục vụ chưa được xác nhận.

[readable_manifest.json](readable_manifest.json) ánh xạ bản gốc → bản đọc và hash của
từng bản. Thông tin như “source hiện tại”, “đã sửa”, “79/90/97 test” bên trong các
file này chỉ có nghĩa ở mốc được viết trước khi snapshot, không phải tại lần đọc sau.
