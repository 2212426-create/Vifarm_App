# Tài liệu RecSys

**Bắt đầu tại [CURRENT_STATE.md](CURRENT_STATE.md):** bộ mô hình, bảng điểm, cấu hình mặc định và giới hạn.
Mỗi kết luận chỉ có một nơi chịu trách nhiệm; tài liệu khác dẫn liên kết thay vì chép lại.

## Tra cứu nhanh

| Cần biết | Đọc |
| :-- | :-- |
| Cài đặt và lệnh chạy | [README dịch vụ](../README.md) |
| Cấu trúc thư mục | [directory_layout](architecture/directory_layout.md) |
| Protocol, nhãn, split, metric | [evaluation_protocol](benchmarks/evaluation_protocol.md) |
| Định nghĩa mô hình, khác biệt với paper/source | [paper_model_alignment](benchmarks/paper_model_alignment.md) |
| File kết quả nào chứa số nào | [Catalog kết quả](../results/CATALOG.md) |
| API và Colab | [colab_api_guide](api/colab_api_guide.md) |
| Quy tắc cập nhật tài liệu | [MAINTENANCE](MAINTENANCE.md) |

## Phân tích theo mô hình

| Tài liệu | Nội dung |
| :-- | :-- |
| [Nguyên nhân IViDR thấp hơn paper](benchmarks/ividr_root_cause_20261027.md) | Hoán đổi latent/feedback, giả thuyết đã bác bỏ, xác nhận 10 seed |
| [Đặc tả IViDR](benchmarks/ividr_reference_20261022.md) | Công thức đã triển khai, lựa chọn paper để ngỏ |
| [Ablation Eq. (10)](benchmarks/ividr_eq10_ablation_20261027.md) | Bản v3 và các biến thể Table 4; mặc định giữ v2 |
| [Nguồn tham khảo IViDR](benchmarks/ividr_sources_20261023.md) | Điểm paper, mã liên quan, chẩn đoán nhánh tái dựng, tài liệu trích dẫn |
| [LCDR và ConAlign](benchmarks/lcdr_conalign_20261027.md) | Lệnh chạy, phần theo paper, kết quả, cửa sổ KuaiRand |
| [Khác biệt protocol của CDR](benchmarks/root_cause_analysis.md) | Vì sao CDR đạt .6567 theo script nhưng thấp hơn nhiều trên H30 |
| [Nguồn CDR, iDCF, IViDR](benchmarks/source_repository_review_20261021.md) | Commit đã khóa, khác biệt dữ liệu Yahoo |
| [MF, loss và optimizer](benchmarks/mf_optimizer_audit.md) | Mục tiêu mặc định của từng đầu chạy |
| [Tham chiếu paper](benchmarks/paper_reference_comparison.md) | Cách trích số paper đúng biến thể |

## Tài liệu tham khảo

- [PDF nghiên cứu](papers/README.md) và [bản chép paper](paper_summaries/README.md).
- [Đề cương](de_cuong/README.md): kế hoạch, không xác nhận kết quả.
- [Slide](presentation/README.md): chưa có bộ slide được kiểm chứng trong thư mục này.
- [Script và log giữ lại](archive/README.md).
