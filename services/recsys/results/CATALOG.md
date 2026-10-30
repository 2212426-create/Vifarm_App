# Catalog kết quả RecSys — mốc 30/10/2026

Phân loại theo nội dung JSON và source hash, không suy ngày chạy từ tên hoặc mtime.
Artifact giữ nguyên byte. Bảng dưới chỉ dẫn cách đọc, không thay metadata và không trộn điểm.
[Trạng thái hiện hành](../docs/CURRENT_STATE.md) · [Checksum](../docs/catalog.json).

## Hiện hành: benchmark sáu mô hình — 28–30/10/2026

Đầy đủ, source `fd1df699561e`, một seed: `lcdr_{coat,yahoo,kuairand}_20261028_081517_b71fff26.json` (H30),
`conalign_{coat,yahoo,kuairand}_20261028_081519_b614253e.json` (C-src, cửa sổ KuaiRand source),
[IViDR KuaiRand](benchmark_kuairand_ividr_be219eee39_20261029_193713_d87515c9_v4.json),
[IViDR Coat/Yahoo chấm lại từ checkpoint](ividr_benchmark_recovered_coat_yahoo_20261029.json).
Nghiên cứu (chọn bằng validation): `conalign_kuairand_window_{source,intended,paper}_seed*_20261028.json`,
`lcdr_constraint_*_20261028.json`, `lcdr_grid_*_20261028.json`;
[tổng hợp](lcdr_conalign_studies_summary_20261030.json). Smoke sáu mô hình source `eaaa557ae302`:
`benchmark_*_all_quick_*_20261030_*` và `cdr_source_*_20261030_*` (kiểm tra vận hành, không phải kết quả);
[CDR validation](console_models_validation_20261030.json).
[Bảng điểm và cách đọc](../docs/benchmarks/lcdr_conalign_20261027.md#kết-quả-đầy-đủ-ba-dataset-2830102026).

## Mốc trước: LCDR, ConAlign, ablation IViDR — 27/10/2026

[LCDR + iDCF Coat 3 seed](lcdr_coat_20261027_220934_6395e1a8.json) (H30, test chấm một lần) ·
[ConAlign Coat seed 0](conalign_coat_20261027_220711_8da7d449.json) (protocol source riêng) ·
`ividr_opt_*_20261027.json`: 5 biến thể IViDR × seed 42/43/44, chọn bằng validation.
File `*_smoke_*` chỉ là kiểm tra vận hành. Chi tiết và bảng điểm:
[LCDR/ConAlign](../docs/benchmarks/lcdr_conalign_20261027.md),
[IViDR](../docs/benchmarks/ividr_eq10_ablation_20261027.md).

## Mốc trước: gỡ MF-CRIB và EGMN — 27/10/2026

Theo yêu cầu người dùng, mọi kết quả, checkpoint và bằng chứng của MF-CRIB/EGMN
(gồm các mốc tích hợp và review PDF 22/10) đã bị xóa, không lưu bản sao.
[CDR validation mới](model_removal_validation_20261027.json): source `5bfc0e4080fe`,
134 test (133 đạt, 1 CUDA skip), ba seed khớp chính xác mốc sắp xếp package.
Điểm bốn mô hình bên dưới giữ nguyên hash huấn luyện gốc.

## Nghiên cứu IViDR — 23/10/2026, không có training mới

[Chẩn đoán checkpoint](ividr_research_diagnostics_20261023.json) chỉ dùng biased
exposure Coat; latent xuất lại khớp cache, checkpoint giữ nguyên checksum.
Perturbation tái dựng 0.2984% theo chuẩn; cosine giữa hai ma trận posterior mean
0.99998778. Đây không phải metric test hoặc bằng chứng tăng NDCG.
[Đối chiếu nguồn và kế hoạch đối chứng](../docs/benchmarks/ividr_optimization_research_20261023.md).
[Biên bản kiểm tra](ividr_research_verification_20261023.json) xác nhận source
runtime không đổi, 477 file bảo toàn giữ checksum; chưa chạy quality ablation.

## Cách tìm file sau đợt dọn 22/10/2026

[Điểm đọc nhanh](README.md) · [155 file đã chuyển vào archive](archive/2026-10-22/README.md)
· [Đường dẫn cũ → mới và SHA-256](../docs/archive/2026-10-22/results_cleanup/plan.json).
Các liên kết trong catalog này đã cập nhật; nội dung artifact giữ nguyên byte.
File được script/evidence bất biến tham chiếu vẫn giữ vị trí cũ. Không phân loại
một kết quả là hiện hành chỉ dựa vào việc nó còn ở cấp ngoài cùng.

## Mốc trước: sắp xếp package theo mô hình

[Kiểm chứng](package_layout_verification_20261022.json)
· [Đối chiếu AST và checkpoint](package_layout_parity_20261022.json)
· [Validation CDR](package_layout_validation_20261022.json).
Source `5cb6ca4bcf5d`, 134 test (133 đạt, 1 CUDA skip), smoke bốn mô hình trên
Coat/Yahoo/KuaiRand. Validation CDR ba seed khớp chính xác điểm/epoch trước sắp xếp.
Nạp lại checkpoint Coat cũ cho bốn mô hình cho metric chính xác như cũ; không
huấn luyện đầy đủ lại. Giữ hash huấn luyện gốc và hash đánh giá mới riêng biệt.

## Mốc trước: IViDR reference v2

[Coat đầy đủ bốn mô hình](benchmark_coat_all_02b9e8eb46_20261022_073711_146173c9_v4.md)
· [Kiểm chứng](ividr_reference_verification_20261022.json)
· [Validation CDR](ividr_reference_validation_20261022.json).
Source dd068e23091a, 132 test (131 đạt, 1 CUDA skip), smoke đủ ba dataset.
IViDR NDCG .541201 / Recall bounded .613273, Recall/all positives .558345.
So với BCE-v1 .529125 / bounded .590419 thì tăng; iDCF cùng lượt .569884 / .602295
vẫn cao hơn về NDCG. Một seed, chưa tái lập mean/std hoặc thắng toàn bộ metric.
MF/iDCF/CDR khớp chính xác mọi metric/tensor mốc trước. Giữ identity mới
`ividr_reference_bce_v2`; không gán lại checkpoint hoặc số lịch sử.
Chi tiết [đặc tả và lựa chọn còn thiếu trong paper](../docs/benchmarks/ividr_reference_20261022.md).

## Mốc trước: IViDR learned IV + dual iVAE + BCE-v1

[Coat đầy đủ](archive/2026-10-22/benchmark_history/benchmark_coat_all_b384ff80db_20261021_115348_e8c7d044_v4.md)
· [Kiểm chứng](archive/2026-10-22/diagnostics/ividr_bce_verification_20261021.json)
· [Validation](ividr_bce_validation_20261021.json).
Source 70897b831d4f; 126 test (125 đạt, 1 CUDA skip), smoke ba dataset.
MF/iDCF/CDR khớp từng tensor và metric trước sửa; IViDR-BCE NDCG .529125,
Recall bounded .590419. Cấu hình feedback chọn bằng validation, test một lần
cho checkpoint thắng. Không gọi là tái lập chính thức; xem
[chi tiết triển khai](../docs/benchmarks/ividr_bce_20261021.md).

[Ablation MSE/BCE](ividr_mse_bce_ablation_20261021.json): cùng latent và
LR/WD, Coat seed 42 cho MSE .540521 / bounded .603493, BCE .529125 / .590419.
Khi mỗi loss chọn LR/WD bằng validation, MSE .516317 / .594711;
BCE .529125 / .590419. Không suy ra ưu thế chung hoặc chọn loss bằng test.

## Mốc trước: bộ bốn theo yêu cầu, IViDR approximation

[Coat đầy đủ bốn mô hình](archive/2026-10-22/benchmark_history/benchmark_coat_all_e052d60c74_20261021_095855_83a07811_v4.md)
· [JSON](benchmark_coat_all_e052d60c74_20261021_095855_83a07811_v4.json)
· [Kiểm chứng](four_model_default_verification_20261021.json).
MF/iDCF/CDR khớp chính xác metric và từng tensor trọng số lượt trước;
IViDR-approx NDCG .532193 / Recall bounded .557884, thuộc pipeline staged cũ.
Training hash 35e5fcf0d0bd, source cuối 4ca654f49942 chỉ sửa thêm caption coat-seeds.
119 test (118 pass, 1 CUDA skip), smoke bốn mô hình trên cả ba dataset;
[validation CDR cuối](four_model_default_final_validation_20261021.json) ba seed khớp mốc cũ.
Xem [triển khai hiện hành](../docs/benchmarks/ividr_bce_20261021.md).

## Mốc trước: bảng ba mô hình chỉ giữ Recall bounded

Chạy lại Coat đầy đủ sau chốt hiển thị:
[MD](archive/2026-10-22/benchmark_history/benchmark_coat_all_666cb1327c_20261021_074841_a3d6e730_v4.md)
· [JSON](benchmark_coat_all_666cb1327c_20261021_074841_a3d6e730_v4.json)
· [Kiểm chứng lặp lại](archive/2026-10-22/diagnostics/coat_reproducibility_20261021_074841.json).
Source 6497b9eefd64, CPU 2 thread, full data/config mặc định; MF/iDCF seed 42,
CDR source seed 2020. Huấn luyện mới cả ba, không dùng lại trọng số cũ để tạo điểm.
Mọi metric, epoch chọn, data identity và từng tensor trọng số khớp lượt trước.
Không xem đây là seed độc lập hoặc bằng chứng hơn/kém giữa các protocol.

[Bảng hiện hành](archive/2026-10-22/benchmark_history/benchmark_report_bounded_20261021_074350_e29d0387.md)
· [JSON](benchmark_report_bounded_20261021_074350_e29d0387.json)
· [Kiểm chứng](bounded_recall_display_verification_20261021.json).
Render source 6497b9eefd64; training/evaluation metadata giữ nguyên từ mốc trước.
Chỉ ẩn cột Recall/all positives; giữ đủ giá trị trong JSON. Không retrain, không
tính lại metric, không sửa báo cáo cũ; vẫn ghi protocol và loại AUC ở từng dòng.

## Mốc trước: đủ metric thực và bảng gộp chín dòng

[Báo cáo mới](archive/2026-10-22/benchmark_history/benchmark_report_20261021_072543_c37b107c.md)
· [JSON](benchmark_report_20261021_072543_c37b107c.json)
· [Biên bản kiểm chứng](complete_metrics_report_verification_20261021.json).
Evaluation source `324556887803`, training source giữ `134b536cc623`.
Tính bổ sung từ checkpoint CDR của
[lượt chạy đủ chín mô hình/dataset](benchmark_all_8e44de4472_20261020_232046_d992f0ff_v4.json).
Không retrain, không sửa file cũ; sáu dòng MF/iDCF và metric gốc CDR giữ nguyên.

| CDR dataset | Recall/all positives | Recall bounded | Precision@5 | HitRate@5 |
| :-- | --: | --: | --: | --: |
| Coat | .493414 | .667816 | .532414 | .931034 |
| Yahoo | .706060 | .731299 | .263778 | .630926 |
| KuaiRand | .260089 | .327372 | .215242 | .645312 |

Đủ chín dòng, không có N/A trong metric của lượt này. Mỗi dòng ghi protocol và
loại AUC. Source empty-positive Recall=1 vẫn giữ; Precision/HitRate=0.
Không so hơn/kém hoặc paired-test chéo protocol. 118 test: 117 đạt, 1 CUDA bỏ qua.
[Validation diagnostic](complete_metrics_report_validation_20261021.json) xác nhận
ba seed vẫn chọn cùng epoch và điểm validation; không phải benchmark mới.

## Mốc trước: đồng nhất log huấn luyện

[Biên bản kiểm chứng](unified_training_logs_verification_20261020.json), source
`134b536cc623`: 115 test (114 đạt, 1 CUDA bỏ qua), CDR/iVAE callback giữ nguyên
trọng số/latent và quyết định dừng/chọn checkpoint.
[Smoke ba mô hình Coat](benchmark_coat_all_quick_7e3c020ae1_20261020_231221_e4861999_v4.json)
xác nhận đủ header, epoch, stage iVAE/feedback, TEST/SOURCE EVAL và checkpoint.
[CDR source Coat đầy đủ](benchmark_coat_cdr_dd41848bc6_20261020_231233_64456c33_v4.json)
vẫn đạt NDCG .656665 / Recall bounded .667816 / AUC global .751293.
[Validation diagnostic](unified_training_logs_validation_20261020.json) khớp
chính xác epoch và điểm validation ba seed trước đổi log; chỉ validation.
Đây là thay đổi hiển thị, không chuyển số Yahoo/KuaiRand cũ sang source mới.

## Mốc trước đổi log: CDR source protocol mặc định

[Biên bản kiểm chứng](cdr_source_default_verification_20261020.json), source
`abc819e34351`: 113 test (112 đạt, 1 CUDA bỏ qua), smoke ba dataset,
benchmark mặc định, seed 2020, tuning quick và reload checkpoint source.

- [Benchmark Coat CDR mặc định](benchmark_coat_cdr_a8d27b91f8_20261020_224913_af558386_v4.json)
  · [MD](archive/2026-10-22/benchmark_history/benchmark_coat_cdr_a8d27b91f8_20261020_224913_af558386_v4.md):
  NDCG .656665 / Recall bounded .667816 / AUC global .751293. Cùng hàm với cdr-source.
- [Yahoo source đầy đủ](cdr_source_yahoo_20261020_225246_193982ea.json):
  NDCG .655929 / Recall bounded .731299 / AUC global .684930.
  Đây là số thực chạy, không thay bằng số paper .6565/.7323/.6912.
- [Coat seed 2020](coat_seeds_73aeaea0873a3298_20261020_224946_b292cb89.json):
  khớp điểm benchmark/source; không phải seed độc lập hoặc độ ổn định nhiều seed.
- [Smoke Coat](benchmark_coat_all_quick_f07c1965db_20261020_224958_c1be1bf7_v4.json),
  [Yahoo](benchmark_yahoo_all_quick_7f2613dc8c_20261020_225005_acf377b2_v4.json),
  [KuaiRand](benchmark_kuairand_all_quick_db610a538f_20261020_225029_401b7143_v4.json):
  chỉ kiểm tra vận hành, CDR có scope dữ liệu/metric riêng; không so chất lượng.
- [Tuning quick](tuning_coat_cdr_e1_a8a81b00f8660f52_ee1f3f4b_v4.json):
  released estimator, 1 epoch, calibration/chọn cấu hình chỉ validation;
  không phải điểm source protocol hoặc lượt tuning hoàn chỉnh.
- [Validation diagnostic](cdr_source_estimator_validation_20261020.json):
  source estimator, ba seed, chỉ validation; không chuyển số sang source benchmark.

Coat/Yahoo source dùng 5% nhãn random chấm điểm cho calibration, >=3, toàn random
log, empty-positive nhận 1, Recall bounded. Báo cáo ở bảng riêng, không paired-test
chéo với MF/iDCF held-out. KuaiRand và API dùng released estimator nhưng có
adaptation dữ liệu/sampler/propensity ghi rõ; không gọi là tái lập toàn bộ script.
Các lượt phát triển trước khi đóng source được giữ nguyên hash, không gán sang mốc này.

## Mốc trước: tích hợp Yahoo và CDR released trên giao thức chung

[Biên bản kiểm chứng](yahoo_source_integration_verification_20261020.json), source
`88769819bd67`: 109 test (108 đạt, 1 CUDA bỏ qua), CDR khớp từng tham số lớp gốc
sau 3 epoch CPU, smoke đủ MF/iDCF/CDR trên Coat, Yahoo và KuaiRand.

- [Yahoo toàn dữ liệu, quick — JSON](benchmark_yahoo_all_quick_5c628bd4b7_20261020_222302_b3d1e0bf_v4.json)
  · [MD](archive/2026-10-22/smoke/benchmark_yahoo_all_quick_5c628bd4b7_20261020_222302_b3d1e0bf_v4.md):
  1 epoch feedback / 2 epoch iVAE; kiểm tra vận hành, chưa phải benchmark chất lượng.
- [Coat smoke](benchmark_coat_all_quick_f91c57579a_20261020_222119_147e6ae1_v4.json),
  [Yahoo 64 user](benchmark_yahoo_all_quick_73a6598a78_20261020_222127_b44aa7e9_v4.json),
  [KuaiRand 64 user](benchmark_kuairand_all_quick_907333adfb_20261020_222130_447f113a_v4.json):
  cùng mốc source; cấu hình smoke ghi metadata, không dùng so paper.
- [CDR released validation ba seed](released_cdr_coat_validation_20261020_yahoo_integration.json):
  chỉ validation, không chấm held-out test, không tuning.
- [CDR source Coat](cdr_source_coat_20261020_222318_c9e8d6e9.json): chạy đủ điều kiện
  script, NDCG .656665 / Recall bounded .667816 / AUC toàn cục .751293.
  Dùng 5% nhãn random chấm điểm cho propensity; không phải held-out benchmark.
- [CDR source Yahoo 1 epoch](cdr_source_yahoo_20261020_222146_a4c6d011.json):
  chỉ kiểm tra vận hành source-protocol; chưa chạy đủ ngân sách.

Các artifact phát triển `benchmark_yahoo_all_quick_4d1d116062...` và
`cdr_source_coat_20261020_222002...` giữ nguyên source hash của chúng; không thay
cho biên bản kiểm chứng source cuối. Chưa có benchmark chất lượng đầy đủ của
ba mô hình Yahoo ở mốc này. Yahoo iDCF là mở rộng địa phương, có thiếu survey;
không gắn số với paper iDCF.

## Benchmark Coat trước tích hợp released và audit CDR

[Báo cáo người dùng vừa chạy](archive/2026-10-22/benchmark_history/benchmark_coat_all_16747d3add_20261020_194738_4bb0b674_v4.md)
· [JSON](benchmark_coat_all_16747d3add_20261020_194738_4bb0b674_v4.json):
full-data seed 42, source `d5bdd13e82c3`, Test NDCG MF .547612, iDCF .569884,
CDR Eq. (7) .448514. Không dùng validation hoặc diagnostic thay cho bảng này;
không chuyển điểm CDR này sang bản released hiện hành.

[Lượt chạy lại 20:13](archive/2026-10-22/benchmark_history/benchmark_coat_all_16747d3add_20261020_201340_ff77c17a_v4.json)
· [MD](archive/2026-10-22/benchmark_history/benchmark_coat_all_16747d3add_20261020_201340_ff77c17a_v4.md) có cùng source,
cấu hình, seed và điểm với lượt 19:48; không coi là seed độc lập.

[Audit CDR sau benchmark](archive/2026-10-22/diagnostics/cdr_followup_audit_20261020.json) giữ kiểm tra dữ liệu,
checkpoint, validation controls và đối chứng script công bố. Script diagnostic
đạt .656665 NDCG / .667816 Recall bounded, có dùng 5% nhãn random chấm điểm cho
propensity; **không phải held-out benchmark dự án**. Giữ nguyên checkpoint đó
chấm >=4/test pool dự án còn .479693, vẫn chỉ là diagnostic.
[Phân tích](../docs/benchmarks/root_cause_analysis.md) nêu khác biệt paper/source.

## Validation sau sửa pipeline Coat

[Validation ba seed](archive/2026-10-22/validation/coat_pipeline_fix_validation_20261020.json): CDR và iDCF
huấn luyện đầy đủ trên train, không gọi held-out test; MF seed 42 làm đối chứng.
CDR đã chọn cấu hình qua một phần miền tuning paper và ba seed validation;
mean/std ở đây là mô tả quá trình chọn cấu hình, không phải benchmark độc lập.
[Search evidence](archive/2026-10-22/diagnostics/coat_pipeline_fix_search_20261020.json) giữ cấu hình và source
của từng trial phát triển; không đổi chúng sang source của bản chốt.

[CLI smoke Coat sau sửa — JSON](archive/2026-10-22/smoke/benchmark_coat_all_quick_13e80854d6_20261020_192736_117c64b0_v4.json)
· [Markdown](archive/2026-10-22/smoke/benchmark_coat_all_quick_13e80854d6_20261020_192736_117c64b0_v4.md):
cả ba mô hình chạy được ở source `d5bdd13e82c3`, feedback 1 epoch / iVAE 2 epoch;
chỉ xác nhận vận hành, không dùng điểm lượt này so với benchmark đầy đủ hoặc paper.

## Benchmark đầy đủ trước sửa pipeline Coat

[Coat, seed 42 — báo cáo](coat_full_20261020_185436_60df72/benchmark_coat_all_429e263db0_v4.md)
· [JSON](coat_full_20261020_185436_60df72/benchmark_coat_all_429e263db0_v4.json)
· [yêu cầu/cấu hình chạy](coat_full_20261020_185436_60df72/request.json)
· [biên bản hoàn tất](coat_full_20261020_185436_60df72/completion.json).
MF/iDCF/CDR chạy đầy đủ dữ liệu, cấu hình mặc định và early stopping; source
`36230d1cd908`, data `314c797e7674`. Chưa tuning, một seed, không phải tái lập paper.
IViDR-approx không thuộc lượt này. Log, script chạy và checkpoint riêng được giữ để đối chiếu.

Lượt người dùng chạy lại: [báo cáo](archive/2026-10-22/benchmark_history/benchmark_coat_all_429e263db0_v4.md) ·
[JSON](benchmark_coat_all_429e263db0_v4.json). Cùng điểm, source/data và seed với
lượt trong thư mục riêng; không coi là seed độc lập hoặc bằng chứng độ ổn định.
[Phân tích báo cáo](archive/2026-10-22/diagnostics/coat_report_analysis_20261020.json) chỉ đọc metadata, lịch sử,
trọng số propensity của train và kiến trúc checkpoint công khai của tác giả;
không có retraining, tuning hoặc lần chấm test mới. Kết luận và giới hạn nằm ở
[root cause analysis](../docs/benchmarks/root_cause_analysis.md).

## Validation, chẩn đoán và kết quả lịch sử

| Artifact | Phạm vi sử dụng | Nguồn ghi trong JSON |
| :-- | :-- | :-- |
| [benchmark_all_8c15e5d925_v4.json](benchmark_all_8c15e5d925_v4.json) · [MD](benchmark_all_8c15e5d925_v4.md) | Kết quả benchmark/tuning lịch sử; đọc metadata từng model/checkpoint; không đại diện mốc source hiện hành | `a9fdeb72ccd6` — source lịch sử |
| [benchmark_coat_all_003679088f_v4.json](benchmark_coat_all_003679088f_v4.json) · [MD](benchmark_coat_all_003679088f_v4.md) | Kết quả benchmark/tuning lịch sử; đọc metadata từng model/checkpoint; không đại diện mốc source hiện hành | 2 source hash khác mốc hiện hành; kiểm tra từng metadata |
| [benchmark_coat_all_19d70ea039_v4.json](benchmark_coat_all_19d70ea039_v4.json) · [MD](benchmark_coat_all_19d70ea039_v4.md) | Kết quả benchmark/tuning lịch sử; đọc metadata từng model/checkpoint; không đại diện mốc source hiện hành | `22ea114a3bdb` — source lịch sử |
| [benchmark_coat_ividr_9cf02b470b_v4.json](benchmark_coat_ividr_9cf02b470b_v4.json) · [MD](benchmark_coat_ividr_9cf02b470b_v4.md) | Kết quả benchmark/tuning lịch sử; đọc metadata từng model/checkpoint; không đại diện mốc source hiện hành | `946754273f79` — source lịch sử |
| [benchmark_kuairand_all_2edb44f179_v4.json](benchmark_kuairand_all_2edb44f179_v4.json) · [MD](benchmark_kuairand_all_2edb44f179_v4.md) | Kết quả benchmark/tuning lịch sử; đọc metadata từng model/checkpoint; không đại diện mốc source hiện hành | 3 source hash khác mốc hiện hành; kiểm tra từng metadata |
| [benchmark_kuairand_all_32e6ded9ad_v4.json](benchmark_kuairand_all_32e6ded9ad_v4.json) · [MD](benchmark_kuairand_all_32e6ded9ad_v4.md) | Kết quả benchmark/tuning lịch sử; đọc metadata từng model/checkpoint; không đại diện mốc source hiện hành | 2 source hash khác mốc hiện hành; kiểm tra từng metadata |
| [cdr_author_protocol_coat_thr3.json](cdr_author_protocol_coat_thr3.json) | Port chẩn đoán; dùng một phần nhãn tập chấm điểm cho propensity; thiếu source hash; không xác nhận tái lập paper | Không có source hash; chưa đủ provenance |
| [cdr_eq7_validation_6346597634257fd0.json](cdr_eq7_validation_6346597634257fd0.json) | Warm-start ablation đã bị thay thế; ba seed chọn MF epoch 0; không đại diện CDR độc lập | `999931b4f5cc` — source lịch sử |
| [cdr_idcf_tune_coat.json](cdr_idcf_tune_coat.json) | Port/filter variance, tuning theo giao thức dự án; thiếu source hash; không thuộc cấu hình CDR hiện hành | Không có source hash; chưa đủ provenance |
| [cdr_paper_method_validation_37b126f2c13fcea9.json](cdr_paper_method_validation_37b126f2c13fcea9.json) | CDR độc lập trước sửa pipeline, ba seed; chỉ validation; có ghi riêng smoke hai dataset; chưa tuning/test | `36230d1cd908` — source trước sửa |
| [coat_seeds_7ae4942b7c4a9f32.json](coat_seeds_7ae4942b7c4a9f32.json) · [MD](coat_seeds_7ae4942b7c4a9f32.md) | CDR lịch sử trước cơ chế giữ epoch 0; không đại diện CDR huấn luyện độc lập | `e5106d9db885` — source lịch sử |
| [coat_seeds_7d37e1975c96a410.json](coat_seeds_7d37e1975c96a410.json) · [MD](coat_seeds_7d37e1975c96a410.md) | iDCF và IViDR-staged cũ; IViDR dùng alpha_residual=1; không phải bản đúng paper | `02582b7e7987` — source lịch sử |
| [coat_seeds_c25da453e8909e5b.json](coat_seeds_c25da453e8909e5b.json) · [MD](coat_seeds_c25da453e8909e5b.md) | Bộ nhiều seed cũ; có kiến trúc joint/CDR cũ; không gán lại số cho mô hình hiện hành | `fbe2d03c1f3d` — source lịch sử |
| [tuning_kuairand_all_e25_4deb0568781e5d74_v4.json](tuning_kuairand_all_e25_4deb0568781e5d74_v4.json) · [MD](tuning_kuairand_all_e25_4deb0568781e5d74_v4.md) | Kết quả benchmark/tuning lịch sử; đọc metadata từng model/checkpoint; không đại diện mốc source hiện hành | `22ea114a3bdb` — source lịch sử |

## Quy tắc trích kết quả

- Trích JSON gốc kèm dataset, mô hình/biến thể, loss, source/data hash, seed và protocol.
- Nếu một artifact có nhiều source hash, không gọi toàn bộ là một phiên bản source đồng nhất.
- Không dùng validation hoặc smoke thay held-out test; không dùng test nhiều lần để chọn cấu hình.
- Markdown cũ có thể kèm bảng paper hoặc kết luận lỗi thời. Giữ nguyên để đối chiếu, không coi phần diễn giải đó là kết luận hiện tại.
- Với port thiếu source hash, không suy mã đã chạy từ file source đang có hôm nay.
- Lượt chạy mới phải đăng ký riêng trong catalog; không đổi nhãn hay ghi đè artifact cũ.
