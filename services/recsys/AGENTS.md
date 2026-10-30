# RecSys: đọc trạng thái trước khi sửa hoặc đánh giá mô hình

Phạm vi: toàn bộ `services/recsys/`.

1. Đọc `docs/CURRENT_STATE.md` trước, sau đó `docs/benchmarks/paper_model_alignment.md`
   và `docs/benchmarks/evaluation_protocol.md` nếu tác vụ liên quan mô hình/metric.
2. Trạng thái hiện tại phải được đối chiếu với logic thực thi và config, không suy ra
   từ comment, tên `v4`, thời gian sửa file, slide hoặc bảng điểm cũ.
3. Đọc `results/CATALOG.md` và metadata JSON trước khi trích số. Phân biệt test,
   validation, smoke, ablation và số paper. Không dùng các số này thay thế cho nhau.
4. `training_profile=paper` là tên profile của triển khai CDR theo công thức;
   không có nghĩa đã tái lập đầy đủ thí nghiệm paper. Ngày 21/10/2026 người dùng
   chọn bộ bốn MF + CDR + iDCF + IViDR và sau đó yêu cầu sửa IViDR theo paper.
   IViDR hiện dùng learned IV + dual iVAE + BCE, tên hiển thị IViDR. Từ 28/10 mặc định
   cố định prior mean giai đoạn 1 bằng 0 và đặt trọng số mẫu âm BCE .1 (lệch Eq. 42/25;
   docs/benchmarks/ividr_root_cause_20261027.md). Bản theo chữ paper: ivae_overrides
   prior_mean='learned', negative_weight=1. Không đặt tên riêng cho cấu hình mặc định. Bản 22/10
   học feature embedding và marginalize xác suất trước BCE; coordinate adapter
   Eq. (10) được công khai tại docs/benchmarks/ividr_reference_20261022.md.
   Model identity mới ividr_reference không được gán cho checkpoint BCE-v1.
   MF/iDCF
   vẫn dùng MSE. Đây là triển khai công thức arXiv với lựa chọn địa phương đã ghi
   rõ, chưa chứng nhận tái lập bản ACM. Checkpoint MSE cũ
   giữ nguyên; kết quả loss ablation không được dùng để tune theo test.
   Người dùng đã chọn CDR source protocol làm mặc định: Coat/Yahoo >=3,
   calibration 5% nhãn random chấm điểm, toàn random log, train-loss stopping,
   Recall bounded/AUC global. Không tự đổi mặc định này thành shared validation-only.
   Có thể gộp bảng hiển thị khi mỗi dòng ghi protocol và loại AUC; không paired-test
   với MF/iDCF khác giao thức. Không điền metric thiếu bằng số giả; tính lại checkpoint.
   Bảng tổng hợp chỉ hiển thị Recall@5 bounded theo lựa chọn người dùng; giữ cả
   hai Recall trong JSON và không đổi tên bounded thành Recall chuẩn khi trích paper.
5. Không ghi đè artifact kết quả, evidence, PDF/bản chép paper hoặc snapshot lưu trữ.
   Ngoại lệ: khi người dùng yêu cầu xóa rõ ràng một nguồn bị loại cùng tài liệu
   liên quan, xóa cả bản lưu của nguồn đó; không tạo ZIP mới giữ lại nội dung đã xóa.
   Khi sửa một nhận định lịch sử, ghi đính chính ở tài liệu hiện hành, dẫn file gốc;
   chạy lại thí nghiệm phải tạo artifact mới có nguồn/cấu hình rõ ràng.
6. Khi code/config/protocol thay đổi, cập nhật trạng thái và bằng chứng phù hợp.
   Không đổi source hash của một lượt chạy cũ thành hash mới và không chuyển điểm
   lịch sử sang phiên bản mới. `docs/state_snapshot.json` ghi mốc kiểm chứng cụ thể.
7. Chạy `python docs/check_docs.py` sau chỉnh tài liệu. Nếu source hash khác snapshot,
   rà lại thay đổi và ghi mốc mới sau kiểm chứng; không bỏ qua bằng cách gán lại hash cũ.
   Tài liệu mới cần được phân loại trong `docs/catalog.json`.
8. LCDR và ConAlign (27/10/2026) là mô hình thực nghiệm; từ 30/10 người dùng yêu cầu đưa vào
   `benchmark --model all` (vẫn chạy riêng được qua `lcdr`, `conalign`). Bảng gộp ghi protocol từng
   dòng: LCDR H30, ConAlign C-src; không paired-test chéo protocol. ConAlign KuaiRand mặc định cửa sổ
   paper vì loader source bỏ sót 01–05/05. LCDR không có mã tác giả: cài đặt lại từ paper trên pipeline
   iDCF, các lựa chọn địa phương ghi tại src/models/lcdr/source.json; không gọi là tái lập.
   ConAlign port từ source khóa commit ở third_party/conalign (repo không có LICENSE),
   protocol/metric riêng, không so điểm trực tiếp với H30 hoặc CDR source protocol.
   Đọc docs/benchmarks/lcdr_conalign_20261027.md trước khi sửa hai pipeline này.

Các quy tắc này giữ thông tin có thể đối chiếu qua các lần làm việc; không yêu cầu
xin phép cho thao tác rà soát hay sửa lỗi đã được người dùng giao.
