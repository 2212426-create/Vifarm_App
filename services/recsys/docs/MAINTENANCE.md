# Cập nhật tài liệu mà không làm mất dấu vết

Điểm đọc chính: [CURRENT_STATE](CURRENT_STATE.md). Phân loại file và checksum:
[catalog.json](catalog.json). Kiểm tra bằng `python docs/check_docs.py` từ thư mục dịch vụ.
Lệnh chỉ đọc và báo lỗi; không tự sửa nhận định, số liệu hoặc ghi lại checksum.

## Quyền chịu trách nhiệm của từng tài liệu

- CURRENT_STATE giữ trạng thái triển khai, giới hạn và mốc bằng chứng.
- `paper_model_alignment` giữ định nghĩa phương pháp và khác biệt với paper/source.
- `evaluation_protocol` giữ giao thức benchmark; API guide giữ hành vi phục vụ riêng.
- `results/CATALOG` phân loại artifact, không sửa nội dung JSON/Markdown kết quả.
- Đề cương là kế hoạch; paper là tài liệu tham khảo; archive là lịch sử.

Không tạo thêm “kết luận hiện tại” hoặc bảng cấu hình ở một file song song khi đã
có nơi chịu trách nhiệm; dẫn liên kết tới nơi đó.

## Khi có thay đổi

1. Với hướng dẫn/trạng thái cần sửa, chụp bản trước dưới mốc archive mới; dùng tên
   chưa tồn tại. Không ghi đè ZIP, evidence, artifact, PDF hay snapshot cũ.
2. Đối chiếu phần code thực thi và metadata gốc. Tách rõ điều đã triển khai,
   điều mới kiểm thử, kết quả validation/test và điều vẫn chỉ là giả thuyết.
3. Sau đổi source/config, dùng kiểm chứng phù hợp rồi cập nhật CURRENT_STATE và
   `state_snapshot.json`. Giữ hash của các artifact cũ đúng với lượt chạy gốc.
   Nếu chưa chạy lại, ghi rõ bằng chứng thuộc mốc trước, không đổi hash cũ.
4. Đăng ký file mới trong `catalog.json`: `path`, `role`, `immutable`; file bảo toàn
   còn có `sha256`. Chỉ lấy checksum ban đầu cho file mới; không cập nhật checksum
   của file bất biến khi checker phát hiện nó đã đổi.
5. Nếu thêm artifact, thêm dòng vào `results/CATALOG.md` với scope, phiên bản và
   giới hạn. Nếu thiếu source hash hoặc provenance, ghi là chưa đủ thông tin.
6. Chạy checker; sửa liên kết hỏng, file chưa phân loại và nguồn trạng thái lỗi thời.
   Checker không xác nhận đúng đắn khoa học của nội dung; việc đó vẫn cần đối chiếu
   logic, paper và bằng chứng thực nghiệm.

## Mốc dọn 20/10/2026

ZIP giữ nguyên byte của 19 tài liệu trước sửa. Năm tài liệu lỗi thời có bản đọc
lưu trữ riêng; đề cương chỉ thêm nhãn kế hoạch. PPTX cũ được chuyển vào archive,
giữ nguyên byte. Báo cáo kết quả, evidence, PDF/bản chép paper và code huấn luyện
được giữ nguyên trong đợt này; [báo cáo dọn tài liệu](documentation_audit_2026-10-20.json)
ghi checksum và phạm vi kiểm tra.

Phần giới thiệu Markdown của notebook Colab và template đã sửa cách gọi IViDR;
bản gốc có ZIP/manifest riêng trong archive. Code cell notebook giữ nguyên, không
chạy notebook hoặc thực hiện đồng bộ Firebase trong đợt dọn tài liệu.

Đã thử sáu tình huống sai trên bản sao tạm: sửa artifact, đổi source, thêm file
chưa phân loại, link hỏng, heading hỏng và sửa ZIP gốc. Checker đều phát hiện;
[biên bản kiểm chứng](archive/2026-10-20/verification/documentation_guard_checks.json)
giữ kết quả và đường dẫn script thử. Đây là kiểm tra cơ chế bảo toàn tài liệu,
không phải lượt chạy lại 97 model test hoặc benchmark chất lượng.

