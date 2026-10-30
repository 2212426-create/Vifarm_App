# Điều tra mô hình: kết luận còn sử dụng được

> **Phạm vi lịch sử trước tích hợp Yahoo/CDR released.** Các nhận định "hiện tại"
> trong phần phân tích dưới thuộc source `d5bdd13e82c3` hoặc các mốc được ghi riêng.
> Sau tích hợp, benchmark Coat/Yahoo mặc định dùng `released`; Eq. (7) chạy tường minh.
> Xem [định nghĩa hiện hành](paper_model_alignment.md) và [CURRENT_STATE](../CURRENT_STATE.md).

Trạng thái triển khai và kết quả mới nằm ở [CURRENT_STATE](../CURRENT_STATE.md).
Bản dài trước dọn được giữ tại [archive](../archive/2026-10-20/benchmarks/root_cause_analysis.md)
và bản nguyên byte trong [ZIP](../archive/2026-10-20/documentation_before_cleanup.zip).

## Rà soát benchmark 19:48 — đối chứng trực tiếp mã CDR công bố

[Báo cáo mới](../../results/archive/2026-10-22/benchmark_history/benchmark_coat_all_16747d3add_20261020_194738_4bb0b674_v4.md),
[evidence](../../results/archive/2026-10-22/diagnostics/cdr_followup_audit_20261020.json) và
[runner/source/weights đối chứng](../archive/2026-10-20/cdr_followup_audit/runners_and_source.zip).
Source dự án vẫn `d5bdd13e82c3`; đợt này không sửa runtime hoặc chọn config theo test.

| Thí nghiệm | NDCG@5 | Recall@5 | Phạm vi |
| :-- | --: | --: | :-- |
| MF vừa chạy | .547612 | .529536 | Test dự án, seed 42 |
| iDCF vừa chạy | .569884 | .551969 | Test dự án, seed 42 |
| CDR vừa chạy | .448514 | .458145 | Test dự án, seed 42 |
| Chạy các lớp/điều kiện script công bố | **.656665** | **.667816** | Diagnostic theo source; Recall bounded; không phải held-out benchmark dự án |

Dòng cuối làm tròn đúng .6567/.6678 của [CDR Table 2](https://jiawei-chen.github.io/paper/CIKM23-CDR.pdf).
Lớp/hàm được trích nguyên AST ở commit `6b4e6cca3df23b8d85b38fdc2e7eb5c812861ea9`;
không dùng port `cdr-author` cũ. Môi trường khác paper nên không tuyên bố bitwise.

### Kiểm tra dữ liệu và khác biệt thực nghiệm

Hai ma trận train/test khớp mọi giá trị với repository CDR gốc; khác byte chỉ do
CRLF. Checkpoint đúng epoch 40 và source/data hash; chấm lại độc lập tái hiện
.448514, score hữu hạn và không bị phẳng. Chưa tìm thấy lỗi tải nhầm dữ liệu/checkpoint.

| Thành phần | Benchmark dự án | Script CDR công bố |
| :-- | :-- | :-- |
| Positive | rating >=4 | rating >=3 |
| Tập chấm | 203 user test riêng | Toàn bộ 290 user random log |
| User không positive | Loại khỏi macro | NDCG/Recall bằng 1 |
| Recall | Chia toàn bộ positive | Chia số positive tối đa trong top K |
| Propensity | Hiệu chỉnh từ validation | 5% nhãn random log cũng dùng chấm điểm |
| Bộ lọc | CV .1 | Variance 10 |
| Recommendation loss | Eq. (7), population-normalized | Correction imputation không cùng inverse weight; tổng chia direct batch |
| Fit imputation/dropout | BCE cùng chiều rec; dropout embedding | BCE đảo chiều; thêm mask output probability |

Paper prose nói rating >3 và split 10/90; không đồng nhất với script. Giữ nguyên
checkpoint script và chấm theo >=4/test pool dự án: NDCG **.479693**. Đây vẫn là
diagnostic vì checkpoint dùng một phần nhãn random để hiệu chỉnh propensity.
Giữ checkpoint dự án nhưng chấm >=3/full-random/empty=1 cho .577030; không coi là
kết quả đã cải thiện hoặc tái lập paper. Không sửa nhãn/evaluator để lấy điểm cao.

### Imputation: bộ lọc đang bảo vệ mô hình

Epoch chọn loại 93.49% observed / 92.78% direct imputation. Lần sửa trước cố định
eta .1 khi tune LR/wd/batch. Đối chứng mới giữ mọi tham số khác, chỉ chấm validation:

| Điều kiện | Val NDCG@5 |
| :-- | --: |
| IPS control, eta 0 | .494527 |
| CDR eta .1 | .498562 |
| eta .5 | .455278 |
| eta 1 | .371773 |
| eta 3/5/7/10/50, không còn lọc | .363517 |

CDR chỉ hơn IPS .004035 ở seed này; nới bộ lọc làm giảm điểm. Probe checkpoint với
200 MC samples cho khoảng 67.46% imputation validation thỏa định nghĩa poisonous,
nhóm retained không có poisonous trong probe. Train error-imputation MSE tăng từ
.183787 (deterministic) lên .729206 (MC mean); validation tương ứng .663995/.833042.
Đây là dấu hiệu nhánh imputation kém và khác error sau dropout, chưa chứng minh
riêng một bug công thức. Paper §3.1 quy định **không dropout lúc train imputation**;
không tự thêm dropout training rồi gọi là sửa đúng paper. Probe 200 mẫu không thay
log train dùng 10 mẫu và trạng thái trọng số thay đổi trong epoch.

Lớp nguyên gốc chạy nhãn/split dự án, chỉ validation calibration đạt .469430 val.
Chỉ đổi chiều BCE fit imputation của bản hiện tại theo source đạt .512568 ở eta .1,
nhưng .320130 ở eta 10. Không có bằng chứng đổi một thành phần sẽ khôi phục .6567
trong benchmark chung; các probe này không chấm test hay thay cấu hình mặc định.

Kết luận: dữ liệu đúng; CDR hiện tại chưa phải thí nghiệm tạo số Table 2 và chưa
cải thiện rõ ràng so với IPS control trên validation. Muốn so số paper, ghi riêng
nhánh theo điều kiện script với calibration/metric đầy đủ; muốn cải thiện benchmark
chung, kiểm chứng imputation và tuning trên validation trước khi khóa cấu hình.
Các phần dưới giữ các mốc điều tra trước lượt 19:48, không thay kết luận mới này.

## DR-BIAS + CDR

Giữ tiêu đề này để liên kết từ bản chép paper cũ vẫn trỏ đúng. Các điểm dưới đây
là đính chính của dự án; công thức/nội dung bài báo nằm ở PDF và bản chép được bảo toàn.

## Đính chính cho lần đọc sau

- Chênh điểm CDR có cả khác giao thức và các bất nhất loss/filter ở bản cũ.
  Không kết luận “chỉ do dữ liệu” hoặc “chỉ do BCE”.
- Bộ lọc variance ngưỡng 10 từng không loại mẫu trong một lượt cũ. Triển khai hiện
  dùng CV; kết quả cũ đó không mô tả bộ lọc hiện tại.
- Những lượt CDR chọn MF epoch 0 là warm-start ablation, không phải thành tích
  của CDR nguyên bản. Benchmark/tuning/seed runner hiện không nạp checkpoint MF.
- CDR paper cho phép nhiều hàm error. Bản hiện hành chọn BCE; không suy ra rằng
  mọi CDR bắt buộc dùng BCE hoặc mọi MF phải đổi sang BCE.
- IViDR-staged cũ có `alpha_residual=1` trả lại treatment gốc; đổi thành 0 vẫn
  không bổ sung được các MLP/reconstruction/BCE còn thiếu của IViDR paper.
- Port `cdr-author` không tương đương bitwise mã công bố và dùng một phần nhãn
  tập chấm điểm để ước lượng propensity. Không dùng số đó để chứng nhận tái lập.

## Sau sửa pipeline Coat — 20/10/2026

Các lỗi đã xử lý: iVAE Coat dùng kiến trúc 16/32/3 và patience 100; chọn checkpoint
và early stopping sau full-beta warm-up. Ngân sách smoke quá ngắn được đánh dấu
riêng. Trainer CDR cập nhật recommendation rồi tính lại sai số để cập nhật
imputation, thay cho cập nhật hai bên từ cùng logits cũ.

CDR Coat mặc định dùng Naive Bayes trên validation, không dùng nhãn test cho
hiệu chỉnh. Trọng số IPS lớn nhất giảm từ 245.07 xuống 14.33; top 1% mẫu chiếm
1.32% tổng trọng số imputation thay vì 50.12%. Đây là thay đổi estimator
propensity có công bố nguồn, không phải cap trọng số hoặc sửa Eq. (7).

Một phần miền tuning paper đã được kiểm tra trên validation. Cấu hình chốt:
LR .1, wd .0001, batch 512, eta .1, dim 4, patience 20; chọn theo mean validation
ba seed 42/43/44 giữa hai cấu hình vào vòng xác nhận. Chưa chạy đủ 1120 tổ hợp.
CDR validation lần lượt .498562/.497547/.491869, mean .495993; vẫn chưa vượt MF.
Các seed này tham gia chọn cấu hình nên không phải kiểm chứng độc lập ngoài mẫu.

[Validation bản chốt](../../results/archive/2026-10-22/validation/coat_pipeline_fix_validation_20261020.json),
[các trial phát triển](../../results/archive/2026-10-22/diagnostics/coat_pipeline_fix_search_20261020.json) và
[trạng thái hiện hành](../CURRENT_STATE.md) giữ số và source tương ứng. Chưa có
benchmark test đầy đủ của bản sửa. Không chuyển số test cũ sang source mới.

## Báo cáo Coat đầy đủ trước sửa — 20/10/2026

**Phần dưới mô tả source `36230d1cd908`, trước bản sửa ở trên.** Những cấu hình
và câu “chưa sửa runtime” trong phần điều tra này là trạng thái tại mốc đó.

[Báo cáo người dùng chạy](../../results/archive/2026-10-22/benchmark_history/benchmark_coat_all_429e263db0_v4.md),
[JSON gốc](../../results/benchmark_coat_all_429e263db0_v4.json) và
[evidence chỉ đọc](../../results/archive/2026-10-22/diagnostics/coat_report_analysis_20261020.json).
Đây là full-data seed 42, không phải smoke; source `36230d1cd908`, chưa tuning.

| Mô hình | Test NDCG@5 dự án | Mốc paper để tham khảo | Cách diễn giải |
| :-- | --: | :-- | :-- |
| MF | .547612 | .5524 ± .0144 trong paper iDCF | Chênh .004788; cùng thang biến thiên seed được paper báo cáo, chưa phải kiểm định tái lập |
| iDCF | .463745 | .5744 ± .0122 trong paper iDCF | Giảm đáng kể; chưa dùng kiến trúc iVAE Coat đã tune công khai |
| DR-BIAS + CDR | .376982 | .6567 trong paper CDR | Khác cả thực nghiệm và cấu hình tối ưu; không coi chênh số thô là mức suy giảm cùng điều kiện |

Mốc paper từ [iDCF Table 2 và Appendix B](https://arxiv.org/pdf/2302.05052)
và [CDR Table 2, §4.1](https://jiawei-chen.github.io/paper/CIKM23-CDR.pdf).
Một seed dự án không thay thế trung bình 10 seed của iDCF. Giao thức chung bám
iDCF; khác biệt nhỏ evaluator không đủ bằng chứng để giải thích toàn bộ chênh lệch.

### iDCF: cấu hình ví dụ khác mô hình Coat đã tune

Local dùng iVAE latent 32 / hidden 64 / 2 lớp theo `sample_config`. Tác giả xuất
latent qua [notebook](https://github.com/BgmLover/iDCF/blob/main/save_ae_params.ipynb)
bằng cách nạp [checkpoint đã tune](https://github.com/BgmLover/iDCF/blob/main/tuned_models/coat_val_ivae_exposure_best.pt).
Kiểm tra trực tiếp checkpoint SHA256 `a37531edb98cdfa1cb0b47505f14d42388fd2e006416705ee7493046bcc4edd8`:
encoder `fc_0.weight` có shape (32,314), `fc_1.weight` (32,32), `fc_2.weight`
(16,32), tức hidden 32 / latent 16 / 3 lớp tuyến tính. Vì vậy nhận định dùng cấu
hình ví dụ là đủ để tái lập Coat cần được rút lại. Tensor không cho biết toàn bộ
siêu tham số huấn luyện; đổi riêng dim chưa chứng minh sẽ khôi phục điểm paper.

Local có 232 user train iVAE, batch 512 nên một update/epoch. Với trần 2000 epoch,
KL warm-up dài 400 update. iVAE chọn epoch 51 (beta lúc train .125), dừng epoch
56 (beta .1375), trong khi validation tính ELBO với beta 1. Stage 2 chọn epoch
3 và dừng 8. Đây là checkpoint được chọn trước khi kết thúc warm-up, cần kiểm
tra ảnh hưởng của schedule/patience trên validation. Chưa có ablation chứng minh
đây là nguyên nhân duy nhất. Chỉ tăng trần epoch, giữ early stopping, không giải
quyết việc dừng sớm này. Mã tác giả còn khác cách đếm update anneal và lấy mẫu
validation, nên không gọi hai quá trình huấn luyện là tương đương.

### CDR: có khác giao thức và dấu hiệu tối ưu kém

Paper mô tả rating > 3 và validation/test 10/90. Script Coat công bố lại dùng
rating >= 3, toàn bộ random log để chấm điểm, quy ước user không positive khác
và ước lượng propensity Naive Bayes từ một phần nhãn random. Dự án dùng rating
>= 4, split user 30/70, loại user không positive và propensity file Coat. Không
đồng nhất script với paper hoặc đổi threshold chỉ để điểm cao hơn.

Triển khai hiện dùng Eq. (7), CV filter và dropout embedding theo paper; script
tác giả có các khác biệt estimator/filter/dropout đã ghi ở
[paper_model_alignment](paper_model_alignment.md). LR .05, dim 4, batch 128 lấy
từ script không mặc nhiên tối ưu sau những thay đổi này. Grid chưa được chạy.

Tuy vậy, khác giao thức không giải thích hết chất lượng nội bộ hiện tại:

- CDR chọn epoch 6, Val NDCG .425608, Test AUC .560873; Popularity NDCG .351106.
  So với Popularity, CDR tăng .025875, Wilcoxon p=.514 trên user của seed này;
  chưa có bằng chứng cải thiện ranking rõ ràng. Đây không phải std giữa seed.
- Risk recommendation quanh .69; imputation loss dao động mạnh (epoch 2–5:
  khoảng 29.8–75.1). Risk tổng hợp không chứng minh mọi dự đoán bằng .5.
- Trên 6960 cặp train, inverse propensity lớn nhất 245.07; IPS ESS khoảng 2211.
  Loss imputation dùng trọng số `w^3 * (1 - 1/w)^2`, lớn nhất khoảng 14.6 triệu;
  70 mẫu có trọng số cao nhất (xấp xỉ 1%) chiếm 50.12% tổng trọng số imputation.
  Đây là khối lượng trọng số, không phải khối lượng gradient; cần kiểm tra residual
  và gradient mới kết luận mất ổn định. Không tự cap trọng số rồi gọi là CDR gốc.
- Bộ lọc CV ở epoch được chọn loại khoảng 5.01% observed và 5.18% direct imputation.
  Không áp dụng lại nhận định cũ “bộ lọc không hoạt động” cho bản này.

Audit cũ từng chấm lại cùng một checkpoint port với quy tắc khác và thấy điểm đổi
mạnh. Điều đó chứng minh metric phụ thuộc protocol, không định lượng phần chênh
do protocol trong checkpoint CDR hiện tại. Không lấy checkpoint port làm benchmark
độc lập vì có dùng nhãn tập chấm điểm cho propensity.

### Thứ tự xử lý cần thiết

1. Xác minh ánh xạ dữ liệu/feature và latent với pipeline iVAE Coat đã tune; tách
   kiểm chứng kiến trúc khỏi kiểm chứng schedule và early stopping trên validation.
2. Với CDR, chốt chạy tái lập công thức paper hay tái lập script có ghi rõ khác
   biệt; kiểm tra định nghĩa/ước lượng propensity và độ tập trung gradient trước
   khi tune LR, weight decay, eta, batch bằng validation. Giữ MF-MSE và CDR-BCE độc lập.
3. Khóa cấu hình, báo mean/std nhiều seed rồi chấm test ở lượt mới. Không chọn
   cấu hình theo test vừa đọc hoặc tuyên bố test công thức đạt là mô hình đã tốt.

Đợt phân tích này không sửa runtime, không tune hoặc chạy lại mô hình. Các nguyên
nhân chưa được kiểm tra bằng thí nghiệm đối chứng vẫn được giữ là giả thuyết.

## Bằng chứng lịch sử

[CDR audit evidence](cdr_audit_2026-10-19_evidence.json) và
[review evidence](review_2026-10-19_evidence.json) giữ nguyên số đo và hash cũ.
Công thức/phép đo trong archive mô tả phiên bản tại thời điểm điều tra;
đường dẫn tới source ngày nay không có nghĩa lỗi đó vẫn còn.

Kết quả được phép trích và phần việc còn thiếu: [catalog kết quả](../../results/CATALOG.md),
[đối chiếu mô hình](paper_model_alignment.md), [CURRENT_STATE](../CURRENT_STATE.md).
