# Trạng thái RecSys hiện hành

## Mốc 30/10/2026: benchmark sáu mô hình, cửa sổ KuaiRand của ConAlign

Theo yêu cầu người dùng, `benchmark --model all` (và `smoke`) chạy **MF, iDCF, IViDR, LCDR, DR-BIAS + CDR,
ConAlign**; `--model lcdr|conalign` chạy riêng. Bảng console/Markdown ghi protocol từng dòng: LCDR **H30**
(cùng dữ liệu/evaluator iDCF, có paired test), ConAlign **C-src** (tháp unbiased, test unbiased, seed 0,
`para()` của source; `--dim/--lr/--batch-size` không áp dụng; UAUC/UNDCG in dưới bảng; không paired test).
ConAlign KuaiRand mặc định **cửa sổ paper** (train 22/04–05/05): loader source bỏ sót 01–05/05 do sinh ngày
bằng phép cộng số nguyên; `kuairand_window='source'` giữ loader gốc.
[Kết quả đầy đủ ba dataset và hai nghiên cứu](benchmarks/lcdr_conalign_20261027.md#kết-quả-đầy-đủ-ba-dataset-2830102026).

| Dataset | IViDR | LCDR | ConAlign UAUC / NDCG (C-src, cửa sổ source) |
| :-- | --: | --: | :-- |
| Coat | .5288 | .5629 | .6733 / .7050 |
| Yahoo!R3 | .6460 | .6569 | .6892 / .7773 |
| KuaiRand | .4095 | .4209 | .5958 / .5278 (cửa sổ paper, 3 seed: .6018 / .5369) |

NDCG@5 H30, một seed, source `fd1df699561e`. LCDR Coat: biến thể ràng buộc và lưới LR × WD không vượt mặc
định (giữ nguyên). Source đã kiểm chứng: `eaaa557ae302485a39c88caade79c246fe4efa791bc02870c8c9d0a04f7e5db1`.
**156 test: 155 đạt, 1 CUDA skip** ([log](archive/2026-10-30/console_models/tests_final.log); lượt đầu
[2 test cũ](archive/2026-10-30/console_models/tests.log) còn kỳ vọng bộ bốn mô hình, đã cập nhật); smoke
sáu mô hình trên ba dataset ([log](archive/2026-10-30/console_models/smoke.log)); CDR validation ba seed khớp
chính xác mốc trước ([validation](../results/console_models_validation_20261030.json)).

## Mốc 28/10/2026: IViDR mặc định mới

Theo quyết định người dùng, IViDR mặc định (benchmark, coat-seeds, smoke) dùng **prior mean giai đoạn 1
bằng 0** và **BCE với mẫu âm trọng số .1**; Eq. (10) giữ v2. Tên hiển thị là **IViDR**, không đặt tên
riêng; metadata ghi `ividr_version=reference_v2_prior0_neg0.1`, `prior_mean`, `negative_weight` và danh
sách điểm lệch paper. Bản theo chữ paper: `ivae_overrides=dict(prior_mean='learned')`, `negative_weight=1`.
Điểm IViDR lịch sử trước 28/10 thuộc cấu hình cũ, không gán sang mặc định mới.
Source đã kiểm chứng: `fd1df699561e05415df720ee7bf5abdc9b4b556c2b37a321dc205949d5f27a1f`. **152 test: 151 đạt, 1 CUDA skip**;
smoke bốn mô hình hiển thị đúng tên/metadata mới; CDR validation ba seed khớp mốc trước.
[Validation](../results/ividr_default_validation_20261028.json) · [Log test](archive/2026-10-28/ividr_default/tests.log).

## Mốc 28/10/2026: IViDR prior mean bằng 0 (tùy chọn)

`ivae_overrides=dict(prior_mean='zero')` (lệch khỏi Eq. 42) kèm `negative_weight=.1`, Coat **10 seed**:
test NDCG@5 0.5657 ± 0.0212, so với mặc định 0.5325 ± 0.0067
(+.033, 9/10 seed, Wilcoxon p ≈ .006) và iDCF 0.5699 ± 0.0107 (không khác biệt, p ≈ .6). Paper .5903.
Chưa đổi mặc định. [Phân tích, mục 6–7](benchmarks/ividr_root_cause_20261027.md).
Source đã kiểm chứng: `742872d084e70591b7763b150b0c0d0652e1349dc7f44957e77ea59ce48b991d`. **152 test: 151 đạt, 1 CUDA skip**;
smoke bốn mô hình; CDR validation ba seed khớp mốc trước.
[Validation](../results/ividr_zero_prior_validation_20261028.json) · [Log test](archive/2026-10-28/ividr_zero_prior/tests.log).

## Mốc 28/10/2026: BCE có trọng số mẫu âm (tùy chọn)

Trainer feedback có thêm `negative_weight` cho BCE (mặc định 1; bốn mô hình mặc định không đổi).
Trên MF Coat, trọng số .2 đưa validation BCE từ .516 lên .607, gần mức MSE .618. Với IViDR, mức tăng
nằm trong nhiễu seed; khoảng cách còn lại với paper gắn với thang latent giai đoạn 1.
[Phân tích nguyên nhân, mục 5](benchmarks/ividr_root_cause_20261027.md).
Source đã kiểm chứng: `48d72ed3f5872a7ed10c0b1792571fdf47d33e0669800fa4d21574980277426a`. **151 test: 150 đạt, 1 CUDA skip**;
smoke bốn mô hình; CDR validation ba seed khớp mốc trước.
[Validation](../results/ividr_bce_validation_20261028.json) · [Log test](archive/2026-10-28/ividr_bce/tests.log).

## Mốc 27/10/2026: LCDR, ConAlign và thử sửa IViDR Eq. (10)

Bộ mặc định giữ nguyên **MF + CDR + iDCF + IViDR-BCE (reference v2)**.
[Hướng dẫn LCDR/ConAlign](benchmarks/lcdr_conalign_20261027.md) ·
[Ablation IViDR](benchmarks/ividr_eq10_ablation_20261027.md).

- **LCDR** (`run.py lcdr`): không có mã tác giả; cài đặt lại theo paper trên pipeline/protocol iDCF.
  Coat 3 seed: NDCG@5 .5674 ± .0054, thấp hơn iDCF cùng seed .5755 ± .0072 và paper .5973.
- **ConAlign** (`run.py conalign`): port từ source khóa commit `f6171bb` (repo không có LICENSE),
  khớp source từng epoch trên Coat. Coat seed 0, tháp unbiased: UAUC .6733, UNDCG .7100
  (paper .6856 / .7066). Protocol/metric riêng, không trộn với H30 hoặc CDR source protocol.
- **IViDR**: thêm tùy chọn v3 (chuẩn hóa phần cộng Eq. 10 theo ‖A_u‖) và ablation Table 4.
  Phần cộng tăng từ ~0.3% lên 100% chuẩn của A nhưng hai posterior vẫn gần trùng; validation
  không cải thiện, nên **mặc định giữ v2**. Khoảng cách với iDCF nằm ở giai đoạn feedback, chưa sửa.
- Yahoo/KuaiRand của LCDR và ConAlign mới chạy smoke.
- [Phân tích nguyên nhân IViDR](benchmarks/ividr_root_cause_20261027.md): nguyên nhân chính là mục tiêu
  feedback BCE (MF + BCE thấp hơn MF + MSE khoảng .07 validation); phụ là latent lệch lớn do prior mean
  học được. Chưa sửa mặc định; cả hai hướng sửa đều lệch khỏi paper.

Source đã kiểm chứng: `2811a292168094fb238f02ca0cdaa6dac26382a2fea2132fed2ddf066a332061`.
**151 test: 150 đạt, 1 CUDA skip**; smoke bốn mô hình trên ba dataset; CDR validation ba seed
khớp chính xác mốc trước. [Validation](../results/lcdr_conalign_validation_20261027.json)
· [Log test](archive/2026-10-27/lcdr_conalign/tests.log).

**Nghiên cứu IViDR ngày 23/10/2026:**
[đối chiếu paper, source và thứ tự tối ưu](benchmarks/ividr_optimization_research_20261023.md).
[Chẩn đoán stage1 Coat](../results/ividr_research_diagnostics_20261023.json) cho thấy
perturbation tái dựng khoảng 0.2984% theo chuẩn, hai posterior mean gần cùng hướng.
Đây là giả thuyết cần ablation validation; chưa sửa mô hình hoặc đo được tăng điểm.
Đã lưu thêm ba PDF tham khảo, khóa commit bốn nguồn liên quan; giữ BCE và nguồn đã loại
ở ngoài project. Source/checkpoint/dữ liệu và mốc kiểm chứng runtime bên dưới giữ nguyên.

## Mốc 27/10/2026: gỡ MF-CRIB và EGMN

Theo yêu cầu người dùng ngày 27/10/2026, project **không còn MF-CRIB và EGMN**.
Đã xóa package `src/models/mf_crib`, `src/models/egmn`, loader/metric/artifact video ngắn,
ba lệnh CLI `mf-crib`, `egmn`, `short-video`, test riêng, source tác giả trong `third_party/`,
checkpoint, kết quả, PDF/bản đọc EGMN, CRIB, LDRI và bằng chứng các mốc tích hợp/review
22/10. Dữ liệu KuaiRand-1K chỉ dùng cho CRIB/LDRI nên đã xóa; KuaiRand-Pure giữ nguyên
vì bộ bốn mô hình dùng. Theo AGENTS.md mục 5, không tạo bản lưu cho phần đã xóa.

Bộ mặc định giữ nguyên **MF + CDR + iDCF + IViDR-BCE**; không đổi loss, config hoặc protocol.
Source đã kiểm chứng:
`5bfc0e4080fe8898526cbc19763db6e4fcd8e706e04cb60800dcf25424e8c438`.
**134 test: 133 đạt, 1 CUDA skip**; smoke bốn mô hình trên ba dataset;
CDR validation ba seed chạy mới khớp chính xác epoch/điểm mốc sắp xếp package.
[Validation](../results/model_removal_validation_20261027.json)
· [Log test](archive/2026-10-27/model_removal/tests.log)
· [Log smoke](archive/2026-10-27/model_removal/smoke.log).

**Dọn results ngày 22/10/2026:** 155 file cũ/smoke/log chuyển nguyên byte vào
[archive kết quả](../results/archive/2026-10-22/README.md); cấp ngoài cùng giảm 252 → 97 file.
Ngày 27/10 mục lục archive bỏ hai dòng smoke MF-CRIB/EGMN đã xóa; còn 153 file.
Source, dữ liệu, checkpoint và metric không đổi; đây không phải lượt training/validation mới.

## Mốc trước: sắp xếp package

Mốc **22/10/2026: sắp xếp package theo từng mô hình**.
Mã chuẩn nằm trong `src/models/mf`, `cdr`, `idcf`, `ividr`; đường dẫn cũ
có lớp import tương thích. [Cấu trúc và trách nhiệm](architecture/directory_layout.md).
Bộ mặc định tiếp tục MF + CDR + iDCF + IViDR-BCE.

Source đã kiểm chứng:
`5cb6ca4bcf5d8963b8a7205290a80cf0d7a4ee15a979dcaaa1dde4438be91479`.
**134 test: 133 đạt, 1 CUDA skip**; smoke đủ bốn mô hình trên ba dataset.
CDR validation ba seed chạy mới khớp chính xác epoch/điểm mốc trước.
Đối chiếu AST chỉ có thay import và bootstrap đường dẫn MF; nạp checkpoint Coat
cũ cho cả bốn mô hình khớp chính xác metric. Dữ liệu, trọng số và kết quả cũ giữ nguyên.
[Đối chiếu và bằng chứng](../results/package_layout_verification_20261022.json)
· [Validation mới](../results/package_layout_validation_20261022.json).

Các điểm Coat bên dưới thuộc lượt huấn luyện trước sắp xếp. Đã xác minh nạp lại
trên source mới, không huấn luyện đầy đủ lại hoặc gán hash mới cho lượt chạy cũ.

## Mốc trước: IViDR reference v2

Mốc **22/10/2026: MF + CDR + iDCF + IViDR reference v2 (BCE)**.
IViDR triển khai lại theo [đặc tả và công thức arXiv](benchmarks/ividr_reference_20261022.md):
feature embedding học được, projector cập nhật theo embedding, gate nhận toàn Z_j
qua lớp đầu factorize, bỏ mean-history/free Linear bridge và marginalize xác suất
trước BCE. Eq. (10) dùng tied-item coordinate adapter tường minh vì tài liệu không
định nghĩa đủ phép đổi kích thước; chưa chứng nhận tái lập tác giả 100%.

Source đã kiểm chứng:
`dd068e23091a263bd967f9cc776d3352082b46842d27f9cc51e02a3d54ce2556`.
**132 test: 131 đạt, 1 CUDA skip**; smoke đủ bốn mô hình trên ba dataset;
CDR validation ba seed khớp mốc trước. Stage1/feedback nạp lại khớp chính xác.
[Kiểm chứng](../results/ividr_reference_verification_20261022.json)
· [Validation](../results/ividr_reference_validation_20261022.json).

[Coat đầy đủ](../results/benchmark_coat_all_02b9e8eb46_20261022_073711_146173c9_v4.md):
MF NDCG .547612 / bounded .584032; iDCF .569884 / .602295;
IViDR .541201 / .613273; CDR .656665 / .667816.
MF/iDCF/CDR khớp metric và từng tensor trọng số mốc trước.
IViDR tăng NDCG và Recall so với BCE-v1; so với iDCF, Recall cao hơn nhưng NDCG
vẫn thấp hơn. Chỉ một seed, không suy ra ưu thế chung hoặc đã tái lập số paper.

## Mốc lịch sử: BCE-v1 và xác nhận giữ objective của paper

Mốc **21/10/2026: MF + CDR + iDCF + IViDR-BCE**. IViDR đã thay lõi staged
bằng learned IV, dual iVAE và feedback BCE theo công thức arXiv; các lựa chọn
địa phương và giới hạn tái lập được ghi trong [hướng dẫn IViDR](benchmarks/ividr_bce_20261021.md).
MF/iDCF giữ MSE; CDR source protocol giữ nguyên. Chưa xác nhận tái lập bản ACM.

Người dùng đã chốt giữ BCE theo Eq. (25), hủy chuyển feedback sang MSE.
Source hiện hành chỉ còn khác mốc chạy BCE ở docstring của pipeline lịch sử:
`017c3601e4f3744c42e95e2eecaad571a761178b8c315d65cb31201f19591b39`.
Code training, workflow và test đã khôi phục nguyên byte; không huấn luyện mới
hoặc gán lại điểm từ mốc `70897b831d4f` sang source mới.
**126 test: 125 đạt, 1 CUDA skip**; smoke đủ bốn mô hình trên ba dataset;
smoke là bằng chứng ở mốc BCE trước. CDR validation ba seed đã chạy lại trên
source hiện hành. [Xác nhận mặc định](../results/archive/2026-10-22/diagnostics/paper_default_confirmation_20261021.json)
· [Validation](../results/paper_default_confirmation_validation_20261021.json).

<!-- source-cleanup-status:start -->
Cleanup completed at the explicit request of the user; rejected-source material and its backups removed. See results/source_cleanup_completion_20261021.json.
<!-- source-cleanup-status:end -->

[Chạy đầy đủ Coat](../results/archive/2026-10-22/benchmark_history/benchmark_coat_all_b384ff80db_20261021_115348_e8c7d044_v4.md):
NDCG MF .547612, iDCF .569884, IViDR-BCE .529125, CDR .656665;
Recall bounded .584032 / .602295 / .590419 / .667816. MF/iDCF/CDR khớp
chính xác metric và mọi tensor mốc trước. IViDR chọn LR/WD bằng validation,
chỉ đánh giá checkpoint thắng trên test.

[Ablation MSE/BCE](../results/ividr_mse_bce_ablation_20261021.json), Coat seed 42:
cùng latent và LR/WD, MSE NDCG .540521 / bounded .603493, BCE .529125 / .590419.
Nếu từng loss chọn cấu hình theo validation, MSE .516317 / .594711;
BCE .529125 / .590419. Đây là một seed, chưa kết luận loss nào luôn tốt hơn;
không dùng test để đổi mặc định BCE theo paper.

## Mốc lịch sử: bộ bốn trước khi sửa IViDR theo paper

Mốc trước **21/10/2026: bộ bốn MF + CDR + iDCF + IViDR-approx**.
[Snapshot](state_snapshot.json) · [Lệnh chạy](../README.md) ·
[Định nghĩa](benchmarks/paper_model_alignment.md) · [Giao thức](benchmarks/evaluation_protocol.md).

Source đã kiểm chứng:
`4ca654f49942424708c3fd56fcfa9f8c939702831b59d4781bf168c5f2ceb883`.

Người dùng giữ cả iDCF và thêm IViDR vào bộ chạy. Tại mốc này lõi staged
địa phương hiển thị **IViDR-approx**, chưa đọc được bản ACM cuối do HTTP 403.
Triển khai hiện hành xem [hướng dẫn IViDR-BCE](benchmarks/ividr_bce_20261021.md).

**Đã chạy đầy đủ bốn mô hình trên Coat**: NDCG MF .547612, iDCF .569884,
IViDR-approx .532193, CDR .656665. Recall bounded tương ứng .584032 / .602295 /
.557884 / .667816. MF/iDCF/CDR giữ chính xác metric và mọi tensor trọng số
so với lượt trước. [Báo cáo](../results/archive/2026-10-22/benchmark_history/benchmark_coat_all_e052d60c74_20261021_095855_83a07811_v4.md)
· [Biên bản](../results/four_model_default_verification_20261021.json).
Training source 35e5fcf0d0bd; sau đó chỉ sửa câu mô tả IViDR trong coat-seeds,
không gán lại source hash cũ. Source cuối đã qua **119 test: 118 đạt, 1 CUDA skip**;
smoke đủ 4 mô hình trên ba dataset và CDR validation ba seed khớp mốc trước.
[Validation cuối](../results/four_model_default_final_validation_20261021.json).
Mặc định `benchmark --model all`, `smoke` và `coat-seeds` có bốn mô hình;
bảng đủ 12 dòng nếu chạy cả ba dataset, chỉ hiển thị Recall bounded.

## Mốc hiển thị trước khi thêm IViDR

Theo lựa chọn người dùng, bảng chỉ giữ Recall@5 bounded, ghi rõ tên cột.
Hai Recall và mọi metric vẫn nguyên trong JSON; không đổi training/evaluation.
[Báo cáo cũ ba mô hình](../results/archive/2026-10-22/benchmark_history/benchmark_report_bounded_20261021_074350_e29d0387.md)
được dựng lại từ JSON có sẵn, không retrain hoặc tính lại metric.
[Kiểm chứng mốc hiển thị](../results/bounded_recall_display_verification_20261021.json).
Training source 134b536cc623, evaluation source 324556887803, render source 6497b9eefd64.

**Đã chạy lại đầy đủ ba mô hình Coat ở mốc 6497b9eefd64**, CPU 2 thread:
MF NDCG .547612 / Recall bounded .584032; iDCF .569884 / .602295;
CDR .656665 / .667816. Điểm gốc, epoch chọn và mọi tensor trọng số khớp chính xác
lượt trước. [Báo cáo mới](../results/archive/2026-10-22/benchmark_history/benchmark_coat_all_666cb1327c_20261021_074841_a3d6e730_v4.md)
· [Đối chiếu checkpoint](../results/archive/2026-10-22/diagnostics/coat_reproducibility_20261021_074841.json).
Đây là kiểm chứng lặp lại cùng seed, không phải seed độc lập hoặc tuning.

CDR bổ sung cả Recall/all positives và Recall bounded, Precision/HitRate từ
cùng ranking/user cohort, giữ nguyên metric nguồn. S-full empty-positive vẫn
có Recall=1; Precision/HitRate=0. Bảng ở mốc cũ có 9 dòng với protocol và
loại AUC; không paired-test chéo protocol. Không đổi training hoặc checkpoint.

[Báo cáo trước khi ẩn Recall/all positives](../results/archive/2026-10-22/benchmark_history/benchmark_report_20261021_072543_c37b107c.md)
được tính từ checkpoint, không retrain; giữ nguyên sáu dòng MF/iDCF và metric gốc
của CDR. JSON giữ training source 134b536cc623 và evaluation source mới riêng biệt.
[Biên bản kiểm chứng](../results/complete_metrics_report_verification_20261021.json).

Log dùng chung tiêu đề cấu hình, prefix model/dataset, tiến độ epoch, kết thúc
và checkpoint. iDCF hiển thị cả iVAE (train/val ELBO, beta, warm-up/full-beta)
và feedback (train loss, validation ranking). CDR source ghi rec/imp loss từng
epoch rồi SOURCE EVAL cuối lượt; không tự thêm validation hoặc đổi cơ chế dừng.
Không thay đổi loss, seed, split, metric, optimizer hay lựa chọn checkpoint.

## Mặc định đang chạy

- CDR benchmark Coat/Yahoo dùng cùng hàm `run_source` với `cdr-source`:
  seed 2020, dim 4, trần 1000 epoch, dừng theo train loss và lấy trọng số cuối.
  Nhãn >=3; calibration bằng 5% nhãn random chấm điểm; đánh giá toàn random log,
  zero-positive nhận 1, Recall bounded và AUC toàn cục.
- Lệnh `benchmark --dataset coat --model cdr` đã chạy đầy đủ:
  **NDCG .6566651228 / Recall bounded .6678160920 / AUC .7512927651**.
  [Báo cáo sau đổi log](../results/archive/2026-10-22/benchmark_history/benchmark_coat_cdr_dd41848bc6_20261020_231233_64456c33_v4.md).
  Khớp lượt cdr-source người dùng xác nhận; không gọi đây là test độc lập chưa dùng nhãn calibration.
  [Yahoo source đầy đủ trước đổi log, source abc819e34351](../results/cdr_source_yahoo_20261020_225246_193982ea.json):
  NDCG .655929 / Recall bounded .731299 / AUC global .684930; không gán lại số paper.
- MF/iDCF giữ MSE, IViDR hiện hành giữ BCE; cả ba dùng >=4,
  random-log user split 30/70 và checkpoint validation.
  Bảng gộp ghi protocol và loại AUC từng dòng; không kiểm định chéo với MF/iDCF khác protocol.
- KuaiRand đã chuyển sang thuật toán CDR released. Dữ liệu vẫn là preprocessing
  địa phương; calibration 5% validation; array sampling thay DataLoader; catalog
  lớn dùng sampling có hoàn lại để giới hạn RAM. Không tuyên bố tái lập chính xác script KuaiRand.
- API đã dùng ReleasedCDR 4 chiều, variance filter, output dropout và source
  update/loss. App không có random log nên giữ propensity item-frequency và
  sampling có hoàn lại, ghi trong training_stats.cdr. Ngân sách phục vụ riêng.
- Tuning Coat/KuaiRand dùng estimator released, trần 1000, seed 2020,
  train-loss stopping/lấy trọng số cuối, calibration 5% validation. Chọn cấu hình
  bằng validation; không dùng nhãn test để tune. Đây là tuning adaptation,
  không phải cách lấy điểm source protocol. Coat CDR tuning dùng >=3, MF >=4.
- `coat-seeds` dùng source protocol cho CDR; checkpoint được giữ lại.
  Recall được gắn đúng tên bounded, không Wilcoxon chéo protocol.
- `cdr-author` là alias `cdr-source`; `cdr-tune` alias tuning released.
  Bản Eq. (7) cũ chỉ chạy tường minh qua `--cdr-implementation equation` hoặc
  hàm legacy; giữ để đọc checkpoint/ablation. `--cdr-implementation shared`
  dùng released với giao thức held-out chung.

## Kiểm chứng mốc hiển thị trước khi thêm IViDR

**118 test: 117 đạt, 1 CUDA bỏ qua**.
[Log](archive/2026-10-21/bounded_recall_display/model_tests.log).
Có kiểm thử 3 epoch CPU khớp từng trọng số lớp gốc, metric source, loại CDR
source khỏi paired tests chung, sampler cho event lặp, API released và dispatch tuning.
Hai test mới xác nhận progress callback không đổi tham số/history/dừng sớm CDR,
latent và checkpoint selection của iVAE.
Ba test mới tính tay cả hai Recall/Precision/HitRate, zero-positive, candidate<k
và bảng 9 dòng có đủ metric thực cùng protocol/loại AUC.

[Biên bản mốc log](../results/unified_training_logs_verification_20261020.json)
dẫn smoke ba mô hình Coat, CDR Coat source đầy đủ và hồi quy validation ba seed.
[Biên bản trước đổi log](../results/cdr_source_default_verification_20261020.json)
giữ kiểm chứng ba dataset, chạy seed, tuning, API và reload tại source abc819e34351.
[Validation-only diagnostic mốc hiển thị](../results/bounded_recall_display_validation_20261021.json)
là phép kiểm tra riêng của estimator với validation, không thay điểm source benchmark.
Ba seed khớp chính xác epoch/điểm validation của mốc trước.
Không coi smoke/quick là kết quả chất lượng.

Python 3.12.10, PyTorch 2.14.1+cpu, NumPy 2.5.4, pandas 3.0.6; CPU 2 thread.
Chưa kiểm chứng CUDA.

## Yahoo và các giới hạn giữ nguyên

Yahoo! R3: 15.400 user, 1.000 item; 311.704 train / 54.000 random ratings;
đã tải từ commit nguồn được chỉ định. MF/iDCF chuyển ID về 0-based; CDR source
giữ ID 1-based/dummy row như script. Train/random overlap bằng 0.

iDCF Yahoo dùng 7 câu survey thật, one-hot 39 chiều; 10.000 user thiếu survey
nhận category thiếu. Đây là adaptation địa phương, chưa phải tái lập pipeline
Yahoo của tác giả; giả định nhân quả ở nhóm thiếu survey chưa được xác minh.
**Đính chính 21/10/2026:** paper iDCF có kết quả Yahoo; mã tác giả chỉ giữ
5.400 user có survey, khác 15.400 user hiện tại. Đã tìm thấy repository chính thức
iDCF. [Biên bản nguồn](benchmarks/source_repository_review_20261021.md).
iVAE Coat/Yahoo 16/32/3, KuaiRand 32/64/2, chọn sau full-beta warm-up.
IViDR thuộc bộ mặc định theo yêu cầu người dùng;
Yahoo giữ adaptation survey/missing category và chưa tái lập paper.

## Lịch sử

Source trước `88769819bd67` dùng released nhưng calibration/chọn checkpoint theo
giao thức chung; chưa phải mặc định source protocol hiện nay.
[Kiểm chứng cũ](../results/yahoo_source_integration_verification_20261020.json)
giữ nguyên số và hash. CDR Eq. (7) .448514 tại source `d5bdd13e82c3` không phải
điểm của CDR source hiện hành.
[Bản trước thay đổi](archive/2026-10-20/cdr_source_default/before_change.zip).

[Catalog kết quả](../results/CATALOG.md) · [Bảo toàn tài liệu](MAINTENANCE.md).
