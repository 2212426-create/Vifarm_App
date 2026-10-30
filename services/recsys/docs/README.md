# Điểm đọc tài liệu RecSys

**Bắt đầu tại [CURRENT_STATE.md](CURRENT_STATE.md).** Đây là trạng thái triển khai,
bằng chứng và việc còn thiếu tại mốc 27/10/2026. Danh sách phân loại đầy đủ:
[catalog.json](catalog.json). Các báo cáo lịch sử không tự thay thế trạng thái này.

## Tài liệu hiện hành

| Tài liệu | Quyết định nội dung nào |
| :-- | :-- |
| [CURRENT_STATE](CURRENT_STATE.md) | Trạng thái, giới hạn, mốc source và bằng chứng đã có |
| [README dịch vụ](../README.md) | Cài đặt và lệnh chạy |
| [Cấu trúc thư mục](architecture/directory_layout.md) | Package từng mô hình và mã tương thích |
| [Nguyên nhân IViDR thấp hơn paper](benchmarks/ividr_root_cause_20261027.md) | Hoán đổi latent/feedback, các giả thuyết đã bác bỏ, nguyên nhân BCE và thang latent |
| [Ablation IViDR Eq. (10)](benchmarks/ividr_eq10_ablation_20261027.md) | Bản v3 chuẩn hóa phần cộng, ablation T/F/R trên Coat 3 seed; mặc định giữ v2 |
| [LCDR và ConAlign](benchmarks/lcdr_conalign_20261027.md) | Hai mô hình thực nghiệm: lệnh chạy, protocol, đối chiếu paper/source và kết quả |
| [Định nghĩa mô hình](benchmarks/paper_model_alignment.md) | Loss, backbone, khởi tạo, khác biệt với paper/source |
| [IViDR hiện hành](benchmarks/ividr_reference_20261022.md) | Công thức, learned feature embedding, marginal BCE, coordinate adapter và cách chạy |
| [Nghiên cứu tối ưu IViDR](benchmarks/ividr_optimization_research_20261023.md) | Điểm paper đúng phiên bản, chẩn đoán nhánh tái dựng, nguồn tham khảo và kế hoạch validation; chưa sửa model |
| [IViDR-BCE cũ](benchmarks/ividr_bce_20261021.md) | Bằng chứng và loss ablation của phiên bản 21/10 |
| [Giao thức](benchmarks/evaluation_protocol.md) | MF/iDCF held-out và CDR source protocol riêng; nhãn, split, calibration, metric |
| [Chạy Yahoo/CDR source](../README.md) | Lệnh download, smoke, benchmark sáu mô hình và đối chứng script |
| [Catalog kết quả](../results/CATALOG.md) | Phân biệt validation, smoke, lịch sử và điều kiện trích số |
| [API](api/colab_api_guide.md) | Dữ liệu và endpoint phục vụ ứng dụng |
| [MF/optimizer](benchmarks/mf_optimizer_audit.md) | Tên loss và phạm vi thí nghiệm Adam/SGD |
| [Tham chiếu paper](benchmarks/paper_reference_comparison.md) | Nguồn bên ngoài, ghi đúng dataset/biến thể |

Mỗi kết luận có một nơi chịu trách nhiệm. README và mục lục dẫn tới nơi đó thay vì
chép lại bảng cấu hình hoặc kết quả rồi để các bản khác nhau theo thời gian.

## Tài liệu tham khảo và lưu trữ

- [PDF nghiên cứu](papers/) và [chỉ dẫn đọc bản chép paper](paper_summaries/README.md):
  mô tả nghiên cứu bên ngoài, không phải trạng thái triển khai của dự án.
- [Đề cương](de_cuong/README.md): tài liệu kế hoạch, không xác nhận các phần đã triển khai.
- [Tình trạng slide/kịch bản](presentation/README.md): bản cũ đã thu hồi vì nhận định
  chưa đủ bằng chứng; chưa có bộ thuyết trình hiện hành được phê duyệt.
- [Archive](archive/README.md): bản đọc lịch sử có nhãn và ZIP nguyên byte trước dọn.
- [Review 19/10](benchmarks/review_2026-10-19.md) và
  [điều tra CDR](benchmarks/root_cause_analysis.md): điểm dẫn vào lịch sử và đính chính,
  không phải hướng dẫn phục hồi mô hình cũ.

## Khi cập nhật tài liệu

1. Đối chiếu runtime config/logic và artifact; ghi rõ kết luận thuộc source nào.
2. Lưu bản trước khi thay nhận định; giữ nguyên số và hash của artifact cũ.
3. Thêm tài liệu mới vào catalog với đúng vai trò; snapshot cũ không ghi đè.
4. Chạy `python docs/check_docs.py` từ thư mục dịch vụ.

[Quy trình bảo toàn và cập nhật](MAINTENANCE.md) mô tả cách thêm mốc mới mà không
đổi số liệu, checksum hoặc kết luận của artifact cũ.

Ngày 20/10 đã dọn các nhận định mâu thuẫn trong bộ tài liệu đọc hiện tại.
Đợt 19/10 trước đó đã gỡ bốn kế hoạch/hướng dẫn vận hành lỗi thời; danh sách nằm
trong bản README cũ ở ZIP archive, không được coi là các file còn tồn tại.
