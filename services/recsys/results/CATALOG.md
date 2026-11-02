# Catalog kết quả RecSys

Cập nhật 02/11/2026. Mỗi file giữ nguyên byte; metadata trong JSON là nguồn cuối cùng để đọc seed, source và protocol.
Bảng điểm tổng hợp: [CURRENT_STATE](../docs/CURRENT_STATE.md).

## Kết quả đầy đủ đang được trích dẫn

| File | Nội dung | Seed | Source |
| :-- | :-- | :-- | :-- |
| [benchmark_report_bounded_20261021_074350_e29d0387.json](benchmark_report_bounded_20261021_074350_e29d0387.json) | MF, iDCF, CDR, Popularity, Random trên ba dataset; đủ cả hai Recall | MF/iDCF 42, CDR 2020 | `134b536cc623` |
| [benchmark_all_8e44de4472_20261020_232046_d992f0ff_v4.json](benchmark_all_8e44de4472_20261020_232046_d992f0ff_v4.json) | Lượt huấn luyện gốc của báo cáo trên; đầu vào của lệnh `report` | như trên | `134b536cc623` |
| [ividr_benchmark_recovered_coat_yahoo_20261029.json](ividr_benchmark_recovered_coat_yahoo_20261029.json) | IViDR Coat, Yahoo, chấm lại từ checkpoint chọn bằng validation | 42 | `fd1df699561e` |
| [benchmark_kuairand_ividr_be219eee39_20261029_193713_d87515c9_v4.json](benchmark_kuairand_ividr_be219eee39_20261029_193713_d87515c9_v4.json) · [MD](benchmark_kuairand_ividr_be219eee39_20261029_193713_d87515c9_v4.md) | IViDR KuaiRand | 42 | `fd1df699561e` |
| `lcdr_{coat,yahoo,kuairand}_20261028_081517_b71fff26.json` | LCDR, protocol H30 | 42 | `fd1df699561e` |
| `conalign_{coat,yahoo,kuairand}_20261028_081519_b614253e.json` | ConAlign, protocol C-src, cửa sổ KuaiRand của source | 0 | `fd1df699561e` |
| [lcdr_coat_20261027_220934_6395e1a8.json](lcdr_coat_20261027_220934_6395e1a8.json) | LCDR và iDCF cùng seed trên Coat | 42–44 | `691998046fa1` |
| [conalign_coat_20261027_220711_8da7d449.json](conalign_coat_20261027_220711_8da7d449.json) | ConAlign Coat lần đầu, đối chiếu paper | 0 | `691998046fa1` |

## Tổng hợp và kiểm chứng

| File | Nội dung |
| :-- | :-- |
| [ividr_ten_seed_summary_20261028.json](ividr_ten_seed_summary_20261028.json) | IViDR mặc định, IViDR theo paper, iDCF: 10 seed Coat và kiểm định ghép cặp |
| [lcdr_conalign_studies_summary_20261030.json](lcdr_conalign_studies_summary_20261030.json) | Cửa sổ KuaiRand của ConAlign; biến thể ràng buộc và lưới LR × WD của LCDR |
| [console_models_validation_20261030.json](console_models_validation_20261030.json) | CDR validation ba seed của mốc hiện hành; `check_docs.py` đối chiếu file này |

## Báo cáo từng lượt của các nghiên cứu: `studies/`

| Mẫu tên file | Thuộc phân tích |
| :-- | :-- |
| `ividr_ten_seed_*` | [Xác nhận 10 seed](../docs/benchmarks/ividr_root_cause_20261027.md#7-xác-nhận-10-seed-4251-28102026) |
| `ividr_rootcause_*`, `ividr_bce_*` | [Nguyên nhân IViDR thấp hơn paper](../docs/benchmarks/ividr_root_cause_20261027.md) |
| `ividr_opt_*` | [Ablation Eq. (10)](../docs/benchmarks/ividr_eq10_ablation_20261027.md) |
| `ividr_research_diagnostics_*` | [Chẩn đoán nhánh tái dựng](../docs/benchmarks/ividr_sources_20261023.md) |
| `conalign_kuairand_window_*`, `lcdr_constraint_*`, `lcdr_grid_*` | [LCDR và ConAlign](../docs/benchmarks/lcdr_conalign_20261027.md) |

Script của các nghiên cứu nằm ở [docs/archive](../docs/archive/README.md). Khi chạy lại, script ghi vào `results/`.

## Quy tắc trích số

- Trích kèm dataset, mô hình, seed, source và protocol; không trộn protocol trong cùng một so sánh.
- Không dùng validation hoặc smoke thay held-out test; không dùng test để chọn cấu hình.
- Lượt chạy mới tạo file mới và thêm dòng vào catalog này; không ghi đè file cũ.
