# Catalog kết quả RecSys

Cập nhật 04/11/2026. Mỗi file giữ nguyên byte; metadata trong JSON là nguồn cuối cùng để đọc seed, source và protocol.
Bảng điểm tổng hợp: [CURRENT_STATE](../docs/CURRENT_STATE.md).

## Kết quả đầy đủ đang được trích dẫn

| File | Nội dung | Seed | Source |
| :-- | :-- | :-- | :-- |
| [benchmark_report_bounded_20261021_074350_e29d0387.json](benchmark_report_bounded_20261021_074350_e29d0387.json) | MF, iDCF, CDR, Popularity, Random trên ba dataset; đủ cả hai Recall | MF/iDCF 42, CDR 2020 | `134b536cc623` |
| [benchmark_all_8e44de4472_20261020_232046_d992f0ff_v4.json](benchmark_all_8e44de4472_20261020_232046_d992f0ff_v4.json) | Lượt huấn luyện gốc của báo cáo trên; đầu vào của lệnh `report` | như trên | `134b536cc623` |
| [ividr_benchmark_recovered_coat_yahoo_20261029.json](ividr_benchmark_recovered_coat_yahoo_20261029.json) | IViDR Coat, Yahoo, chấm lại từ checkpoint chọn bằng validation | 42 | `fd1df699561e` |
| [benchmark_kuairand_ividr_be219eee39_20261029_193713_d87515c9_v4.json](benchmark_kuairand_ividr_be219eee39_20261029_193713_d87515c9_v4.json) · [MD](benchmark_kuairand_ividr_be219eee39_20261029_193713_d87515c9_v4.md) | IViDR KuaiRand | 42 | `fd1df699561e` |
| `lcdr_{coat,yahoo,kuairand}_20261028_081517_b71fff26.json` | LCDR, protocol H30 | 42 | `fd1df699561e` |
| `conalign_{coat,yahoo,kuairand}_20261102_*.json` | ConAlign, protocol C-src, KuaiRand cửa sổ paper; 9 file, sau khi sửa `best_state` | 0–2 | `4e05072a90c3` |
| [lcdr_coat_20261027_220934_6395e1a8.json](lcdr_coat_20261027_220934_6395e1a8.json) | LCDR và iDCF cùng seed trên Coat | 42–44 | `691998046fa1` |
| [cf_dl_coat_20261103_200701_387e7f14.json](cf_dl_coat_20261103_200701_387e7f14.json) | `cf-dl` Coat: TopPop, ItemKNN, MF, GMF, MLP, NeuMF, NeuMF-pre; trung bình, kiểm định theo seed và theo user. Khóa từng seed bị ghi đè do lỗi workflow, xem file `_per_seed` | 42–51 | `1341c2ff1acb` |
| [cf_dl_coat_20261103_200701_387e7f14_per_seed.json](cf_dl_coat_20261103_200701_387e7f14_per_seed.json) | Số từng seed của file trên, chấm lại từ checkpoint đã chọn, không huấn luyện; trung bình khớp file gốc (chênh 0) | 42–51 | chấm lại ở `56aea4e7592b` |
| [cf_dl_yahoo_20261103_203152_cce07ea1.json](cf_dl_yahoo_20261103_203152_cce07ea1.json) | NeuMF Yahoo, mã tác giả NCF | 42 | `56aea4e7592b` |
| [cf_dl_kuairand_20261103_203153_182dbb3e.json](cf_dl_kuairand_20261103_203153_182dbb3e.json) | NeuMF KuaiRand, mã tác giả NCF, đủ 100 epoch | 42 | `56aea4e7592b` |
| [lcdr_coat_20261104_001633_38fc69d6.json](lcdr_coat_20261104_001633_38fc69d6.json) | LCDR Coat 10 seed, protocol H30 | 42–51 | `56aea4e7592b` |
| [mrdr_cal_coat_20261104_013609_11a6bf42.json](mrdr_cal_coat_20261104_013609_11a6bf42.json) | MRDR-CAL Coat, protocol Hu et al., kèm số bài báo | 0–9 | `fc12897bbcf8` |
| [mrdr_cal_yahoo_20261104_013610_aa1da2a8.json](mrdr_cal_yahoo_20261104_013610_aa1da2a8.json) | MRDR-CAL Yahoo!R3, protocol Hu et al. | 0–9 | `fc12897bbcf8` |
| [mrdr_cal_kuairand_20261104_013611_0644a364.json](mrdr_cal_kuairand_20261104_013611_0644a364.json) | MRDR-CAL KuaiRand-Pure, protocol Hu et al.; Recall chuẩn hóa và dạng đếm | 0–2 | `fc12897bbcf8` |
| [clev_coat_20261104_011507_7e1c36a1.json](clev_coat_20261104_011507_7e1c36a1.json) | CLEV-DR Coat, protocol Zhang et al., quét alpha .4/.6/.8 | 0–4 | `3bb669cc0d45` |
| [clev_yahoo_20261104_011509_c0d3258f.json](clev_yahoo_20261104_011509_c0d3258f.json) | CLEV-DR Yahoo!R3, quét alpha .4/.6/.8 | 0–2 | `3bb669cc0d45` |
| [clev_kuairand_20261104_171457_8a75f508.json](clev_kuairand_20261104_171457_8a75f508.json) | CLEV-DR KuaiRand-Pure, quét alpha .2–.8, mảng int32 tối ưu RAM | 0–2 | `d24904b` |
| [serving_latency_20261106_203153_7d041bbb.json](serving_latency_20261106_203153_7d041bbb.json) | Độ trễ suy luận CPU chấm 1.000 và 6.712 ứng viên (MF, NeuMF, CDR, iDCF/LCDR, CLEV-DR predict, ConAlign; khởi tạo ngẫu nhiên, kích thước KuaiRand) và `/recommend` trong tiến trình trên export TopTop. Sinh bằng `experiments/workflows/serving_latency.py` | 0 | trong JSON |

## Tổng hợp và kiểm chứng

| File | Nội dung |
| :-- | :-- |
| [ividr_ten_seed_summary_20261028.json](ividr_ten_seed_summary_20261028.json) | IViDR mặc định, IViDR theo paper, iDCF: 10 seed Coat và kiểm định ghép cặp |
| [conalign_summary_20261102.json](conalign_summary_20261102.json) | ConAlign 3 seed: trung bình, độ lệch chuẩn, số paper, danh sách file |
| [lcdr_conalign_studies_summary_20261030.json](lcdr_conalign_studies_summary_20261030.json) | Biến thể ràng buộc và lưới LR × WD của LCDR; phần cửa sổ KuaiRand của ConAlign đo trước khi sửa `best_state`, không trích điểm tuyệt đối |
| [conalign_fix_validation_20261102.json](conalign_fix_validation_20261102.json) | CDR validation ba seed của mốc 02/11 |
| [ncf_milestone_validation_20261103.json](ncf_milestone_validation_20261103.json) | CDR validation ba seed của mốc NeuMF (04/11 sáng) |
| [mrdr_cal_clev_validation_20261104.json](mrdr_cal_clev_validation_20261104.json) | CDR validation ba seed của mốc hiện hành (MRDR-CAL, CLEV-DR), khớp chính xác mốc trước; `check_docs.py` đối chiếu file này |
| [benchmark_all_f109d46fbe_20261104_222805_e21bb674_v4.json](benchmark_all_f109d46fbe_20261104_222805_e21bb674_v4.json) | Lượt chạy benchmark tổng hợp mốc 04/11 (iDCF Yahoo .6578, KuaiRand .4055 so với mốc lịch sử .6558 / .4053 do phương sai seed ngẫu nhiên trên CPU; không thay thế mốc chuẩn khi chưa có đối chiếu chính thức) |

## Báo cáo từng lượt của các nghiên cứu: `studies/`

| Mẫu tên file | Thuộc phân tích |
| :-- | :-- |
| `ividr_ten_seed_*` | [Xác nhận 10 seed](../docs/benchmarks/ividr_root_cause_20261027.md#7-xác-nhận-10-seed-4251-28102026) |
| `ividr_rootcause_*`, `ividr_bce_*` | [Nguyên nhân IViDR thấp hơn paper](../docs/benchmarks/ividr_root_cause_20261027.md) |
| `ividr_opt_*` | [Ablation Eq. (10)](../docs/benchmarks/ividr_eq10_ablation_20261027.md) |
| `ividr_research_diagnostics_*` | [Chẩn đoán nhánh tái dựng](../docs/benchmarks/ividr_sources_20261023.md) |
| `lcdr_constraint_*`, `lcdr_grid_*` | [LCDR và ConAlign](../docs/benchmarks/lcdr_conalign_20261027.md) |
| `conalign_kuairand_*_20261028*` | Cửa sổ KuaiRand của ConAlign, đo trước khi sửa `best_state`; chỉ giữ để tái lập chiều so sánh |

Script của các nghiên cứu nằm ở [docs/archive](../docs/archive/README.md). Khi chạy lại, script ghi vào `results/`.

## Quy tắc trích số

- Trích kèm dataset, mô hình, seed, source và protocol; không trộn protocol trong cùng một so sánh.
- Không dùng validation hoặc smoke thay held-out test; không dùng test để chọn cấu hình.
- Lượt chạy mới tạo file mới và thêm dòng vào catalog này; không ghi đè file cũ.
