# Catalog kết quả RecSys

Cập nhật 11/11/2026. Mỗi file giữ nguyên byte; metadata trong JSON là nguồn cuối cùng để đọc seed, source và protocol.
Bảng điểm tổng hợp: [CURRENT_STATE](../docs/CURRENT_STATE.md).

## Kết quả đầy đủ đang được trích dẫn

| File | Nội dung | Seed | Source |
| :-- | :-- | :-- | :-- |
| [benchmark_report_bounded_20261021_074350_e29d0387.json](benchmark_report_bounded_20261021_074350_e29d0387.json) | MF, iDCF, CDR, Popularity, Random trên ba dataset; đủ cả hai Recall | MF/iDCF 42, CDR 2020 | `134b536cc623` |
| [benchmark_all_8e44de4472_20261020_232046_d992f0ff_v4.json](benchmark_all_8e44de4472_20261020_232046_d992f0ff_v4.json) | Lượt huấn luyện gốc của báo cáo trên; đầu vào của lệnh `report` | như trên | `134b536cc623` |
| `lcdr_{coat,yahoo,kuairand}_20261028_081517_b71fff26.json` | LCDR, protocol H30 | 42 | `fd1df699561e` |
| `conalign_{coat,yahoo,kuairand}_20261102_*.json` | ConAlign, protocol C-src, KuaiRand cửa sổ paper; 9 file, sau khi sửa `best_state` | 0–2 | `4e05072a90c3` |
| [lcdr_coat_20261027_220934_6395e1a8.json](lcdr_coat_20261027_220934_6395e1a8.json) | LCDR và iDCF cùng seed trên Coat | 42–44 | `691998046fa1` |
| [cf_dl_coat_20261103_200701_387e7f14.json](cf_dl_coat_20261103_200701_387e7f14.json) | `cf-dl` Coat: MF, GMF, MLP, NeuMF, NeuMF-pre (file còn dòng TopPop/ItemKNN của mã đã xóa 07/11, không trích); trung bình, kiểm định theo seed và theo user. Khóa từng seed bị ghi đè do lỗi workflow, xem file `_per_seed` | 42–51 | `1341c2ff1acb` |
| [cf_dl_coat_20261103_200701_387e7f14_per_seed.json](cf_dl_coat_20261103_200701_387e7f14_per_seed.json) | Số từng seed của file trên, chấm lại từ checkpoint đã chọn, không huấn luyện; trung bình khớp file gốc (chênh 0) | 42–51 | chấm lại ở `56aea4e7592b` |
| [cf_dl_yahoo_20261103_203152_cce07ea1.json](cf_dl_yahoo_20261103_203152_cce07ea1.json) | NeuMF Yahoo, mã tác giả NCF | 42 | `56aea4e7592b` |
| [cf_dl_kuairand_20261103_203153_182dbb3e.json](cf_dl_kuairand_20261103_203153_182dbb3e.json) | NeuMF KuaiRand, mã tác giả NCF, đủ 100 epoch | 42 | `56aea4e7592b` |
| [lcdr_coat_20261104_001633_38fc69d6.json](lcdr_coat_20261104_001633_38fc69d6.json) | LCDR Coat 10 seed, protocol H30 | 42–51 | `56aea4e7592b` |
| [coat_seeds_4b77ed83d03fd5b3_20261111_163912_80b99b32.json](coat_seeds_4b77ed83d03fd5b3_20261111_163912_80b99b32.json) | MF và iDCF Coat 10 seed (`coat-seeds`), Windows; kiểm định theo cặp seed. MF trùng từng seed với lượt `cf-dl`; iDCF ra lại .5699 ± .0107 của mốc 28/10 (file gốc đã xóa cùng IViDR ngày 07/11) | 42–51 | `97ca516a40df` |
| [idcf_coat_10seeds_windows_20261111.json](idcf_coat_10seeds_windows_20261111.json) | iDCF Coat 10 seed, cùng seed và cùng máy với file trên, thêm Recall@5 bounded và AUC từng seed; NDCG@5 trùng tuyệt đối. Nguồn cho dòng iDCF Coat | 42–51 | `97ca516a40df` |
| [idcf_coat_10seeds_20261108.json](idcf_coat_10seeds_20261108.json) | iDCF Coat 10 seed chạy trên Linux: .5651 ± .0209, lệch bản Windows ở 6 seed (seed 45: .5110 so với .5726). Chỉ để tham khảo; không so cặp seed với MF, NeuMF, LCDR vì các mô hình đó chạy trên Windows | 42–51 | ghi trong JSON |
| [mrdr_cal_coat_20261104_013609_11a6bf42.json](mrdr_cal_coat_20261104_013609_11a6bf42.json) | MRDR-CAL Coat lượt 04/11; lượt 07/11 khớp tuyệt đối và thay thế | 0–9 | `fc12897bbcf8` |
| [mrdr_cal_yahoo_20261104_013610_aa1da2a8.json](mrdr_cal_yahoo_20261104_013610_aa1da2a8.json) | MRDR-CAL Yahoo!R3 lượt 04/11, thay bằng lượt 07/11 (lệch trong phương sai seed) | 0–9 | `fc12897bbcf8` |
| [mrdr_cal_kuairand_20261104_013611_0644a364.json](mrdr_cal_kuairand_20261104_013611_0644a364.json) | MRDR-CAL KuaiRand-Pure lượt 04/11, thay bằng lượt 08/11 (lệch trong phương sai seed) | 0–2 | `fc12897bbcf8` |
| [mrdr_cal_coat_20261107_222905_f9db8ab0.json](mrdr_cal_coat_20261107_222905_f9db8ab0.json) | MRDR-CAL Coat, protocol Hu et al., kèm số bài báo và NDCG@5/Recall@5 của đồ án | 0–9 | `97ca516a40df` |
| [mrdr_cal_yahoo_20261107_224026_a0c7fad3.json](mrdr_cal_yahoo_20261107_224026_a0c7fad3.json) | MRDR-CAL Yahoo!R3, kèm NDCG@5/Recall@5 | 0–9 | `97ca516a40df` |
| [mrdr_cal_kuairand_20261108_022532_067ff6a2.json](mrdr_cal_kuairand_20261108_022532_067ff6a2.json) | MRDR-CAL KuaiRand-Pure; Recall chuẩn hóa và dạng đếm, kèm NDCG@5/Recall@5 | 0–2 | `97ca516a40df` |
| [clev_coat_20261104_011507_7e1c36a1.json](clev_coat_20261104_011507_7e1c36a1.json) | CLEV-DR Coat, protocol Zhang et al., quét alpha .4/.6/.8 | 0–4 | `3bb669cc0d45` |
| [clev_yahoo_20261104_011509_c0d3258f.json](clev_yahoo_20261104_011509_c0d3258f.json) | CLEV-DR Yahoo!R3, quét alpha .4/.6/.8 | 0–2 | `3bb669cc0d45` |
| [clev_kuairand_20261104_171457_8a75f508.json](clev_kuairand_20261104_171457_8a75f508.json) | CLEV-DR KuaiRand-Pure, quét alpha .2–.8, mảng int32 tối ưu RAM | 0–2 | `aaadb81eb5a6` |
| [serving_latency_20261106_203153_7d041bbb.json](serving_latency_20261106_203153_7d041bbb.json) | Độ trễ suy luận CPU chấm 1.000 và 6.712 ứng viên (MF, NeuMF, CDR, iDCF/LCDR, CLEV-DR predict, ConAlign; khởi tạo ngẫu nhiên, kích thước KuaiRand) và `/recommend` trong tiến trình trên export TopTop. Sinh bằng `experiments/workflows/serving_latency.py` | 0 | trong JSON |

## Tổng hợp và kiểm chứng

| File | Nội dung |
| :-- | :-- |
| [conalign_summary_20261102.json](conalign_summary_20261102.json) | ConAlign 3 seed: trung bình, độ lệch chuẩn, số paper, danh sách file |
| [lcdr_conalign_studies_summary_20261030.json](lcdr_conalign_studies_summary_20261030.json) | Biến thể ràng buộc và lưới LR × WD của LCDR; phần cửa sổ KuaiRand của ConAlign đo trước khi sửa `best_state`, không trích điểm tuyệt đối |
| [conalign_fix_validation_20261102.json](conalign_fix_validation_20261102.json) | CDR validation ba seed của mốc 02/11 |
| [ncf_milestone_validation_20261103.json](ncf_milestone_validation_20261103.json) | CDR validation ba seed của mốc NeuMF (04/11 sáng) |
| [mrdr_cal_clev_validation_20261104.json](mrdr_cal_clev_validation_20261104.json) | CDR validation ba seed của mốc MRDR-CAL, CLEV-DR (04/11), khớp chính xác mốc trước |
| [model_removal_validation_20261107.json](model_removal_validation_20261107.json) | CDR validation ba seed của mốc xóa IViDR, TopPop/ItemKNN-CF (07/11), khớp chính xác mốc trước |
| [lint_cleanup_validation_20261107.json](lint_cleanup_validation_20261107.json) | CDR validation ba seed của mốc dọn lint (07/11), khớp chính xác mốc trước |
| [mrdr_topk_validation_20261108.json](mrdr_topk_validation_20261108.json) | CDR validation ba seed của mốc hiện hành (MRDR-CAL thêm chỉ số @5), khớp chính xác mốc trước; `check_docs.py` đối chiếu file này |
| [benchmark_all_f109d46fbe_20261104_222805_e21bb674_v4.json](benchmark_all_f109d46fbe_20261104_222805_e21bb674_v4.json) | Lượt chạy benchmark tổng hợp mốc 04/11 (iDCF Yahoo .6578, KuaiRand .4055 so với mốc lịch sử .6558 / .4053 do phương sai seed ngẫu nhiên trên CPU; không thay thế mốc chuẩn khi chưa có đối chiếu chính thức) |

## Báo cáo từng lượt của các nghiên cứu: `studies/`

| Mẫu tên file | Thuộc phân tích |
| :-- | :-- |
| `lcdr_constraint_*`, `lcdr_grid_*` | [LCDR và ConAlign](../docs/benchmarks/lcdr_conalign_20261027.md) |
| `conalign_kuairand_*_20261028*` | Cửa sổ KuaiRand của ConAlign, đo trước khi sửa `best_state`; chỉ giữ để tái lập chiều so sánh |

Script của các nghiên cứu nằm ở [docs/archive](../docs/archive/README.md). Khi chạy lại, script ghi vào `results/`.

## Quy tắc trích số

- Trích kèm dataset, mô hình, seed, source và protocol; không trộn protocol trong cùng một so sánh.
- Không dùng validation hoặc smoke thay held-out test; không dùng test để chọn cấu hình.
- Lượt chạy mới tạo file mới và thêm dòng vào catalog này; không ghi đè file cũ.
